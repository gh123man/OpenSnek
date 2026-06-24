import Foundation
import OpenSnekCore
import OpenSnekHardware

/// Adds remote updates behavior to `AppStateDeviceController`.
@MainActor
extension AppStateDeviceController {
    func handleBackendDeviceListUpdate(_ listed: [MouseDevice], updatedAt: Date = Date()) async {
        guard !isTearingDown else { return }
        guard !environment.usesRemoteServiceTransport else { return }
        let previousIDs = Set(deviceStore.devices.map(\.id))
        _ = applyDeviceList(listed, source: "subscription", updatedAt: updatedAt)
        guard !listed.isEmpty else { return }
        let prioritizedDeviceIDs = listed
            .filter { $0.transport == .bluetooth && !previousIDs.contains($0.id) }
            .map(\.id)
        await refreshAllDeviceStates(prioritizing: prioritizedDeviceIDs)
        await refreshDpiUpdateTransportStatuses(for: listed)
    }

    func applyRemoteServiceSnapshot(_ snapshot: SharedServiceSnapshot) {
        guard !isTearingDown else { return }
        guard environment.usesRemoteServiceTransport else { return }

        let liveIDs = Set(snapshot.devices.map(\.id))
        let now = Date()
        pruneRemoteSnapshotCaches(liveIDs: liveIDs, devices: snapshot.devices)
        var didApplySnapshotChange = applyRemoteSoftwareLightingStatuses(snapshot, liveIDs: liveIDs, now: now)
        applyRemoteUSBControlAvailability(snapshot, liveIDs: liveIDs)
        if applyRemoteStateCache(snapshot, liveIDs: liveIDs) {
            didApplySnapshotChange = true
        }

        let sortedSnapshotDevices = snapshot.devices.sorted { $0.product_name < $1.product_name }
        let selectedDeviceMissing = deviceStore.selectedDeviceID.map { !liveIDs.contains($0) } ?? !sortedSnapshotDevices.isEmpty
        let shouldApplyDeviceList = deviceStore.devices != sortedSnapshotDevices || selectedDeviceMissing
        let deviceListChanged = shouldApplyDeviceList
            ? applyDeviceList(snapshot.devices, source: "subscription")
            : false
        didApplySnapshotChange = didApplySnapshotChange || deviceListChanged

        for (deviceID, remoteState) in snapshot.stateByDeviceID
            where remoteState.device.transport == .usb &&
            snapshot.usbControlAvailabilityByDeviceID[deviceID]?.blocksUSBControlInteraction != true {
            clearUSBPhysicalConnectSettling(for: deviceID)
        }
        scheduleRemoteSnapshotSoftwareLightingAutoStart(for: snapshot.devices, now: now)

        if applySelectedRemoteSnapshotPresentation(deviceListChanged: deviceListChanged) {
            didApplySnapshotChange = true
        }

        if didApplySnapshotChange {
            Task { [weak self] in
                await self?.refreshDpiUpdateTransportStatuses(for: snapshot.devices)
            }
        }
    }

    func pruneRemoteSnapshotCaches(liveIDs: Set<String>, devices: [MouseDevice]) {
        let liveSoftwareLightingAutoStartKeys = Set(devices.map { DevicePersistenceKeys.key(for: $0) })
        remoteSnapshotSoftwareLightingAutoStartAttemptAtByDeviceKey =
            remoteSnapshotSoftwareLightingAutoStartAttemptAtByDeviceKey.filter {
                liveSoftwareLightingAutoStartKeys.contains($0.key)
            }
        stateCacheByDeviceID = stateCacheByDeviceID.filter { liveIDs.contains($0.key) }
        lastUpdatedByDeviceID = lastUpdatedByDeviceID.filter { liveIDs.contains($0.key) }
        lastStateMutationAtByDeviceID = lastStateMutationAtByDeviceID.filter { liveIDs.contains($0.key) }
        usbControlAvailabilityByDeviceID = usbControlAvailabilityByDeviceID.filter { liveIDs.contains($0.key) }
        for deviceID in Array(pendingUSBControlUnavailableTasksByDeviceID.keys) where !liveIDs.contains(deviceID) {
            cancelPendingUSBControlUnavailable(for: deviceID)
        }
        pruneUSBPhysicalConnectSettling(liveIDs: liveIDs)
    }

