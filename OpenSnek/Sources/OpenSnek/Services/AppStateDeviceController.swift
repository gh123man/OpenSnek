import Foundation
import OpenSnekCore

@MainActor
final class AppStateDeviceController {
    unowned let appState: AppState

    private var stateCacheByDeviceID: [String: MouseState] = [:]
    private var lastUpdatedByDeviceID: [String: Date] = [:]
    private var refreshingStateDeviceIDs: Set<String> = []
    private var refreshingFastDpiDeviceIDs: Set<String> = []
    private var suppressFastDpiUntilByDeviceID: [String: Date] = [:]
    private var lastUSBFastDpiAtByDeviceID: [String: Date] = [:]
    private var isPollingDevices = false
    private var refreshFailureCountByDeviceID: [String: Int] = [:]
    private var stateRefreshSuppressedUntilByDeviceID: [String: Date] = [:]
    private var unavailableDeviceIDs: Set<String> = []
    private var dpiUpdateTransportStatusByDeviceID: [String: DpiUpdateTransportStatus] = [:]

    init(appState: AppState) {
        self.appState = appState
    }

    func tearDown() {
    }

    func cachedState(for deviceID: String) -> MouseState? {
        stateCacheByDeviceID[deviceID]
    }

    func storeState(_ state: MouseState, for deviceID: String, updatedAt: Date) {
        stateCacheByDeviceID[deviceID] = state
        lastUpdatedByDeviceID[deviceID] = updatedAt
    }

    func setFastDpiSuppressed(until: Date, for deviceID: String) {
        suppressFastDpiUntilByDeviceID[deviceID] = until
    }

    func diagnosticsConnectionLines(for device: MouseDevice) -> [String] {
        let deviceConnectionState = connectionState(for: device)
        let presence = appState.devices.contains(where: { $0.id == device.id }) ? "Detected by macOS" : "Not detected"
        let dpiPath = deviceConnectionState == .disconnected
            ? "Unavailable while disconnected"
            : dpiUpdateTransportStatus(for: device).diagnosticsLabel
        return [
            "Presence: \(presence)",
            "Telemetry: \(deviceConnectionState.diagnosticsLabel)",
            "DPI updates: \(dpiPath)",
        ]
    }

    func refreshConnectionDiagnostics(for device: MouseDevice) async {
        guard !isStrictlyUnsupported(device) else {
            dpiUpdateTransportStatusByDeviceID[device.id] = .unsupported
            return
        }
        guard appState.devices.contains(where: { $0.id == device.id }) || appState.selectedDeviceID == device.id else {
            dpiUpdateTransportStatusByDeviceID[device.id] = .unknown
            return
        }
        let usesFastPolling = await appState.backend.shouldUseFastDPIPolling(device: device)
        guard appState.devices.contains(where: { $0.id == device.id }) || appState.selectedDeviceID == device.id else {
            return
        }
        dpiUpdateTransportStatusByDeviceID[device.id] = usesFastPolling ? .pollingFallback : .realTimeHID
    }

    func handleBackendDeviceListUpdate(_ listed: [MouseDevice]) async {
        guard !appState.usesRemoteServiceUpdates else { return }
        let previousIDs = Set(appState.devices.map(\.id))
        _ = applyDeviceList(listed, source: "subscription")
        guard !listed.isEmpty else { return }
        let prioritizedDeviceIDs = listed
            .filter { $0.transport == .bluetooth && !previousIDs.contains($0.id) }
            .map(\.id)
        await refreshAllDeviceStates(prioritizing: prioritizedDeviceIDs)
        await refreshDpiUpdateTransportStatuses(for: listed)
    }

