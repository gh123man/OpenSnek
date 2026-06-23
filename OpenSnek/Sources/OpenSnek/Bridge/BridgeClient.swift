import Foundation
import IOKit.hid
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

actor BridgeClient {
    struct USBDpiStageSnapshot: Equatable, Sendable {
        let active: Int
        let values: [Int]
        let pairs: [DpiPair]
        let stageIDs: [UInt8]
    }

    struct BluetoothExpectedDpiState: Equatable, Sendable {
        let active: Int
        let values: [Int]
        let pairs: [DpiPair]
        let previousActive: Int?
        let previousValues: [Int]?
        let previousPairs: [DpiPair]?
        let expiresAt: Date
        var remainingMasks: Int
    }

    struct BluetoothResolvedDpiStageWrite: Equatable, Sendable {
        let active: Int
        let stages: [Int]
        let pairs: [DpiPair]
    }

    struct USBDpiApplyLogContext {
        let device: MouseDevice
        let patch: DevicePatch
        let cachedDpiStages: DpiStages?
        let current: USBDpiStageSnapshot?
        let activeClamped: Int
        let livePair: DpiPair
        let stages: [Int]
    }

    struct USBActiveDpiOnlyApplyContext {
        let device: MouseDevice
        let patch: DevicePatch
        let cachedState: MouseState?
        let activeClamped: Int
        let livePair: DpiPair
    }

    struct USBResolvedDpiStagesApplyContext {
        let device: MouseDevice
        let stages: [Int]
        let activeClamped: Int
        let livePair: DpiPair
        let resolvedStagePairs: [DpiPair]
        let stageIDs: [UInt8]?
        let usesProjectedReadback: Bool
    }

    nonisolated static func resolveBluetoothDpiStageWrite(
        device: MouseDevice,
        patch: DevicePatch,
        current: BLEVendorProtocol.DpiStageSnapshot?
    ) throws -> BluetoothResolvedDpiStageWrite {
        let resolvedValues = patch.dpiStagePairs?.map(\.x) ??
            patch.dpiStages ??
            current.map { Array($0.slots.prefix($0.count)) }
        guard let resolvedValues, !resolvedValues.isEmpty else {
            throw BridgeError.commandFailed("Failed to resolve Bluetooth DPI stages")
        }
        let stages = resolvedValues.map {
            DeviceProfiles.clampDPI($0, device: device)
        }
        let stagePairs = Self.resolveDpiStagePairs(
            values: patch.dpiStages,
            pairs: patch.dpiStagePairs,
            fallbackPairs: current.map { Array($0.pairs.prefix($0.count)) }
        )?.map { pair in
            DpiPair(
                x: DeviceProfiles.clampDPI(pair.x, device: device),
                y: DeviceProfiles.clampDPI(pair.y, device: device)
            )
        } ?? stages.map { DpiPair(x: $0, y: $0) }
        let active = patch.activeStage ?? current?.active ?? 0
        return BluetoothResolvedDpiStageWrite(active: active, stages: stages, pairs: stagePairs)
    }

    nonisolated static func resolvedUSBActiveStage(
        stages: USBDpiStageSnapshot,
        liveDpi: DpiPair?
    ) -> Int {
        guard let liveDpi else {
            return stages.active
        }
        let pairs = stages.pairs.isEmpty
            ? stages.values.map { DpiPair(x: $0, y: $0) }
            : stages.pairs
        let visiblePairs = Array(pairs.prefix(max(1, min(stages.values.count, pairs.count))))
        let matchingIndices = visiblePairs.enumerated().compactMap { index, pair in
            pair == liveDpi ? index : nil
        }
        return matchingIndices.count == 1 ? matchingIndices[0] : stages.active
    }

    nonisolated static func resolvedUSBFastDpiActiveStage(
        stages: USBDpiStageSnapshot,
        liveDpi: Int?
    ) -> Int {
        resolvedUSBActiveStage(
            stages: stages,
            liveDpi: liveDpi.map { DpiPair(x: $0, y: $0) }
        )
    }
    static let bluetoothPassiveHeartbeatHealthyInterval: TimeInterval = 1.5
    static let usbReconnectSettleInterval: TimeInterval = 2.0
    static let emptyHIDManagerRefreshInterval: TimeInterval = 1.0

    var deviceSessions: [String: USBHIDControlSession] = [:]
    var deviceSessionCandidates: [String: [USBHIDControlSession]] = [:]
    var lastStateByDeviceID: [String: MouseState] = [:]
    var usbReconnectSettleUntilByDeviceID: [String: Date] = [:]
    let devicePresenceEvents = BroadcastStream<HIDDevicePresenceEvent>()
    let passiveDpiEvents = BroadcastStream<PassiveDPIEvent>()
    let passiveDpiHeartbeatEvents = BroadcastStream<PassiveDPIHeartbeatEvent>()
    let passiveProfileSwitchEvents = BroadcastStream<PassiveProfileSwitchEvent>()
    var passiveDpiArmedDeviceIDs: Set<String> = []
    var passiveDpiHeartbeatDeviceIDs: Set<String> = []
    var passiveDpiObservedDeviceIDs: Set<String> = []
    var passiveDpiLastHeartbeatAtByDeviceID: [String: Date] = [:]
    var passiveDpiLastObservedAtByDeviceID: [String: Date] = [:]
    var passiveDpiTargetIDsByDeviceID: [String: Set<String>] = [:]
    var passiveDpiTargetsByDeviceID: [String: [PassiveDPIEventMonitor.WatchTarget]] = [:]
    var passiveDpiUpgradeNotBeforeByDeviceID: [String: Date] = [:]
    var btReqID: UInt8 = 0x30
    var btDpiSnapshotByDeviceID: [String: BLEVendorProtocol.DpiStageSnapshot] = [:]
    var btExpectedDpiByDeviceID: [String: BluetoothExpectedDpiState] = [:]
    let btVendorClient = BLEVendorTransportClient()
    let hidDevicePresenceMonitor = HIDDevicePresenceMonitor()
    let passiveDpiMonitor = PassiveDPIEventMonitor()
    var btExchangeLocked = false
    var btExchangeWaiters: [CheckedContinuation<Void, Never>] = []
    var hidAccessDenied = false
    var managerAccessDenied = false
    var lastOpenDeniedLogAt: Date?

    let usbVID = 0x1532
    let btVID = 0x068E
    private var hidManager: IOHIDManager?
    private var hidManagerOpenResult: IOReturn?
    private var lastEmptyHIDManagerRefreshAt: Date?

    init(startHIDMonitoring: Bool = true) {
        hidDevicePresenceMonitor.onChange = { [weak self] event in
            Task {
                await self?.handleHIDDevicePresenceEvent(event)
            }
        }
        passiveDpiMonitor.onEvent = { [weak self] event in
            Task {
                await self?.handlePassiveDpiEvent(event)
            }
        }
        passiveDpiMonitor.onHeartbeat = { [weak self] event in
            Task {
                await self?.handlePassiveDpiHeartbeat(event)
            }
        }
        passiveDpiMonitor.onProfileSwitch = { [weak self] event in
            Task {
                await self?.handlePassiveProfileSwitch(event)
            }
        }
        if startHIDMonitoring {
            hidDevicePresenceMonitor.start()
        }
    }

    func devicePresenceEventStream() -> AsyncStream<HIDDevicePresenceEvent> {
        devicePresenceEvents.makeStream()
    }

    private func handleHIDDevicePresenceEvent(_ event: HIDDevicePresenceEvent) {
        updateUSBReconnectSettleDeadline(for: event)
        AppLog.event(
            "Bridge",
            "hidPresence change=\(event.change.rawValue) device=\(event.deviceID)"
        )
        invalidateDiscoveryState(for: event.deviceID, reason: "hid-\(event.change.rawValue)")
        devicePresenceEvents.yield(event)
    }

    private func invalidateDiscoveryState(for deviceID: String, reason: String) {
        deviceSessions.removeValue(forKey: deviceID)
        deviceSessionCandidates.removeValue(forKey: deviceID)
        lastStateByDeviceID.removeValue(forKey: deviceID)
        passiveDpiArmedDeviceIDs.remove(deviceID)
        passiveDpiHeartbeatDeviceIDs.remove(deviceID)
        passiveDpiLastHeartbeatAtByDeviceID.removeValue(forKey: deviceID)
        passiveDpiLastObservedAtByDeviceID.removeValue(forKey: deviceID)
        passiveDpiTargetIDsByDeviceID.removeValue(forKey: deviceID)
        passiveDpiTargetsByDeviceID.removeValue(forKey: deviceID)
        passiveDpiUpgradeNotBeforeByDeviceID.removeValue(forKey: deviceID)
        clearPassiveDpiObservation(deviceID: deviceID, reason: reason)
        clearManagedHIDManager()
    }

    func usbDeviceIsAbsentAfterDiscoveryRefresh(device: MouseDevice, operation: String) async -> Bool {
        guard device.transport == .usb else { return false }

        // Stale IOHIDDevice handles can report telemetry failures after a dongle is pulled.
        // Always re-run discovery before calling that a sleeping/off mouse; absence means the
        // receiver itself is gone and the UI must leave the dongle-only state on replug.
        clearManagedHIDManager()
        do {
            let devices = try await listDevices()
            let isPresent = devices.contains { $0.id == device.id }
            AppLog.debug(
                "Bridge",
                "usb discovery refresh after \(operation) device=\(device.id) " +
                "present=\(isPresent) candidates=\(deviceSessionCandidates[device.id]?.count ?? 0)"
            )
            if !isPresent {
                invalidateDiscoveryState(for: device.id, reason: "\(operation)-absent")
            }
            return !isPresent
        } catch {
            AppLog.debug(
                "Bridge",
                "usb discovery refresh after \(operation) failed device=\(device.id): \(error.localizedDescription)"
            )
            return false
        }
    }

    private func managedHIDManager() -> (manager: IOHIDManager, openResult: IOReturn) {
        if let hidManager, let hidManagerOpenResult, hidManagerOpenResult == kIOReturnSuccess {
            return (hidManager, hidManagerOpenResult)
        }

        clearManagedHIDManager()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, [
            [kIOHIDVendorIDKey: usbVID] as CFDictionary,
            [kIOHIDVendorIDKey: btVID] as CFDictionary
        ] as CFArray)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        managerAccessDenied = openResult == kIOReturnNotPermitted
        if openResult != kIOReturnSuccess {
            AppLog.error("Bridge", "IOHIDManagerOpen failed (\(openResult)); continuing best-effort discovery")
            if openResult == kIOReturnNotPermitted {
                AppLog.error(
                    "Bridge",
                    "IOHID access not permitted; USB access may be blocked unless Input Monitoring permission is granted"
                )
            }
        }

        hidManager = manager
        hidManagerOpenResult = openResult
        return (manager, openResult)
    }

    private func currentHIDDeviceSnapshot() -> (devices: [IOHIDDevice], openResult: IOReturn) {
        let (manager, openResult) = managedHIDManager()
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return ([], openResult)
        }
        return (Array(set), openResult)
    }

    private func clearManagedHIDManager() {
        if let hidManager {
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.hidManager = nil
        }
        hidManagerOpenResult = nil
        managerAccessDenied = false
        lastEmptyHIDManagerRefreshAt = nil
    }

    func hidAccessStatus(forceRefresh: Bool = true) -> HIDAccessStatus {
        if forceRefresh {
            AppLog.debug("Bridge", "hidAccessStatus forcing IOHIDManager refresh")
            clearManagedHIDManager()
        } else {
            AppLog.debug("Bridge", "hidAccessStatus reusing shared IOHIDManager")
        }

        let (_, openResult) = managedHIDManager()
        let authorization: HIDAccessAuthorization
        let detail: String?

        switch openResult {
        case kIOReturnSuccess:
            authorization = .granted
            detail = nil
        case kIOReturnNotPermitted:
            authorization = .denied
            detail = "Input Monitoring is required before macOS will allow HID listeners and feature-report access."
        default:
            authorization = .unavailable
            detail = "IOHIDManagerOpen failed (\(openResult))."
        }

        return HIDAccessStatus(
            authorization: authorization,
            hostLabel: PermissionSupport.currentHostLabel(),
            bundleIdentifier: Bundle.main.bundleIdentifier,
            detail: detail
        )
    }

    func listDevices() async throws -> [MouseDevice] {
        let start = Date()
        var hidSnapshot = currentHIDDeviceSnapshot()
        if hidSnapshot.devices.isEmpty {
            let now = Date()
            if Self.shouldRefreshEmptyHIDManagerSnapshot(
                openResult: hidSnapshot.openResult,
                lastRefreshAt: lastEmptyHIDManagerRefreshAt,
                now: now
            ) {
                // macOS can show a replugged receiver in IORegistry while a previously opened
                // IOHIDManager keeps returning an empty device set and never emits another
                // presence callback. Reopen the manager so polling can rediscover the device.
                clearManagedHIDManager()
                hidSnapshot = currentHIDDeviceSnapshot()
                if hidSnapshot.devices.isEmpty {
                    lastEmptyHIDManagerRefreshAt = now
                    AppLog.debug("Bridge", "listDevices refreshed empty HID manager snapshot; still empty")
                } else {
                    lastEmptyHIDManagerRefreshAt = nil
                    AppLog.event(
                        "Bridge",
                        "listDevices recovered stale empty HID manager snapshot devices=\(hidSnapshot.devices.count)"
                    )
                }
            }
        } else {
            lastEmptyHIDManagerRefreshAt = nil
        }
        let openResult = hidSnapshot.openResult
        let connectedBluetoothPeripheralNames = await btVendorClient.connectedPeripheralSummaries()?.map(\.name)

        let devices = hidSnapshot.devices

        var modelsByID: [String: MouseDevice] = [:]
        var sessionsByID: [String: [(score: Int, session: USBHIDControlSession)]] = [:]
        var passiveDpiTargets: [PassiveDPIEventMonitor.WatchTarget] = []
        for device in devices {
            guard let vendor = USBHIDSupport.intProperty(device, key: kIOHIDVendorIDKey as CFString),
                  vendor == usbVID || vendor == btVID,
                  let product = USBHIDSupport.intProperty(device, key: kIOHIDProductIDKey as CFString) else { continue }

            let name = USBHIDSupport.stringProperty(device, key: kIOHIDProductKey as CFString) ?? "Razer Mouse"
            let serial = USBHIDSupport.stringProperty(device, key: kIOHIDSerialNumberKey as CFString)
            let transportRaw = (USBHIDSupport.stringProperty(device, key: kIOHIDTransportKey as CFString) ?? "").lowercased()
            let transport: DeviceTransportKind = transportRaw.contains("bluetooth") || vendor == btVID ? .bluetooth : .usb
            if transport == .bluetooth,
               !Self.shouldIncludeBluetoothHIDDevice(
                hidDeviceName: name,
                connectedPeripheralNames: connectedBluetoothPeripheralNames
               ) {
                continue
            }
            let location = USBHIDSupport.intProperty(device, key: kIOHIDLocationIDKey as CFString) ?? 0
            let id = String(format: "%04x:%04x:%08x:%@", vendor, product, location, transport.rawValue)
            let profile = DeviceProfiles.resolve(vendorID: vendor, productID: product, transport: transport)

            let model = MouseDevice(
                id: id,
                vendor_id: vendor,
                product_id: product,
                product_name: name,
                transport: transport,
                path_b64: "",
                serial: serial,
                firmware: nil,
                location_id: location,
                profile_id: profile?.id,
                button_layout: profile?.buttonLayout,
                supports_advanced_lighting_effects: profile?.supportsAdvancedLightingEffects ?? false,
                onboard_profile_count: profile?.onboardProfileCount ?? 1
            )
            if modelsByID[id] == nil {
                modelsByID[id] = model
            }

            if let passiveTarget = passiveDpiWatchTarget(
                for: device,
                deviceID: id,
                profile: profile,
                transport: transport
            ) {
                passiveDpiTargets.append(passiveTarget)
            }

            let score = USBHIDSupport.handlePreferenceScore(device: device)
            sessionsByID[id, default: []].append((score: score, session: USBHIDControlSession(device: device, deviceID: id)))
        }
        var preferredSessionsByID: [String: USBHIDControlSession] = [:]
        var candidatesByID: [String: [USBHIDControlSession]] = [:]
        for (id, scoredHandles) in sessionsByID {
            let sorted = scoredHandles.sorted { lhs, rhs in
                if lhs.score == rhs.score { return false }
                return lhs.score > rhs.score
            }
            let sessions = sorted.map(\.session)
            candidatesByID[id] = sessions
            if let first = sessions.first {
                preferredSessionsByID[id] = first
            }
        }
        if !candidatesByID.isEmpty {
            let candidateSummary = candidatesByID.keys.sorted().map { id in
                "\(id)=\(candidatesByID[id]?.count ?? 0)"
            }.joined(separator: ",")
            AppLog.debug("Bridge", "listDevices hid candidates \(candidateSummary)")
        }
        deviceSessionCandidates = candidatesByID
        deviceSessions = preferredSessionsByID
        await updatePassiveDpiTracking(with: passiveDpiTargets)
        var result = Array(modelsByID.values)

        let hasBluetoothDevice = result.contains(where: { $0.transport == .bluetooth })
        if !hasBluetoothDevice, result.isEmpty, openResult == kIOReturnNotPermitted {
            do {
                _ = try await btExchange([], timeout: 0.8)
                guard let summary = await btVendorClient.currentPeripheralSummary() else {
                    throw BridgeError.commandFailed("Bluetooth fallback discovery resolved no peripheral identity")
                }
                let fallback = Self.makeBluetoothFallbackDevice(summary: summary)
                result.append(fallback)
                AppLog.event(
                    "Bridge",
                    "listDevices added Bluetooth fallback device after HID permission denial " +
                    "name=\(fallback.product_name) product=0x\(String(format: "%04x", fallback.product_id)) " +
                    "supported=\(fallback.profile_id != nil)"
                )
            } catch {
                AppLog.error("Bridge", "Bluetooth fallback discovery failed: \(error.localizedDescription)")
            }
        }

        let sorted = result.sorted { $0.product_name < $1.product_name }
        if sorted.isEmpty, openResult == kIOReturnNotPermitted {
            throw BridgeError.commandFailed(
                "HID access denied by macOS (kIOReturnNotPermitted). " +
                "Enable Input Monitoring for OpenSnek (or Terminal/Xcode when running via swift run/Xcode), " +
                "or ensure a supported Bluetooth device is connected."
            )
        }
        AppLog.event("Bridge", "listDevices count=\(sorted.count) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s")
        return sorted
    }

    nonisolated static func shouldIncludeBluetoothHIDDevice(
        hidDeviceName: String,
        connectedPeripheralNames: [String?]?
    ) -> Bool {
        guard let connectedPeripheralNames else { return true }
        guard !connectedPeripheralNames.isEmpty else { return false }
        guard let normalizedHIDName = normalizedPeripheralName(hidDeviceName) else { return true }

        var sawUnknownConnectedName = false
        for connectedName in connectedPeripheralNames {
            guard let normalizedConnectedName = normalizedPeripheralName(connectedName) else {
                sawUnknownConnectedName = true
                continue
            }
            if normalizedHIDName == normalizedConnectedName ||
                normalizedHIDName.contains(normalizedConnectedName) ||
                normalizedConnectedName.contains(normalizedHIDName) {
                return true
            }
        }

        return sawUnknownConnectedName
    }

    private nonisolated static func normalizedPeripheralName(_ value: String?) -> String? {
        BluetoothNameMatcher.normalized(value)
    }

    nonisolated static func isUSBTelemetryUnavailableError(_ error: any Error) -> Bool {
        if let bridgeError = error as? BridgeError,
           case .usbMouseUnavailable = bridgeError {
            return true
        }
        let lowered = error.localizedDescription.lowercased()
        return lowered.contains("telemetry unavailable") || lowered.contains("usable responses")
    }

    nonisolated static func usbReconnectSettleDeadline(for event: HIDDevicePresenceEvent) -> Date? {
        guard event.transport == .usb, event.change == .connected else { return nil }
        return event.observedAt.addingTimeInterval(Self.usbReconnectSettleInterval)
    }

    nonisolated static func shouldDeferUSBReconnectRead(until settleDeadline: Date?, now: Date = Date()) -> Bool {
        guard let settleDeadline else { return false }
        return now < settleDeadline
    }

    nonisolated static func shouldRefreshEmptyHIDManagerSnapshot(
        openResult: IOReturn,
        lastRefreshAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard openResult == kIOReturnSuccess else { return false }
        guard let lastRefreshAt else { return true }
        return now.timeIntervalSince(lastRefreshAt) >= Self.emptyHIDManagerRefreshInterval
    }

    private func updateUSBReconnectSettleDeadline(for event: HIDDevicePresenceEvent) {
        guard event.transport == .usb else { return }
        if let settleDeadline = Self.usbReconnectSettleDeadline(for: event) {
            usbReconnectSettleUntilByDeviceID[event.deviceID] = settleDeadline
        } else {
            usbReconnectSettleUntilByDeviceID.removeValue(forKey: event.deviceID)
        }
    }

    func deferUSBReconnectReadIfNeeded(deviceID: String, operation: String) async throws {
        while let settleDeadline = usbReconnectSettleUntilByDeviceID[deviceID] {
            let now = Date()
            if Self.shouldDeferUSBReconnectRead(until: settleDeadline, now: now) {
                let remaining = settleDeadline.timeIntervalSince(now)
                AppLog.debug(
                    "Bridge",
                    "usb reconnect settle device=\(deviceID) operation=\(operation) " +
                    "remaining=\(String(format: "%.3f", remaining))s"
                )
                try await Task.sleep(nanoseconds: UInt64(max(0, remaining) * 1_000_000_000))
                continue
            }

            guard usbReconnectSettleUntilByDeviceID[deviceID] == settleDeadline else { continue }
            usbReconnectSettleUntilByDeviceID.removeValue(forKey: deviceID)
            await refreshUSBDiscoveryAfterReconnectSettle(deviceID: deviceID, operation: operation)
            return
        }
    }

    private func refreshUSBDiscoveryAfterReconnectSettle(deviceID: String, operation: String) async {
        deviceSessions.removeValue(forKey: deviceID)
        deviceSessionCandidates.removeValue(forKey: deviceID)
        clearManagedHIDManager()

        do {
            _ = try await listDevices()
            AppLog.debug(
                "Bridge",
                "usb reconnect discovery refreshed device=\(deviceID) operation=\(operation) " +
                "candidates=\(deviceSessionCandidates[deviceID]?.count ?? 0)"
            )
        } catch {
            AppLog.debug(
                "Bridge",
                "usb reconnect discovery refresh failed device=\(deviceID) operation=\(operation): " +
                error.localizedDescription
            )
        }
    }

    nonisolated static func makeBluetoothFallbackDevice(
        summary: BLEVendorTransportClient.ConnectedPeripheralSummary
    ) -> MouseDevice {
        let profile = DeviceProfiles.resolveBluetoothFallback(name: summary.name)
        let productID = profile?.supportedProducts.first ?? 0
        let productName = summary.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? summary.name!.trimmingCharacters(in: .whitespacesAndNewlines)
            : (profile?.productName ?? "Razer Bluetooth Device")
        let locationID = Int(UInt32(truncatingIfNeeded: summary.identifier.uuidString.hashValue))
        let id = String(format: "%04x:%04x:%08x:%@", 0x068E, productID, locationID, DeviceTransportKind.bluetooth.rawValue)

        return MouseDevice(
            id: id,
            vendor_id: 0x068E,
            product_id: productID,
            product_name: productName,
            transport: .bluetooth,
            path_b64: "",
            serial: nil,
            firmware: nil,
            location_id: locationID,
            profile_id: profile?.id,
            button_layout: profile?.buttonLayout,
            supports_advanced_lighting_effects: profile?.supportsAdvancedLightingEffects ?? false,
            onboard_profile_count: profile?.onboardProfileCount ?? 1
        )
    }

    nonisolated static func preferredBluetoothControlWarmupName(
        vendorID: Int,
        productID: Int,
        transport: DeviceTransportKind
    ) -> String? {
        guard transport == .bluetooth else { return nil }
        return DeviceProfiles.resolve(
            vendorID: vendorID,
            productID: productID,
            transport: transport
        )?.productName
    }

    func prepareBluetoothControlConnection(preferredPeripheralName: String?) async -> Bool {
        let trimmedName = preferredPeripheralName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let start = Date()

        do {
            _ = try await btExchange(
                [],
                timeout: 1.0,
                preferredPeripheralName: trimmedName
            )
            AppLog.debug(
                "Bridge",
                "btPrepareConnection ready name=\(trimmedName ?? "any") " +
                "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
            )
            return true
        } catch {
            AppLog.debug(
                "Bridge",
                "btPrepareConnection failed name=\(trimmedName ?? "any"): \(error.localizedDescription)"
            )
            return false
        }
    }

    func readState(device: MouseDevice) async throws -> MouseState {
        let start = Date()
        if device.transport == .bluetooth {
            do {
                let session = sessionFor(device: device)
                let previous = lastStateByDeviceID[device.id]
                let state = try await readBluetoothState(device: device, session: session)
                let resolved: MouseState
                if passiveDpiObservedDeviceIDs.contains(device.id),
                   let previous {
                    resolved = previous.mergedWithStableReadTelemetry(from: state)
                    AppLog.debug(
                        "Bridge",
                        "readState bt preserved passive DPI device=\(device.id) " +
                        "previousActive=\(previous.dpi_stages.active_stage.map(String.init) ?? "nil") " +
                        "readActive=\(state.dpi_stages.active_stage.map(String.init) ?? "nil")"
                    )
                } else {
                    resolved = state
                }
                lastStateByDeviceID[device.id] = resolved
                AppLog.debug("Bridge", "readState bt device=\(device.id) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s")
                return resolved
            } catch {
                clearPassiveDpiObservation(deviceID: device.id, reason: "read-state-failed")
                throw error
            }
        }

        try await deferUSBReconnectReadIfNeeded(deviceID: device.id, operation: "read-state")

        let sessions = sessionsFor(device: device)
        guard !sessions.isEmpty else {
            if managerAccessDenied {
                throw BridgeError.commandFailed(
                    "USB HID access denied by macOS. Enable Input Monitoring for OpenSnek " +
                    "(or Terminal/Xcode when running via swift run/Xcode), then relaunch."
                )
            }
            throw BridgeError.commandFailed("Device not available")
        }

        var firstError: Error?
        for (index, session) in sessions.enumerated() {
            do {
                let state = try await readUSBState(device: device, session: session)
                if index > 0 {
                    deviceSessions[device.id] = session
                    AppLog.debug("Bridge", "readState usb switched to alternate session index=\(index) device=\(device.id)")
                }
                lastStateByDeviceID[device.id] = state
                await maybeUpgradeUSBPassiveDpiFromPolling(device: device, reason: "read-state-ok")
                AppLog.debug(
                    "Bridge",
                    "readState usb device=\(device.id) " +
                    "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
                )
                return state
            } catch {
                if firstError == nil {
                    firstError = error
                }
                AppLog.debug("Bridge", "readState usb candidate index=\(index) failed: \(error.localizedDescription)")
            }
        }

        deviceSessions[device.id]?.invalidateCachedTransaction()
        if let firstError {
            if Self.isUSBTelemetryUnavailableError(firstError),
               await usbDeviceIsAbsentAfterDiscoveryRefresh(device: device, operation: "read-state") {
                throw BridgeError.commandFailed("Device not available")
            }
            throw firstError
        }
        throw BridgeError.commandFailed("USB device telemetry unavailable")
    }

    func readDpiStagesFast(device: MouseDevice) async throws -> (active: Int, values: [Int])? {
        if device.transport == .bluetooth {
            let supportsMappedOnboardProfiles = DeviceProfiles.resolve(
                vendorID: device.vendor_id,
                productID: device.product_id,
                transport: device.transport
            )?.supportsMappedOnboardProfileCRUD == true
            if passiveDpiObservedDeviceIDs.contains(device.id),
               let state = lastStateByDeviceID[device.id],
               let active = state.dpi_stages.active_stage,
               let values = state.dpi_stages.values,
               !values.isEmpty {
                return (active: max(0, min(values.count - 1, active)), values: values)
            }
            if supportsMappedOnboardProfiles {
                guard let state = lastStateByDeviceID[device.id],
                      let values = state.dpi_stages.values,
                      !values.isEmpty else {
                    return nil
                }
                let active = max(0, min(values.count - 1, state.dpi_stages.active_stage ?? 0))
                return (active: active, values: values)
            }
            guard let parsed = try await btGetDpiStages(device: device) else { return nil }
            let now = Date()
            if passiveDpiObservedDeviceIDs.contains(device.id),
               Self.shouldResetBluetoothPassiveObservation(
                BluetoothPassiveObservationResetContext(
                    previousState: lastStateByDeviceID[device.id],
                    active: parsed.active,
                    values: parsed.values,
                    lastHeartbeatAt: passiveDpiLastHeartbeatAtByDeviceID[device.id],
                    lastObservedAt: passiveDpiLastObservedAtByDeviceID[device.id],
                    now: now
                )
               ) {
                AppLog.debug(
                    "Bridge",
                    "passiveDpi reset device=\(device.id) reason=watchdog-miss; fast polling will resume"
                )
                clearPassiveDpiObservation(deviceID: device.id, reason: "watchdog-miss")
                await rearmPassiveDpi(deviceID: device.id, reason: "watchdog-miss")
            }
            return (active: parsed.active, values: parsed.values)
        }

        guard device.transport == .usb else { return nil }
        try await deferUSBReconnectReadIfNeeded(deviceID: device.id, operation: "fast-dpi-read")
        let orderedSessions = sessionsFor(device: device)
        guard !orderedSessions.isEmpty else { return nil }

        var firstError: Error?
        for session in orderedSessions {
            do {
                let snapshot = try session.withExclusiveDeviceAccess { () throws -> (active: Int, values: [Int])? in
                    guard let stages = try getDPIStageSnapshot(session, device) else { return nil }
                    let liveDpi = try getDPI(session, device)?.0
                    let active = Self.resolvedUSBFastDpiActiveStage(stages: stages, liveDpi: liveDpi)
                    AppLog.debug(
                        "Bridge",
                        "readDpiStagesFast usb device=\(device.id) tableActive=\(stages.active) " +
                        "liveX=\(liveDpi.map(String.init) ?? "nil") resolved=\(active) " +
                        "values=\(stages.values.map(String.init).joined(separator: ","))"
                    )
                    return (active: active, values: stages.values)
                }
                guard let snapshot else { continue }
                deviceSessions[device.id] = session
                await maybeUpgradeUSBPassiveDpiFromPolling(device: device, reason: "fast-poll-ok")
                return snapshot
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            if Self.isUSBTelemetryUnavailableError(firstError),
               await usbDeviceIsAbsentAfterDiscoveryRefresh(device: device, operation: "fast-dpi-read") {
                throw BridgeError.commandFailed("Device not available")
            }
            throw firstError
        }
        return nil
    }

    func readLightingColor(device: MouseDevice) async throws -> RGBPatch? {
        guard device.transport == .bluetooth else { return nil }
        if isBluetoothV3ProLightingDevice(device) {
            let ledIDs = bluetoothLightingLEDIDs(device: device)
            var colors: [(UInt8, RGBPatch)] = []
            for ledID in ledIDs {
                if let color = try await btReadLightingColor(device: device, ledID: ledID) {
                    colors.append((ledID, color))
                }
            }
            guard let first = colors.first?.1 else { return nil }
            if colors.contains(where: { $0.1 != first }) {
                AppLog.debug(
                    "Bridge",
                    "readLightingColor zone-mismatch device=\(device.id) colors=\(formatLightingZoneColors(colors))"
                )
            }
            return first
        }

        return try await btReadLightingColor(device: device, ledID: 0x01)
    }

}
