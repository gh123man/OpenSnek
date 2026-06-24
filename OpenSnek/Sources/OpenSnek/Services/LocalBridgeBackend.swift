import Foundation
import Network
import OpenSnekCore
import OpenSnekHardware

/// Serializes local bridge backend state and operations.
final actor LocalBridgeBackend: HIDAccessRefreshControllingBackend, ApplyOptionsSupportingBackend {
    static let shared = LocalBridgeBackend()
    private static let usbDisconnectDebounceInterval: TimeInterval = 0.75
    private static let softwareLightingUSBReachabilityProbeInterval: TimeInterval = 1.0
    static let softwareLightingReconnectReassertInterval: TimeInterval = 1.0

    private let client = BridgeClient()
    let softwareLightingEngine: SoftwareLightingEngine
    private var cachedDevices: [MouseDevice] = []
    private var cachedDevicesAt: Date?
    var cachedStateByDeviceID: [String: MouseState] = [:]
    private var cachedStateAtByDeviceID: [String: Date] = [:]
    private var softwareLightingStatusByDeviceID: [String: SoftwareLightingEngineStatus] = [:]
    private var usbControlAvailabilityByDeviceID: [String: USBControlAvailability] = [:]
    private var cachedFastByDeviceID: [String: DpiFastSnapshot] = [:]
    private var cachedFastAtByDeviceID: [String: Date] = [:]
    private var softwareLightingUSBReachabilityProbeAtByDeviceID: [String: Date] = [:]
    var reconnectSeedStateByDeviceID: [String: MouseState] = [:]
    private var bluetoothControlReadyDeviceIDs: Set<String> = []
    private let stateUpdatesStream = BroadcastStream<BackendStateUpdate>()
    private var devicePresenceRefreshTask: Task<Void, Never>?
    private var pendingUSBDisconnectRefreshTasks: [String: Task<Void, Never>] = [:]
    private var activeBluetoothWarmupKeys: Set<String> = []
    var softwareLightingReconnectReassertAtByDeviceKey: [String: Date] = [:]
    var softwareLightingReconnectReassertInFlightKeys: Set<String> = []
    private var activeApplyCount = 0
    private var maxConcurrentApplyCount = 0

    nonisolated var usesRemoteServiceTransport: Bool { false }

    init() {
        softwareLightingEngine = SoftwareLightingEngine(
            frameWriter: BridgeSoftwareLightingFrameWriter(client: client)
        )
        Task { [weak self] in
            guard let self else { return }
            let stream = await self.client.passiveDpiEventStream()
            for await event in stream {
                await self.handlePassiveDpiEvent(event)
            }
        }
        Task { [weak self] in
            guard let self else { return }
            let stream = await self.client.passiveDpiHeartbeatStream()
            for await event in stream {
                await self.handlePassiveDpiHeartbeat(event)
            }
        }
        Task { [weak self] in
            guard let self else { return }
            let stream = await self.client.passiveProfileSwitchEventStream()
            for await event in stream {
                await self.handlePassiveProfileSwitch(event)
            }
        }
        Task { [weak self] in
            guard let self else { return }
            let stream = await self.client.devicePresenceEventStream()
            for await event in stream {
                await self.handleDevicePresenceEvent(event)
            }
        }
        Task { [weak self] in
            guard let self else { return }
            let stream = await self.softwareLightingEngine.updates()
            for await status in stream {
                await self.handleSoftwareLightingStatus(status)
            }
        }
    }

    func listDevices() async throws -> [MouseDevice] {
        let startedAt = Date()
        if let cachedDevicesAt,
           Date().timeIntervalSince(cachedDevicesAt) < 1.0,
           !cachedDevices.isEmpty {
#if DEBUG
            OpenSnekUITestSupport.recordListDevices(
                cachedDevices,
                elapsed: Date().timeIntervalSince(startedAt),
                source: "local-cache"
            )
#endif
            return cachedDevices
        }
        do {
            let previousIDs = Set(cachedDevices.map(\.id))
            let devices = try await client.listDevices()
            updateCachedDevices(devices, updatedAt: Date(), publishUpdate: false)
            scheduleBluetoothWarmups(for: devices.filter { device in
                device.transport == .bluetooth && !previousIDs.contains(device.id)
            })
            publishSnapshotIfService()
#if DEBUG
            OpenSnekUITestSupport.recordListDevices(
                devices,
                elapsed: Date().timeIntervalSince(startedAt),
                source: "local"
            )
#endif
            return devices
        } catch {
#if DEBUG
            OpenSnekUITestSupport.recordListDevicesError(
                error,
                elapsed: Date().timeIntervalSince(startedAt),
                source: "local"
            )
#endif
            throw error
        }
    }

    func readState(device: MouseDevice) async throws -> MouseState {
        let readStartedAt = Date()
        let cachedStateBeforeRead = cachedStateByDeviceID[device.id]
        if shouldServeCachedTelemetryDuringSoftwareLighting(deviceID: device.id),
           let cached = cachedStateBeforeRead {
            try await verifyUSBReachabilityDuringSoftwareLightingIfNeeded(device: device, now: readStartedAt)
#if DEBUG
            OpenSnekUITestSupport.recordReadState(
                device: device,
                state: cached,
                elapsed: Date().timeIntervalSince(readStartedAt),
                source: "local-software-lighting-cache"
            )
#endif
            return cached
        }
        let shouldUseFastPolling = device.transport == .bluetooth
            ? await client.shouldUseFastDPIPolling(device: device)
            : true
        if let cachedAt = cachedStateAtByDeviceID[device.id],
           let cached = cachedStateByDeviceID[device.id] {
            if Self.shouldReuseCachedStateForRead(
                device: device,
                cachedAt: cachedAt,
                now: readStartedAt,
                shouldUseFastDPIPolling: shouldUseFastPolling
            ),
               !(device.transport == .usb && usbControlAvailabilityByDeviceID[device.id]?.blocksUSBControlInteraction == true) {
#if DEBUG
                OpenSnekUITestSupport.recordReadState(
                    device: device,
                    state: cached,
                    elapsed: Date().timeIntervalSince(readStartedAt),
                    source: "local-cache"
                )
#endif
                return cached
            }
        }

        let state: MouseState
        do {
            state = try await client.readState(device: device)
        } catch {
            if device.transport == .usb {
                let availability: USBControlAvailability
                if BridgeClient.isUSBTelemetryUnavailableError(error) {
                    availability = .receiverPresentMouseUnavailable
                } else if Self.isDeviceNotAvailableError(error) {
                    availability = .receiverAbsent
                } else {
                    availability = usbControlAvailabilityByDeviceID[device.id] ?? .unknown
                }
                if availability != .unknown {
                    recordUSBControlAvailability(availability, for: device.id, updatedAt: Date(), publishSnapshot: true)
                }
            }
            throw error
        }
        if device.transport == .usb {
            recordUSBControlAvailability(.receiverPresentMouseReachable, for: device.id, updatedAt: Date(), publishSnapshot: false)
        }
        if Self.completedReadWasSuperseded(startedAt: readStartedAt, latestCachedAt: cachedStateAtByDeviceID[device.id]),
           let cached = cachedStateByDeviceID[device.id] {
            if cached.differsOnlyInDynamicDpiState(from: cachedStateBeforeRead) {
                let merged = cached.mergedWithStableReadTelemetry(from: state)
                let now = Date()
                cachedStateByDeviceID[device.id] = merged
                cachedStateAtByDeviceID[device.id] = now
                reconnectSeedStateByDeviceID[device.id] = merged
                updateSoftwareLightingBatteryPercent(deviceID: device.id, from: merged)
                publishSnapshotIfService()
#if DEBUG
                OpenSnekUITestSupport.recordReadState(
                    device: device,
                    state: merged,
                    elapsed: Date().timeIntervalSince(readStartedAt),
                    source: "local-merged"
                )
#endif
                return merged
            }
            AppLog.debug(
                "Backend",
                "readState stale-result masked device=\(device.id) startedAt=\(readStartedAt.timeIntervalSince1970) " +
                "cachedAt=\(cachedStateAtByDeviceID[device.id]?.timeIntervalSince1970 ?? 0)"
            )
#if DEBUG
            OpenSnekUITestSupport.recordReadState(
                device: device,
                state: cached,
                elapsed: Date().timeIntervalSince(readStartedAt),
                source: "local-stale-mask"
            )
#endif
            return cached
        }
        if device.transport == .bluetooth,
           !shouldUseFastPolling,
           let cached = cachedStateByDeviceID[device.id] {
            let merged = cached.mergedWithStableReadTelemetry(from: state)
            let now = Date()
            cachedStateByDeviceID[device.id] = merged
            cachedStateAtByDeviceID[device.id] = now
            reconnectSeedStateByDeviceID[device.id] = merged
            updateSoftwareLightingBatteryPercent(deviceID: device.id, from: merged)
            publishSnapshotIfService()
            AppLog.debug(
                "Backend",
                "readState preserved passive BT DPI device=\(device.id) " +
                "cachedActive=\(cached.dpi_stages.active_stage.map(String.init) ?? "nil") " +
                "readActive=\(state.dpi_stages.active_stage.map(String.init) ?? "nil")"
            )
#if DEBUG
            OpenSnekUITestSupport.recordReadState(
                device: device,
                state: merged,
                elapsed: Date().timeIntervalSince(readStartedAt),
                source: "local-merged"
            )
#endif
            return merged
        }
        cachedStateByDeviceID[device.id] = state
        cachedStateAtByDeviceID[device.id] = Date()
        reconnectSeedStateByDeviceID[device.id] = state
        updateSoftwareLightingBatteryPercent(deviceID: device.id, from: state)
        publishSnapshotIfService()
#if DEBUG
        OpenSnekUITestSupport.recordReadState(
            device: device,
            state: state,
            elapsed: Date().timeIntervalSince(readStartedAt),
            source: "local"
        )
#endif
        return state
    }

    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot? {
        let readStartedAt = Date()
        if shouldServeCachedTelemetryDuringSoftwareLighting(deviceID: device.id) {
            try await verifyUSBReachabilityDuringSoftwareLightingIfNeeded(device: device, now: readStartedAt)
            if let cached = cachedFastByDeviceID[device.id] {
                return cached
            }
            if let cachedState = cachedStateByDeviceID[device.id],
               let active = cachedState.dpi_stages.active_stage,
               let values = cachedState.dpi_stages.values {
                return DpiFastSnapshot(active: active, values: values)
            }
        }
        let shouldUseFastPolling = await client.shouldUseFastDPIPolling(device: device)
        if let cachedAt = cachedFastAtByDeviceID[device.id],
           let cached = cachedFastByDeviceID[device.id],
           Self.shouldReuseCachedFastSnapshot(
            device: device,
            cachedAt: cachedAt,
            now: readStartedAt,
            shouldUseFastDPIPolling: shouldUseFastPolling
           ),
           !(device.transport == .usb && usbControlAvailabilityByDeviceID[device.id]?.blocksUSBControlInteraction == true) {
            return cached
        }
        let snapshot: (active: Int, values: [Int])?
        do {
            snapshot = try await client.readDpiStagesFast(device: device)
        } catch {
            if device.transport == .usb {
                if BridgeClient.isUSBTelemetryUnavailableError(error) {
                    recordUSBControlAvailability(
                        .receiverPresentMouseUnavailable,
                        for: device.id,
                        updatedAt: Date(),
                        publishSnapshot: true
                    )
                } else if Self.isDeviceNotAvailableError(error) {
                    recordUSBControlAvailability(
                        .receiverAbsent,
                        for: device.id,
                        updatedAt: Date(),
                        publishSnapshot: true
                    )
                }
            }
            throw error
        }
        guard let snapshot else { return nil }
        if device.transport == .usb {
            recordUSBControlAvailability(.receiverPresentMouseReachable, for: device.id, updatedAt: Date(), publishSnapshot: false)
        }
        if Self.completedReadWasSuperseded(startedAt: readStartedAt, latestCachedAt: cachedFastAtByDeviceID[device.id]),
           let cached = cachedFastByDeviceID[device.id] {
            AppLog.debug(
                "Backend",
                "readDpiFast stale-result masked device=\(device.id) startedAt=\(readStartedAt.timeIntervalSince1970) " +
                "cachedAt=\(cachedFastAtByDeviceID[device.id]?.timeIntervalSince1970 ?? 0)"
            )
            return cached
        }
        let fast = DpiFastSnapshot(active: snapshot.active, values: snapshot.values)
        cachedFastByDeviceID[device.id] = fast
        cachedFastAtByDeviceID[device.id] = Date()
        if updateCachedStateFromFastSnapshot(fast, for: device.id) != nil {
            publishSnapshotIfService()
        }
        return fast
    }

    func shouldUseFastDPIPolling(device: MouseDevice) async -> Bool {
        await client.shouldUseFastDPIPolling(device: device)
    }

    func usbControlAvailability(device: MouseDevice) async throws -> USBControlAvailability {
        guard device.transport == .usb else { return .unknown }
        let availability = try await client.usbControlAvailability(device: device)
        recordUSBControlAvailability(availability, for: device.id, updatedAt: Date(), publishSnapshot: true)
        return availability
    }

    func dpiUpdateTransportStatus(device: MouseDevice) async -> DpiUpdateTransportStatus {
        await client.dpiUpdateTransportStatus(device: device)
    }

    func hidAccessStatus() async -> HIDAccessStatus {
        await hidAccessStatus(forceRefresh: true)
    }

    func hidAccessStatus(forceRefresh: Bool) async -> HIDAccessStatus {
        let status = await client.hidAccessStatus(forceRefresh: forceRefresh)
#if DEBUG
        OpenSnekUITestSupport.recordHIDAccessStatus(status, source: "local")
#endif
        return status
    }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        stateUpdatesStream.makeStream()
    }

    func apply(device: MouseDevice, patch: DevicePatch, options: ApplyOptions) async throws -> MouseState {
        let startedAt = Date()
        activeApplyCount += 1
        maxConcurrentApplyCount = max(maxConcurrentApplyCount, activeApplyCount)
#if DEBUG
        OpenSnekUITestSupport.recordApplyStart(
            UITestApplyEvent(
                device: device,
                patch: patch,
                state: nil,
                activeApplyCount: activeApplyCount,
                maxConcurrentApplyCount: maxConcurrentApplyCount,
                elapsed: nil,
                readbackPolicy: options.readbackPolicy.rawValue,
                error: nil
            )
        )
        if activeApplyCount > 1 {
            OpenSnekUITestSupport.recordOverlapDetected(
                device: device,
                patch: patch,
                activeApplyCount: activeApplyCount,
                maxConcurrentApplyCount: maxConcurrentApplyCount
            )
        }
#endif
        defer {
            activeApplyCount -= 1
        }

        let state: MouseState
        do {
            state = try await client.apply(device: device, patch: patch, options: options)
        } catch {
#if DEBUG
            OpenSnekUITestSupport.recordApplyError(
                UITestApplyEvent(
                    device: device,
                    patch: patch,
                    state: nil,
                    activeApplyCount: activeApplyCount,
                    maxConcurrentApplyCount: maxConcurrentApplyCount,
                    elapsed: Date().timeIntervalSince(startedAt),
                    readbackPolicy: options.readbackPolicy.rawValue,
                    error: error
                )
            )
#endif
            throw error
        }
        let merged = Self.mergedApplyState(
            state,
            previous: cachedStateByDeviceID[device.id] ?? reconnectSeedStateByDeviceID[device.id]
        )
        let now = Date()
        cachedStateByDeviceID[device.id] = merged
        cachedStateAtByDeviceID[device.id] = now
        reconnectSeedStateByDeviceID[device.id] = merged
        updateSoftwareLightingBatteryPercent(deviceID: device.id, from: merged)
        if let values = merged.dpi_stages.values,
           let active = merged.dpi_stages.active_stage {
            let fast = DpiFastSnapshot(active: active, values: values)
            cachedFastByDeviceID[device.id] = fast
            cachedFastAtByDeviceID[device.id] = now
        }
        publishSnapshotIfService()
#if DEBUG
        OpenSnekUITestSupport.recordApplyEnd(
            UITestApplyEvent(
                device: device,
                patch: patch,
                state: merged,
                activeApplyCount: activeApplyCount,
                maxConcurrentApplyCount: maxConcurrentApplyCount,
                elapsed: Date().timeIntervalSince(startedAt),
                readbackPolicy: options.readbackPolicy.rawValue,
                error: nil
            )
        )
#endif
        return merged
    }

    func listOnboardProfiles(device: MouseDevice) async throws -> OnboardProfileInventory {
        try await client.listOnboardProfiles(device: device)
    }

    func readOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot {
        let snapshot = try await client.readOnboardProfile(device: device, profileID: profileID)
        await cacheActiveOnboardProfileSnapshotIfCurrent(snapshot, device: device, source: "readOnboardProfile")
        return snapshot
    }

    func readOnboardProfileCore(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot {
        let snapshot = try await client.readOnboardProfileCore(device: device, profileID: profileID)
        await cacheActiveOnboardProfileSnapshotIfCurrent(snapshot, device: device, source: "readOnboardProfileCore")
        return snapshot
    }

    func readOnboardProfileButtonBindings(device: MouseDevice, profileID: Int) async throws -> [Int: ButtonBindingDraft] {
        try await client.readOnboardProfileButtonBindings(device: device, profileID: profileID)
    }

    func createOnboardProfile(
        device: MouseDevice,
        mutation: OnboardProfileMutation,
        targetProfileID: Int?,
        replaceAssignedProfile: Bool
    ) async throws -> OnboardProfileSnapshot {
        try await client.createOnboardProfile(
            device: device,
            mutation: mutation,
            targetProfileID: targetProfileID,
            replaceAssignedProfile: replaceAssignedProfile
        )
    }

    func renameOnboardProfile(device: MouseDevice, profileID: Int, name: String) async throws -> OnboardProfileSnapshot {
        try await client.renameOnboardProfile(device: device, profileID: profileID, name: name)
    }

    func updateOnboardProfile(
        device: MouseDevice,
        profileID: Int,
        mutation: OnboardProfileMutation
    ) async throws -> OnboardProfileSnapshot {
        try await client.updateOnboardProfile(device: device, profileID: profileID, mutation: mutation)
    }

    func projectOnboardProfileDPIToActiveLayer(device: MouseDevice, profileID: Int, dpi: OnboardDPIProfileSnapshot) async throws -> Bool {
        try await client.projectOnboardProfileDPIToActiveLayer(device: device, profileID: profileID, dpi: dpi)
    }

    func deleteOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileInventory {
        try await client.deleteOnboardProfile(device: device, profileID: profileID)
    }

    func activateOnboardProfile(device: MouseDevice, profileID: Int) async throws -> MouseState {
        let state = try await client.activateOnboardProfile(device: device, profileID: profileID)
        let merged = cacheAndPublishState(state, for: device.id, updatedAt: Date())
        await reassertSoftwareLightingAfterProfileChange(device: device, state: merged)
        return merged
    }

    func refreshActiveOnboardProfile(device: MouseDevice) async throws -> MouseState {
        let state = try await client.refreshActiveOnboardProfile(device: device)
        cacheAndPublishState(state, for: device.id, updatedAt: Date())
        return state
    }

    private func cacheActiveOnboardProfileSnapshotIfCurrent(
        _ snapshot: OnboardProfileSnapshot,
        device: MouseDevice,
        source: String
    ) async {
        guard snapshot.profileID > 0,
              let active = cachedStateByDeviceID[device.id]?.active_onboard_profile
                ?? reconnectSeedStateByDeviceID[device.id]?.active_onboard_profile,
              active == snapshot.profileID else {
            return
        }

        do {
            let profile = try await client.mappedOnboardProfileSupport(for: device)
            let state = await client.storeProjectedActiveOnboardProfileState(
                device: device,
                profile: profile,
                activeProfileID: active,
                snapshot: snapshot
            )
            cacheAndPublishState(state, for: device.id, updatedAt: Date())
            AppLog.debug(
                "Backend",
                "cached active onboard profile snapshot source=\(source) device=\(device.id) " +
                    "profile=\(snapshot.profileID) dpiCount=\(snapshot.dpi?.stageCount ?? 0) " +
                    "dpiValues=\(snapshot.dpi?.values.map(String.init).joined(separator: ",") ?? "<none>")"
            )
        } catch {
            AppLog.debug(
                "Backend",
                "active onboard profile snapshot cache skipped source=\(source) device=\(device.id) " +
                    "profile=\(snapshot.profileID): \(error.localizedDescription)"
            )
        }
    }

    private func restoreOnDeviceLightingAfterSoftwareLightingStop(device: MouseDevice) async {
        let cachedState = cachedStateByDeviceID[device.id] ?? reconnectSeedStateByDeviceID[device.id]
        let cachedProfileID = cachedState?.active_onboard_profile
        let onboardProfileCount = max(1, cachedState?.onboard_profile_count ?? device.onboard_profile_count)
        let activeProfileID: Int

        if let cachedProfileID {
            activeProfileID = cachedProfileID
        } else {
            do {
                let state = try await client.refreshActiveOnboardProfile(device: device)
                cacheAndPublishState(state, for: device.id, updatedAt: Date())
                guard let refreshedProfileID = state.active_onboard_profile else {
                    AppLog.debug(
                        "Backend",
                        "software lighting stop skipped onboard restore: no active profile for device=\(device.id)"
                    )
                    return
                }
                activeProfileID = refreshedProfileID
            } catch {
                AppLog.warning(
                    "Backend",
                    "software lighting stop active-profile refresh failed device=\(device.id): \(error.localizedDescription)"
                )
                return
            }
        }

        guard activeProfileID >= 1, activeProfileID <= onboardProfileCount else {
            AppLog.debug(
                "Backend",
                "software lighting stop skipped onboard restore: active profile \(activeProfileID) outside 1...\(onboardProfileCount) for device=\(device.id)"
            )
            return
        }

        do {
            let snapshot = try await client.readOnboardProfileCore(device: device, profileID: activeProfileID)
            let mutation = OnboardProfileMutation(
                brightnessByLEDID: snapshot.brightnessByLEDID.isEmpty ? nil : snapshot.brightnessByLEDID,
                staticColorByLEDID: snapshot.staticColorByLEDID.isEmpty ? nil : snapshot.staticColorByLEDID
            )
            if !mutation.isEmpty {
                _ = try await client.updateOnboardProfile(
                    device: device,
                    profileID: activeProfileID,
                    mutation: mutation
                )
            }
            let state = try await client.activateOnboardProfile(device: device, profileID: activeProfileID)
            cacheAndPublishState(state, for: device.id, updatedAt: Date())
        } catch {
            AppLog.warning(
                "Backend",
                "software lighting stop onboard restore failed device=\(device.id) profile=\(activeProfileID): \(error.localizedDescription)"
            )
        }
    }

    func readLightingColor(device: MouseDevice) async throws -> RGBPatch? {
        try await client.readLightingColor(device: device)
    }

    func startSoftwareLighting(
        device: MouseDevice,
        request: SoftwareLightingEffectRequest
    ) async throws -> SoftwareLightingEngineStatus {
        let batteryPercent = cachedStateByDeviceID[device.id]?.battery_percent
            ?? reconnectSeedStateByDeviceID[device.id]?.battery_percent
        let status = try await softwareLightingEngine.start(
            device: device,
            request: request,
            batteryPercent: batteryPercent
        )
        handleSoftwareLightingStatus(status)
        return status
    }

    func stopSoftwareLighting(deviceID: String) async -> SoftwareLightingEngineStatus? {
        let status = await softwareLightingEngine.stop(deviceID: deviceID)
        if let status {
            handleSoftwareLightingStatus(status)
        }
        return status
    }

    func stopSoftwareLighting(device: MouseDevice) async -> SoftwareLightingEngineStatus? {
        let status = await softwareLightingEngine.stop(deviceID: device.id)
        if let status {
            handleSoftwareLightingStatus(status)
        }
        await restoreOnDeviceLightingAfterSoftwareLightingStop(device: device)
        return status
    }

    func stopAllSoftwareLighting() async -> [SoftwareLightingEngineStatus] {
        let statuses = await softwareLightingEngine.stopAll()
        for status in statuses {
            handleSoftwareLightingStatus(status)
        }
        return statuses
    }

    func softwareLightingStatus(deviceID: String) async -> SoftwareLightingEngineStatus? {
        await softwareLightingEngine.status(deviceID: deviceID)
    }

    func debugUSBReadButtonBinding(device: MouseDevice, slot: Int, profile: Int) async throws -> [UInt8]? {
        try await client.debugUSBReadButtonBinding(device: device, slot: slot, profile: profile)
    }

    private func handleDevicePresenceEvent(_ event: HIDDevicePresenceEvent) {
        if event.transport == .usb {
            if event.change == .connected {
                pendingUSBDisconnectRefreshTasks.removeValue(forKey: event.deviceID)?.cancel()
                invalidateCachedTelemetry(for: event.deviceID)
                recordUSBControlAvailability(
                    .unknown,
                    for: event.deviceID,
                    updatedAt: event.observedAt,
                    publishSnapshot: true
                )
                devicePresenceRefreshTask?.cancel()
                devicePresenceRefreshTask = Task { [weak self] in
                    guard let self, !Task.isCancelled else { return }
                    await self.refreshCachedDevicesAfterPresenceChange(observedAt: event.observedAt, event: event)
                }
            } else {
                scheduleUSBDisconnectRefresh(for: event)
            }
            return
        }

        invalidateCachedTelemetry(for: event.deviceID)
        scheduleBluetoothWarmup(for: event)
        devicePresenceRefreshTask?.cancel()
        devicePresenceRefreshTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.refreshCachedDevicesAfterPresenceChange(observedAt: event.observedAt, event: event)

            guard event.transport == .bluetooth, event.change == .connected else { return }

            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await self.refreshCachedDevicesAfterPresenceChange(observedAt: Date(), event: event)
        }
    }

    private func scheduleUSBDisconnectRefresh(for event: HIDDevicePresenceEvent) {
        pendingUSBDisconnectRefreshTasks.removeValue(forKey: event.deviceID)?.cancel()
        pendingUSBDisconnectRefreshTasks[event.deviceID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.usbDisconnectDebounceInterval * 1_000_000_000))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            await self.finishUSBDisconnectRefresh(for: event)
        }
    }

    private func finishUSBDisconnectRefresh(for event: HIDDevicePresenceEvent) async {
        guard pendingUSBDisconnectRefreshTasks[event.deviceID] != nil else { return }
        pendingUSBDisconnectRefreshTasks[event.deviceID] = nil
        devicePresenceRefreshTask?.cancel()
        devicePresenceRefreshTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            await self.refreshCachedDevicesAfterPresenceChange(observedAt: Date(), event: event)
        }
    }

    private func scheduleBluetoothWarmup(for event: HIDDevicePresenceEvent) {
        guard event.transport == .bluetooth, event.change == .connected else { return }
        guard let preferredPeripheralName = BridgeClient.preferredBluetoothControlWarmupName(
            vendorID: event.vendorID,
            productID: event.productID,
            transport: event.transport
        ) else {
            return
        }
        scheduleBluetoothWarmup(
            deviceID: event.deviceID,
            preferredPeripheralName: preferredPeripheralName
        )
    }

    private func scheduleBluetoothWarmups(for devices: [MouseDevice]) {
        for device in devices where device.transport == .bluetooth {
            scheduleBluetoothWarmup(
                deviceID: device.id,
                preferredPeripheralName: device.product_name
            )
        }
    }

    private func scheduleBluetoothWarmup(
        deviceID: String? = nil,
        preferredPeripheralName: String?
    ) {
        let normalizedKey = deviceID ?? preferredPeripheralName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "*"
        guard activeBluetoothWarmupKeys.insert(normalizedKey).inserted else { return }

        let client = self.client
        Task { [deviceID, preferredPeripheralName, normalizedKey] in
            let warmed = await client.prepareBluetoothControlConnection(
                preferredPeripheralName: preferredPeripheralName
            )
            self.finishBluetoothWarmup(
                key: normalizedKey,
                deviceID: deviceID,
                warmed: warmed
            )
        }
    }

    private func finishBluetoothWarmup(
        key: String,
        deviceID: String?,
        warmed: Bool
    ) {
        activeBluetoothWarmupKeys.remove(key)
        guard warmed, let deviceID else { return }
        bluetoothControlReadyDeviceIDs.insert(deviceID)
        promoteReconnectSeedIfAvailable(deviceID: deviceID)
    }

    private func promoteReconnectSeedIfAvailable(deviceID: String, updatedAt: Date = Date()) {
        guard bluetoothControlReadyDeviceIDs.contains(deviceID) else { return }
        guard cachedDevices.contains(where: { $0.id == deviceID }) else { return }
        guard let seed = reconnectSeedStateByDeviceID[deviceID] else { return }

        cachedStateByDeviceID[deviceID] = seed
        cachedStateAtByDeviceID[deviceID] = updatedAt
        bluetoothControlReadyDeviceIDs.remove(deviceID)
        publishStateUpdate(.deviceState(deviceID: deviceID, state: seed, updatedAt: updatedAt))
        publishSnapshotIfService()
    }

    @discardableResult
    private func updateCachedStateFromFastSnapshot(_ snapshot: DpiFastSnapshot, for deviceID: String) -> MouseState? {
        guard let previous = cachedStateByDeviceID[deviceID], !snapshot.values.isEmpty else { return nil }
        let active = max(0, min(snapshot.values.count - 1, snapshot.active))
        let currentStagePairs = BridgeClient.resolveDpiStagePairs(
            values: snapshot.values,
            pairs: nil,
            fallbackPairs: previous.dpi_stages.pairs
        )
        let currentDpi = currentStagePairs?[active] ?? DpiPair(x: snapshot.values[active], y: snapshot.values[active])
        let updated = MouseState(
            device: previous.device,
            connection: previous.connection,
            battery_percent: previous.battery_percent,
            charging: previous.charging,
            dpi: currentDpi,
            dpi_stages: DpiStages(
                active_stage: active,
                values: snapshot.values,
                pairs: currentStagePairs
            ),
            poll_rate: previous.poll_rate,
            sleep_timeout: previous.sleep_timeout,
            device_mode: previous.device_mode,
            low_battery_threshold_raw: previous.low_battery_threshold_raw,
            scroll_mode: previous.scroll_mode,
            scroll_acceleration: previous.scroll_acceleration,
            scroll_smart_reel: previous.scroll_smart_reel,
            active_onboard_profile: previous.active_onboard_profile,
            onboard_profile_count: previous.onboard_profile_count,
            led_value: previous.led_value,
            capabilities: previous.capabilities
        )
        guard updated != previous else { return nil }
        cachedStateByDeviceID[deviceID] = updated
        reconnectSeedStateByDeviceID[deviceID] = updated
        return updated
    }

    private func handlePassiveDpiEvent(_ event: PassiveDPIEvent) async {
        let previousState: MouseState?
        if let cached = cachedStateByDeviceID[event.deviceID] {
            previousState = cached
        } else if let reconnectSeed = reconnectSeedStateByDeviceID[event.deviceID] {
            previousState = reconnectSeed
        } else if let device = cachedDevices.first(where: { $0.id == event.deviceID }) {
            previousState = Self.seededStateForPassiveDpiEvent(
                device: device,
                event: event,
                fastSnapshot: cachedFastByDeviceID[event.deviceID]
            )
        } else {
            previousState = nil
        }

        guard let updated = mergedStateFromPassiveDpiEvent(
            previous: previousState,
            event: event
        ) else {
            AppLog.warning(
                "DPITrace",
                "backend passiveDpi ignored device=\(event.deviceID) dpi=\(event.dpiX)x\(event.dpiY) previous={\(AppStateEditorController.diagnosticDPIState(previousState))}"
            )
            return
        }
        AppLog.warning(
            "DPITrace",
            "backend passiveDpi merged device=\(event.deviceID) dpi=\(event.dpiX)x\(event.dpiY) previous={\(AppStateEditorController.diagnosticDPIState(previousState))} updated={\(AppStateEditorController.diagnosticDPIState(updated))}"
        )

        cachedStateByDeviceID[event.deviceID] = updated
        cachedStateAtByDeviceID[event.deviceID] = event.observedAt
        reconnectSeedStateByDeviceID[event.deviceID] = updated
        if cachedDevices.first(where: { $0.id == event.deviceID })?.transport == .usb {
            recordUSBControlAvailability(
                .receiverPresentMouseReachable,
                for: event.deviceID,
                updatedAt: event.observedAt,
                publishSnapshot: false
            )
        }
        let needsDirectActiveRead = Self.passiveDpiEventHasAmbiguousStageMatch(previous: previousState, event: event)
        let fastActive = updated.dpi_stages.active_stage ?? cachedFastByDeviceID[event.deviceID]?.active ?? 0
        if let values = updated.dpi_stages.values {
            if needsDirectActiveRead {
                cachedFastByDeviceID.removeValue(forKey: event.deviceID)
                cachedFastAtByDeviceID.removeValue(forKey: event.deviceID)
            } else {
                cachedFastByDeviceID[event.deviceID] = DpiFastSnapshot(active: fastActive, values: values)
                cachedFastAtByDeviceID[event.deviceID] = event.observedAt
            }
        }

        if needsDirectActiveRead,
           let device = cachedDevices.first(where: { $0.id == event.deviceID }) {
            do {
                if let snapshot = try await client.readDpiStagesFast(device: device) {
                    let fast = DpiFastSnapshot(active: snapshot.active, values: snapshot.values)
                    let readAt = Date()
                    cachedFastByDeviceID[event.deviceID] = fast
                    cachedFastAtByDeviceID[event.deviceID] = readAt
                    if device.transport == .usb {
                        recordUSBControlAvailability(
                            .receiverPresentMouseReachable,
                            for: event.deviceID,
                            updatedAt: readAt,
                            publishSnapshot: false
                        )
                    }
                    if let precise = updateCachedStateFromFastSnapshot(fast, for: event.deviceID) {
                        AppLog.warning(
                            "DPITrace",
                            "backend passiveDpi precise-read device=\(event.deviceID) fastActive=\(fast.active + 1) fastValues=\(fast.values.map(String.init).joined(separator: ",")) precise={\(AppStateEditorController.diagnosticDPIState(precise))}"
                        )
                        publishStateUpdate(.deviceState(deviceID: event.deviceID, state: precise, updatedAt: readAt))
                        publishSnapshotIfService()
                        return
                    }
                }
            } catch {
                AppLog.debug(
                    "Backend",
                    "passive DPI ambiguous active-stage read failed device=\(event.deviceID): \(error.localizedDescription)"
                )
            }
        }

        publishStateUpdate(.deviceState(deviceID: event.deviceID, state: updated, updatedAt: event.observedAt))
        publishSnapshotIfService()
    }

    private func handlePassiveDpiHeartbeat(_ event: PassiveDPIHeartbeatEvent) {
        if cachedDevices.first(where: { $0.id == event.deviceID })?.transport == .usb {
            recordUSBControlAvailability(
                .receiverPresentMouseReachable,
                for: event.deviceID,
                updatedAt: event.observedAt,
                publishSnapshot: false
            )
        }
        publishStateUpdate(
            .dpiTransportStatus(
                deviceID: event.deviceID,
                status: .streamActive,
                updatedAt: event.observedAt
            )
        )
    }

    private func handlePassiveProfileSwitch(_ event: PassiveProfileSwitchEvent) async {
        guard let device = cachedDevices.first(where: { $0.id == event.deviceID }) else { return }
        do {
            AppLog.warning(
                "DPITrace",
                "backend passiveProfileSwitch refresh start device=\(event.deviceID)"
            )
            let state = try await client.refreshActiveOnboardProfile(device: device)
            AppLog.warning(
                "DPITrace",
                "backend passiveProfileSwitch refresh read device=\(event.deviceID) state={\(AppStateEditorController.diagnosticDPIState(state))}"
            )
            let merged = cacheAndPublishState(state, for: event.deviceID, updatedAt: event.observedAt)
            AppLog.warning(
                "DPITrace",
                "backend passiveProfileSwitch published device=\(event.deviceID) merged={\(AppStateEditorController.diagnosticDPIState(merged))}"
            )
            await reassertSoftwareLightingAfterProfileChange(device: device, state: merged)
        } catch {
            AppLog.warning(
                "Backend",
                "passive profile switch refresh failed device=\(event.deviceID): \(error.localizedDescription)"
            )
        }
    }

    func handleSoftwareLightingStatus(_ status: SoftwareLightingEngineStatus) {
        let previousStatus = softwareLightingStatusByDeviceID[status.deviceID]
        softwareLightingStatusByDeviceID[status.deviceID] = status
        if previousStatus != status {
            AppLog.event(
                "LightingTrace",
                "backend software lighting status device=\(status.deviceID) " +
                    "previous=\(SoftwareLightingDiagnostics.statusSummary(previousStatus)) " +
                    "next=\(SoftwareLightingDiagnostics.statusSummary(status))"
            )
        }
        publishStateUpdate(
            .softwareLightingStatus(
                deviceID: status.deviceID,
                status: status,
                updatedAt: status.updatedAt
            )
        )
        publishSnapshotIfService()
    }

    private func shouldServeCachedTelemetryDuringSoftwareLighting(deviceID: String) -> Bool {
        softwareLightingStatusByDeviceID[deviceID]?.state == .running
    }

    private func verifyUSBReachabilityDuringSoftwareLightingIfNeeded(device: MouseDevice, now: Date) async throws {
        guard device.transport == .usb else { return }
        if let lastProbeAt = softwareLightingUSBReachabilityProbeAtByDeviceID[device.id],
           now.timeIntervalSince(lastProbeAt) < Self.softwareLightingUSBReachabilityProbeInterval,
           usbControlAvailabilityByDeviceID[device.id] == .receiverPresentMouseReachable {
            return
        }

        let availability = try await client.usbControlAvailability(device: device)
        let previousAvailability = usbControlAvailabilityByDeviceID[device.id]
        softwareLightingUSBReachabilityProbeAtByDeviceID[device.id] = now
        recordUSBControlAvailability(availability, for: device.id, updatedAt: now, publishSnapshot: true)

        switch availability {
        case .receiverPresentMouseReachable:
            if previousAvailability != .receiverPresentMouseReachable {
                await reassertRunningSoftwareLightingAfterReconnect(
                    device: device,
                    reason: "usbReachability"
                )
            }
            return
        case .unknown:
            return
        case .receiverPresentMouseUnavailable:
            throw BridgeError.usbMouseUnavailable
        case .receiverAbsent:
            throw BridgeError.commandFailed("Device not available")
        }
    }

    @discardableResult
    private func cacheAndPublishState(_ state: MouseState, for deviceID: String, updatedAt: Date) -> MouseState {
        let merged = Self.mergedApplyState(
            state,
            previous: cachedStateByDeviceID[deviceID] ?? reconnectSeedStateByDeviceID[deviceID]
        )
        cachedStateByDeviceID[deviceID] = merged
        cachedStateAtByDeviceID[deviceID] = updatedAt
        reconnectSeedStateByDeviceID[deviceID] = merged
        updateSoftwareLightingBatteryPercent(deviceID: deviceID, from: merged)
        if merged.device.transport == .usb {
            recordUSBControlAvailability(.receiverPresentMouseReachable, for: deviceID, updatedAt: updatedAt, publishSnapshot: false)
        }
        if let values = merged.dpi_stages.values,
           let active = merged.dpi_stages.active_stage {
            cachedFastByDeviceID[deviceID] = DpiFastSnapshot(active: active, values: values)
            cachedFastAtByDeviceID[deviceID] = updatedAt
        }
        publishStateUpdate(.deviceState(deviceID: deviceID, state: merged, updatedAt: updatedAt))
        publishSnapshotIfService()
        return merged
    }

    private func updateSoftwareLightingBatteryPercent(deviceID: String, from state: MouseState) {
        Task { [softwareLightingEngine, batteryPercent = state.battery_percent] in
            await softwareLightingEngine.updateBatteryPercent(deviceID: deviceID, batteryPercent: batteryPercent)
        }
    }

    private func recordUSBControlAvailability(
        _ availability: USBControlAvailability,
        for deviceID: String,
        updatedAt: Date,
        publishSnapshot: Bool
    ) {
        guard usbControlAvailabilityByDeviceID[deviceID] != availability else {
            if publishSnapshot {
                publishSnapshotIfService()
            }
            return
        }
        usbControlAvailabilityByDeviceID[deviceID] = availability
        AppLog.debug(
            "Backend",
            "usbControlAvailability device=\(deviceID) availability=\(availability.rawValue)"
        )
        publishStateUpdate(.usbControlAvailability(deviceID: deviceID, availability: availability, updatedAt: updatedAt))
        if publishSnapshot {
            publishSnapshotIfService()
        }
    }

    private func publishStateUpdate(_ update: BackendStateUpdate) {
        stateUpdatesStream.yield(update)
    }

    private func refreshCachedDevicesAfterPresenceChange(
        observedAt: Date,
        event: HIDDevicePresenceEvent? = nil
    ) async {
        do {
            let previousIDs = Set(cachedDevices.map(\.id))
            let devices = try await client.listDevices()
            updateCachedDevices(devices, updatedAt: observedAt, publishUpdate: true)
            let bluetoothDevicesToWarm: [MouseDevice]
            if let event,
               event.transport == .bluetooth,
               event.change == .connected,
               let eventDevice = devices.first(where: { $0.id == event.deviceID }) {
                bluetoothDevicesToWarm = [eventDevice]
            } else {
                bluetoothDevicesToWarm = devices.filter { device in
                    device.transport == .bluetooth && !previousIDs.contains(device.id)
                }
            }
            scheduleBluetoothWarmups(for: bluetoothDevicesToWarm)
            for device in bluetoothDevicesToWarm {
                promoteReconnectSeedIfAvailable(deviceID: device.id, updatedAt: observedAt)
            }
            if event?.change == .connected {
                await reassertRunningSoftwareLightingAfterPresenceReconnect(
                    event: event,
                    devices: devices
                )
            }
            publishSnapshotIfService()
        } catch {
            AppLog.warning(
                "Backend",
                "device presence refresh failed: \(error.localizedDescription)"
            )
        }
    }

    private func updateCachedDevices(
        _ devices: [MouseDevice],
        updatedAt: Date,
        publishUpdate: Bool
    ) {
        let previousIDs = Set(cachedDevices.map(\.id))
        let nextIDs = Set(devices.map(\.id))
        purgeCaches(forRemovedDeviceIDs: previousIDs.subtracting(nextIDs))
        cachedDevices = devices
        cachedDevicesAt = updatedAt
        if publishUpdate {
            publishStateUpdate(.deviceList(devices, updatedAt: updatedAt))
        }
        resumeSuspendedSoftwareLighting(for: devices)
    }

    private func invalidateCachedTelemetry(for deviceID: String) {
        if let cached = cachedStateByDeviceID[deviceID] {
            reconnectSeedStateByDeviceID[deviceID] = cached
        }
        cachedDevicesAt = nil
        cachedStateByDeviceID.removeValue(forKey: deviceID)
        cachedStateAtByDeviceID.removeValue(forKey: deviceID)
        cachedFastByDeviceID.removeValue(forKey: deviceID)
        cachedFastAtByDeviceID.removeValue(forKey: deviceID)
        softwareLightingUSBReachabilityProbeAtByDeviceID.removeValue(forKey: deviceID)
        bluetoothControlReadyDeviceIDs.remove(deviceID)
    }

    private func purgeCaches(forRemovedDeviceIDs removedDeviceIDs: Set<String>) {
        guard !removedDeviceIDs.isEmpty else { return }
        for deviceID in removedDeviceIDs {
            cachedStateByDeviceID.removeValue(forKey: deviceID)
            cachedStateAtByDeviceID.removeValue(forKey: deviceID)
            cachedFastByDeviceID.removeValue(forKey: deviceID)
            cachedFastAtByDeviceID.removeValue(forKey: deviceID)
            softwareLightingUSBReachabilityProbeAtByDeviceID.removeValue(forKey: deviceID)
            usbControlAvailabilityByDeviceID.removeValue(forKey: deviceID)
            Task { [softwareLightingEngine] in
                _ = await softwareLightingEngine.suspend(deviceID: deviceID, message: "Device disconnected")
            }
        }
    }

    private func resumeSuspendedSoftwareLighting(for devices: [MouseDevice]) {
        guard !devices.isEmpty else { return }
        Task { [softwareLightingEngine] in
            for device in devices {
                _ = try? await softwareLightingEngine.resumeIfNeeded(device: device)
            }
        }
    }

    private func publishSnapshotIfService() {
        guard OpenSnekProcessRole.current.isService else { return }
        let liveIDs = Set(cachedDevices.map(\.id))
        publishStateUpdate(
            .snapshot(
                SharedServiceSnapshot(
                    devices: cachedDevices,
                    stateByDeviceID: cachedStateByDeviceID.filter { liveIDs.contains($0.key) },
                    lastUpdatedByDeviceID: cachedStateAtByDeviceID.filter { liveIDs.contains($0.key) },
                    observedAtByDeviceID: latestObservedAtByDeviceID(liveIDs: liveIDs),
                    softwareLightingStatusByDeviceID: softwareLightingStatusByDeviceID.filter { liveIDs.contains($0.key) },
                    usbControlAvailabilityByDeviceID: usbControlAvailabilityByDeviceID.filter { liveIDs.contains($0.key) }
                )
            )
        )
    }

    private func latestObservedAtByDeviceID(liveIDs: Set<String>) -> [String: Date] {
        var observedAtByDeviceID = cachedStateAtByDeviceID.filter { liveIDs.contains($0.key) }
        for (deviceID, fastAt) in cachedFastAtByDeviceID where liveIDs.contains(deviceID) {
            if let existing = observedAtByDeviceID[deviceID] {
                observedAtByDeviceID[deviceID] = max(existing, fastAt)
            } else {
                observedAtByDeviceID[deviceID] = fastAt
            }
        }
        return observedAtByDeviceID
    }
}