    func applyRemoteServiceSnapshot(_ snapshot: SharedServiceSnapshot) {
        guard appState.usesRemoteServiceUpdates else { return }

        let liveIDs = Set(snapshot.devices.map(\.id))
        stateCacheByDeviceID = stateCacheByDeviceID.filter { liveIDs.contains($0.key) }
        lastUpdatedByDeviceID = lastUpdatedByDeviceID.filter { liveIDs.contains($0.key) }

        for (deviceID, remoteState) in snapshot.stateByDeviceID {
            let snapshotUpdatedAt = snapshot.lastUpdatedByDeviceID[deviceID] ?? Date()
            if let latestCachedAt = lastUpdatedByDeviceID[deviceID],
               latestCachedAt > snapshotUpdatedAt {
                AppLog.debug(
                    "AppState",
                    "remoteSnapshot superseded-drop device=\(deviceID) updatedAt=\(snapshotUpdatedAt.timeIntervalSince1970) " +
                    "cachedAt=\(latestCachedAt.timeIntervalSince1970)"
                )
                continue
            }
            stateCacheByDeviceID[deviceID] = remoteState
            lastUpdatedByDeviceID[deviceID] = snapshotUpdatedAt
            refreshFailureCountByDeviceID[deviceID] = 0
            unavailableDeviceIDs.remove(deviceID)
        }

        _ = applyDeviceList(snapshot.devices, source: "subscription")

        if let selectedDeviceID = appState.selectedDeviceID,
           let selectedState = stateCacheByDeviceID[selectedDeviceID],
           let selectedDevice = appState.selectedDevice {
            appState.state = selectedState
            appState.lastUpdated = lastUpdatedByDeviceID[selectedDeviceID]
            if appState.applyController.shouldHydrateEditable {
                appState.editorController.hydrateEditable(from: selectedState)
            }
            appState.errorMessage = nil
            setTelemetryWarning(appState.editorController.telemetryWarning(for: selectedState, device: selectedDevice), device: selectedDevice)
        } else if let selectedDeviceID = appState.selectedDeviceID {
            syncSelectedDevicePresentation(deviceID: selectedDeviceID)
            appState.errorMessage = nil
        } else {
            appState.state = nil
            appState.lastUpdated = nil
            appState.warningMessage = nil
            appState.errorMessage = nil
        }

        Task { [weak self] in
            await self?.refreshDpiUpdateTransportStatuses(for: snapshot.devices)
        }
    }

    func applyBackendDeviceStateUpdate(deviceID: String, state updatedState: MouseState, updatedAt: Date) {
        guard let sourceDevice = appState.devices.first(where: { $0.id == deviceID }),
              let presentationDevice = presentationDevice(for: sourceDevice) else {
            return
        }

        let presentationDeviceID = presentationDevice.id
        if let latestCachedAt = latestCachedUpdateAt(sourceDeviceID: deviceID, presentationDeviceID: presentationDeviceID),
           latestCachedAt > updatedAt {
            AppLog.debug(
                "AppState",
                "backendStateUpdate superseded-drop device=\(presentationDeviceID) updatedAt=\(updatedAt.timeIntervalSince1970) " +
                "cachedAt=\(latestCachedAt.timeIntervalSince1970)"
            )
            return
        }

        let previous = stateCacheByDeviceID[presentationDeviceID] ?? stateCacheByDeviceID[deviceID]
        let merged = updatedState.merged(with: previous)
        let shouldFocusOnActivity = shouldFocusServiceSelectionOnActivity(previous: previous, next: merged)

        cacheState(merged, sourceDeviceID: deviceID, presentationDeviceID: presentationDeviceID, updatedAt: updatedAt)
        dpiUpdateTransportStatusByDeviceID[deviceID] = .realTimeHID
        dpiUpdateTransportStatusByDeviceID[presentationDeviceID] = .realTimeHID
        refreshFailureCountByDeviceID[deviceID] = 0
        refreshFailureCountByDeviceID[presentationDeviceID] = 0
        unavailableDeviceIDs.remove(deviceID)
        unavailableDeviceIDs.remove(presentationDeviceID)

        if shouldFocusOnActivity {
            focusServiceSelectionOnActivity(deviceID: presentationDeviceID)
        }

        if appState.selectedDeviceID == presentationDeviceID {
            if appState.state != merged {
                appState.state = merged
            }
            if appState.applyController.shouldHydrateEditable {
                appState.editorController.hydrateEditable(from: merged)
            }
            appState.errorMessage = nil
            setTelemetryWarning(appState.editorController.telemetryWarning(for: merged, device: presentationDevice), device: presentationDevice)
        }
    }

    func refreshDevices() async {
        guard appState.runtimeController.isBackendReady else {
            AppLog.debug("AppState", "refreshDevices deferred until backend is ready")
            return
        }
        let start = Date()
        AppLog.event("AppState", "refreshDevices start")
        appState.isLoading = true
        defer { appState.isLoading = false }

        do {
            let listed = try await appState.backend.listDevices()
            _ = applyDeviceList(listed, source: "refresh")
            appState.errorMessage = nil
        } catch {
            AppLog.error("AppState", "refreshDevices failed: \(error.localizedDescription)")
            appState.errorMessage = error.localizedDescription
        }

        await refreshAllDeviceStates()
        await refreshDpiUpdateTransportStatuses(for: appState.devices)
        AppLog.event("AppState", "refreshDevices end elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s")
    }