    func applyRemoteSoftwareLightingStatuses(
        _ snapshot: SharedServiceSnapshot,
        liveIDs: Set<String>,
        now: Date = Date()
    ) -> Bool {
        let previousStatuses = deviceStore.softwareLightingStatusByDeviceID
        var nextStatuses = snapshot.softwareLightingStatusByDeviceID.filter { liveIDs.contains($0.key) }
        for (deviceID, previousStatus) in previousStatuses where liveIDs.contains(deviceID) {
            guard shouldPreserveLocalSoftwareLightingStatus(
                deviceID: deviceID,
                previousStatus: previousStatus,
                snapshotStatus: nextStatuses[deviceID],
                now: now
            ) else {
                continue
            }
            nextStatuses[deviceID] = previousStatus
        }
        guard previousStatuses != nextStatuses else { return false }
        deviceStore.softwareLightingStatusByDeviceID = nextStatuses
        return true
    }

    func shouldPreserveLocalSoftwareLightingStatus(
        deviceID: String,
        previousStatus: SoftwareLightingEngineStatus,
        snapshotStatus: SoftwareLightingEngineStatus?,
        now: Date
    ) -> Bool {
        guard previousStatus.state == .running else { return false }
        if let snapshotStatus, previousStatus.updatedAt <= snapshotStatus.updatedAt {
            return false
        }

        let age = now.timeIntervalSince(previousStatus.updatedAt)
        guard age <= Self.remoteSnapshotSoftwareLightingStatusGraceInterval else {
            AppLog.event(
                "LightingTrace",
                "remote snapshot stale local software lighting status device=\(deviceID) " +
                    "age=\(SoftwareLightingDiagnostics.seconds(age)) " +
                    "local=\(SoftwareLightingDiagnostics.statusSummary(previousStatus)) " +
                    "snapshot=\(SoftwareLightingDiagnostics.statusSummary(snapshotStatus))"
            )
            return false
        }

        AppLog.debug(
            "LightingTrace",
            "remote snapshot preserving recent local software lighting status device=\(deviceID) " +
                "age=\(SoftwareLightingDiagnostics.seconds(age)) " +
                "local=\(SoftwareLightingDiagnostics.statusSummary(previousStatus)) " +
                "snapshot=\(SoftwareLightingDiagnostics.statusSummary(snapshotStatus))"
        )
        return true
    }

    func applyRemoteUSBControlAvailability(
        _ snapshot: SharedServiceSnapshot,
        liveIDs: Set<String>
    ) {
        for (deviceID, availability) in snapshot.usbControlAvailabilityByDeviceID where liveIDs.contains(deviceID) {
            let observedAt = snapshot.observedAtByDeviceID[deviceID] ?? Date()
            if shouldDropStaleUSBControlUnavailable(availability, for: deviceID, observedAt: observedAt) {
                AppLog.debug(
                    "AppState",
                    "remoteSnapshot usbControlAvailability stale-drop device=\(deviceID) " +
                    "availability=\(availability.rawValue)"
                )
                continue
            }
            setUSBControlAvailability(
                availability,
                for: deviceID,
                observedAt: observedAt
            )
        }
    }

