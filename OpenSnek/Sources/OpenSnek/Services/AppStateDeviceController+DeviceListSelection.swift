import Foundation
import OpenSnekCore
import OpenSnekHardware

@MainActor
extension AppStateDeviceController {
    func refreshDevices() async {
        guard !isTearingDown else { return }
        guard runtimeController.isBackendReady else {
            AppLog.debug("AppState", "refreshDevices deferred until backend is ready")
            return
        }
        guard !isRefreshingDevices else {
            AppLog.debug("AppState", "refreshDevices skipped already-refreshing")
            return
        }
        isRefreshingDevices = true
        let start = Date()
        AppLog.event("AppState", "refreshDevices start")
        deviceStore.isLoading = true
        defer {
            deviceStore.isLoading = false
            isRefreshingDevices = false
        }

        do {
            let listed = try await environment.backend.listDevices()
            _ = applyDeviceList(listed, source: "refresh")
            deviceStore.errorMessage = nil
        } catch {
            AppLog.error("AppState", "refreshDevices failed: \(error.localizedDescription)")
            deviceStore.errorMessage = error.localizedDescription
        }

        await refreshVisibleDeviceStatesForCurrentRuntimeContext()
        await refreshDpiUpdateTransportStatuses(for: deviceStore.devices)
        AppLog.event("AppState", "refreshDevices end elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s")
    }