    func pollDevicePresence() async {
        guard !isPollingDevices, !appState.isLoading else { return }
        isPollingDevices = true
        defer { isPollingDevices = false }

        do {
            let listed = try await appState.backend.listDevices()
            let changed = applyDeviceList(listed, source: "poll")
            if changed {
                appState.errorMessage = nil
                await refreshAllDeviceStates()
                await refreshDpiUpdateTransportStatuses(for: listed)
            } else if appState.selectedDevice != nil, appState.state == nil {
                await refreshState()
            } else if let selectedDevice = appState.selectedDevice {
                await refreshConnectionDiagnostics(for: selectedDevice)
            }
        } catch {
            if appState.devices.isEmpty {
                let lowered = error.localizedDescription.lowercased()
                if lowered.contains("no device") || lowered.contains("no supported device") || lowered.contains("not found") {
                    appState.errorMessage = nil
                } else {
                    AppLog.warning("AppState", "pollDevicePresence failed with no visible devices: \(error.localizedDescription)")
                    appState.errorMessage = error.localizedDescription
                }
            } else {
                AppLog.debug("AppState", "pollDevicePresence failed: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func applyDeviceList(_ listed: [MouseDevice], source: String) -> Bool {
        let sorted = listed.sorted { $0.product_name < $1.product_name }
        let previousDevices = appState.devices
        let previousIDs = Set(previousDevices.map(\.id))
        let previousSelectedID = appState.selectedDeviceID
        let previousSelectedDevice = previousDevices.first(where: { $0.id == previousSelectedID })
        let previousSelectedIdentity = previousSelectedDevice.map(deviceIdentityKey)

        let newIDs = Set(sorted.map(\.id))
        let removedIDs = previousIDs.subtracting(newIDs)
        if !removedIDs.isEmpty {
            appState.editorController.removeHydratedState(for: removedIDs)
            for id in removedIDs {
                stateCacheByDeviceID[id] = nil
                refreshFailureCountByDeviceID[id] = nil
                stateRefreshSuppressedUntilByDeviceID[id] = nil
                unavailableDeviceIDs.remove(id)
                dpiUpdateTransportStatusByDeviceID[id] = nil
                lastUpdatedByDeviceID[id] = nil
                suppressFastDpiUntilByDeviceID[id] = nil
                lastUSBFastDpiAtByDeviceID[id] = nil
                refreshingStateDeviceIDs.remove(id)
                refreshingFastDpiDeviceIDs.remove(id)
            }
        }

        appState.devices = sorted
        if let previousSelectedID, newIDs.contains(previousSelectedID) {
            appState.selectedDeviceID = previousSelectedID
        } else if let previousSelectedIdentity,
                  let match = sorted.first(where: { deviceIdentityKey($0) == previousSelectedIdentity }) {
            appState.selectedDeviceID = match.id
        } else {
            appState.selectedDeviceID = sorted.first?.id
        }

        if let recoverySelection = preferredBluetoothRecoverySelection(
            in: sorted,
            previousIDs: previousIDs,
            previousSelectedDevice: previousSelectedDevice
        ) {
            appState.selectedDeviceID = recoverySelection.id
            AppLog.event(
                "AppState",
                "applyDeviceList recovery-select previous=\(previousSelectedDevice?.id ?? "nil") replacement=\(recoverySelection.id)"
            )
        }

        if let selectedDeviceID = appState.selectedDeviceID {
            syncSelectedDevicePresentation(deviceID: selectedDeviceID)
        } else {
            appState.state = nil
            appState.errorMessage = nil
            appState.warningMessage = nil
            appState.lastUpdated = nil
        }

        let changed = previousIDs != newIDs || previousSelectedID != appState.selectedDeviceID
        if changed {
            AppLog.event(
                "AppState",
                "applyDeviceList source=\(source) count=\(sorted.count) selected=\(appState.selectedDeviceID ?? "nil")"
            )
        }
        if appState.usesRemoteServiceUpdates, previousSelectedID != appState.selectedDeviceID {
            appState.runtimeController.sendRemoteClientPresence()
        }
        return changed
    }

    func preferredBluetoothRecoverySelection(
        in devices: [MouseDevice],
        previousIDs: Set<String>,
        previousSelectedDevice: MouseDevice?
    ) -> MouseDevice? {
        guard let previousSelectedDevice else { return nil }
        guard appState.selectedDeviceID == previousSelectedDevice.id else { return nil }
        guard previousSelectedDevice.transport == .usb else { return nil }
        guard selectedDeviceNeedsRecovery(previousSelectedDevice) else { return nil }

        let newlyAddedBluetoothDevices = devices.filter { candidate in
            candidate.transport == .bluetooth && !previousIDs.contains(candidate.id)
        }
        guard !newlyAddedBluetoothDevices.isEmpty else { return nil }

        let previousSerial = normalizedSerial(for: previousSelectedDevice)
        if let previousSerial {
            let serialMatches = newlyAddedBluetoothDevices.filter {
                normalizedSerial(for: $0) == previousSerial
            }
            if serialMatches.count == 1 {
                return serialMatches[0]
            }
        }

        let nameMatches = newlyAddedBluetoothDevices.filter {
            $0.product_name == previousSelectedDevice.product_name
        }
        if nameMatches.count == 1 {
            return nameMatches[0]
        }

        return nil
    }

    func selectDevice(_ deviceID: String) {
        guard appState.selectedDeviceID != deviceID else { return }
        appState.selectedDeviceID = deviceID
        syncSelectedDevicePresentation(deviceID: deviceID)
        if let selectedDevice = appState.selectedDevice {
            Task { [weak self] in
                await self?.refreshConnectionDiagnostics(for: selectedDevice)
            }
        }
        if appState.usesRemoteServiceUpdates {
            appState.runtimeController.sendRemoteClientPresence()
        }
    }

    func syncSelectedDevicePresentation(deviceID: String) {
        guard let device = appState.devices.first(where: { $0.id == deviceID }) else {
            appState.state = nil
            appState.errorMessage = nil
            appState.warningMessage = nil
            appState.lastUpdated = nil
            appState.isRefreshingState = false
            return
        }

        appState.isRefreshingState = refreshingStateDeviceIDs.contains(deviceID)
        if unavailableDeviceIDs.contains(deviceID) {
            appState.state = nil
            appState.lastUpdated = nil
            appState.warningMessage = nil
            if appState.errorMessage == nil || !Self.isDeviceAvailabilityMessage(appState.errorMessage ?? "") {
                appState.errorMessage = "Device disconnected or unavailable"
            }
        } else if let cached = stateCacheByDeviceID[deviceID] {
            appState.state = cached
            appState.lastUpdated = lastUpdatedByDeviceID[deviceID]
            appState.warningMessage = appState.editorController.telemetryWarning(for: cached, device: device)
            if appState.applyController.shouldHydrateEditable {
                appState.editorController.hydrateEditable(from: cached)
            }
        } else if let state = appState.state, stateSummaryMatchesDevice(state, device: device) {
            appState.warningMessage = appState.editorController.telemetryWarning(for: state, device: device)
            if appState.applyController.shouldHydrateEditable {
                appState.editorController.hydrateEditable(from: state)
            }
        } else {
            appState.state = nil
            appState.lastUpdated = nil
            appState.warningMessage = nil
        }
        if !unavailableDeviceIDs.contains(deviceID) {
            appState.errorMessage = nil
        }
    }

    func setTelemetryWarning(_ newValue: String?, device: MouseDevice) {
        if appState.warningMessage != newValue, let newValue {
            AppLog.warning("AppState", "telemetry degraded device=\(device.id) transport=\(device.transport.rawValue): \(newValue)")
        }
        appState.warningMessage = newValue
    }

    func connectionState(for device: MouseDevice) -> DeviceConnectionState {
        if isStrictlyUnsupported(device) {
            return .unsupported
        }

        if !appState.devices.contains(where: { $0.id == device.id }) && appState.selectedDeviceID != device.id {
            return .disconnected
        }

        if unavailableDeviceIDs.contains(device.id) {
            return .disconnected
        }

        if device.id == appState.selectedDeviceID, let errorMessage = appState.errorMessage, !errorMessage.isEmpty {
            let lowered = errorMessage.lowercased()
            return Self.isDeviceAvailabilityMessage(lowered) ? .disconnected : .error
        }

        let failures = refreshFailureCountByDeviceID[device.id] ?? 0
        if failures > 0 {
            return .reconnecting
        }

        guard let updatedAt = lastUpdatedTimestamp(for: device) else {
            return .reconnecting
        }

        let age = Date().timeIntervalSince(updatedAt)
        if age > max(4.5, appState.currentPollingProfile.refreshStateInterval * 1.7) {
            return .reconnecting
        }

        return .connected
    }

    func statusIndicator(for device: MouseDevice) -> DeviceStatusIndicator {
        connectionState(for: device).indicator
    }

    func lastUpdatedTimestamp(for device: MouseDevice) -> Date? {
        lastUpdatedByDeviceID[device.id] ?? (device.id == appState.selectedDeviceID ? appState.lastUpdated : nil)
    }

    func dpiUpdateTransportStatus(for device: MouseDevice) -> DpiUpdateTransportStatus {
        if isStrictlyUnsupported(device) {
            return .unsupported
        }
        return dpiUpdateTransportStatusByDeviceID[device.id] ?? .unknown
    }

    func refreshDpiUpdateTransportStatuses(for devices: [MouseDevice]) async {
        for device in devices {
            await refreshConnectionDiagnostics(for: device)
        }
    }

    func focusServiceSelectionOnActivity(deviceID: String) {
        guard appState.launchRole.isService else { return }
        guard appState.selectedDeviceID != deviceID else { return }
        guard appState.devices.contains(where: { $0.id == deviceID }) else { return }
        appState.selectedDeviceID = deviceID
        syncSelectedDevicePresentation(deviceID: deviceID)
    }

    func shouldFocusServiceSelectionOnActivity(previous: MouseState?, next: MouseState) -> Bool {
        guard appState.launchRole.isService else { return false }
        guard let previous else { return false }

        return previous.dpi != next.dpi ||
            previous.dpi_stages != next.dpi_stages ||
            previous.poll_rate != next.poll_rate ||
            previous.sleep_timeout != next.sleep_timeout ||
            previous.device_mode != next.device_mode ||
            previous.low_battery_threshold_raw != next.low_battery_threshold_raw ||
            previous.scroll_mode != next.scroll_mode ||
            previous.scroll_acceleration != next.scroll_acceleration ||
            previous.scroll_smart_reel != next.scroll_smart_reel ||
            previous.active_onboard_profile != next.active_onboard_profile ||
            previous.onboard_profile_count != next.onboard_profile_count ||
            previous.led_value != next.led_value
    }

    func deviceIdentityKey(_ device: MouseDevice) -> String {
        if let serial = device.serial?.trimmingCharacters(in: .whitespacesAndNewlines),
           !serial.isEmpty {
            return "serial:\(serial.lowercased())"
        }
        return String(
            format: "vp:%04x:%04x:%@",
            device.vendor_id,
            device.product_id,
            device.transport.rawValue
        )
    }

    func stateSummaryMatchesDevice(_ state: MouseState, device: MouseDevice) -> Bool {
        let deviceSerial = device.serial?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let stateSerial = state.device.serial?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if let deviceSerial, !deviceSerial.isEmpty,
           let stateSerial, !stateSerial.isEmpty {
            return deviceSerial == stateSerial
        }

        return state.device.transport == device.transport &&
            state.device.product_name == device.product_name
    }

    func selectedDeviceNeedsRecovery(_ device: MouseDevice) -> Bool {
        if unavailableDeviceIDs.contains(device.id) {
            return true
        }
        if (refreshFailureCountByDeviceID[device.id] ?? 0) > 0 {
            return true
        }
        if stateCacheByDeviceID[device.id] != nil || lastUpdatedByDeviceID[device.id] != nil {
            return false
        }
        if appState.selectedDeviceID == device.id,
           let state = appState.state,
           stateSummaryMatchesDevice(state, device: device) {
            return false
        }
        return true
    }

    func normalizedSerial(for device: MouseDevice) -> String? {
        guard let serial = device.serial?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !serial.isEmpty else {
            return nil
        }
        return serial
    }

    func isStrictlyUnsupported(_ device: MouseDevice) -> Bool {
        appState.resolvedProfile(for: device) == nil && device.transport == .bluetooth
    }

    func presentationDevice(for device: MouseDevice) -> MouseDevice? {
        if let exactMatch = appState.devices.first(where: { $0.id == device.id }) {
            return exactMatch
        }
        let identityKey = deviceIdentityKey(device)
        return appState.devices.first(where: { deviceIdentityKey($0) == identityKey })
    }

    func refreshableDevicesInPriorityOrder(prioritizing prioritizedDeviceIDs: [String] = []) -> [MouseDevice] {
        guard !appState.devices.isEmpty else { return [] }
        let now = Date()

        var ordered: [MouseDevice] = []
        var seen: Set<String> = []

        for deviceID in prioritizedDeviceIDs {
            guard let device = appState.devices.first(where: { $0.id == deviceID }) else { continue }
            guard !isStrictlyUnsupported(device) else { continue }
            guard seen.insert(device.id).inserted else { continue }
            ordered.append(device)
        }

        if let selectedDevice = appState.selectedDevice,
           !isStrictlyUnsupported(selectedDevice),
           seen.insert(selectedDevice.id).inserted {
            ordered.append(selectedDevice)
        }

        for device in appState.devices where !isStrictlyUnsupported(device) {
            guard seen.insert(device.id).inserted else { continue }
            if appState.selectedDeviceID != device.id,
               let suppressedUntil = stateRefreshSuppressedUntilByDeviceID[device.id],
               now < suppressedUntil {
                continue
            }
            ordered.append(device)
        }

        return ordered
    }

    func cacheState(_ state: MouseState, sourceDeviceID: String, presentationDeviceID: String, updatedAt: Date = Date()) {
        stateCacheByDeviceID[sourceDeviceID] = state
        lastUpdatedByDeviceID[sourceDeviceID] = updatedAt

        if presentationDeviceID != sourceDeviceID {
            stateCacheByDeviceID[presentationDeviceID] = state
            lastUpdatedByDeviceID[presentationDeviceID] = updatedAt
        }

        if appState.selectedDeviceID == presentationDeviceID {
            appState.lastUpdated = updatedAt
        }
    }

    func latestCachedUpdateAt(sourceDeviceID: String, presentationDeviceID: String) -> Date? {
        [lastUpdatedByDeviceID[sourceDeviceID], lastUpdatedByDeviceID[presentationDeviceID]]
            .compactMap { $0 }
            .max()
    }

    static func isDeviceAvailabilityMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("no device") ||
            lowered.contains("disconnected") ||
            lowered.contains("not available") ||
            lowered.contains("telemetry unavailable") ||
            lowered.contains("bt vendor timeout") ||
            lowered.contains("failed to connect") ||
            lowered.contains("bluetooth is powered off")
    }

    func stateRefreshBackoffInterval(for device: MouseDevice, failures: Int, error: any Error) -> TimeInterval {
        let lowered = error.localizedDescription.lowercased()
        if device.transport == .usb,
           lowered.contains("telemetry unavailable") || lowered.contains("usable responses") {
            return 30.0
        }

        switch failures {
        case ...1:
            return 8.0
        case 2:
            return 15.0
        case 3:
            return 30.0
        default:
            return 60.0
        }
    }

    func refreshState() async {
        guard let selectedDevice = appState.selectedDevice else {
            appState.state = nil
            appState.errorMessage = nil
            appState.warningMessage = nil
            appState.lastUpdated = nil
            appState.isRefreshingState = false
            return
        }
        guard !isStrictlyUnsupported(selectedDevice) else {
            appState.state = nil
            appState.warningMessage = nil
            appState.errorMessage = nil
            appState.lastUpdated = nil
            appState.isRefreshingState = false
            return
        }
        _ = await refreshState(for: selectedDevice)
    }

    func refreshAllDeviceStates(prioritizing prioritizedDeviceIDs: [String] = []) async {
        let devicesToRefresh = refreshableDevicesInPriorityOrder(prioritizing: prioritizedDeviceIDs)
        guard !devicesToRefresh.isEmpty else {
            if let selectedDevice = appState.selectedDevice, isStrictlyUnsupported(selectedDevice) {
                appState.state = nil
                appState.warningMessage = nil
                appState.errorMessage = nil
                appState.lastUpdated = nil
                appState.isRefreshingState = false
            } else if let selectedDeviceID = appState.selectedDeviceID {
                syncSelectedDevicePresentation(deviceID: selectedDeviceID)
            } else {
                appState.state = nil
                appState.warningMessage = nil
                appState.errorMessage = nil
                appState.lastUpdated = nil
                appState.isRefreshingState = false
            }
            return
        }

        for device in devicesToRefresh {
            _ = await refreshState(for: device)
        }

        if let selectedDeviceID = appState.selectedDeviceID {
            syncSelectedDevicePresentation(deviceID: selectedDeviceID)
        }
    }

    @discardableResult
    func refreshState(for device: MouseDevice) async -> Bool {
        guard !isStrictlyUnsupported(device) else { return false }
        guard !refreshingStateDeviceIDs.contains(device.id) else { return false }
        guard !appState.isApplying else {
            AppLog.debug("AppState", "refreshState skipped applying device=\(device.id)")
            return false
        }
        guard !appState.applyController.hasPendingLocalEditsAffecting(device) else {
            AppLog.debug("AppState", "refreshState skipped pending-local-edits device=\(device.id)")
            return false
        }

        if appState.selectedDeviceID == device.id, let cached = stateCacheByDeviceID[device.id] {
            appState.state = cached
        }

        refreshingStateDeviceIDs.insert(device.id)
        if appState.selectedDeviceID == device.id {
            appState.isRefreshingState = true
        }
        defer {
            refreshingStateDeviceIDs.remove(device.id)
            if appState.selectedDeviceID == device.id {
                appState.isRefreshingState = false
            }
        }

        let refreshRevision = appState.applyController.stateRevision
        let refreshDeviceID = device.id
        let start = Date()

        do {
            let fetched = try await appState.backend.readState(device: device)
            guard refreshRevision == appState.applyController.stateRevision else {
                AppLog.debug("AppState", "refreshState stale-drop rev=\(refreshRevision) current=\(appState.applyController.stateRevision)")
                return false
            }
            guard let presentationDevice = presentationDevice(for: device) else {
                AppLog.debug("AppState", "refreshState drop missing-presentation device=\(refreshDeviceID)")
                return false
            }

            let presentationDeviceID = presentationDevice.id
            if let latestCachedAt = latestCachedUpdateAt(sourceDeviceID: refreshDeviceID, presentationDeviceID: presentationDeviceID),
               latestCachedAt > start {
                AppLog.debug(
                    "AppState",
                    "refreshState superseded-drop device=\(presentationDeviceID) startedAt=\(start.timeIntervalSince1970) " +
                    "cachedAt=\(latestCachedAt.timeIntervalSince1970)"
                )
                return false
            }
            let previous = stateCacheByDeviceID[presentationDeviceID] ?? stateCacheByDeviceID[refreshDeviceID]
            let merged = fetched.merged(with: previous)
            let shouldFocusOnActivity = shouldFocusServiceSelectionOnActivity(previous: previous, next: merged)
            let updatedAt = Date()
            cacheState(merged, sourceDeviceID: refreshDeviceID, presentationDeviceID: presentationDeviceID, updatedAt: updatedAt)
            refreshFailureCountByDeviceID[refreshDeviceID] = 0
            refreshFailureCountByDeviceID[presentationDeviceID] = 0
            stateRefreshSuppressedUntilByDeviceID[refreshDeviceID] = nil
            stateRefreshSuppressedUntilByDeviceID[presentationDeviceID] = nil
            unavailableDeviceIDs.remove(refreshDeviceID)
            unavailableDeviceIDs.remove(presentationDeviceID)
            if shouldFocusOnActivity {
                focusServiceSelectionOnActivity(deviceID: presentationDeviceID)
            }

            if appState.selectedDeviceID == presentationDeviceID {
                if appState.state != merged {
                    appState.state = merged
                }
                if appState.applyController.shouldHydrateEditable {
                    appState.editorController.hydrateEditable(from: merged)
                    await appState.editorController.hydrateLightingStateIfNeeded(device: presentationDevice)
                    await appState.editorController.hydrateButtonBindingsIfNeeded(device: presentationDevice)
                }
                appState.errorMessage = nil
                setTelemetryWarning(appState.editorController.telemetryWarning(for: merged, device: presentationDevice), device: presentationDevice)
            }

            AppLog.debug(
                "AppState",
                "refreshState ok device=\(presentationDeviceID) active=\(merged.dpi_stages.active_stage.map(String.init) ?? "nil") " +
                "values=\(merged.dpi_stages.values?.map(String.init).joined(separator: ",") ?? "nil") " +
                "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
            )
            return true
        } catch {
            let presentationDeviceID = presentationDevice(for: device)?.id ?? refreshDeviceID
            let failures = (refreshFailureCountByDeviceID[presentationDeviceID] ?? 0) + 1
            refreshFailureCountByDeviceID[refreshDeviceID] = failures
            refreshFailureCountByDeviceID[presentationDeviceID] = failures
            let isAvailabilityFailure = Self.isDeviceAvailabilityMessage(error.localizedDescription)
            if isAvailabilityFailure {
                unavailableDeviceIDs.insert(refreshDeviceID)
                unavailableDeviceIDs.insert(presentationDeviceID)
            }

            if appState.selectedDeviceID != presentationDeviceID {
                let suppressedUntil = Date().addingTimeInterval(
                    stateRefreshBackoffInterval(for: device, failures: failures, error: error)
                )
                stateRefreshSuppressedUntilByDeviceID[refreshDeviceID] = suppressedUntil
                stateRefreshSuppressedUntilByDeviceID[presentationDeviceID] = suppressedUntil
                AppLog.debug(
                    "AppState",
                    "refreshState backoff device=\(presentationDeviceID) failures=\(failures) " +
                    "until=\(suppressedUntil.timeIntervalSince1970): \(error.localizedDescription)"
                )
            }

            guard appState.selectedDeviceID == presentationDeviceID else {
                AppLog.debug("AppState", "refreshState masked non-selected failure device=\(presentationDeviceID): \(error.localizedDescription)")
                return false
            }

            if isAvailabilityFailure {
                appState.state = nil
                appState.lastUpdated = nil
                appState.warningMessage = nil
                appState.errorMessage = error.localizedDescription
                return false
            }

            if stateCacheByDeviceID[presentationDeviceID] == nil {
                AppLog.error(
                    "AppState",
                    "refreshState failed device=\(presentationDeviceID) transport=\(device.transport.rawValue) no-cache: \(error.localizedDescription)"
                )
                appState.errorMessage = error.localizedDescription
                appState.warningMessage = nil
            } else {
                AppLog.debug("AppState", "refreshState transient-failure masked: \(error.localizedDescription)")
                if failures >= 3 {
                    if failures == 3 {
                        AppLog.warning(
                            "AppState",
                            "device read unstable device=\(presentationDeviceID) failures=\(failures): \(error.localizedDescription)"
                        )
                    }
                    appState.errorMessage = "Device read is failing repeatedly (\(failures)x): \(error.localizedDescription)"
                } else {
                    appState.errorMessage = nil
                }
                appState.warningMessage = "Using the last known values while live telemetry settles."
            }
            return false
        }
    }

    func refreshDpiFast() async {
        guard !appState.isApplying else { return }

        let now = Date()
        for deviceID in appState.runtimeController.activeFastPollingDeviceIDs(at: now) {
            guard let device = appState.devices.first(where: { $0.id == deviceID }) else { continue }
            await refreshDpiFast(for: device, now: now)
        }
    }

    private func refreshDpiFast(for device: MouseDevice, now: Date) async {
        guard device.transport == .bluetooth || device.transport == .usb else { return }
        guard !isStrictlyUnsupported(device) else { return }
        guard !refreshingFastDpiDeviceIDs.contains(device.id) else { return }
        guard !refreshingStateDeviceIDs.contains(device.id) else { return }
        guard !appState.applyController.hasPendingLocalEditsAffecting(device) else { return }
        let usesFastPolling = await appState.backend.shouldUseFastDPIPolling(device: device)
        if !usesFastPolling {
            dpiUpdateTransportStatusByDeviceID[device.id] = .realTimeHID
            return
        }

        if device.transport == .usb,
           let lastUSBFastDpiAt = lastUSBFastDpiAtByDeviceID[device.id],
           now.timeIntervalSince(lastUSBFastDpiAt) < 0.55 {
            return
        }
        if let until = suppressFastDpiUntilByDeviceID[device.id] {
            if now < until { return }
            suppressFastDpiUntilByDeviceID[device.id] = nil
        }

        refreshingFastDpiDeviceIDs.insert(device.id)
        defer { refreshingFastDpiDeviceIDs.remove(device.id) }
        let fastRevision = appState.applyController.stateRevision

        do {
            guard let fast = try await appState.backend.readDpiStagesFast(device: device) else { return }
            guard let presentationDevice = presentationDevice(for: device) else { return }
            let readAt = Date()
            if device.transport == .usb {
                lastUSBFastDpiAtByDeviceID[device.id] = readAt
                lastUSBFastDpiAtByDeviceID[presentationDevice.id] = readAt
            }
            guard fastRevision == appState.applyController.stateRevision else {
                AppLog.debug("AppState", "refreshDpiFast stale-drop rev=\(fastRevision) current=\(appState.applyController.stateRevision)")
                return
            }
            let presentationDeviceID = presentationDevice.id
            let previous = stateCacheByDeviceID[presentationDeviceID] ?? stateCacheByDeviceID[device.id] ?? appState.state
            guard let previous else { return }
            let active = max(0, min(fast.values.count - 1, fast.active))
            let currentDpiValue = fast.values[active]
            let updated = MouseState(
                device: previous.device,
                connection: previous.connection,
                battery_percent: previous.battery_percent,
                charging: previous.charging,
                dpi: DpiPair(x: currentDpiValue, y: currentDpiValue),
                dpi_stages: DpiStages(active_stage: active, values: fast.values),
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

            let shouldFocusOnActivity = shouldFocusServiceSelectionOnActivity(previous: previous, next: updated)
            cacheState(updated, sourceDeviceID: device.id, presentationDeviceID: presentationDeviceID, updatedAt: readAt)
            dpiUpdateTransportStatusByDeviceID[device.id] = .pollingFallback
            dpiUpdateTransportStatusByDeviceID[presentationDeviceID] = .pollingFallback
            unavailableDeviceIDs.remove(device.id)
            unavailableDeviceIDs.remove(presentationDeviceID)
            if shouldFocusOnActivity {
                focusServiceSelectionOnActivity(deviceID: presentationDeviceID)
            }
            if appState.selectedDeviceID == presentationDeviceID {
                if appState.state != updated {
                    appState.state = updated
                }
                if appState.applyController.shouldHydrateEditable {
                    appState.editorController.hydrateEditable(from: updated)
                }
            }
            AppLog.debug(
                "AppState",
                "refreshDpiFast ok device=\(presentationDeviceID) active=\(active) " +
                "values=\(fast.values.map(String.init).joined(separator: ","))"
            )
        } catch {
            // Ignore fast-poll transient failures to keep UI stable.
        }
    }
}