    func applyRemoteStateCache(
        _ snapshot: SharedServiceSnapshot,
        liveIDs: Set<String>
    ) -> Bool {
        var didApplySnapshotChange = false
        for (deviceID, remoteState) in snapshot.stateByDeviceID where liveIDs.contains(deviceID) {
            let snapshotUpdatedAt = snapshot.lastUpdatedByDeviceID[deviceID] ?? Date()
            applyRemoteUSBObservationIfNeeded(snapshot, deviceID: deviceID, remoteState: remoteState, updatedAt: snapshotUpdatedAt)
            if shouldDropSupersededRemoteState(deviceID: deviceID, updatedAt: snapshotUpdatedAt) {
                continue
            }
            if stateCacheByDeviceID[deviceID] != remoteState ||
                lastUpdatedByDeviceID[deviceID] != snapshotUpdatedAt {
                didApplySnapshotChange = true
                stateCacheByDeviceID[deviceID] = remoteState
                lastUpdatedByDeviceID[deviceID] = snapshotUpdatedAt
            }
            lastStateMutationAtByDeviceID[deviceID] = snapshotUpdatedAt
            if clearConnectionFailureState(sourceDeviceID: deviceID, presentationDeviceID: deviceID) {
                didApplySnapshotChange = true
            }
        }
        return didApplySnapshotChange
    }

    func applyRemoteUSBObservationIfNeeded(
        _ snapshot: SharedServiceSnapshot,
        deviceID: String,
        remoteState: MouseState,
        updatedAt snapshotUpdatedAt: Date
    ) {
        guard remoteState.device.transport == .usb else { return }
        if snapshot.usbControlAvailabilityByDeviceID[deviceID] == nil {
            setUSBControlAvailability(
                .receiverPresentMouseReachable,
                for: deviceID,
                observedAt: snapshot.observedAtByDeviceID[deviceID] ?? Date()
            )
        }
        guard snapshot.usbControlAvailabilityByDeviceID[deviceID]?.blocksUSBControlInteraction != true else { return }
        let observedAt = max(snapshot.observedAtByDeviceID[deviceID] ?? snapshotUpdatedAt, snapshotUpdatedAt)
        recordUSBLiveObservation(
            sourceDeviceID: deviceID,
            presentationDeviceID: deviceID,
            observedAt: observedAt,
            transportStatus: .pollingFallback
        )
    }

    func shouldDropSupersededRemoteState(deviceID: String, updatedAt snapshotUpdatedAt: Date) -> Bool {
        guard let latestCachedAt = lastUpdatedByDeviceID[deviceID], latestCachedAt > snapshotUpdatedAt else {
            return false
        }
        AppLog.debug(
            "AppState",
            "remoteSnapshot superseded-drop device=\(deviceID) updatedAt=\(snapshotUpdatedAt.timeIntervalSince1970) " +
            "cachedAt=\(latestCachedAt.timeIntervalSince1970)"
        )
        return true
    }

    func applySelectedRemoteSnapshotPresentation(deviceListChanged: Bool) -> Bool {
        if let selectedDeviceID = deviceStore.selectedDeviceID,
           let selectedState = stateCacheByDeviceID[selectedDeviceID],
           let selectedDevice = deviceStore.selectedDevice {
            return applySelectedRemoteState(
                selectedDeviceID: selectedDeviceID,
                selectedState: selectedState,
                selectedDevice: selectedDevice,
                deviceListChanged: deviceListChanged
            )
        }
        if let selectedDeviceID = deviceStore.selectedDeviceID {
            return applyMissingSelectedRemoteState(selectedDeviceID: selectedDeviceID, deviceListChanged: deviceListChanged)
        }
        return clearRemoteSelectionPresentation()
    }

