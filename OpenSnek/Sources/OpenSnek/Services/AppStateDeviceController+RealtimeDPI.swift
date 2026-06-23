import Foundation
import OpenSnekCore
import OpenSnekHardware

@MainActor
extension AppStateDeviceController {
    func refreshDpiFast() async {
        guard !isTearingDown else { return }
        guard !deviceStore.isApplying else { return }

        let now = Date()
        for deviceID in runtimeController.activeFastPollingDeviceIDs(at: now) {
            guard let device = deviceStore.devices.first(where: { $0.id == deviceID }) else { continue }
            await refreshDpiFast(for: device, now: now)
        }
    }

    func refreshDpiFast(for device: MouseDevice, now: Date) async {
        guard !isTearingDown else { return }
        guard device.transport.supportsHIDBackedControls else { return }
        guard !isStrictlyUnsupported(device) else { return }
        guard !refreshingFastDpiDeviceIDs.contains(device.id) else { return }
        guard !refreshingStateDeviceIDs.contains(device.id) else { return }
        guard !isRestoringSettings(for: device) else { return }
        guard !applyController.hasPendingLocalEditsAffecting(device) else { return }
        let usesFastPolling = await environment.backend.shouldUseFastDPIPolling(device: device)
        guard !isTearingDown else { return }
        let correctionOnly = !usesFastPolling
        if correctionOnly,
           device.transport == .bluetooth,
           Self.shouldDelayBluetoothRealtimeCorrection(
            lastHeartbeatAt: lastPassiveHeartbeatAtByDeviceID[device.id],
            now: now
           ) {
            return
        }
        if correctionOnly {
            setDpiUpdateTransportStatus(.realTimeHID, for: device.id)
            let minimumInterval = realtimeCorrectionMinimumInterval(for: device)
            if let lastCorrectionAt = lastRealtimeCorrectionAtByDeviceID[device.id],
               now.timeIntervalSince(lastCorrectionAt) < minimumInterval {
                return
            }
            lastRealtimeCorrectionAtByDeviceID[device.id] = now
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
        let fastRevision = applyController.stateRevision
        let restoreRevision = settingsRestoreRevision(for: device)

        do {
            guard let fast = try await environment.backend.readDpiStagesFast(device: device) else { return }
            guard !isTearingDown else { return }
            guard let presentationDevice = presentationDevice(for: device) else { return }
            let readAt = Date()
            if device.transport == .usb {
                recordUSBLiveObservation(
                    sourceDeviceID: device.id,
                    presentationDeviceID: presentationDevice.id,
                    observedAt: readAt,
                    transportStatus: .pollingFallback,
                    recordsFastDpi: true
                )
            }
            guard fastRevision == applyController.stateRevision else {
                AppLog.debug("AppState", "refreshDpiFast stale-drop rev=\(fastRevision) current=\(applyController.stateRevision)")
                return
            }
            guard restoreRevision == settingsRestoreRevision(for: device) else {
                AppLog.debug(
                    "AppState",
                    "refreshDpiFast stale-drop restore-rev=\(restoreRevision) current=\(settingsRestoreRevision(for: device)) device=\(device.id)"
                )
                return
            }
            let presentationDeviceID = presentationDevice.id
            let previous = stateCacheByDeviceID[presentationDeviceID] ?? stateCacheByDeviceID[device.id] ?? deviceStore.state
            guard let previous else { return }
            let active = max(0, min(fast.values.count - 1, fast.active))
            let currentStagePairs = BridgeClient.resolveDpiStagePairs(
                values: fast.values,
                pairs: nil,
                fallbackPairs: previous.dpi_stages.pairs
            )
            let currentDpi = currentStagePairs?[active] ?? DpiPair(x: fast.values[active], y: fast.values[active])
            let updated = MouseState(
                device: previous.device,
                connection: previous.connection,
                battery_percent: previous.battery_percent,
                charging: previous.charging,
                dpi: currentDpi,
                dpi_stages: DpiStages(
                    active_stage: active,
                    values: fast.values,
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

            let shouldFocusOnActivity = shouldFocusServiceSelectionOnActivity(previous: previous, next: updated)
            // Fast DPI snapshots should not advance the stable-state freshness
            // timestamp; the slow poller uses that timestamp to decide when a
            // full telemetry read is overdue.
            let stableUpdatedAt = latestCachedUpdateAt(
                sourceDeviceID: device.id,
                presentationDeviceID: presentationDeviceID
            ) ?? readAt
            cacheState(
                updated,
                sourceDeviceID: device.id,
                presentationDeviceID: presentationDeviceID,
                updatedAt: stableUpdatedAt,
                observedAt: readAt
            )
            if correctionOnly {
                let stillUsesFastPolling = await environment.backend.shouldUseFastDPIPolling(device: device)
                let nextStatus: DpiUpdateTransportStatus = stillUsesFastPolling ? .pollingFallback : .realTimeHID
                setDpiUpdateTransportStatus(nextStatus, for: device.id)
                setDpiUpdateTransportStatus(nextStatus, for: presentationDeviceID)
            } else {
                let existingTransportStatus = dpiUpdateTransportStatusByDeviceID[presentationDeviceID]
                if existingTransportStatus != .listening && existingTransportStatus != .streamActive {
                    setDpiUpdateTransportStatus(.pollingFallback, for: device.id)
                    setDpiUpdateTransportStatus(.pollingFallback, for: presentationDeviceID)
                }
            }
            unavailableDeviceIDs.remove(device.id)
            unavailableDeviceIDs.remove(presentationDeviceID)
            if shouldFocusOnActivity {
                focusServiceSelectionOnActivity(deviceID: presentationDeviceID)
            }
            runtimeController.updateStatusItemTransientDpi(previous: previous, next: updated, deviceID: presentationDeviceID)
            if deviceStore.selectedDeviceID == presentationDeviceID {
                if deviceStore.state != updated {
                    deviceStore.state = updated
                }
                let holdsPersistedConnectPresentation = primeSelectedConnectPresentationIfNeeded(
                    device: presentationDevice,
                    applyController: applyController,
                    editorController: editorController
                )
                hydrateSelectedEditorPresentation(
                    EditorPresentationHydrationRequest(
                        state: updated,
                        device: presentationDevice,
                        holdsPersistedConnectPresentation: holdsPersistedConnectPresentation,
                        applyController: applyController,
                        editorController: editorController,
                        scheduleButtonHydration: false
                    )
                )
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

    func setDpiUpdateTransportStatus(_ status: DpiUpdateTransportStatus?, for deviceID: String) {
        let previous = dpiUpdateTransportStatusByDeviceID[deviceID]
        guard previous != status else { return }
        dpiUpdateTransportStatusByDeviceID[deviceID] = status
        AppLog.debug(
            "AppState",
            "dpiTransportStatus device=\(deviceID) previous=\(previous?.rawValue ?? "nil") next=\(status?.rawValue ?? "nil")"
        )
        deviceStore.invalidateConnectionDiagnostics()
    }

    func usbControlAvailability(for device: MouseDevice) -> USBControlAvailability {
        guard device.transport == .usb else { return .unknown }
        return usbControlAvailabilityByDeviceID[device.id] ?? .unknown
    }

    func setUSBControlAvailability(
        _ availability: USBControlAvailability,
        for deviceID: String,
        observedAt _: Date = Date()
    ) {
        cancelPendingUSBControlUnavailable(for: deviceID)
        if availability == .receiverPresentMouseReachable {
            clearUSBPhysicalConnectSettling(for: deviceID)
        }
        let previous = usbControlAvailabilityByDeviceID[deviceID]
        guard previous != availability else { return }
        usbControlAvailabilityByDeviceID[deviceID] = availability
        AppLog.debug(
            "AppState",
            "usbControlAvailability device=\(deviceID) previous=\(previous?.rawValue ?? "nil") next=\(availability.rawValue)"
        )
        deviceStore.invalidateConnectionDiagnostics()
    }

    @discardableResult
    func setBackendObservedUSBControlAvailability(
        _ availability: USBControlAvailability,
        for deviceID: String,
        observedAt: Date
    ) -> Bool {
        if shouldDropStaleUSBControlUnavailable(availability, for: deviceID, observedAt: observedAt) {
            AppLog.debug(
                "AppState",
                "usbControlAvailability stale-drop device=\(deviceID) availability=\(availability.rawValue)"
            )
            return false
        }

        if shouldDebounceUSBControlUnavailable(availability, for: deviceID) {
            schedulePendingUSBControlUnavailable(for: deviceID, observedAt: observedAt)
            return false
        }

        setUSBControlAvailability(availability, for: deviceID, observedAt: observedAt)
        return true
    }

    func shouldDropStaleUSBControlUnavailable(
        _ availability: USBControlAvailability,
        for deviceID: String,
        observedAt: Date
    ) -> Bool {
        guard availability == .receiverPresentMouseUnavailable else { return false }
        guard let latestUSBObservationAt = latestUSBLiveObservationAt(for: deviceID) else { return false }
        return observedAt < latestUSBObservationAt
    }

    func shouldDebounceUSBControlUnavailable(_ availability: USBControlAvailability, for deviceID: String) -> Bool {
        guard availability == .receiverPresentMouseUnavailable else { return false }
        guard usbControlAvailabilityByDeviceID[deviceID] != .receiverPresentMouseUnavailable else { return false }
        guard let device = usbControlAvailabilityDevice(for: deviceID) else { return false }
        return shouldTreatActivePassiveHIDAsConnected(device: device, now: Date())
    }

    func schedulePendingUSBControlUnavailable(for deviceID: String, observedAt: Date) {
        pendingUSBControlUnavailableTasksByDeviceID[deviceID]?.cancel()
        // USB feature-report probes can fail once while fast DPI or passive HID
        // still proves the mouse is alive; wait briefly before changing UI state.
        pendingUSBControlUnavailableTasksByDeviceID[deviceID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(Self.usbControlUnavailableDebounceInterval * 1_000_000_000)
                )
            } catch {
                return
            }
            guard let self, !self.isTearingDown else { return }
            self.pendingUSBControlUnavailableTasksByDeviceID.removeValue(forKey: deviceID)
            guard !self.shouldDropStaleUSBControlUnavailable(
                .receiverPresentMouseUnavailable,
                for: deviceID,
                observedAt: observedAt
            ) else {
                AppLog.debug("AppState", "usbControlAvailability pending stale-drop device=\(deviceID)")
                return
            }
            self.setUSBControlAvailability(
                .receiverPresentMouseUnavailable,
                for: deviceID,
                observedAt: observedAt
            )
        }
    }

    func cancelPendingUSBControlUnavailable(for deviceID: String) {
        pendingUSBControlUnavailableTasksByDeviceID.removeValue(forKey: deviceID)?.cancel()
    }

    func usbControlAvailabilityDevice(for deviceID: String) -> MouseDevice? {
        if let device = deviceStore.devices.first(where: { $0.id == deviceID }) {
            return device
        }
        if deviceStore.selectedDeviceID == deviceID {
            return deviceStore.selectedDevice
        }
        return nil
    }

    func armUSBPhysicalConnectSettling(
        for deviceIDs: Set<String>,
        in devices: [MouseDevice],
        observedAt: Date
    ) {
        let usbDeviceIDs = deviceIDs.filter { isUSBDeviceID($0, in: devices) }
        guard !usbDeviceIDs.isEmpty else { return }
        let now = Date()
        let deadline = max(observedAt, now).addingTimeInterval(Self.usbPhysicalConnectStatusGraceInterval)
        for deviceID in usbDeviceIDs {
            usbPhysicalConnectSettlingUntilByDeviceID[deviceID] = deadline
            usbPhysicalConnectSettleTasksByDeviceID[deviceID]?.cancel()
            usbPhysicalConnectSettleTasksByDeviceID[deviceID] = Task { @MainActor [weak self] in
                let sleepInterval = max(0, deadline.timeIntervalSinceNow)
                do {
                    try await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
                } catch {
                    return
                }
                guard let self,
                      !self.isTearingDown,
                      self.usbPhysicalConnectSettlingUntilByDeviceID[deviceID] == deadline else {
                    return
                }
                self.usbPhysicalConnectSettlingUntilByDeviceID.removeValue(forKey: deviceID)
                self.usbPhysicalConnectSettleTasksByDeviceID[deviceID] = nil
                self.deviceStore.invalidateConnectionDiagnostics()
            }
        }
        deviceStore.invalidateConnectionDiagnostics()
    }

    func clearUSBPhysicalConnectSettling(for deviceID: String) {
        usbPhysicalConnectSettlingUntilByDeviceID.removeValue(forKey: deviceID)
        usbPhysicalConnectSettleTasksByDeviceID.removeValue(forKey: deviceID)?.cancel()
    }

    func pruneUSBPhysicalConnectSettling(liveIDs: Set<String>) {
        for deviceID in Array(usbPhysicalConnectSettlingUntilByDeviceID.keys) where !liveIDs.contains(deviceID) {
            clearUSBPhysicalConnectSettling(for: deviceID)
        }
    }

    func isUSBPhysicalConnectSettling(for device: MouseDevice) -> Bool {
        guard device.transport == .usb,
              let deadline = usbPhysicalConnectSettlingUntilByDeviceID[device.id] else {
            return false
        }
        if Date() < deadline {
            return true
        }
        clearUSBPhysicalConnectSettling(for: device.id)
        return false
    }

    func recordUSBLiveObservation(
        sourceDeviceID: String,
        presentationDeviceID: String,
        observedAt: Date,
        transportStatus: DpiUpdateTransportStatus? = nil,
        recordsFastDpi: Bool = false
    ) {
        setUSBControlAvailability(.receiverPresentMouseReachable, for: sourceDeviceID, observedAt: observedAt)
        setUSBControlAvailability(.receiverPresentMouseReachable, for: presentationDeviceID, observedAt: observedAt)
        lastPassiveHeartbeatAtByDeviceID[sourceDeviceID] = observedAt
        lastPassiveHeartbeatAtByDeviceID[presentationDeviceID] = observedAt
        if recordsFastDpi {
            lastUSBFastDpiAtByDeviceID[sourceDeviceID] = observedAt
            lastUSBFastDpiAtByDeviceID[presentationDeviceID] = observedAt
        }
        markUSBLiveObservationFresh(for: sourceDeviceID, transportStatus: transportStatus)
        markUSBLiveObservationFresh(for: presentationDeviceID, transportStatus: transportStatus)
    }

    func markUSBLiveObservationFresh(for deviceID: String, transportStatus: DpiUpdateTransportStatus?) {
        guard let transportStatus else { return }
        let existingTransportStatus = dpiUpdateTransportStatusByDeviceID[deviceID]
        if existingTransportStatus != .listening,
           existingTransportStatus != .streamActive,
           existingTransportStatus != .realTimeHID {
            setDpiUpdateTransportStatus(transportStatus, for: deviceID)
        }
    }

    func shouldTreatActivePassiveHIDAsConnected(device: MouseDevice, now: Date) -> Bool {
        guard resolvedProfile(for: device)?.passiveDPIInput != nil else { return false }

        let transportStatus = dpiUpdateTransportStatusByDeviceID[device.id]

        if device.transport == .usb {
            guard transportStatus == .streamActive ||
                transportStatus == .realTimeHID ||
                transportStatus == .pollingFallback else {
                return false
            }
            guard stateCacheByDeviceID[device.id] != nil ||
                (deviceStore.selectedDeviceID == device.id && deviceStore.state != nil) else {
                return false
            }
            return isPassiveUSBObservationFresh(for: device, now: now)
        }
        if device.transport == .bluetooth {
            guard transportStatus == .streamActive || transportStatus == .realTimeHID else { return false }
            return isPassiveBluetoothHeartbeatFresh(for: device, now: now)
        }
        return false
    }

    func shouldPreserveUSBTelemetryBackoffPresentation(for device: MouseDevice) -> Bool {
        guard device.transport == .usb else { return false }
        guard !usbControlAvailability(for: device).blocksUSBControlInteraction else { return false }
        guard usbTelemetryUnavailableBackoffDeviceIDs.contains(device.id) else { return false }
        guard deviceStore.devices.contains(where: { $0.id == device.id }) else { return false }
        return stateCacheByDeviceID[device.id] != nil ||
            lastUpdatedByDeviceID[device.id] != nil ||
            (deviceStore.selectedDeviceID == device.id && deviceStore.state != nil)
    }

    func latestUSBLiveObservationAt(for device: MouseDevice) -> Date? {
        latestUSBLiveObservationAt(for: device.id)
    }

    func latestUSBLiveObservationAt(for deviceID: String) -> Date? {
        [
            lastPassiveHeartbeatAtByDeviceID[deviceID],
            lastUSBFastDpiAtByDeviceID[deviceID]
        ].compactMap { $0 }.max()
    }

    func isPassiveUSBObservationFresh(for device: MouseDevice, now: Date) -> Bool {
        guard device.transport == .usb else { return false }
        guard let lastObservedAt = latestUSBLiveObservationAt(for: device) else {
            return false
        }
        return now.timeIntervalSince(lastObservedAt) <= Self.usbPassiveActivityConnectedInterval
    }

    static func shouldApplyBackendDpiTransportStatusUpdate(
        current: DpiUpdateTransportStatus?,
        incoming: DpiUpdateTransportStatus
    ) -> Bool {
        guard let current else { return true }
        return dpiTransportStatusPriority(incoming) >= dpiTransportStatusPriority(current)
    }

    static func dpiTransportStatusPriority(_ status: DpiUpdateTransportStatus) -> Int {
        switch status {
        case .unknown:
            0
        case .pollingFallback:
            1
        case .listening:
            2
        case .streamActive:
            3
        case .realTimeHID:
            4
        case .unsupported:
            5
        }
    }

    nonisolated static func shouldDelayBluetoothRealtimeCorrection(lastHeartbeatAt: Date?, now: Date) -> Bool {
        guard let lastHeartbeatAt else { return false }
        return now.timeIntervalSince(lastHeartbeatAt) < 0.4
    }

    nonisolated static func realtimeCorrectionMinimumInterval(isService: Bool) -> TimeInterval {
        isService ? 0.45 : 1.0
    }

    func realtimeCorrectionMinimumInterval(for _: MouseDevice) -> TimeInterval {
        Self.realtimeCorrectionMinimumInterval(isService: environment.launchRole.isService)
    }

    nonisolated static func shouldDelayBluetoothRealtimeStateRefresh(
        _ context: BluetoothRealtimeRefreshDelayContext
    ) -> Bool {
        guard context.transport == .bluetooth else { return false }
        guard context.transportStatus == .streamActive || context.transportStatus == .realTimeHID else { return false }
        guard let lastHeartbeatAt = context.lastHeartbeatAt,
              context.now.timeIntervalSince(lastHeartbeatAt) < 0.8 else {
            return false
        }
        guard let lastFullStateRefreshStartedAt = context.lastFullStateRefreshStartedAt else { return false }
        return context.now.timeIntervalSince(lastFullStateRefreshStartedAt) < context.minimumRefreshInterval
    }

    func restorePersistedSettingsIfNeeded(for device: MouseDevice) async {
        guard !isTearingDown else { return }
        guard let applyController = optionalApplyController,
              let editorController = optionalEditorController else {
            return
        }
        guard pendingSettingsRestoreDeviceIDs.contains(device.id) else { return }
        guard !restoringSettingsDeviceIDs.contains(device.id) else { return }
        guard !(deviceStore.selectedDeviceID == device.id && !applyController.shouldHydrateEditable(for: device)) else { return }
        guard !applyController.hasPendingLocalEditsAffecting(device) else { return }
        let pendingGeneration = pendingSettingsRestoreGenerationByDeviceID[device.id, default: 0]

        guard let restorePlan = editorController.persistedSettingsRestorePlan(device: device) else {
            if pendingSettingsRestoreGenerationByDeviceID[device.id, default: 0] == pendingGeneration {
                pendingSettingsRestoreDeviceIDs.remove(device.id)
            }
            await editorController.startPersistedSoftwareLightingOnConnectIfNeeded(for: device)
            return
        }

        bumpSettingsRestoreRevision(for: device)
        restoringSettingsDeviceIDs.insert(device.id)
        defer {
            restoringSettingsDeviceIDs.remove(device.id)
            bumpSettingsRestoreRevision(for: device)
        }

        let restored = await applyController.applyPersistedSettingsRestore(
            restorePlan,
            to: device
        )
        if restored {
            editorController.markSingleSlotPersistedSettingsRestored(
                snapshot: restorePlan.snapshot,
                device: device
            )
            let currentGeneration = pendingSettingsRestoreGenerationByDeviceID[device.id, default: 0]
            if currentGeneration == pendingGeneration {
                pendingSettingsRestoreDeviceIDs.remove(device.id)
                await editorController.startPersistedSoftwareLightingOnConnectIfNeeded(for: device)
            } else {
                Task { @MainActor [weak self] in
                    await self?.restorePersistedSettingsIfNeeded(for: device)
                }
            }
        }
    }
}
