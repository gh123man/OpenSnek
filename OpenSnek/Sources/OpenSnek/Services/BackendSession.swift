import Foundation
import Network
import OpenSnekCore
import OpenSnekHardware

enum OpenSnekProcessRole: String, Sendable {
    case app
    case service

    static var current: OpenSnekProcessRole {
        ProcessInfo.processInfo.arguments.contains("--service-mode") ? .service : .app
    }

    var isService: Bool {
        self == .service
    }
}

protocol DeviceBackend: AnyObject, Sendable {
    var usesRemoteServiceTransport: Bool { get }
    func listDevices() async throws -> [MouseDevice]
    func readState(device: MouseDevice) async throws -> MouseState
    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot?
    func shouldUseFastDPIPolling(device: MouseDevice) async -> Bool
    func dpiUpdateTransportStatus(device: MouseDevice) async -> DpiUpdateTransportStatus
    func hidAccessStatus() async -> HIDAccessStatus
    func stateUpdates() async -> AsyncStream<BackendStateUpdate>
    func updateRemoteClientPresence(sourceProcessID: Int32, selectedDeviceID: String?) async
    func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState
    func listOnboardProfiles(device: MouseDevice) async throws -> OnboardProfileInventory
    func readOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot
    func readOnboardProfileCore(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot
    func readOnboardProfileButtonBindings(device: MouseDevice, profileID: Int) async throws -> [Int: ButtonBindingDraft]
    func createOnboardProfile(
        device: MouseDevice,
        mutation: OnboardProfileMutation,
        targetProfileID: Int?,
        replaceAssignedProfile: Bool
    ) async throws -> OnboardProfileSnapshot
    func renameOnboardProfile(device: MouseDevice, profileID: Int, name: String) async throws -> OnboardProfileSnapshot
    func updateOnboardProfile(
        device: MouseDevice,
        profileID: Int,
        mutation: OnboardProfileMutation
    ) async throws -> OnboardProfileSnapshot
    func deleteOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileInventory
    func activateOnboardProfile(device: MouseDevice, profileID: Int) async throws -> MouseState
    func refreshActiveOnboardProfile(device: MouseDevice) async throws -> MouseState
    func readLightingColor(device: MouseDevice) async throws -> RGBPatch?
    func debugUSBReadButtonBinding(device: MouseDevice, slot: Int, profile: Int) async throws -> [UInt8]?
}

protocol HIDAccessRefreshControllingBackend: DeviceBackend {
    func hidAccessStatus(forceRefresh: Bool) async -> HIDAccessStatus
}

extension ApplyOptionsSupportingBackend {
    func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState {
        try await apply(device: device, patch: patch, options: ApplyOptions())
    }
}

final actor BootstrapPendingBackend: DeviceBackend {
    nonisolated static let shared = BootstrapPendingBackend()

    nonisolated var usesRemoteServiceTransport: Bool { false }

    func listDevices() async throws -> [MouseDevice] { [] }

    func readState(device _: MouseDevice) async throws -> MouseState {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? { nil }

    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool { true }

    func dpiUpdateTransportStatus(device _: MouseDevice) async -> DpiUpdateTransportStatus { .unknown }

    func hidAccessStatus() async -> HIDAccessStatus {
        .unknown(detail: "Backend is still starting.")
    }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        AsyncStream { _ in }
    }

    func updateRemoteClientPresence(sourceProcessID _: Int32, selectedDeviceID _: String?) async {}

    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func listOnboardProfiles(device _: MouseDevice) async throws -> OnboardProfileInventory {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func readOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileSnapshot {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func readOnboardProfileCore(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileSnapshot {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func readOnboardProfileButtonBindings(device _: MouseDevice, profileID _: Int) async throws -> [Int: ButtonBindingDraft] {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func createOnboardProfile(
        device _: MouseDevice,
        mutation _: OnboardProfileMutation,
        targetProfileID _: Int?,
        replaceAssignedProfile _: Bool
    ) async throws -> OnboardProfileSnapshot {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func renameOnboardProfile(device _: MouseDevice, profileID _: Int, name _: String) async throws -> OnboardProfileSnapshot {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func updateOnboardProfile(
        device _: MouseDevice,
        profileID _: Int,
        mutation _: OnboardProfileMutation
    ) async throws -> OnboardProfileSnapshot {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func deleteOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileInventory {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func activateOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> MouseState {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func refreshActiveOnboardProfile(device _: MouseDevice) async throws -> MouseState {
        throw BridgeError.commandFailed("Backend is still starting")
    }

    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? { nil }

    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? { nil }
}

extension DeviceBackend {
    func dpiUpdateTransportStatus(device: MouseDevice) async -> DpiUpdateTransportStatus {
        let usesFastPolling = await shouldUseFastDPIPolling(device: device)
        return usesFastPolling ? .pollingFallback : .realTimeHID
    }

    func updateRemoteClientPresence(sourceProcessID _: Int32, selectedDeviceID _: String?) async {
    }

    func listOnboardProfiles(device _: MouseDevice) async throws -> OnboardProfileInventory {
        throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.")
    }

    func readOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileSnapshot {
        throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.")
    }

    func readOnboardProfileCore(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileSnapshot {
        throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.")
    }

    func readOnboardProfileButtonBindings(device _: MouseDevice, profileID _: Int) async throws -> [Int: ButtonBindingDraft] {
        throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.")
    }

    func createOnboardProfile(
        device _: MouseDevice,
        mutation _: OnboardProfileMutation,
        targetProfileID _: Int?,
        replaceAssignedProfile _: Bool
    ) async throws -> OnboardProfileSnapshot {
        throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.")
    }

    func renameOnboardProfile(device _: MouseDevice, profileID _: Int, name _: String) async throws -> OnboardProfileSnapshot {
        throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.")
    }

    func updateOnboardProfile(
        device _: MouseDevice,
        profileID _: Int,
        mutation _: OnboardProfileMutation
    ) async throws -> OnboardProfileSnapshot {
        throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.")
    }

    func deleteOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileInventory {
        throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.")
    }

    func activateOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> MouseState {
        throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.")
    }

    func refreshActiveOnboardProfile(device _: MouseDevice) async throws -> MouseState {
        throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.")
    }
}

struct DpiFastSnapshot: Codable, Hashable, Sendable {
    let active: Int
    let values: [Int]
}

enum HIDAccessAuthorization: String, Codable, Sendable {
    case unknown
    case granted
    case denied
    case unavailable
}

struct HIDAccessStatus: Codable, Equatable, Sendable {
    let authorization: HIDAccessAuthorization
    let hostLabel: String
    let bundleIdentifier: String?
    let detail: String?

    static func unknown(detail: String? = nil) -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .unknown,
            hostLabel: PermissionSupport.currentHostLabel(),
            bundleIdentifier: Bundle.main.bundleIdentifier,
            detail: detail
        )
    }

    static func unavailable(detail: String? = nil) -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .unavailable,
            hostLabel: PermissionSupport.currentHostLabel(),
            bundleIdentifier: Bundle.main.bundleIdentifier,
            detail: detail
        )
    }

    var isDenied: Bool {
        authorization == .denied
    }

    var diagnosticsLabel: String {
        switch authorization {
        case .unknown:
            return "Checking"
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .unavailable:
            return "Unavailable"
        }
    }
}

struct SharedServiceSnapshot: Codable, Sendable {
    let devices: [MouseDevice]
    let stateByDeviceID: [String: MouseState]
    let lastUpdatedByDeviceID: [String: Date]
    let observedAtByDeviceID: [String: Date]

    init(
        devices: [MouseDevice],
        stateByDeviceID: [String: MouseState],
        lastUpdatedByDeviceID: [String: Date],
        observedAtByDeviceID: [String: Date] = [:]
    ) {
        self.devices = devices
        self.stateByDeviceID = stateByDeviceID
        self.lastUpdatedByDeviceID = lastUpdatedByDeviceID
        self.observedAtByDeviceID = observedAtByDeviceID
    }

    private enum CodingKeys: String, CodingKey {
        case devices
        case stateByDeviceID
        case lastUpdatedByDeviceID
        case observedAtByDeviceID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        devices = try container.decode([MouseDevice].self, forKey: .devices)
        stateByDeviceID = try container.decode([String: MouseState].self, forKey: .stateByDeviceID)
        lastUpdatedByDeviceID = try container.decode([String: Date].self, forKey: .lastUpdatedByDeviceID)
        observedAtByDeviceID = try container.decodeIfPresent([String: Date].self, forKey: .observedAtByDeviceID) ?? [:]
    }
}

struct CrossProcessClientPresence: Codable, Sendable {
    let sourceProcessID: Int32
    let selectedDeviceID: String?
}

enum BackendStateUpdate: Codable, Sendable {
    case deviceList([MouseDevice], updatedAt: Date)
    case deviceState(deviceID: String, state: MouseState, updatedAt: Date)
    case dpiTransportStatus(deviceID: String, status: DpiUpdateTransportStatus, updatedAt: Date)
    case snapshot(SharedServiceSnapshot)
    case openSettingsRequested
}

func mergedStateFromPassiveDpiEvent(
    previous: MouseState?,
    event: PassiveDPIEvent
) -> MouseState? {
    guard let previous, let stageValues = previous.dpi_stages.values, !stageValues.isEmpty else { return nil }

    let resolvedStageValues: [Int]
    let resolvedStagePairs: [DpiPair]?
    let resolvedActiveStage: Int?
    if stageValues.count == 1,
       stageValues[0] == previous.dpi?.x,
       stageValues[0] != event.dpiX {
        // A HID-only bootstrap path only knows the most recently observed DPI.
        // Keep that single-slot fallback state fresh until a full read seeds the
        // actual stage list.
        resolvedStageValues = [event.dpiX]
        resolvedStagePairs = [DpiPair(x: event.dpiX, y: event.dpiY)]
        resolvedActiveStage = 0
    } else {
        resolvedStageValues = stageValues
        let basePairs = BridgeClient.resolveDpiStagePairs(
            values: stageValues,
            pairs: nil,
            fallbackPairs: previous.dpi_stages.pairs
        )
        let matchingIndices = stageValues.enumerated().compactMap { index, value in
            value == event.dpiX ? index : nil
        }
        if matchingIndices.count == 1,
           var basePairs {
            let matchedStage = matchingIndices[0]
            resolvedActiveStage = matchedStage
            if matchedStage >= 0, matchedStage < basePairs.count {
                basePairs[matchedStage] = DpiPair(x: event.dpiX, y: event.dpiY)
            }
            resolvedStagePairs = basePairs
        } else {
            resolvedActiveStage = previous.dpi_stages.active_stage
            resolvedStagePairs = basePairs
        }
    }

    return MouseState(
        device: previous.device,
        connection: previous.connection,
        battery_percent: previous.battery_percent,
        charging: previous.charging,
        dpi: DpiPair(x: event.dpiX, y: event.dpiY),
        dpi_stages: DpiStages(active_stage: resolvedActiveStage, values: resolvedStageValues, pairs: resolvedStagePairs),
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
}

final actor LocalBridgeBackend: HIDAccessRefreshControllingBackend, ApplyOptionsSupportingBackend {
    static let shared = LocalBridgeBackend()
    private static let usbDisconnectDebounceInterval: TimeInterval = 0.75

    private let client = BridgeClient()
    private var cachedDevices: [MouseDevice] = []
    private var cachedDevicesAt: Date?
    private var cachedStateByDeviceID: [String: MouseState] = [:]
    private var cachedStateAtByDeviceID: [String: Date] = [:]
    private var cachedFastByDeviceID: [String: DpiFastSnapshot] = [:]
    private var cachedFastAtByDeviceID: [String: Date] = [:]
    private var reconnectSeedStateByDeviceID: [String: MouseState] = [:]
    private var bluetoothControlReadyDeviceIDs: Set<String> = []
    private let stateUpdatesStream = BroadcastStream<BackendStateUpdate>()
    private var devicePresenceRefreshTask: Task<Void, Never>?
    private var pendingUSBDisconnectRefreshTasks: [String: Task<Void, Never>] = [:]
    private var activeBluetoothWarmupKeys: Set<String> = []
    private var activeApplyCount = 0
    private var maxConcurrentApplyCount = 0

    nonisolated var usesRemoteServiceTransport: Bool { false }

    init() {
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
            ) {
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

        let state = try await client.readState(device: device)
        if Self.completedReadWasSuperseded(startedAt: readStartedAt, latestCachedAt: cachedStateAtByDeviceID[device.id]),
           let cached = cachedStateByDeviceID[device.id] {
            if cached.differsOnlyInDynamicDpiState(from: cachedStateBeforeRead) {
                let merged = cached.mergedWithStableReadTelemetry(from: state)
                let now = Date()
                cachedStateByDeviceID[device.id] = merged
                cachedStateAtByDeviceID[device.id] = now
                reconnectSeedStateByDeviceID[device.id] = merged
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
        let shouldUseFastPolling = await client.shouldUseFastDPIPolling(device: device)
        if let cachedAt = cachedFastAtByDeviceID[device.id],
           let cached = cachedFastByDeviceID[device.id],
           Self.shouldReuseCachedFastSnapshot(
            device: device,
            cachedAt: cachedAt,
            now: readStartedAt,
            shouldUseFastDPIPolling: shouldUseFastPolling
           ) {
            return cached
        }
        guard let snapshot = try await client.readDpiStagesFast(device: device) else { return nil }
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
        updateCachedStateFromFastSnapshot(fast, for: device.id)
        publishSnapshotIfService()
        return fast
    }

    func shouldUseFastDPIPolling(device: MouseDevice) async -> Bool {
        await client.shouldUseFastDPIPolling(device: device)
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
            device: device,
            patch: patch,
            activeApplyCount: activeApplyCount,
            maxConcurrentApplyCount: maxConcurrentApplyCount,
            readbackPolicy: options.readbackPolicy.rawValue
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
                device: device,
                patch: patch,
                activeApplyCount: activeApplyCount,
                maxConcurrentApplyCount: maxConcurrentApplyCount,
                elapsed: Date().timeIntervalSince(startedAt),
                readbackPolicy: options.readbackPolicy.rawValue,
                error: error
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
        if let values = merged.dpi_stages.values,
           let active = merged.dpi_stages.active_stage {
            let fast = DpiFastSnapshot(active: active, values: values)
            cachedFastByDeviceID[device.id] = fast
            cachedFastAtByDeviceID[device.id] = now
        }
        publishSnapshotIfService()
#if DEBUG
        OpenSnekUITestSupport.recordApplyEnd(
            device: device,
            patch: patch,
            state: merged,
            activeApplyCount: activeApplyCount,
            maxConcurrentApplyCount: maxConcurrentApplyCount,
            elapsed: Date().timeIntervalSince(startedAt),
            readbackPolicy: options.readbackPolicy.rawValue
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

    func deleteOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileInventory {
        try await client.deleteOnboardProfile(device: device, profileID: profileID)
    }

    func activateOnboardProfile(device: MouseDevice, profileID: Int) async throws -> MouseState {
        let state = try await client.activateOnboardProfile(device: device, profileID: profileID)
        cacheAndPublishState(state, for: device.id, updatedAt: Date())
        return state
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

    func readLightingColor(device: MouseDevice) async throws -> RGBPatch? {
        try await client.readLightingColor(device: device)
    }

    func debugUSBReadButtonBinding(device: MouseDevice, slot: Int, profile: Int) async throws -> [UInt8]? {
        try await client.debugUSBReadButtonBinding(device: device, slot: slot, profile: profile)
    }

    nonisolated static func mergedApplyState(_ state: MouseState, previous: MouseState?) -> MouseState {
        state.merged(with: previous)
    }

    nonisolated static func shouldReuseCachedStateForRead(
        device: MouseDevice,
        cachedAt: Date,
        now: Date,
        shouldUseFastDPIPolling: Bool
    ) -> Bool {
        guard now.timeIntervalSince(cachedAt) < 1.0 else { return false }
        if device.transport == .bluetooth, !shouldUseFastDPIPolling {
            return false
        }
        return true
    }

    nonisolated static func shouldReuseCachedFastSnapshot(
        device: MouseDevice,
        cachedAt: Date,
        now: Date,
        shouldUseFastDPIPolling: Bool
    ) -> Bool {
        if device.transport == .bluetooth, !shouldUseFastDPIPolling {
            return true
        }

        return now.timeIntervalSince(cachedAt) < 0.2
    }

    nonisolated static func completedReadWasSuperseded(startedAt: Date, latestCachedAt: Date?) -> Bool {
        guard let latestCachedAt else { return false }
        return latestCachedAt > startedAt
    }

    nonisolated static func passiveDpiEventHasAmbiguousStageMatch(
        previous: MouseState?,
        event: PassiveDPIEvent
    ) -> Bool {
        guard let previous,
              let values = previous.dpi_stages.values,
              values.count > 1 else {
            return false
        }
        let matchingIndices = values.enumerated().compactMap { index, value in
            value == event.dpiX ? index : nil
        }
        return matchingIndices.count != 1
    }

    nonisolated static func seededStateForPassiveDpiEvent(
        device: MouseDevice,
        event: PassiveDPIEvent,
        fastSnapshot: DpiFastSnapshot? = nil
    ) -> MouseState {
        let knownStageValues = fastSnapshot?.values.isEmpty == false
            ? fastSnapshot?.values
            : [event.dpiX]
        let matchingIndices = (knownStageValues ?? []).enumerated().compactMap { index, value in
            value == event.dpiX ? index : nil
        }
        let resolvedActiveStage: Int?
        if matchingIndices.count == 1 {
            resolvedActiveStage = matchingIndices[0]
        } else if let fastSnapshot {
            resolvedActiveStage = max(0, min(fastSnapshot.values.count - 1, fastSnapshot.active))
        } else {
            resolvedActiveStage = 0
        }

        return MouseState(
            device: DeviceSummary(
                id: device.id,
                product_name: device.product_name,
                serial: device.serial,
                transport: device.transport,
                firmware: device.firmware
            ),
            connection: device.connectionLabel,
            battery_percent: nil,
            charging: nil,
            dpi: DpiPair(x: event.dpiX, y: event.dpiY),
            dpi_stages: DpiStages(
                active_stage: resolvedActiveStage,
                values: knownStageValues,
                pairs: knownStageValues?.count == 1 ? [DpiPair(x: event.dpiX, y: event.dpiY)] : nil
            ),
            poll_rate: nil,
            sleep_timeout: nil,
            device_mode: nil,
            low_battery_threshold_raw: nil,
            scroll_mode: nil,
            scroll_acceleration: nil,
            scroll_smart_reel: nil,
            active_onboard_profile: nil,
            onboard_profile_count: device.onboard_profile_count,
            led_value: nil,
            capabilities: Capabilities(
                dpi_stages: true,
                poll_rate: device.transport == .usb,
                power_management: true,
                button_remap: device.button_layout != nil,
                lighting: device.showsLightingControls
            )
        )
    }

    private func handleDevicePresenceEvent(_ event: HIDDevicePresenceEvent) {
        if event.transport == .usb {
            if event.change == .connected {
                pendingUSBDisconnectRefreshTasks.removeValue(forKey: event.deviceID)?.cancel()
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
            return
        }

        cachedStateByDeviceID[event.deviceID] = updated
        cachedStateAtByDeviceID[event.deviceID] = event.observedAt
        reconnectSeedStateByDeviceID[event.deviceID] = updated
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
                    if let precise = updateCachedStateFromFastSnapshot(fast, for: event.deviceID) {
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
            let state = try await client.refreshActiveOnboardProfile(device: device)
            cacheAndPublishState(state, for: event.deviceID, updatedAt: event.observedAt)
        } catch {
            AppLog.warning(
                "Backend",
                "passive profile switch refresh failed device=\(event.deviceID): \(error.localizedDescription)"
            )
        }
    }

    private func cacheAndPublishState(_ state: MouseState, for deviceID: String, updatedAt: Date) {
        let merged = Self.mergedApplyState(
            state,
            previous: cachedStateByDeviceID[deviceID] ?? reconnectSeedStateByDeviceID[deviceID]
        )
        cachedStateByDeviceID[deviceID] = merged
        cachedStateAtByDeviceID[deviceID] = updatedAt
        reconnectSeedStateByDeviceID[deviceID] = merged
        if let values = merged.dpi_stages.values,
           let active = merged.dpi_stages.active_stage {
            cachedFastByDeviceID[deviceID] = DpiFastSnapshot(active: active, values: values)
            cachedFastAtByDeviceID[deviceID] = updatedAt
        }
        publishStateUpdate(.deviceState(deviceID: deviceID, state: merged, updatedAt: updatedAt))
        publishSnapshotIfService()
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
        bluetoothControlReadyDeviceIDs.remove(deviceID)
    }

    private func purgeCaches(forRemovedDeviceIDs removedDeviceIDs: Set<String>) {
        guard !removedDeviceIDs.isEmpty else { return }
        for deviceID in removedDeviceIDs {
            cachedStateByDeviceID.removeValue(forKey: deviceID)
            cachedStateAtByDeviceID.removeValue(forKey: deviceID)
            cachedFastByDeviceID.removeValue(forKey: deviceID)
            cachedFastAtByDeviceID.removeValue(forKey: deviceID)
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
                    observedAtByDeviceID: latestObservedAtByDeviceID(liveIDs: liveIDs)
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

private actor BackgroundServiceRequestHandler {
    private let backend: any DeviceBackend

    init(backend: any DeviceBackend) {
        self.backend = backend
    }

    func handle(_ request: BackgroundServiceRequestEnvelope) async -> BackgroundServiceResponseEnvelope {
        do {
            return try await makeResponse(for: request)
        } catch {
            return BackgroundServiceResponseEnvelope(payload: nil, error: error.localizedDescription)
        }
    }

    private func makeResponse(for request: BackgroundServiceRequestEnvelope) async throws -> BackgroundServiceResponseEnvelope {
        let payload: Data

        switch request.method {
        case .ping:
            payload = try BackendCodec.encode(true)
        case .listDevices:
            payload = try BackendCodec.encode(try await backend.listDevices())
        case .readState:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.readState(device: device))
        case .readDpiStagesFast:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.readDpiStagesFast(device: device))
        case .shouldUseFastDPIPolling:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(await backend.shouldUseFastDPIPolling(device: device))
        case .dpiUpdateTransportStatus:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(await backend.dpiUpdateTransportStatus(device: device))
        case .hidAccessStatus:
            let forceRefresh = (try? decodePayload(Bool.self, from: request.payload)) ?? true
            if let backend = backend as? any HIDAccessRefreshControllingBackend {
                payload = try BackendCodec.encode(await backend.hidAccessStatus(forceRefresh: forceRefresh))
            } else {
                payload = try BackendCodec.encode(await backend.hidAccessStatus())
            }
        case .apply:
            let applyRequest = try decodePayload(ApplyRequest.self, from: request.payload)
            if let backend = backend as? any ApplyOptionsSupportingBackend {
                payload = try BackendCodec.encode(
                    try await backend.apply(
                        device: applyRequest.device,
                        patch: applyRequest.patch,
                        options: applyRequest.options
                    )
                )
            } else {
                payload = try BackendCodec.encode(
                    try await backend.apply(device: applyRequest.device, patch: applyRequest.patch)
                )
            }
        case .listOnboardProfiles:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.listOnboardProfiles(device: device))
        case .readOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileIDRequest.self, from: request.payload)
            payload = try BackendCodec.encode(
                try await backend.readOnboardProfile(
                    device: onboardRequest.device,
                    profileID: onboardRequest.profileID
                )
            )
        case .readOnboardProfileCore:
            let onboardRequest = try decodePayload(OnboardProfileIDRequest.self, from: request.payload)
            payload = try BackendCodec.encode(
                try await backend.readOnboardProfileCore(
                    device: onboardRequest.device,
                    profileID: onboardRequest.profileID
                )
            )
        case .readOnboardProfileButtonBindings:
            let onboardRequest = try decodePayload(OnboardProfileIDRequest.self, from: request.payload)
            payload = try BackendCodec.encode(
                try await backend.readOnboardProfileButtonBindings(
                    device: onboardRequest.device,
                    profileID: onboardRequest.profileID
                )
            )
        case .createOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileCreateRequest.self, from: request.payload)
            payload = try BackendCodec.encode(
                try await backend.createOnboardProfile(
                    device: onboardRequest.device,
                    mutation: onboardRequest.mutation,
                    targetProfileID: onboardRequest.targetProfileID,
                    replaceAssignedProfile: onboardRequest.replaceAssignedProfile
                )
            )
        case .renameOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileRenameRequest.self, from: request.payload)
            payload = try BackendCodec.encode(
                try await backend.renameOnboardProfile(
                    device: onboardRequest.device,
                    profileID: onboardRequest.profileID,
                    name: onboardRequest.name
                )
            )
        case .updateOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileUpdateRequest.self, from: request.payload)
            payload = try BackendCodec.encode(
                try await backend.updateOnboardProfile(
                    device: onboardRequest.device,
                    profileID: onboardRequest.profileID,
                    mutation: onboardRequest.mutation
                )
            )
        case .deleteOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileIDRequest.self, from: request.payload)
            payload = try BackendCodec.encode(
                try await backend.deleteOnboardProfile(
                    device: onboardRequest.device,
                    profileID: onboardRequest.profileID
                )
            )
        case .activateOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileIDRequest.self, from: request.payload)
            payload = try BackendCodec.encode(
                try await backend.activateOnboardProfile(
                    device: onboardRequest.device,
                    profileID: onboardRequest.profileID
                )
            )
        case .refreshActiveOnboardProfile:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.refreshActiveOnboardProfile(device: device))
        case .readLightingColor:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.readLightingColor(device: device))
        case .debugUSBReadButtonBinding:
            let bindingRequest = try decodePayload(ButtonBindingReadRequest.self, from: request.payload)
            payload = try BackendCodec.encode(
                try await backend.debugUSBReadButtonBinding(
                    device: bindingRequest.device,
                    slot: bindingRequest.slot,
                    profile: bindingRequest.profile
                )
            )
        case .subscribeStateUpdates:
            payload = try BackendCodec.encode(true)
        }

        return BackgroundServiceResponseEnvelope(payload: payload, error: nil)
    }

    private func decodePayload<T: Decodable>(_ type: T.Type, from payload: Data?) throws -> T {
        guard let payload else {
            throw BackgroundServiceTransportError.missingPayload
        }
        return try BackendCodec.decode(type, from: payload)
    }
}

final actor IPCDeviceBackend: HIDAccessRefreshControllingBackend, ApplyOptionsSupportingBackend {
    private let host: NWEndpoint.Host = .ipv4(.loopback)
    private let port: NWEndpoint.Port
    private var latestRemoteClientPresence: CrossProcessClientPresence
    private var remoteSubscription: BackgroundServiceClientSubscription?

    init(port: NWEndpoint.Port) {
        self.port = port
        latestRemoteClientPresence = CrossProcessClientPresence(
            sourceProcessID: Int32(ProcessInfo.processInfo.processIdentifier),
            selectedDeviceID: nil
        )
    }

    nonisolated var usesRemoteServiceTransport: Bool { true }

    func ping() async -> Bool {
        (try? await request(method: .ping, payload: nil, responseType: Bool.self)) ?? false
    }

    func listDevices() async throws -> [MouseDevice] {
        try await request(method: .listDevices, payload: nil, responseType: [MouseDevice].self)
    }

    func readState(device: MouseDevice) async throws -> MouseState {
        try await request(
            method: .readState,
            payload: try BackendCodec.encode(device),
            responseType: MouseState.self
        )
    }

    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot? {
        try await request(
            method: .readDpiStagesFast,
            payload: try BackendCodec.encode(device),
            responseType: DpiFastSnapshot?.self
        )
    }

    func shouldUseFastDPIPolling(device: MouseDevice) async -> Bool {
        (try? await request(
            method: .shouldUseFastDPIPolling,
            payload: try BackendCodec.encode(device),
            responseType: Bool.self
        )) ?? false
    }

    func dpiUpdateTransportStatus(device: MouseDevice) async -> DpiUpdateTransportStatus {
        (try? await request(
            method: .dpiUpdateTransportStatus,
            payload: try BackendCodec.encode(device),
            responseType: DpiUpdateTransportStatus.self
        )) ?? .unknown
    }

    func hidAccessStatus() async -> HIDAccessStatus {
        await hidAccessStatus(forceRefresh: true)
    }

    func hidAccessStatus(forceRefresh: Bool) async -> HIDAccessStatus {
        (try? await request(
            method: .hidAccessStatus,
            payload: try BackendCodec.encode(forceRefresh),
            responseType: HIDAccessStatus.self
        )) ?? HIDAccessStatus.unavailable(detail: "Failed to query HID access status from background service.")
    }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        if let remoteSubscription {
            await remoteSubscription.stop()
        }
        let remoteSubscription = BackgroundServiceClientSubscription(
            host: host,
            port: port,
            initialPresence: latestRemoteClientPresence
        )
        self.remoteSubscription = remoteSubscription
        return await remoteSubscription.makeStream()
    }

    func updateRemoteClientPresence(sourceProcessID: Int32, selectedDeviceID: String?) async {
        let presence = CrossProcessClientPresence(
            sourceProcessID: sourceProcessID,
            selectedDeviceID: selectedDeviceID
        )
        latestRemoteClientPresence = presence
        guard let remoteSubscription else { return }
        await remoteSubscription.updatePresence(presence)
    }

    func apply(device: MouseDevice, patch: DevicePatch, options: ApplyOptions) async throws -> MouseState {
        try await request(
            method: .apply,
            payload: try BackendCodec.encode(ApplyRequest(device: device, patch: patch, options: options)),
            responseType: MouseState.self
        )
    }

    func listOnboardProfiles(device: MouseDevice) async throws -> OnboardProfileInventory {
        try await request(
            method: .listOnboardProfiles,
            payload: try BackendCodec.encode(device),
            responseType: OnboardProfileInventory.self
        )
    }

    func readOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot {
        try await request(
            method: .readOnboardProfile,
            payload: try BackendCodec.encode(OnboardProfileIDRequest(device: device, profileID: profileID)),
            responseType: OnboardProfileSnapshot.self
        )
    }

    func readOnboardProfileCore(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot {
        try await request(
            method: .readOnboardProfileCore,
            payload: try BackendCodec.encode(OnboardProfileIDRequest(device: device, profileID: profileID)),
            responseType: OnboardProfileSnapshot.self
        )
    }

    func readOnboardProfileButtonBindings(device: MouseDevice, profileID: Int) async throws -> [Int: ButtonBindingDraft] {
        try await request(
            method: .readOnboardProfileButtonBindings,
            payload: try BackendCodec.encode(OnboardProfileIDRequest(device: device, profileID: profileID)),
            responseType: [Int: ButtonBindingDraft].self
        )
    }

    func createOnboardProfile(
        device: MouseDevice,
        mutation: OnboardProfileMutation,
        targetProfileID: Int?,
        replaceAssignedProfile: Bool
    ) async throws -> OnboardProfileSnapshot {
        try await request(
            method: .createOnboardProfile,
            payload: try BackendCodec.encode(
                OnboardProfileCreateRequest(
                    device: device,
                    mutation: mutation,
                    targetProfileID: targetProfileID,
                    replaceAssignedProfile: replaceAssignedProfile
                )
            ),
            responseType: OnboardProfileSnapshot.self
        )
    }

    func renameOnboardProfile(device: MouseDevice, profileID: Int, name: String) async throws -> OnboardProfileSnapshot {
        try await request(
            method: .renameOnboardProfile,
            payload: try BackendCodec.encode(
                OnboardProfileRenameRequest(device: device, profileID: profileID, name: name)
            ),
            responseType: OnboardProfileSnapshot.self
        )
    }

    func updateOnboardProfile(
        device: MouseDevice,
        profileID: Int,
        mutation: OnboardProfileMutation
    ) async throws -> OnboardProfileSnapshot {
        try await request(
            method: .updateOnboardProfile,
            payload: try BackendCodec.encode(
                OnboardProfileUpdateRequest(device: device, profileID: profileID, mutation: mutation)
            ),
            responseType: OnboardProfileSnapshot.self
        )
    }

    func deleteOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileInventory {
        try await request(
            method: .deleteOnboardProfile,
            payload: try BackendCodec.encode(OnboardProfileIDRequest(device: device, profileID: profileID)),
            responseType: OnboardProfileInventory.self
        )
    }

    func activateOnboardProfile(device: MouseDevice, profileID: Int) async throws -> MouseState {
        try await request(
            method: .activateOnboardProfile,
            payload: try BackendCodec.encode(OnboardProfileIDRequest(device: device, profileID: profileID)),
            responseType: MouseState.self
        )
    }

    func refreshActiveOnboardProfile(device: MouseDevice) async throws -> MouseState {
        try await request(
            method: .refreshActiveOnboardProfile,
            payload: try BackendCodec.encode(device),
            responseType: MouseState.self
        )
    }

    func readLightingColor(device: MouseDevice) async throws -> RGBPatch? {
        try await request(
            method: .readLightingColor,
            payload: try BackendCodec.encode(device),
            responseType: RGBPatch?.self
        )
    }

    func debugUSBReadButtonBinding(device: MouseDevice, slot: Int, profile: Int) async throws -> [UInt8]? {
        try await request(
            method: .debugUSBReadButtonBinding,
            payload: try BackendCodec.encode(ButtonBindingReadRequest(device: device, slot: slot, profile: profile)),
            responseType: [UInt8]?.self
        )
    }

    private func request<T: Decodable & Sendable>(
        method: BackgroundServiceMethod,
        payload: Data?,
        responseType: T.Type
    ) async throws -> T {
        let connection = NWConnection(host: host, port: port, using: BackgroundServiceTransport.clientParameters())
        defer { connection.cancel() }

        try await BackgroundServiceTransport.awaitReady(connection: connection)

        let request = BackgroundServiceRequestEnvelope(method: method, payload: payload)
        try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(request), over: connection)

        let responseData = try await BackgroundServiceTransport.receiveFrame(from: connection)
        let response = try BackendCodec.decode(BackgroundServiceResponseEnvelope.self, from: responseData)
        if let error = response.error {
            throw NSError(domain: "OpenSnek.Service", code: 2, userInfo: [
                NSLocalizedDescriptionKey: error
            ])
        }
        guard let payload = response.payload else {
            throw NSError(domain: "OpenSnek.Service", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Background service returned no payload"
            ])
        }
        return try BackendCodec.decode(responseType, from: payload)
    }
}

private actor BackgroundServiceClientSubscription {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private var latestPresence: CrossProcessClientPresence
    private var connection: NWConnection?
    private var isReady = false
    private var readinessWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        initialPresence: CrossProcessClientPresence
    ) {
        self.host = host
        self.port = port
        latestPresence = initialPresence
    }

    func makeStream() async -> AsyncStream<BackendStateUpdate> {
        let stream = AsyncStream { continuation in
            let task = Task {
                await self.run(continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task {
                    await self.stop()
                }
            }
        }
        await waitUntilReady()
        return stream
    }

    func updatePresence(_ presence: CrossProcessClientPresence) async {
        latestPresence = presence
        guard let connection else { return }
        do {
            try await sendClientPresence(presence, over: connection)
        } catch {
            connection.cancel()
            if self.connection === connection {
                self.connection = nil
            }
        }
    }

    func stop() {
        connection?.cancel()
        connection = nil
        resumeReadinessWaiters()
    }

    private func run(continuation: AsyncStream<BackendStateUpdate>.Continuation) async {
        let connection = NWConnection(host: host, port: port, using: BackgroundServiceTransport.clientParameters())
        self.connection = connection

        defer {
            connection.cancel()
            if self.connection === connection {
                self.connection = nil
            }
            continuation.finish()
        }

        do {
            try await BackgroundServiceTransport.awaitReady(connection: connection)

            let subscribeRequest = BackgroundServiceRequestEnvelope(
                method: .subscribeStateUpdates,
                payload: try BackendCodec.encode(
                    StreamSubscriptionRequest(
                        sourceProcessID: latestPresence.sourceProcessID,
                        selectedDeviceID: latestPresence.selectedDeviceID
                    )
                )
            )
            try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(subscribeRequest), over: connection)

            let responseData = try await BackgroundServiceTransport.receiveFrame(from: connection)
            let response = try BackendCodec.decode(BackgroundServiceResponseEnvelope.self, from: responseData)
            if let error = response.error {
                throw NSError(domain: "OpenSnek.Service", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: error
                ])
            }
            isReady = true
            resumeReadinessWaiters()

            while !Task.isCancelled {
                let frame = try await BackgroundServiceTransport.receiveFrame(from: connection)
                let envelope = try BackendCodec.decode(BackgroundServiceStreamServerEnvelope.self, from: frame)
                switch envelope.event {
                case .stateUpdate:
                    guard let payload = envelope.payload else {
                        throw BackgroundServiceTransportError.missingPayload
                    }
                    continuation.yield(try BackendCodec.decode(BackendStateUpdate.self, from: payload))
                case .openSettingsRequested:
                    continuation.yield(.openSettingsRequested)
                }
            }
        } catch {
            resumeReadinessWaiters()
            if !Task.isCancelled,
               !isConnectionClosed(error) {
                AppLog.warning("Service", "background service subscription failed: \(error.localizedDescription)")
            }
        }
    }

    private func sendClientPresence(_ presence: CrossProcessClientPresence, over connection: NWConnection) async throws {
        let envelope = BackgroundServiceStreamClientEnvelope(
            event: .clientPresence,
            payload: try BackendCodec.encode(presence)
        )
        try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(envelope), over: connection)
    }

    private func isConnectionClosed(_ error: Error) -> Bool {
        if let transportError = error as? BackgroundServiceTransportError {
            if case .connectionClosed = transportError {
                return true
            }
        }
        return false
    }

    private func waitUntilReady() async {
        guard !isReady else { return }
        await withCheckedContinuation { continuation in
            readinessWaiters.append(continuation)
        }
    }

    private func resumeReadinessWaiters() {
        let waiters = readinessWaiters
        readinessWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor BackgroundServiceSubscriberSession {
    nonisolated let id = UUID()

    private let connection: NWConnection
    private let sourceProcessID: Int32
    private let initialSelectedDeviceID: String?
    private let onPresenceUpdate: @Sendable (CrossProcessClientPresence) async -> Void
    private let onDisconnect: @Sendable (Int32) async -> Void
    private var didHandleDisconnect = false

    init(
        connection: NWConnection,
        subscription: StreamSubscriptionRequest,
        onPresenceUpdate: @escaping @Sendable (CrossProcessClientPresence) async -> Void,
        onDisconnect: @escaping @Sendable (Int32) async -> Void
    ) {
        self.connection = connection
        sourceProcessID = subscription.sourceProcessID
        initialSelectedDeviceID = subscription.selectedDeviceID
        self.onPresenceUpdate = onPresenceUpdate
        self.onDisconnect = onDisconnect
    }

    func run() async {
        await onPresenceUpdate(
            CrossProcessClientPresence(
                sourceProcessID: sourceProcessID,
                selectedDeviceID: initialSelectedDeviceID
            )
        )

        do {
            while !Task.isCancelled {
                let frame = try await BackgroundServiceTransport.receiveFrame(from: connection)
                let envelope = try BackendCodec.decode(BackgroundServiceStreamClientEnvelope.self, from: frame)
                switch envelope.event {
                case .clientPresence:
                    guard let payload = envelope.payload else {
                        throw BackgroundServiceTransportError.missingPayload
                    }
                    let presence = try BackendCodec.decode(CrossProcessClientPresence.self, from: payload)
                    await onPresenceUpdate(presence)
                }
            }
        } catch {
            if !Task.isCancelled,
               !isConnectionClosed(error) {
                AppLog.warning("Service", "subscriber session failed: \(error.localizedDescription)")
            }
        }

        await disconnect()
    }

    func sendStateUpdate(_ update: BackendStateUpdate) async throws {
        try await send(
            BackgroundServiceStreamServerEnvelope(
                event: .stateUpdate,
                payload: try BackendCodec.encode(update)
            )
        )
    }

    func sendOpenSettingsRequested() async throws {
        try await send(
            BackgroundServiceStreamServerEnvelope(
                event: .openSettingsRequested,
                payload: nil
            )
        )
    }

    func stop() async {
        connection.cancel()
        await disconnect()
    }

    private func disconnect() async {
        guard !didHandleDisconnect else { return }
        didHandleDisconnect = true
        await onDisconnect(sourceProcessID)
    }

    private func send(_ envelope: BackgroundServiceStreamServerEnvelope) async throws {
        try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(envelope), over: connection)
    }

    private func isConnectionClosed(_ error: Error) -> Bool {
        if let transportError = error as? BackgroundServiceTransportError {
            if case .connectionClosed = transportError {
                return true
            }
        }
        return false
    }
}

private actor BackgroundServiceSubscriberRegistry {
    private var sessions: [UUID: BackgroundServiceSubscriberSession] = [:]

    func add(_ session: BackgroundServiceSubscriberSession) {
        sessions[session.id] = session
    }

    func remove(id: UUID) {
        sessions.removeValue(forKey: id)
    }

    func closeAll() async {
        let currentSessions = Array(sessions.values)
        sessions.removeAll()
        for session in currentSessions {
            await session.stop()
        }
    }

    func broadcast(_ update: BackendStateUpdate) async {
        for (id, session) in sessions {
            do {
                try await session.sendStateUpdate(update)
            } catch {
                sessions.removeValue(forKey: id)
                await session.stop()
            }
        }
    }

    func requestOpenSettings() async -> Bool {
        var delivered = false
        for (id, session) in sessions {
            do {
                try await session.sendOpenSettingsRequested()
                delivered = true
            } catch {
                sessions.removeValue(forKey: id)
                await session.stop()
            }
        }
        return delivered
    }
}

final class BackgroundServiceHost: @unchecked Sendable {
    private let defaults: UserDefaults
    private let pid = ProcessInfo.processInfo.processIdentifier
    private let listener: NWListener
    private let backend: any DeviceBackend
    private let handler: BackgroundServiceRequestHandler
    private let subscribers = BackgroundServiceSubscriberRegistry()
    private let remoteClientPresenceHandler: @Sendable (CrossProcessClientPresence) async -> Void
    private let remoteClientDisconnectHandler: @Sendable (Int32) async -> Void
    private let queue = DispatchQueue(label: "io.opensnek.service.host")
    private var backendStateUpdatesTask: Task<Void, Never>?

    init(
        backend: any DeviceBackend,
        defaults: UserDefaults = .standard,
        remoteClientPresenceHandler: @escaping @Sendable (CrossProcessClientPresence) async -> Void = { _ in },
        remoteClientDisconnectHandler: @escaping @Sendable (Int32) async -> Void = { _ in }
    ) throws {
        self.defaults = defaults
        self.listener = try NWListener(using: BackgroundServiceTransport.listenerParameters())
        self.backend = backend
        self.handler = BackgroundServiceRequestHandler(backend: backend)
        self.remoteClientPresenceHandler = remoteClientPresenceHandler
        self.remoteClientDisconnectHandler = remoteClientDisconnectHandler
    }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        let port = try await BackgroundServiceTransport.awaitReady(listener: listener)
        defaults.removeObject(forKey: BackgroundServiceCoordinator.endpointDefaultsKey)
        defaults.set(Int(port.rawValue), forKey: BackgroundServiceCoordinator.portDefaultsKey)
        defaults.set(pid, forKey: BackgroundServiceCoordinator.pidDefaultsKey)
        defaults.synchronize()
        startBroadcastingBackendStateUpdates()
        AppLog.info("Service", "background service published pid=\(pid) port=\(port.rawValue)")
    }

    func stop() {
        backendStateUpdatesTask?.cancel()
        backendStateUpdatesTask = nil
        Task {
            await subscribers.closeAll()
        }
        if defaults.integer(forKey: BackgroundServiceCoordinator.pidDefaultsKey) == pid {
            defaults.removeObject(forKey: BackgroundServiceCoordinator.endpointDefaultsKey)
            defaults.removeObject(forKey: BackgroundServiceCoordinator.portDefaultsKey)
            defaults.removeObject(forKey: BackgroundServiceCoordinator.pidDefaultsKey)
            defaults.synchronize()
        }
        listener.cancel()
    }

    func requestOpenSettingsForConnectedClients() async -> Bool {
        await subscribers.requestOpenSettings()
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.handle(connection)
            case .failed(let error):
                AppLog.warning("Service", "background service connection failed: \(error.localizedDescription)")
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func handle(_ connection: NWConnection) {
        let handler = self.handler
        let subscribers = self.subscribers
        let remoteClientPresenceHandler = self.remoteClientPresenceHandler
        let remoteClientDisconnectHandler = self.remoteClientDisconnectHandler
        Task {
            do {
                let requestData = try await BackgroundServiceTransport.receiveFrame(from: connection)
                let request = try BackendCodec.decode(BackgroundServiceRequestEnvelope.self, from: requestData)

                if request.method == .subscribeStateUpdates {
                    guard let payload = request.payload else {
                        throw BackgroundServiceTransportError.missingPayload
                    }
                    let subscription = try BackendCodec.decode(StreamSubscriptionRequest.self, from: payload)
                    let session = BackgroundServiceSubscriberSession(
                        connection: connection,
                        subscription: subscription,
                        onPresenceUpdate: remoteClientPresenceHandler,
                        onDisconnect: remoteClientDisconnectHandler
                    )
                    await subscribers.add(session)
                    let response = BackgroundServiceResponseEnvelope(
                        payload: try BackendCodec.encode(true),
                        error: nil
                    )
                    try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(response), over: connection)
                    await session.run()
                    await subscribers.remove(id: session.id)
                    return
                }

                let response = await handler.handle(request)
                try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(response), over: connection)
            } catch {
                AppLog.warning("Service", "background service request failed: \(error.localizedDescription)")
            }
            connection.cancel()
        }
    }

    private func startBroadcastingBackendStateUpdates() {
        backendStateUpdatesTask?.cancel()
        backendStateUpdatesTask = Task { [backend, subscribers] in
            let stream = await backend.stateUpdates()
            for await update in stream {
                await subscribers.broadcast(update)
            }
        }
    }
}