    func applySelectedRemoteState(
        selectedDeviceID: String,
        selectedState: MouseState,
        selectedDevice: MouseDevice,
        deviceListChanged: Bool
    ) -> Bool {
        var didApplySnapshotChange = false
        let activeStage = selectedState.dpi_stages.active_stage.map(String.init) ?? "nil"
        let dpi = Self.diagnosticDpiPair(selectedState.dpi)
        let values = selectedState.dpi_stages.values?.map(String.init).joined(separator: ",") ?? "nil"
        let scroll = Self.diagnosticScrollState(selectedState)
        let pendingLocal = String(applyController.hasPendingLocalEdits)
        let pendingActive = applyController.pendingActiveStageSelection(for: selectedDevice).map(String.init) ?? "nil"
        AppLog.debug(
            "AppState",
            "remoteSnapshot selected device=\(selectedDeviceID) " +
            "active=\(activeStage) " +
            "dpi=\(dpi) " +
            "values=\(values) " +
            "scroll=\(scroll) " +
            "pendingLocal=\(pendingLocal) " +
            "pendingActive=\(pendingActive)"
        )
        let selectedLastUpdated = lastUpdatedByDeviceID[selectedDeviceID]
        let selectedStateChanged = deviceStore.state != selectedState
        let selectedLastUpdatedChanged = deviceStore.lastUpdated != selectedLastUpdated
        if selectedStateChanged {
            deviceStore.state = selectedState
            didApplySnapshotChange = true
        }
        if selectedLastUpdatedChanged {
            deviceStore.lastUpdated = selectedLastUpdated
            didApplySnapshotChange = true
        }
        if selectedStateChanged || selectedLastUpdatedChanged || deviceListChanged {
            hydrateSelectedRemoteState(selectedState, selectedDevice: selectedDevice)
        }
        if deviceStore.errorMessage != nil {
            deviceStore.errorMessage = nil
            didApplySnapshotChange = true
        }
        didApplySnapshotChange = clearOrUpdateSelectedRemoteWarning(
            selectedState: selectedState,
            selectedDevice: selectedDevice
        ) || didApplySnapshotChange
        return didApplySnapshotChange
    }

    func hydrateSelectedRemoteState(_ selectedState: MouseState, selectedDevice: MouseDevice) {
        let holdsPersistedConnectPresentation = primeSelectedConnectPresentationIfNeeded(
            device: selectedDevice,
            applyController: applyController,
            editorController: editorController
        )
        hydrateSelectedEditorPresentation(
            EditorPresentationHydrationRequest(
                state: selectedState,
                device: selectedDevice,
                holdsPersistedConnectPresentation: holdsPersistedConnectPresentation,
                applyController: applyController,
                editorController: editorController,
                scheduleButtonHydration: true
            )
        )
        scheduleSelectedDeviceLightingHydration(device: selectedDevice)
    }

    func clearOrUpdateSelectedRemoteWarning(selectedState: MouseState, selectedDevice: MouseDevice) -> Bool {
        if selectedDevice.transport == .usb, usbControlAvailability(for: selectedDevice).blocksUSBControlInteraction {
            guard deviceStore.warningMessage != nil else { return false }
            deviceStore.warningMessage = nil
            return true
        }
        setTelemetryWarning(editorController.telemetryWarning(for: selectedState, device: selectedDevice), device: selectedDevice)
        return false
    }

    func applyMissingSelectedRemoteState(selectedDeviceID: String, deviceListChanged: Bool) -> Bool {
        if deviceListChanged {
            syncSelectedDevicePresentation(deviceID: selectedDeviceID)
        }
        guard deviceStore.errorMessage != nil else { return false }
        deviceStore.errorMessage = nil
        return true
    }

    func clearRemoteSelectionPresentation() -> Bool {
        var didApplySnapshotChange = false
        if deviceStore.state != nil {
            deviceStore.state = nil
            didApplySnapshotChange = true
        }
        if deviceStore.lastUpdated != nil {
            deviceStore.lastUpdated = nil
            didApplySnapshotChange = true
        }
        if deviceStore.warningMessage != nil {
            deviceStore.warningMessage = nil
            didApplySnapshotChange = true
        }
        if deviceStore.errorMessage != nil {
            deviceStore.errorMessage = nil
            didApplySnapshotChange = true
        }
        return didApplySnapshotChange
    }