    func pollDevicePresence() async {
        guard !isTearingDown else { return }
        guard !isPollingDevices, !deviceStore.isLoading else { return }
        isPollingDevices = true
        defer { isPollingDevices = false }

        do {
            let listed = try await environment.backend.listDevices()
            let changed = applyDeviceList(listed, source: "poll")
            if changed {
                deviceStore.errorMessage = nil
                await refreshVisibleDeviceStatesForCurrentRuntimeContext()
                await refreshDpiUpdateTransportStatuses(for: listed)
            } else if deviceStore.selectedDevice != nil, deviceStore.state == nil {
                await refreshState()
            } else if let selectedDevice = deviceStore.selectedDevice {
                await refreshConnectionDiagnostics(for: selectedDevice)
            }
        } catch {
            if deviceStore.devices.isEmpty {
                let lowered = error.localizedDescription.lowercased()
                if lowered.contains("no device") || lowered.contains("no supported device") || lowered.contains("not found") {
                    deviceStore.errorMessage = nil
                } else {
                    AppLog.warning("AppState", "pollDevicePresence failed with no visible devices: \(error.localizedDescription)")
                    deviceStore.errorMessage = error.localizedDescription
                }
            } else {
                AppLog.debug("AppState", "pollDevicePresence failed: \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    func applyDeviceList(_ listed: [MouseDevice], source: String, updatedAt: Date = Date()) -> Bool {
        guard !isTearingDown else { return false }
        guard let editorController = optionalEditorController,
              let runtimeController = optionalRuntimeController else {
            return false
        }
        let sorted = listed.sorted { $0.product_name < $1.product_name }
        let previousDevices = deviceStore.devices
        let previousIDs = Set(previousDevices.map(\.id))
        let previousSelectedID = deviceStore.selectedDeviceID
        let previousSelectedDevice = previousDevices.first(where: { $0.id == previousSelectedID })
        let previousSelectedIdentity = previousSelectedDevice.map(deviceIdentityKey)

        let newIDs = Set(sorted.map(\.id))
        let removedIDs = previousIDs.subtracting(newIDs)
        let removedReconnectSeedByIdentity = reconnectSeedStatesByIdentity(
            previousDevices: previousDevices,
            removedIDs: removedIDs
        )
        if source == "subscription" {
            let newlyVisibleIDs = newIDs.subtracting(previousIDs)
            armUSBPhysicalConnectSettling(
                for: newlyVisibleIDs,
                in: sorted,
                observedAt: updatedAt
            )
            let suppressedDeviceIDs = newlyVisibleIDs.filter { id in
                stateRefreshSuppressedUntilByDeviceID[id] != nil &&
                    !isUSBDeviceID(id, in: sorted) &&
                    !usbTelemetryUnavailableBackoffDeviceIDs.contains(id)
            }
            let preservedUSBBackoffIDs = newlyVisibleIDs.filter { id in
                stateRefreshSuppressedUntilByDeviceID[id] != nil &&
                    (isUSBDeviceID(id, in: sorted) || usbTelemetryUnavailableBackoffDeviceIDs.contains(id))
            }
            for id in suppressedDeviceIDs {
                stateRefreshSuppressedUntilByDeviceID[id] = nil
            }
            if !suppressedDeviceIDs.isEmpty {
                AppLog.debug(
                    "AppState",
                    "refreshState backoff cleared by device-list subscription devices=\(suppressedDeviceIDs.sorted().joined(separator: ","))"
                )
            }
            if !preservedUSBBackoffIDs.isEmpty {
                AppLog.debug(
                    "AppState",
                    "refreshState usb backoff preserved by device-list subscription devices=\(preservedUSBBackoffIDs.sorted().joined(separator: ","))"
                )
            }
        }
        if !removedIDs.isEmpty {
            editorController.removeHydratedState(for: removedIDs)
            for id in removedIDs {
                stateCacheByDeviceID[id] = nil
                refreshFailureCountByDeviceID[id] = nil
                stateRefreshSuppressedUntilByDeviceID[id] = nil
                usbTelemetryUnavailableBackoffDeviceIDs.remove(id)
                usbControlAvailabilityByDeviceID.removeValue(forKey: id)
                cancelPendingUSBControlUnavailable(for: id)
                clearUSBPhysicalConnectSettling(for: id)
                unavailableDeviceIDs.remove(id)
                setDpiUpdateTransportStatus(nil, for: id)
                lastUpdatedByDeviceID[id] = nil
                lastStateMutationAtByDeviceID[id] = nil
                lastFullStateRefreshStartedAtByDeviceID[id] = nil
                suppressFastDpiUntilByDeviceID[id] = nil
                lastUSBFastDpiAtByDeviceID[id] = nil
                lastPassiveHeartbeatAtByDeviceID[id] = nil
                refreshingStateDeviceIDs.remove(id)
                refreshingFastDpiDeviceIDs.remove(id)
                pendingSettingsRestoreDeviceIDs.remove(id)
                pendingSettingsRestoreGenerationByDeviceID[id] = nil
                restoringSettingsDeviceIDs.remove(id)
                settingsRestoreRevisionByDeviceID[id] = nil
                seededReconnectStateDeviceIDs.remove(id)
            }
        }

        if !environment.usesRemoteServiceTransport {
            let newlyVisibleIDs = newIDs.subtracting(previousIDs)
            if !newlyVisibleIDs.isEmpty {
                armPendingSettingsRestore(for: newlyVisibleIDs)
            }
            if source == "subscription", previousIDs == newIDs, !newIDs.isEmpty {
                armPendingSettingsRestore(for: newIDs)
            }
        }
        if !environment.usesRemoteServiceTransport, source == "subscription", previousIDs == newIDs, !newIDs.isEmpty {
            editorController.invalidateOnboardProfileState(for: newIDs)
        }

        deviceStore.devices = sorted
        if let previousSelectedID, newIDs.contains(previousSelectedID) {
            deviceStore.selectedDeviceID = previousSelectedID
        } else if shouldPreserveMissingBluetoothSelection(
            previousSelectedID: previousSelectedID,
            previousSelectedDevice: previousSelectedDevice,
            devices: sorted
        ) {
            deviceStore.selectedDeviceID = previousSelectedID
        } else if let previousSelectedIdentity,
                  let match = sorted.first(where: { deviceIdentityKey($0) == previousSelectedIdentity }) {
            deviceStore.selectedDeviceID = match.id
        } else {
            deviceStore.selectedDeviceID = sorted.first?.id
        }

        if let recoverySelection = preferredBluetoothRecoverySelection(
            in: sorted,
            previousIDs: previousIDs,
            previousSelectedDevice: previousSelectedDevice
        ) {
            deviceStore.selectedDeviceID = recoverySelection.id
            AppLog.event(
                "AppState",
                "applyDeviceList recovery-select previous=\(previousSelectedDevice?.id ?? "nil") replacement=\(recoverySelection.id)"
            )
        }

        if let preferredServiceSelection = runtimeController.preferredServiceSelectedDeviceID(
            availableDeviceIDs: newIDs,
            currentSelectedDeviceID: deviceStore.selectedDeviceID
        ) {
            deviceStore.selectedDeviceID = preferredServiceSelection
        }

        if previousSelectedID != deviceStore.selectedDeviceID {
            optionalApplyController?.cancelPendingLocalEditsForSelectionChange()
            cancelSelectedRecoveryRefresh()
        }

        seedSelectedDeviceStateFromReconnectIfNeeded(
            previousSelectedDevice: previousSelectedDevice,
            selectedDeviceID: deviceStore.selectedDeviceID,
            removedReconnectSeedByIdentity: removedReconnectSeedByIdentity
        )

        if let selectedDeviceID = deviceStore.selectedDeviceID {
            syncSelectedDevicePresentation(deviceID: selectedDeviceID)
        } else {
            deviceStore.state = nil
            deviceStore.errorMessage = nil
            deviceStore.warningMessage = nil
            deviceStore.lastUpdated = nil
        }

        let changed = previousIDs != newIDs || previousSelectedID != deviceStore.selectedDeviceID
        if changed {
            runtimeController.clearStatusItemTransientDpi()
            AppLog.event(
                "AppState",
                "applyDeviceList source=\(source) count=\(sorted.count) selected=\(deviceStore.selectedDeviceID ?? "nil")"
            )
        }
        if environment.usesRemoteServiceTransport, previousSelectedID != deviceStore.selectedDeviceID {
            runtimeController.sendRemoteClientPresence()
        }

        if let selectedDevice = deviceStore.selectedDevice {
            requestSelectedDeviceRefreshIfNeeded(for: selectedDevice)
        }
        return changed
    }

    func isUSBDeviceID(_ deviceID: String, in devices: [MouseDevice]) -> Bool {
        devices.first(where: { $0.id == deviceID })?.transport == .usb
    }

    func preferredBluetoothRecoverySelection(
        in devices: [MouseDevice],
        previousIDs: Set<String>,
        previousSelectedDevice: MouseDevice?
    ) -> MouseDevice? {
        guard let previousSelectedDevice else { return nil }
        guard deviceStore.selectedDeviceID == previousSelectedDevice.id else { return nil }
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

    func shouldPreserveMissingBluetoothSelection(
        previousSelectedID: String?,
        previousSelectedDevice: MouseDevice?,
        devices: [MouseDevice]
    ) -> Bool {
        guard let previousSelectedID,
              let previousSelectedDevice,
              previousSelectedDevice.transport == .bluetooth else {
            return false
        }
        guard !devices.contains(where: { $0.id == previousSelectedID }) else {
            return false
        }

        let identity = deviceIdentityKey(previousSelectedDevice)
        let sameIdentityDevices = devices.filter { deviceIdentityKey($0) == identity }
        guard sameIdentityDevices.contains(where: { $0.transport == .usb }) else {
            return false
        }
        return !sameIdentityDevices.contains(where: { $0.transport == .bluetooth })
    }

    func selectDevice(_ deviceID: String) {
        guard !isTearingDown else { return }
        guard let runtimeController = optionalRuntimeController else { return }
        guard deviceStore.selectedDeviceID != deviceID else { return }
        optionalApplyController?.cancelPendingLocalEditsForSelectionChange()
        runtimeController.clearStatusItemTransientDpi()
        deviceStore.selectedDeviceID = deviceID
        syncSelectedDevicePresentation(deviceID: deviceID)
        if let selectedDevice = deviceStore.selectedDevice {
            requestSelectedDeviceRefreshIfNeeded(for: selectedDevice)
            Task { [weak self] in
                await self?.refreshConnectionDiagnostics(for: selectedDevice)
            }
        }
        if environment.usesRemoteServiceTransport {
            runtimeController.sendRemoteClientPresence()
        }
    }

    func syncSelectedDevicePresentation(deviceID: String) {
        guard !isTearingDown else { return }
        guard let applyController = optionalApplyController,
              let editorController = optionalEditorController else {
            return
        }
        guard let device = deviceStore.devices.first(where: { $0.id == deviceID }) else {
            deviceStore.state = nil
            deviceStore.errorMessage = nil
            deviceStore.warningMessage = nil
            deviceStore.lastUpdated = nil
            deviceStore.isRefreshingState = false
            return
        }

        deviceStore.isRefreshingState = refreshingStateDeviceIDs.contains(deviceID)
        let holdsPersistedConnectPresentation = primeSelectedConnectPresentationIfNeeded(
            device: device,
            applyController: applyController,
            editorController: editorController
        )
        let usbAvailability = usbControlAvailability(for: device)
        let preservesTelemetryBackoffPresentation = shouldPreserveUSBTelemetryBackoffPresentation(for: device)
        if usbAvailability == .receiverPresentMouseUnavailable, let cached = stateCacheByDeviceID[deviceID] {
            deviceStore.state = cached
            deviceStore.lastUpdated = lastUpdatedByDeviceID[deviceID]
            deviceStore.warningMessage = nil
            hydrateSelectedEditorPresentation(
                EditorPresentationHydrationRequest(
                    state: cached,
                    device: device,
                    holdsPersistedConnectPresentation: holdsPersistedConnectPresentation,
                    applyController: applyController,
                    editorController: editorController,
                    scheduleButtonHydration: false
                )
            )
        } else if (unavailableDeviceIDs.contains(deviceID) && !preservesTelemetryBackoffPresentation) ||
            usbAvailability == .receiverAbsent {
            deviceStore.state = nil
            deviceStore.lastUpdated = nil
            deviceStore.warningMessage = nil
            if isUSBPhysicalConnectSettling(for: device) {
                deviceStore.errorMessage = nil
            } else if deviceStore.errorMessage == nil || !Self.isDeviceAvailabilityMessage(deviceStore.errorMessage ?? "") {
                deviceStore.errorMessage = "Device disconnected or unavailable"
            }
        } else if let cached = stateCacheByDeviceID[deviceID] {
            deviceStore.state = cached
            deviceStore.lastUpdated = lastUpdatedByDeviceID[deviceID]
            deviceStore.warningMessage = editorController.telemetryWarning(for: cached, device: device)
            let hydratedEditable = hydrateSelectedEditorPresentation(
                EditorPresentationHydrationRequest(
                    state: cached,
                    device: device,
                    holdsPersistedConnectPresentation: holdsPersistedConnectPresentation,
                    applyController: applyController,
                    editorController: editorController,
                    scheduleButtonHydration: true
                )
            )
            if hydratedEditable {
                scheduleSelectedDeviceLightingHydration(device: device)
            }
        } else if let state = deviceStore.state, stateSummaryMatchesDevice(state, device: device) {
            if state.device.id != device.id {
                deviceStore.state = stateForPresentation(state, device: device)
            }
            deviceStore.warningMessage = editorController.telemetryWarning(for: state, device: device)
            let hydratedEditable = hydrateSelectedEditorPresentation(
                EditorPresentationHydrationRequest(
                    state: deviceStore.state ?? state,
                    device: device,
                    holdsPersistedConnectPresentation: holdsPersistedConnectPresentation,
                    applyController: applyController,
                    editorController: editorController,
                    scheduleButtonHydration: true
                )
            )
            if hydratedEditable {
                scheduleSelectedDeviceLightingHydration(device: device)
            }
        } else {
            deviceStore.state = nil
            deviceStore.lastUpdated = nil
            deviceStore.warningMessage = nil
        }
        if (!unavailableDeviceIDs.contains(deviceID) && !usbAvailability.blocksUSBControlInteraction) ||
            preservesTelemetryBackoffPresentation ||
            usbAvailability == .receiverPresentMouseUnavailable {
            deviceStore.errorMessage = nil
        }
    }

    func primeSelectedConnectPresentationIfNeeded(
        device: MouseDevice,
        applyController: AppStateApplyController,
        editorController: AppStateEditorController
    ) -> Bool {
        guard !environment.usesRemoteServiceTransport else { return false }
        guard applyController.shouldHydrateEditable(for: device) else { return false }
        let hydratedPersistedSnapshot = editorController.hydrateConnectPresentationIfNeeded(device: device)
        return hydratedPersistedSnapshot && pendingSettingsRestoreDeviceIDs.contains(device.id)
    }

    @discardableResult
    func hydrateSelectedEditorPresentation(_ request: EditorPresentationHydrationRequest) -> Bool {
        let state = request.state
        let device = request.device
        let applyController = request.applyController
        let editorController = request.editorController
        guard applyController.shouldHydrateEditable(for: device) else {
            editorController.hydrateLiveDpiPresentation(from: state)
            return false
        }
        if request.holdsPersistedConnectPresentation {
            editorController.hydrateLiveDpiPresentation(from: state)
            return false
        }

        editorController.hydrateEditable(from: state)
        if request.scheduleButtonHydration {
            scheduleSelectedDeviceButtonBindingHydration(device: device)
        }
        return true
    }

    func scheduleSelectedDeviceButtonBindingHydration(device: MouseDevice) {
        Task { [weak self] in
            guard let self, !self.isTearingDown,
                  let editorController = self.optionalEditorController else {
                return
            }
            await editorController.hydrateButtonBindingsIfNeeded(device: device)
        }
    }

    func scheduleSelectedDeviceLightingHydration(device: MouseDevice) {
        Task { [weak self] in
            guard let self, !self.isTearingDown,
                  let editorController = self.optionalEditorController else {
                return
            }
            await editorController.hydrateLightingStateIfNeeded(device: device)
        }
    }

    func scheduleSelectedEditorHydration(device: MouseDevice) {
        selectedEditorHydrationTasksByDeviceID[device.id]?.cancel()
        let token = UUID()
        selectedEditorHydrationTokensByDeviceID[device.id] = token
        selectedEditorHydrationTasksByDeviceID[device.id] = Task { @MainActor [weak self] in
            guard let self,
                  !self.isTearingDown,
                  self.deviceStore.selectedDeviceID == device.id,
                  let editorController = self.optionalEditorController else {
                return
            }
            defer {
                if self.selectedEditorHydrationTokensByDeviceID[device.id] == token {
                    self.selectedEditorHydrationTokensByDeviceID.removeValue(forKey: device.id)
                    self.selectedEditorHydrationTasksByDeviceID.removeValue(forKey: device.id)
                }
            }

            await editorController.hydrateLightingStateIfNeeded(device: device)
            guard !Task.isCancelled,
                  !self.isTearingDown,
                  self.deviceStore.selectedDeviceID == device.id else {
                return
            }
            await editorController.hydrateButtonBindingsIfNeeded(device: device)
        }
    }

    func requestSelectedDeviceRefreshIfNeeded(for device: MouseDevice) {
        guard !isTearingDown else { return }
        guard !isStrictlyUnsupported(device) else { return }
        guard deviceStore.selectedDeviceID == device.id else { return }

        let hasNoCachedState = stateCacheByDeviceID[device.id] == nil
        let lacksPresentedState = deviceStore.state == nil
        let needsRecoveryRefresh = hasNoCachedState ||
            lacksPresentedState ||
            unavailableDeviceIDs.contains(device.id) ||
            (device.transport == .usb && usbControlAvailability(for: device).blocksUSBControlInteraction)
        guard needsRecoveryRefresh else { return }

        let failures = max(1, refreshFailureCountByDeviceID[device.id] ?? 0)
        let recoveryDelay: TimeInterval
        if stateRefreshSuppressedUntilByDeviceID[device.id] != nil {
            recoveryDelay = selectedRecoveryRetryDelay(for: device, failures: failures)
        } else {
            recoveryDelay = refreshingStateDeviceIDs.contains(device.id) ? 0.8 : 0
        }
        scheduleSelectedRecoveryRefresh(
            for: device,
            delay: recoveryDelay
        )
    }

    func setTelemetryWarning(_ newValue: String?, device: MouseDevice) {
        guard deviceStore.warningMessage != newValue else { return }
        if let newValue {
            AppLog.warning("AppState", "telemetry degraded device=\(device.id) transport=\(device.transport.rawValue): \(newValue)")
        }
        deviceStore.warningMessage = newValue
    }

    func connectionState(for device: MouseDevice) -> DeviceConnectionState {
        guard !isTearingDown else { return .disconnected }
        if isStrictlyUnsupported(device) {
            return .unsupported
        }

        if !deviceStore.devices.contains(where: { $0.id == device.id }) && deviceStore.selectedDeviceID != device.id {
            return .disconnected
        }

        let now = Date()
        if isUSBPhysicalConnectSettling(for: device),
           usbControlAvailability(for: device).blocksUSBControlInteraction ||
            unavailableDeviceIDs.contains(device.id) {
            return .reconnecting
        }

        if device.transport == .usb, usbControlAvailability(for: device).blocksUSBControlInteraction {
            return .disconnected
        }

        if unavailableDeviceIDs.contains(device.id) {
            if shouldPreserveUSBTelemetryBackoffPresentation(for: device) {
                if shouldTreatActivePassiveHIDAsConnected(device: device, now: now) {
                    return .connected
                }
                return .reconnecting
            }
            return .disconnected
        }

        if device.id == deviceStore.selectedDeviceID, let errorMessage = deviceStore.errorMessage, !errorMessage.isEmpty {
            let lowered = errorMessage.lowercased()
            return Self.isDeviceAvailabilityMessage(lowered) ? .disconnected : .error
        }

        let hasCachedState = hasCachedPresentationState(for: device)
        let failures = refreshFailureCountByDeviceID[device.id] ?? 0
        if failures > 0 {
            if hasCachedState, deviceStore.devices.contains(where: { $0.id == device.id }) {
                return .connected
            }
            if failures < 3, shouldTreatActivePassiveHIDAsConnected(device: device, now: now) {
                return .connected
            }
            return .reconnecting
        }

        guard let updatedAt = lastUpdatedTimestamp(for: device) else {
            return .reconnecting
        }

        let age = now.timeIntervalSince(updatedAt)
        let refreshInterval = optionalRuntimeController?.currentPollingProfile.refreshStateInterval ?? 2.5
        if age > max(4.5, refreshInterval * 1.7) {
            if hasCachedState, deviceStore.devices.contains(where: { $0.id == device.id }) {
                return .connected
            }
            if shouldTreatActivePassiveHIDAsConnected(device: device, now: now) {
                return .connected
            }
            return .reconnecting
        }

        return .connected
    }

    func statusIndicator(for device: MouseDevice) -> DeviceStatusIndicator {
        connectionState(for: device).indicator
    }

    func lastUpdatedTimestamp(for device: MouseDevice) -> Date? {
        lastUpdatedByDeviceID[device.id] ?? (device.id == deviceStore.selectedDeviceID ? deviceStore.lastUpdated : nil)
    }

    func dpiUpdateTransportStatus(for device: MouseDevice) -> DpiUpdateTransportStatus {
        if isStrictlyUnsupported(device) {
            return .unsupported
        }
        return dpiUpdateTransportStatusByDeviceID[device.id] ?? .unknown
    }

    func allowsFastDpiPolling(for device: MouseDevice) -> Bool {
        (!unavailableDeviceIDs.contains(device.id) ||
            shouldPreserveUSBTelemetryBackoffPresentation(for: device)) &&
            !(device.transport == .usb && usbControlAvailability(for: device).blocksUSBControlInteraction)
    }

    func isPassiveBluetoothHeartbeatFresh(for device: MouseDevice, now: Date) -> Bool {
        guard device.transport == .bluetooth else { return false }
        guard let lastHeartbeatAt = lastPassiveHeartbeatAtByDeviceID[device.id] else { return false }
        return now.timeIntervalSince(lastHeartbeatAt) <= Self.bluetoothPassiveHeartbeatConnectedInterval
    }

    func refreshDpiUpdateTransportStatuses(for devices: [MouseDevice]) async {
        guard !isTearingDown else { return }
        for device in devices {
            await refreshConnectionDiagnostics(for: device)
        }
    }

    func focusServiceSelectionOnActivity(deviceID: String) {
        guard !isTearingDown else { return }
        guard environment.launchRole.isService else { return }
        guard runtimeController.shouldAllowServiceSelectionFocusOnActivity(deviceID: deviceID) else { return }
        guard deviceStore.selectedDeviceID != deviceID else { return }
        guard deviceStore.devices.contains(where: { $0.id == deviceID }) else { return }
        deviceStore.selectedDeviceID = deviceID
        syncSelectedDevicePresentation(deviceID: deviceID)
    }

    func shouldFocusServiceSelectionOnActivity(previous: MouseState?, next: MouseState) -> Bool {
        guard environment.launchRole.isService else { return false }
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
        if let serial = DevicePersistenceKeys.normalizedStableSerial(device.serial) {
            return "serial:\(serial)"
        }
        return String(
            format: "vp:%04x:%04x:%@",
            device.vendor_id,
            device.product_id,
            device.transport.rawValue
        )
    }

    func stateSummaryMatchesDevice(_ state: MouseState, device: MouseDevice) -> Bool {
        let deviceSerial = DevicePersistenceKeys.normalizedStableSerial(device.serial)
        let stateSerial = DevicePersistenceKeys.normalizedStableSerial(state.device.serial)

        if let deviceSerial, !deviceSerial.isEmpty,
           let stateSerial, !stateSerial.isEmpty {
            return deviceSerial == stateSerial
        }

        return state.device.transport == device.transport &&
            state.device.product_name == device.product_name
    }

    func selectedDeviceNeedsRecovery(_ device: MouseDevice, now: Date = Date()) -> Bool {
        if let suppressedUntil = stateRefreshSuppressedUntilByDeviceID[device.id],
           now < suppressedUntil {
            return false
        }
        if unavailableDeviceIDs.contains(device.id) {
            return true
        }
        if device.transport == .usb, usbControlAvailability(for: device).blocksUSBControlInteraction {
            return true
        }
        if (refreshFailureCountByDeviceID[device.id] ?? 0) > 0 {
            return true
        }
        if stateCacheByDeviceID[device.id] != nil || lastUpdatedByDeviceID[device.id] != nil {
            return false
        }
        if deviceStore.selectedDeviceID == device.id,
           let state = deviceStore.state,
           stateSummaryMatchesDevice(state, device: device) {
            if let stateDeviceID = state.device.id, stateDeviceID != device.id {
                return true
            }
            return false
        }
        return true
    }

    func normalizedSerial(for device: MouseDevice) -> String? {
        DevicePersistenceKeys.normalizedStableSerial(device.serial)
    }

    func isStrictlyUnsupported(_ device: MouseDevice) -> Bool {
        resolvedProfile(for: device) == nil && device.transport == .bluetooth
    }

    func presentationDevice(for device: MouseDevice) -> MouseDevice? {
        if let exactMatch = deviceStore.devices.first(where: { $0.id == device.id }) {
            return exactMatch
        }
        let identityKey = deviceIdentityKey(device)
        return deviceStore.devices.first(where: { deviceIdentityKey($0) == identityKey })
    }

    func resolvedProfile(for device: MouseDevice) -> DeviceProfile? {
        DeviceProfiles.resolve(
            vendorID: device.vendor_id,
            productID: device.product_id,
            transport: device.transport
        )
    }

    func reconnectSeedStatesByIdentity(
        previousDevices: [MouseDevice],
        removedIDs: Set<String>
    ) -> [String: (state: MouseState, updatedAt: Date?)] {
        guard !removedIDs.isEmpty else { return [:] }

        var seeds: [String: (state: MouseState, updatedAt: Date?)] = [:]
        for device in previousDevices where removedIDs.contains(device.id) {
            let state = stateCacheByDeviceID[device.id]
                ?? ((deviceStore.selectedDeviceID == device.id) ? deviceStore.state : nil)
            guard let state, stateSummaryMatchesDevice(state, device: device) else { continue }
            seeds[deviceIdentityKey(device)] = (state, lastUpdatedByDeviceID[device.id] ?? deviceStore.lastUpdated)
        }
        return seeds
    }

    func seedSelectedDeviceStateFromReconnectIfNeeded(
        previousSelectedDevice: MouseDevice?,
        selectedDeviceID: String?,
        removedReconnectSeedByIdentity: [String: (state: MouseState, updatedAt: Date?)]
    ) {
        guard let previousSelectedDevice,
              let selectedDeviceID,
              let selectedDevice = deviceStore.devices.first(where: { $0.id == selectedDeviceID }) else {
            return
        }
        guard previousSelectedDevice.id != selectedDeviceID else { return }
        guard stateCacheByDeviceID[selectedDeviceID] == nil else { return }

        let identity = deviceIdentityKey(selectedDevice)
        guard identity == deviceIdentityKey(previousSelectedDevice),
              let seed = removedReconnectSeedByIdentity[identity],
              stateSummaryMatchesDevice(seed.state, device: selectedDevice) else {
            return
        }

        let seededState = stateForPresentation(seed.state, device: selectedDevice)
        stateCacheByDeviceID[selectedDeviceID] = seededState
        if let updatedAt = seed.updatedAt {
            lastUpdatedByDeviceID[selectedDeviceID] = updatedAt
        }
        seededReconnectStateDeviceIDs.insert(selectedDeviceID)
        AppLog.debug(
            "AppState",
            "seeded reconnect state previous=\(previousSelectedDevice.id) replacement=\(selectedDeviceID)"
        )
    }

    func stateForPresentation(_ state: MouseState, device: MouseDevice) -> MouseState {
        MouseState(
            device: DeviceSummary(
                id: device.id,
                product_name: device.product_name,
                serial: device.serial ?? state.device.serial,
                transport: device.transport,
                firmware: device.firmware ?? state.device.firmware
            ),
            connection: device.connectionLabel,
            battery_percent: state.battery_percent,
            charging: state.charging,
            dpi: state.dpi,
            dpi_stages: state.dpi_stages,
            poll_rate: state.poll_rate,
            sleep_timeout: state.sleep_timeout,
            device_mode: state.device_mode,
            low_battery_threshold_raw: state.low_battery_threshold_raw,
            scroll_mode: state.scroll_mode,
            scroll_acceleration: state.scroll_acceleration,
            scroll_smart_reel: state.scroll_smart_reel,
            active_onboard_profile: state.active_onboard_profile,
            onboard_profile_count: state.onboard_profile_count,
            led_value: state.led_value,
            capabilities: state.capabilities
        )
    }

    func cancelSelectedRecoveryRefresh() {
        selectedRecoveryRefreshTask?.cancel()
        selectedRecoveryRefreshTask = nil
        selectedRecoveryRefreshDeviceID = nil
    }

    func scheduleSelectedRecoveryRefresh(for device: MouseDevice, delay: TimeInterval) {
        guard !isTearingDown else { return }
        guard deviceStore.selectedDeviceID == device.id else { return }
        guard selectedDeviceNeedsRecovery(device) else { return }

        if selectedRecoveryRefreshDeviceID == device.id, selectedRecoveryRefreshTask != nil {
            return
        }

        cancelSelectedRecoveryRefresh()
        selectedRecoveryRefreshDeviceID = device.id
        selectedRecoveryRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.selectedRecoveryRefreshDeviceID == device.id {
                    self.selectedRecoveryRefreshTask = nil
                    self.selectedRecoveryRefreshDeviceID = nil
                }
            }

            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }

            guard !Task.isCancelled,
                  !self.isTearingDown,
                  self.deviceStore.selectedDeviceID == device.id,
                  self.selectedDeviceNeedsRecovery(device),
                  !self.refreshingStateDeviceIDs.contains(device.id) else {
                return
            }

            let refreshed = await self.refreshState(for: device)
            guard !refreshed,
                  !Task.isCancelled,
                  !self.isTearingDown,
                  self.deviceStore.selectedDeviceID == device.id,
                  self.selectedDeviceNeedsRecovery(device) else {
                return
            }

            let failures = max(1, self.refreshFailureCountByDeviceID[device.id] ?? 0)
            let retryDelay = self.selectedRecoveryRetryDelay(for: device, failures: failures)
            self.selectedRecoveryRefreshTask = nil
            self.selectedRecoveryRefreshDeviceID = nil
            self.scheduleSelectedRecoveryRefresh(for: device, delay: retryDelay)
        }
    }

    func selectedRecoveryRetryDelay(for device: MouseDevice, failures: Int, now: Date = Date()) -> TimeInterval {
        let exponentialDelay = min(3.0, 0.8 * pow(1.8, Double(max(0, failures - 1))))
        guard let suppressedUntil = stateRefreshSuppressedUntilByDeviceID[device.id] else {
            return exponentialDelay
        }

        let remainingBackoff = suppressedUntil.timeIntervalSince(now)
        guard remainingBackoff > 0 else { return exponentialDelay }
        return max(exponentialDelay, min(remainingBackoff, 30.0))
    }

    func refreshableDevicesInPriorityOrder(prioritizing prioritizedDeviceIDs: [String] = []) -> [MouseDevice] {
        guard !deviceStore.devices.isEmpty else { return [] }
        let now = Date()

        var ordered: [MouseDevice] = []
        var seen: Set<String> = []

        for deviceID in prioritizedDeviceIDs {
            guard let device = deviceStore.devices.first(where: { $0.id == deviceID }) else { continue }
            guard !isStrictlyUnsupported(device) else { continue }
            guard seen.insert(device.id).inserted else { continue }
            ordered.append(device)
        }

        if let selectedDevice = deviceStore.selectedDevice,
           !isStrictlyUnsupported(selectedDevice),
           seen.insert(selectedDevice.id).inserted {
            ordered.append(selectedDevice)
        }

        for device in deviceStore.devices where !isStrictlyUnsupported(device) {
            guard seen.insert(device.id).inserted else { continue }
            if deviceStore.selectedDeviceID != device.id,
               let suppressedUntil = stateRefreshSuppressedUntilByDeviceID[device.id],
               now < suppressedUntil {
                continue
            }
            ordered.append(device)
        }

        return ordered
    }

    func cacheState(
        _ state: MouseState,
        sourceDeviceID: String,
        presentationDeviceID: String,
        updatedAt: Date = Date(),
        observedAt: Date? = nil
    ) {
        let resolvedObservedAt = observedAt ?? updatedAt
        stateCacheByDeviceID[sourceDeviceID] = state
        lastUpdatedByDeviceID[sourceDeviceID] = updatedAt
        lastStateMutationAtByDeviceID[sourceDeviceID] = resolvedObservedAt

        if presentationDeviceID != sourceDeviceID {
            stateCacheByDeviceID[presentationDeviceID] = state
            lastUpdatedByDeviceID[presentationDeviceID] = updatedAt
            lastStateMutationAtByDeviceID[presentationDeviceID] = resolvedObservedAt
        }

        if deviceStore.selectedDeviceID == presentationDeviceID {
            deviceStore.lastUpdated = updatedAt
            deviceStore.invalidateConnectionDiagnostics()
        }
    }

    @discardableResult
    func clearConnectionFailureState(sourceDeviceID: String, presentationDeviceID: String) -> Bool {
        var changed = false
        for deviceID in Set([sourceDeviceID, presentationDeviceID]) {
            if (refreshFailureCountByDeviceID[deviceID] ?? 0) != 0 {
                changed = true
            }
            refreshFailureCountByDeviceID[deviceID] = 0
            if stateRefreshSuppressedUntilByDeviceID.removeValue(forKey: deviceID) != nil {
                changed = true
            }
            if usbTelemetryUnavailableBackoffDeviceIDs.remove(deviceID) != nil {
                changed = true
            }
            if unavailableDeviceIDs.remove(deviceID) != nil {
                changed = true
            }
        }

        if changed {
            deviceStore.invalidateConnectionDiagnostics()
        }
        return changed
    }

    static func diagnosticDpiPair(_ pair: DpiPair?) -> String {
        guard let pair else { return "nil" }
        return "(\(pair.x),\(pair.y))"
    }

    static func diagnosticScrollState(_ state: MouseState) -> String {
        "mode=\(state.scroll_mode.map(String.init) ?? "nil")," +
            "accel=\(state.scroll_acceleration.map(String.init) ?? "nil")," +
            "smart=\(state.scroll_smart_reel.map(String.init) ?? "nil")"
    }

    func latestCachedUpdateAt(sourceDeviceID: String, presentationDeviceID: String) -> Date? {
        [lastUpdatedByDeviceID[sourceDeviceID], lastUpdatedByDeviceID[presentationDeviceID]]
            .compactMap { $0 }
            .max()
    }

    func latestCachedMutationAt(sourceDeviceID: String, presentationDeviceID: String) -> Date? {
        [lastStateMutationAtByDeviceID[sourceDeviceID], lastStateMutationAtByDeviceID[presentationDeviceID]]
            .compactMap { $0 }
            .max()
    }

    func hasCachedPresentationState(for device: MouseDevice) -> Bool {
        if stateCacheByDeviceID[device.id] != nil {
            return true
        }
        guard deviceStore.selectedDeviceID == device.id,
              let selectedState = deviceStore.state else {
            return false
        }
        return stateSummaryMatchesDevice(selectedState, device: device)
    }

    func shouldPreferRecentDynamicDpiMutation(
        over read: MouseState,
        latestCachedState: MouseState?,
        latestCachedMutationAt: Date?,
        latestCachedStableUpdateAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let latestCachedState,
              latestCachedState.differsOnlyInDynamicDpiState(from: read),
              let latestCachedMutationAt,
              now.timeIntervalSince(latestCachedMutationAt) <= Self.recentDynamicDpiMutationMergeWindow else {
            return false
        }
        guard let latestCachedStableUpdateAt else { return true }
        return latestCachedMutationAt > latestCachedStableUpdateAt
    }

    func refreshVisibleDeviceStatesForCurrentRuntimeContext(now: Date = Date()) async {
        if environment.launchRole.isService,
           runtimeController.pollingProfile(at: now) == .serviceInteractive {
            let priorityDeviceIDs = runtimeController.serviceInteractivePriorityDeviceIDs(at: now)
            await refreshDeviceStates(deviceIDs: priorityDeviceIDs)
            return
        }

        await refreshAllDeviceStates()
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

    static func isDeviceNotAvailableMessage(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("device not available") || lowered.contains("no device")
    }
}