    func scheduleRemoteSnapshotSoftwareLightingAutoStart(
        for devices: [MouseDevice],
        now: Date = Date()
    ) {
        guard let editorController = optionalEditorController else { return }
        let candidates = devices.compactMap { device in
            remoteSnapshotSoftwareLightingAutoStartCandidate(
                for: device,
                editorController: editorController,
                now: now
            )
        }
        guard !candidates.isEmpty else { return }
        Task { [weak self, weak editorController] in
            guard let self,
                  let editorController,
                  !self.isTearingDown,
                  !Task.isCancelled else {
                return
            }
            for candidate in candidates {
                let didStart = await editorController.startPersistedSoftwareLightingOnConnectIfNeeded(
                    for: candidate.device,
                    reassertRunning: true
                )
                AppLog.debug(
                    "LightingTrace",
                    "remote software lighting reconcile finished device=\(candidate.device.id) " +
                        "key=\(candidate.deviceKey) didStart=\(didStart) " +
                        "priorStatus=\(SoftwareLightingDiagnostics.statusSummary(candidate.previousStatus))"
                )
            }
        }
    }

    func remoteSnapshotSoftwareLightingAutoStartCandidate(
        for device: MouseDevice,
        editorController: AppStateEditorController,
        now: Date
    ) -> RemoteLightingAutoStartCandidate? {
        guard device.supportsSoftwareLightingEffects else { return nil }

        let deviceKey = DevicePersistenceKeys.key(for: device)
        let status = deviceStore.softwareLightingStatusByDeviceID[device.id]
        if status?.state == .running {
            remoteSnapshotSoftwareLightingAutoStartAttemptAtByDeviceKey.removeValue(forKey: deviceKey)
            return nil
        }
        if let status {
            remoteSnapshotSoftwareLightingAutoStartAttemptAtByDeviceKey.removeValue(forKey: deviceKey)
            AppLog.debug(
                "LightingTrace",
                "remote software lighting reconcile skipped device=\(device.id) " +
                    "key=\(deviceKey) reason=authoritativeNonRunning " +
                    "status=\(SoftwareLightingDiagnostics.statusSummary(status))"
            )
            return nil
        }

        guard editorController.preferenceStore.loadSoftwareLightingApplyOnConnect(device: device) else {
            remoteSnapshotSoftwareLightingAutoStartAttemptAtByDeviceKey.removeValue(forKey: deviceKey)
            AppLog.debug(
                "LightingTrace",
                "remote software lighting reconcile skipped device=\(device.id) " +
                    "key=\(deviceKey) applyOnConnect=false " +
                    "status=\(SoftwareLightingDiagnostics.statusSummary(status))"
            )
            return nil
        }

        if let lastAttemptAt = remoteSnapshotSoftwareLightingAutoStartAttemptAtByDeviceKey[deviceKey] {
            let elapsed = now.timeIntervalSince(lastAttemptAt)
            if elapsed < Self.remoteSnapshotSoftwareLightingAutoStartRetryInterval {
                AppLog.debug(
                    "LightingTrace",
                    "remote software lighting reconcile debounced device=\(device.id) " +
                        "key=\(deviceKey) elapsed=\(SoftwareLightingDiagnostics.seconds(elapsed)) " +
                        "status=\(SoftwareLightingDiagnostics.statusSummary(status))"
                )
                return nil
            }
        }

        remoteSnapshotSoftwareLightingAutoStartAttemptAtByDeviceKey[deviceKey] = now
        AppLog.event(
            "LightingTrace",
            "remote software lighting reconcile queued device=\(device.id) " +
                "key=\(deviceKey) applyOnConnect=true " +
                "status=\(SoftwareLightingDiagnostics.statusSummary(status))"
        )
        return RemoteLightingAutoStartCandidate(
            device: device,
            deviceKey: deviceKey,
            previousStatus: status
        )
    }

    func applyBackendSoftwareLightingStatusUpdate(
        deviceID: String,
        status: SoftwareLightingEngineStatus?,
        updatedAt _: Date
    ) {
        if let status {
            deviceStore.softwareLightingStatusByDeviceID[deviceID] = status
        } else {
            deviceStore.softwareLightingStatusByDeviceID.removeValue(forKey: deviceID)
        }
    }

    func applyBackendUSBControlAvailabilityUpdate(
        deviceID: String,
        availability: USBControlAvailability,
        updatedAt: Date
    ) {
        guard !isTearingDown else { return }
        let previousSourceAvailability = usbControlAvailabilityByDeviceID[deviceID]
        let didApplySourceAvailability = setBackendObservedUSBControlAvailability(
            availability,
            for: deviceID,
            observedAt: updatedAt
        )

        guard let sourceDevice = deviceStore.devices.first(where: { $0.id == deviceID }),
              let presentationDevice = presentationDevice(for: sourceDevice) else {
            return
        }

        let presentationDeviceID = presentationDevice.id
        let previousPresentationAvailability = usbControlAvailabilityByDeviceID[presentationDeviceID]
        let didApplyPresentationAvailability = presentationDeviceID == deviceID
            ? didApplySourceAvailability
            : setBackendObservedUSBControlAvailability(
                availability,
                for: presentationDeviceID,
                observedAt: updatedAt
            )
        let clearsPhysicalAbsence = availability == .unknown &&
            (
                previousSourceAvailability?.blocksUSBControlInteraction == true ||
                    previousPresentationAvailability?.blocksUSBControlInteraction == true
            )
        if availability == .receiverPresentMouseReachable || clearsPhysicalAbsence {
            clearConnectionFailureState(sourceDeviceID: deviceID, presentationDeviceID: presentationDeviceID)
            if deviceStore.selectedDeviceID == presentationDeviceID {
                Task { @MainActor [weak self] in
                    _ = await self?.refreshState(for: presentationDevice)
                }
            }
        } else if availability.blocksUSBControlInteraction,
                  didApplyPresentationAvailability,
                  deviceStore.selectedDeviceID == presentationDeviceID {
            deviceStore.errorMessage = nil
            deviceStore.warningMessage = nil
        }
    }

    func applyBackendDeviceStateUpdate(deviceID: String, state updatedState: MouseState, updatedAt: Date) {
        guard !isTearingDown else { return }
        guard let sourceDevice = deviceStore.devices.first(where: { $0.id == deviceID }),
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
        logBackendStateUpdate(
            sourceDeviceID: deviceID,
            presentationDevice: presentationDevice,
            incoming: updatedState,
            merged: merged
        )

        cacheState(merged, sourceDeviceID: deviceID, presentationDeviceID: presentationDeviceID, updatedAt: updatedAt)
        setDpiUpdateTransportStatus(.realTimeHID, for: deviceID)
        setDpiUpdateTransportStatus(.realTimeHID, for: presentationDeviceID)
        if sourceDevice.transport == .usb {
            recordUSBLiveObservation(
                sourceDeviceID: deviceID,
                presentationDeviceID: presentationDeviceID,
                observedAt: updatedAt,
                transportStatus: .realTimeHID
            )
        }
        refreshFailureCountByDeviceID[deviceID] = 0
        refreshFailureCountByDeviceID[presentationDeviceID] = 0
        unavailableDeviceIDs.remove(deviceID)
        unavailableDeviceIDs.remove(presentationDeviceID)

        if shouldFocusOnActivity {
            focusServiceSelectionOnActivity(deviceID: presentationDeviceID)
        }
        runtimeController.updateStatusItemTransientDpi(previous: previous, next: merged, deviceID: presentationDeviceID)

        applySelectedBackendStateUpdate(merged, presentationDevice: presentationDevice)
    }

    func logBackendStateUpdate(
        sourceDeviceID: String,
        presentationDevice: MouseDevice,
        incoming updatedState: MouseState,
        merged: MouseState
    ) {
        let incomingActive = updatedState.dpi_stages.active_stage.map(String.init) ?? "nil"
        let incomingDpi = Self.diagnosticDpiPair(updatedState.dpi)
        let incomingScroll = Self.diagnosticScrollState(updatedState)
        let mergedActive = merged.dpi_stages.active_stage.map(String.init) ?? "nil"
        let mergedDpi = Self.diagnosticDpiPair(merged.dpi)
        let mergedValues = merged.dpi_stages.values?.map(String.init).joined(separator: ",") ?? "nil"
        let mergedScroll = Self.diagnosticScrollState(merged)
        let selectedDeviceID = deviceStore.selectedDeviceID ?? "nil"
        let pendingLocal = String(applyController.hasPendingLocalEdits)
        let pendingActive = applyController.pendingActiveStageSelection(for: presentationDevice).map(String.init) ?? "nil"
        AppLog.debug(
            "AppState",
            "backendStateUpdate apply device=\(presentationDevice.id) source=\(sourceDeviceID) " +
            "incomingActive=\(incomingActive) " +
            "incomingDpi=\(incomingDpi) " +
            "incomingScroll=\(incomingScroll) " +
            "mergedActive=\(mergedActive) " +
            "mergedDpi=\(mergedDpi) " +
            "mergedValues=\(mergedValues) " +
            "mergedScroll=\(mergedScroll) " +
            "selected=\(selectedDeviceID) " +
            "pendingLocal=\(pendingLocal) " +
            "pendingActive=\(pendingActive)"
        )
    }

    func applySelectedBackendStateUpdate(_ merged: MouseState, presentationDevice: MouseDevice) {
        guard deviceStore.selectedDeviceID == presentationDevice.id else { return }
        if deviceStore.state != merged {
            deviceStore.state = merged
        }
        let holdsPersistedConnectPresentation = primeSelectedConnectPresentationIfNeeded(
            device: presentationDevice,
            applyController: applyController,
            editorController: editorController
        )
        hydrateSelectedEditorPresentation(
            EditorPresentationHydrationRequest(
                state: merged,
                device: presentationDevice,
                holdsPersistedConnectPresentation: holdsPersistedConnectPresentation,
                applyController: applyController,
                editorController: editorController,
                scheduleButtonHydration: true
            )
        )
        deviceStore.errorMessage = nil
        setTelemetryWarning(editorController.telemetryWarning(for: merged, device: presentationDevice), device: presentationDevice)
    }

    func applyBackendDpiTransportStatusUpdate(deviceID: String, status: DpiUpdateTransportStatus, updatedAt: Date) {
        guard !isTearingDown else { return }
        if status == .streamActive {
            lastPassiveHeartbeatAtByDeviceID[deviceID] = updatedAt
        }

        let currentStatus = dpiUpdateTransportStatusByDeviceID[deviceID]
        let shouldApplySourceStatus = Self.shouldApplyBackendDpiTransportStatusUpdate(
            current: currentStatus,
            incoming: status
        )
        if !shouldApplySourceStatus, status != .streamActive {
            return
        }

        if shouldApplySourceStatus {
            setDpiUpdateTransportStatus(status, for: deviceID)
        }

        guard let sourceDevice = deviceStore.devices.first(where: { $0.id == deviceID }),
              let presentationDevice = presentationDevice(for: sourceDevice) else {
            return
        }

        let presentationDeviceID = presentationDevice.id
        if status == .streamActive {
            lastPassiveHeartbeatAtByDeviceID[presentationDeviceID] = updatedAt
        }
        let presentationStatus = dpiUpdateTransportStatusByDeviceID[presentationDeviceID]
        if Self.shouldApplyBackendDpiTransportStatusUpdate(current: presentationStatus, incoming: status) {
            setDpiUpdateTransportStatus(status, for: presentationDeviceID)
        }
        if sourceDevice.transport == .usb, status == .streamActive {
            recordUSBLiveObservation(
                sourceDeviceID: deviceID,
                presentationDeviceID: presentationDeviceID,
                observedAt: updatedAt,
                transportStatus: status
            )
        }
    }

}
