import Foundation
import OpenSnekCore
import OpenSnekHardware

@MainActor
extension AppStateDeviceController {
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
        guard !isTearingDown else { return }
        guard let selectedDevice = deviceStore.selectedDevice else {
            deviceStore.state = nil
            deviceStore.errorMessage = nil
            deviceStore.warningMessage = nil
            deviceStore.lastUpdated = nil
            deviceStore.isRefreshingState = false
            return
        }
        guard !isStrictlyUnsupported(selectedDevice) else {
            deviceStore.state = nil
            deviceStore.warningMessage = nil
            deviceStore.errorMessage = nil
            deviceStore.lastUpdated = nil
            deviceStore.isRefreshingState = false
            return
        }
        _ = await refreshState(for: selectedDevice)
    }

    func refreshAllDeviceStates(prioritizing prioritizedDeviceIDs: [String] = []) async {
        guard !isTearingDown else { return }
        let devicesToRefresh = refreshableDevicesInPriorityOrder(prioritizing: prioritizedDeviceIDs)
        guard !devicesToRefresh.isEmpty else {
            if let selectedDevice = deviceStore.selectedDevice, isStrictlyUnsupported(selectedDevice) {
                deviceStore.state = nil
                deviceStore.warningMessage = nil
                deviceStore.errorMessage = nil
                deviceStore.lastUpdated = nil
                deviceStore.isRefreshingState = false
            } else if let selectedDeviceID = deviceStore.selectedDeviceID {
                syncSelectedDevicePresentation(deviceID: selectedDeviceID)
            } else {
                deviceStore.state = nil
                deviceStore.warningMessage = nil
                deviceStore.errorMessage = nil
                deviceStore.lastUpdated = nil
                deviceStore.isRefreshingState = false
            }
            return
        }

        for device in devicesToRefresh {
            _ = await refreshState(for: device)
        }

        if let selectedDeviceID = deviceStore.selectedDeviceID {
            syncSelectedDevicePresentation(deviceID: selectedDeviceID)
        }
    }

    func refreshDeviceStates(deviceIDs: [String]) async {
        guard !isTearingDown else { return }

        let targetDeviceIDs = Set(deviceIDs)
        let devicesToRefresh = refreshableDevicesInPriorityOrder(prioritizing: deviceIDs)
            .filter { targetDeviceIDs.contains($0.id) }

        guard !devicesToRefresh.isEmpty else {
            if let selectedDeviceID = deviceStore.selectedDeviceID {
                syncSelectedDevicePresentation(deviceID: selectedDeviceID)
            }
            return
        }

        for device in devicesToRefresh {
            _ = await refreshState(for: device)
        }

        if let selectedDeviceID = deviceStore.selectedDeviceID {
            syncSelectedDevicePresentation(deviceID: selectedDeviceID)
        }
    }

    @discardableResult
    func refreshState(for device: MouseDevice) async -> Bool {
        let now = Date()
        guard canStartRefreshState(for: device, now: now) else {
            return false
        }

        presentCachedSelectedStateIfNeeded(for: device)

        refreshingStateDeviceIDs.insert(device.id)
        if deviceStore.selectedDeviceID == device.id {
            deviceStore.isRefreshingState = true
        }
        defer {
            refreshingStateDeviceIDs.remove(device.id)
            if deviceStore.selectedDeviceID == device.id {
                deviceStore.isRefreshingState = false
            }
        }

        let refreshRevision = applyController.stateRevision
        let restoreRevision = settingsRestoreRevision(for: device)
        let refreshDeviceID = device.id
        let cachedStateBeforeRefresh = stateCacheByDeviceID[device.id]
        let start = Date()
        let wasRecoveringUSBBackoff = device.transport == .usb &&
            (
                stateRefreshSuppressedUntilByDeviceID[refreshDeviceID] != nil ||
                    usbTelemetryUnavailableBackoffDeviceIDs.contains(refreshDeviceID) ||
                    (refreshFailureCountByDeviceID[refreshDeviceID] ?? 0) > 0
            )

        do {
            let fetched = try await environment.backend.readState(device: device)
            guard !isTearingDown else { return false }
            guard refreshRevision == applyController.stateRevision else {
                AppLog.debug("AppState", "refreshState stale-drop rev=\(refreshRevision) current=\(applyController.stateRevision)")
                return false
            }
            guard restoreRevision == settingsRestoreRevision(for: device) else {
                AppLog.debug(
                    "AppState",
                    "refreshState stale-drop restore-rev=\(restoreRevision) current=\(settingsRestoreRevision(for: device)) device=\(device.id)"
                )
                return false
            }
            guard let presentationDevice = presentationDevice(for: device) else {
                AppLog.debug("AppState", "refreshState drop missing-presentation device=\(refreshDeviceID)")
                return false
            }

            let presentationDeviceID = presentationDevice.id
            let latestCachedState = stateCacheByDeviceID[presentationDeviceID] ?? stateCacheByDeviceID[refreshDeviceID]
            if shouldTreatPartialUSBTelemetryAsUnavailable(
                fetched,
                device: presentationDevice,
                wasRecoveringUSBBackoff: wasRecoveringUSBBackoff,
                hasCachedState: latestCachedState != nil
            ) {
                AppLog.debug(
                    "AppState",
                    "refreshState partial usb telemetry treated unavailable device=\(presentationDeviceID)"
                )
                throw Self.usbTelemetryUnavailableError()
            }
            let latestCachedStableUpdateAt = latestCachedUpdateAt(sourceDeviceID: refreshDeviceID, presentationDeviceID: presentationDeviceID)
            if let handledRecentDpi = await handleRecentDynamicDpiRefreshIfNeeded(
                RecentDynamicDpiRefreshContext(
                    fetched: fetched,
                    latestCachedState: latestCachedState,
                    cachedStateBeforeRefresh: cachedStateBeforeRefresh,
                    latestCachedStableUpdateAt: latestCachedStableUpdateAt,
                    sourceDevice: device,
                    presentationDevice: presentationDevice,
                    sourceDeviceID: refreshDeviceID,
                    start: start
                )
            ) {
                return handledRecentDpi
            }
            let previous = stateCacheByDeviceID[presentationDeviceID] ?? stateCacheByDeviceID[refreshDeviceID]
            let merged = fetched.merged(with: previous)
            let shouldFocusOnActivity = shouldFocusServiceSelectionOnActivity(previous: previous, next: merged)
            await finishSuccessfulRefreshState(
                SuccessfulRefreshContext(
                    merged: merged,
                    sourceDevice: device,
                    presentationDevice: presentationDevice,
                    previous: previous,
                    sourceDeviceID: refreshDeviceID,
                    start: start,
                    shouldFocusOnActivity: shouldFocusOnActivity,
                    clearSeededReconnectState: true
                )
            )

            AppLog.debug(
                "AppState",
                "refreshState ok device=\(presentationDeviceID) active=\(merged.dpi_stages.active_stage.map(String.init) ?? "nil") " +
                "values=\(merged.dpi_stages.values?.map(String.init).joined(separator: ",") ?? "nil") " +
                "scroll=\(Self.diagnosticScrollState(merged)) " +
                "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
            )
            return true
        } catch {
            return handleRefreshStateFailure(error, device: device, refreshDeviceID: refreshDeviceID)
        }
    }

    func canStartRefreshState(for device: MouseDevice, now: Date) -> Bool {
        guard !isTearingDown else { return false }
        guard !isStrictlyUnsupported(device) else { return false }
        guard !refreshingStateDeviceIDs.contains(device.id) else { return false }
        guard !isRestoringSettings(for: device) else {
            AppLog.debug("AppState", "refreshState skipped restoring-settings device=\(device.id)")
            return false
        }
        guard !deviceStore.isApplying else {
            AppLog.debug("AppState", "refreshState skipped applying device=\(device.id)")
            return false
        }
        guard !applyController.hasPendingLocalEditsAffecting(device) else {
            AppLog.debug("AppState", "refreshState skipped pending-local-edits device=\(device.id)")
            return false
        }
        guard !isRefreshBackoffActive(for: device, now: now) else { return false }
        return !shouldDeferBluetoothRealtimeRefresh(for: device, now: now)
    }

    func isRefreshBackoffActive(for device: MouseDevice, now: Date) -> Bool {
        guard let suppressedUntil = stateRefreshSuppressedUntilByDeviceID[device.id], now < suppressedUntil else {
            return false
        }
        AppLog.debug(
            "AppState",
            "refreshState skipped backoff device=\(device.id) remaining=\(String(format: "%.3f", suppressedUntil.timeIntervalSince(now)))s"
        )
        return true
    }

    func shouldDeferBluetoothRealtimeRefresh(for device: MouseDevice, now: Date) -> Bool {
        let shouldDefer = Self.shouldDelayBluetoothRealtimeStateRefresh(
            BluetoothRealtimeRefreshDelayContext(
                transport: device.transport,
                transportStatus: dpiUpdateTransportStatusByDeviceID[device.id],
                lastHeartbeatAt: lastPassiveHeartbeatAtByDeviceID[device.id],
                lastFullStateRefreshStartedAt: lastFullStateRefreshStartedAtByDeviceID[device.id],
                minimumRefreshInterval: runtimeController.effectiveRefreshStateInterval(
                    at: now,
                    profile: runtimeController.pollingProfile(at: now)
                ),
                now: now
            )
        )
        if shouldDefer {
            AppLog.debug("AppState", "refreshState deferred active-bt-realtime device=\(device.id)")
        }
        return shouldDefer
    }

    func presentCachedSelectedStateIfNeeded(for device: MouseDevice) {
        guard deviceStore.selectedDeviceID == device.id, let cached = stateCacheByDeviceID[device.id] else { return }
        deviceStore.state = cached
    }

    func handleRecentDynamicDpiRefreshIfNeeded(_ context: RecentDynamicDpiRefreshContext) async -> Bool? {
        let fetched = context.fetched
        let latestCachedState = context.latestCachedState
        let latestCachedStableUpdateAt = context.latestCachedStableUpdateAt
        let sourceDevice = context.sourceDevice
        let presentationDevice = context.presentationDevice
        let sourceDeviceID = context.sourceDeviceID
        let start = context.start
        let presentationDeviceID = presentationDevice.id
        let latestMutationAt = latestCachedMutationAt(
            sourceDeviceID: sourceDeviceID,
            presentationDeviceID: presentationDeviceID
        )
        if let latestMutationAt, latestMutationAt > start {
            return await handleConcurrentDynamicDpiMutation(
                latestMutationAt: latestMutationAt,
                context: context
            )
        }
        guard shouldPreferRecentDynamicDpiMutation(
            over: fetched,
            latestCachedState: latestCachedState,
            latestCachedMutationAt: latestMutationAt,
            latestCachedStableUpdateAt: latestCachedStableUpdateAt
        ),
              let latestCachedState else {
            return nil
        }

        let merged = latestCachedState.mergedWithStableReadTelemetry(from: fetched)
        await finishSuccessfulRefreshState(
            SuccessfulRefreshContext(
                merged: merged,
                sourceDevice: sourceDevice,
                presentationDevice: presentationDevice,
                previous: nil,
                sourceDeviceID: sourceDeviceID,
                start: start,
                shouldFocusOnActivity: false,
                clearSeededReconnectState: false
            )
        )
        AppLog.debug(
            "AppState",
            "refreshState merged recent-fast-dpi device=\(presentationDevice.id) active=\(merged.dpi_stages.active_stage.map(String.init) ?? "nil") " +
            "values=\(merged.dpi_stages.values?.map(String.init).joined(separator: ",") ?? "nil") " +
            "scroll=\(Self.diagnosticScrollState(merged))"
        )
        return true
    }

    func handleConcurrentDynamicDpiMutation(
        latestMutationAt: Date,
        context: RecentDynamicDpiRefreshContext
    ) async -> Bool {
        let latestCachedState = context.latestCachedState
        let cachedStateBeforeRefresh = context.cachedStateBeforeRefresh
        let fetched = context.fetched
        let latestCachedStableUpdateAt = context.latestCachedStableUpdateAt
        let sourceDevice = context.sourceDevice
        let presentationDevice = context.presentationDevice
        let sourceDeviceID = context.sourceDeviceID
        let start = context.start
        if let latestCachedState,
           latestCachedState.differsOnlyInDynamicDpiState(from: cachedStateBeforeRefresh) {
            let merged = latestCachedState.mergedWithStableReadTelemetry(from: fetched)
            await finishSuccessfulRefreshState(
                SuccessfulRefreshContext(
                    merged: merged,
                    sourceDevice: sourceDevice,
                    presentationDevice: presentationDevice,
                    previous: nil,
                    sourceDeviceID: sourceDeviceID,
                    start: start,
                    shouldFocusOnActivity: false,
                    clearSeededReconnectState: false
                )
            )
            return true
        }
        AppLog.debug(
            "AppState",
            "refreshState superseded-drop device=\(presentationDevice.id) startedAt=\(start.timeIntervalSince1970) " +
            "cachedAt=\(latestCachedStableUpdateAt?.timeIntervalSince1970 ?? 0) mutationAt=\(latestMutationAt.timeIntervalSince1970)"
        )
        return false
    }

    func finishSuccessfulRefreshState(_ context: SuccessfulRefreshContext) async {
        let merged = context.merged
        let sourceDevice = context.sourceDevice
        let presentationDevice = context.presentationDevice
        let previous = context.previous
        let sourceDeviceID = context.sourceDeviceID
        let start = context.start
        let shouldFocusOnActivity = context.shouldFocusOnActivity
        let clearSeededReconnectState = context.clearSeededReconnectState
        let presentationDeviceID = presentationDevice.id
        let updatedAt = Date()
        cacheState(merged, sourceDeviceID: sourceDeviceID, presentationDeviceID: presentationDeviceID, updatedAt: updatedAt)
        if sourceDevice.transport == .usb {
            recordUSBLiveObservation(
                sourceDeviceID: sourceDeviceID,
                presentationDeviceID: presentationDeviceID,
                observedAt: updatedAt
            )
        }
        if clearSeededReconnectState {
            seededReconnectStateDeviceIDs.remove(sourceDeviceID)
            seededReconnectStateDeviceIDs.remove(presentationDeviceID)
        }
        // Track when the full read started so passive-HID throttling preserves
        // the configured poll cadence instead of adding vendor-read latency.
        lastFullStateRefreshStartedAtByDeviceID[sourceDeviceID] = start
        lastFullStateRefreshStartedAtByDeviceID[presentationDeviceID] = start
        clearRefreshFailureState(sourceDeviceID: sourceDeviceID, presentationDeviceID: presentationDeviceID)
        if shouldFocusOnActivity {
            focusServiceSelectionOnActivity(deviceID: presentationDeviceID)
        }
        if let previous {
            runtimeController.updateStatusItemTransientDpi(previous: previous, next: merged, deviceID: presentationDeviceID)
        }
        applySelectedSuccessfulRefreshState(merged, presentationDevice: presentationDevice)
        await restorePersistedSettingsIfNeeded(for: presentationDevice)
    }

    func clearRefreshFailureState(sourceDeviceID: String, presentationDeviceID: String) {
        refreshFailureCountByDeviceID[sourceDeviceID] = 0
        refreshFailureCountByDeviceID[presentationDeviceID] = 0
        stateRefreshSuppressedUntilByDeviceID[sourceDeviceID] = nil
        stateRefreshSuppressedUntilByDeviceID[presentationDeviceID] = nil
        usbTelemetryUnavailableBackoffDeviceIDs.remove(sourceDeviceID)
        usbTelemetryUnavailableBackoffDeviceIDs.remove(presentationDeviceID)
        unavailableDeviceIDs.remove(sourceDeviceID)
        unavailableDeviceIDs.remove(presentationDeviceID)
    }

    func applySelectedSuccessfulRefreshState(_ merged: MouseState, presentationDevice: MouseDevice) {
        guard deviceStore.selectedDeviceID == presentationDevice.id else { return }
        if deviceStore.state != merged {
            deviceStore.state = merged
        }
        let holdsPersistedConnectPresentation = primeSelectedConnectPresentationIfNeeded(
            device: presentationDevice,
            applyController: applyController,
            editorController: editorController
        )
        let hydratedEditable = hydrateSelectedEditorPresentation(
            EditorPresentationHydrationRequest(
                state: merged,
                device: presentationDevice,
                holdsPersistedConnectPresentation: holdsPersistedConnectPresentation,
                applyController: applyController,
                editorController: editorController,
                scheduleButtonHydration: false
            )
        )
        if hydratedEditable {
            scheduleSelectedEditorHydration(device: presentationDevice)
        }
        deviceStore.errorMessage = nil
        setTelemetryWarning(editorController.telemetryWarning(for: merged, device: presentationDevice), device: presentationDevice)
    }

    struct RefreshFailureContext {
        let presentationDeviceID: String
        let failures: Int
        let isAvailabilityFailure: Bool
        let isUSBTelemetryUnavailable: Bool
        let hasCachedPresentationState: Bool
        let isRecoveringUSBAvailability: Bool
        let shouldTreatAsHardAvailabilityFailure: Bool
    }

    func handleRefreshStateFailure(
        _ error: Error,
        device: MouseDevice,
        refreshDeviceID: String
    ) -> Bool {
        let context = refreshFailureContext(error, device: device, refreshDeviceID: refreshDeviceID)
        applyRefreshFailureBackoffIfNeeded(context, error: error, device: device, refreshDeviceID: refreshDeviceID)

        guard deviceStore.selectedDeviceID == context.presentationDeviceID else {
            AppLog.debug("AppState", "refreshState masked non-selected failure device=\(context.presentationDeviceID): \(error.localizedDescription)")
            return false
        }
        return surfaceSelectedRefreshFailure(context, error: error, device: device)
    }

    func refreshFailureContext(
        _ error: Error,
        device: MouseDevice,
        refreshDeviceID: String
    ) -> RefreshFailureContext {
        let presentationDeviceID = presentationDevice(for: device)?.id ?? refreshDeviceID
        let failures = (refreshFailureCountByDeviceID[presentationDeviceID] ?? 0) + 1
        refreshFailureCountByDeviceID[refreshDeviceID] = failures
        refreshFailureCountByDeviceID[presentationDeviceID] = failures

        let isAvailabilityFailure = Self.isDeviceAvailabilityMessage(error.localizedDescription)
        let usbControlAvailabilityFailure = usbControlAvailabilityFailure(
            error,
            device: device,
            isAvailabilityFailure: isAvailabilityFailure
        )
        let isUSBTelemetryUnavailable = usbControlAvailabilityFailure == .receiverPresentMouseUnavailable
        if let usbControlAvailabilityFailure {
            setUSBControlAvailability(usbControlAvailabilityFailure, for: refreshDeviceID)
            setUSBControlAvailability(usbControlAvailabilityFailure, for: presentationDeviceID)
        }
        if isUSBTelemetryUnavailable {
            usbTelemetryUnavailableBackoffDeviceIDs.insert(refreshDeviceID)
            usbTelemetryUnavailableBackoffDeviceIDs.insert(presentationDeviceID)
        }

        let hasCachedPresentationState = hasCachedState(sourceDeviceID: refreshDeviceID, presentationDeviceID: presentationDeviceID)
        let hasSeededReconnectState = seededReconnectStateDeviceIDs.contains(presentationDeviceID)
        let isRecoveringUSBAvailability =
            device.transport == .usb &&
            isAvailabilityFailure &&
            !isUSBTelemetryUnavailable &&
            (hasCachedPresentationState || hasSeededReconnectState)
        let shouldTreatAsHardAvailabilityFailure =
            isAvailabilityFailure &&
            !isUSBTelemetryUnavailable &&
            !isRecoveringUSBAvailability
        if shouldTreatAsHardAvailabilityFailure {
            unavailableDeviceIDs.insert(refreshDeviceID)
            unavailableDeviceIDs.insert(presentationDeviceID)
        }

        return RefreshFailureContext(
            presentationDeviceID: presentationDeviceID,
            failures: failures,
            isAvailabilityFailure: isAvailabilityFailure,
            isUSBTelemetryUnavailable: isUSBTelemetryUnavailable,
            hasCachedPresentationState: hasCachedPresentationState,
            isRecoveringUSBAvailability: isRecoveringUSBAvailability,
            shouldTreatAsHardAvailabilityFailure: shouldTreatAsHardAvailabilityFailure
        )
    }

    func usbControlAvailabilityFailure(
        _ error: Error,
        device: MouseDevice,
        isAvailabilityFailure: Bool
    ) -> USBControlAvailability? {
        guard device.transport == .usb else { return nil }
        if BridgeClient.isUSBTelemetryUnavailableError(error) {
            return .receiverPresentMouseUnavailable
        }
        if isAvailabilityFailure, Self.isDeviceNotAvailableMessage(error.localizedDescription) {
            return .receiverAbsent
        }
        return nil
    }

    func hasCachedState(sourceDeviceID: String, presentationDeviceID: String) -> Bool {
        stateCacheByDeviceID[presentationDeviceID] != nil ||
            stateCacheByDeviceID[sourceDeviceID] != nil ||
            (deviceStore.selectedDeviceID == presentationDeviceID && deviceStore.state != nil)
    }

    func applyRefreshFailureBackoffIfNeeded(
        _ context: RefreshFailureContext,
        error: Error,
        device: MouseDevice,
        refreshDeviceID: String
    ) {
        guard context.isAvailabilityFailure ||
            context.isUSBTelemetryUnavailable ||
            deviceStore.selectedDeviceID != context.presentationDeviceID else {
            return
        }
        let suppressedUntil = Date().addingTimeInterval(
            stateRefreshBackoffInterval(for: device, failures: context.failures, error: error)
        )
        stateRefreshSuppressedUntilByDeviceID[refreshDeviceID] = suppressedUntil
        stateRefreshSuppressedUntilByDeviceID[context.presentationDeviceID] = suppressedUntil
        AppLog.debug(
            "AppState",
            "refreshState backoff device=\(context.presentationDeviceID) " +
            "selected=\(deviceStore.selectedDeviceID == context.presentationDeviceID) failures=\(context.failures) " +
            "until=\(suppressedUntil.timeIntervalSince1970): \(error.localizedDescription)"
        )
    }

    func surfaceSelectedRefreshFailure(
        _ context: RefreshFailureContext,
        error: Error,
        device: MouseDevice
    ) -> Bool {
        if context.isUSBTelemetryUnavailable {
            deviceStore.errorMessage = nil
            deviceStore.warningMessage = nil
            if !context.hasCachedPresentationState {
                deviceStore.state = nil
                deviceStore.lastUpdated = nil
            }
            return false
        }

        if context.shouldTreatAsHardAvailabilityFailure {
            deviceStore.state = nil
            deviceStore.lastUpdated = nil
            deviceStore.warningMessage = nil
            deviceStore.errorMessage = error.localizedDescription
            return false
        }

        if stateCacheByDeviceID[context.presentationDeviceID] == nil {
            AppLog.error(
                "AppState",
                "refreshState failed device=\(context.presentationDeviceID) transport=\(device.transport.rawValue) no-cache: \(error.localizedDescription)"
            )
            deviceStore.errorMessage = context.isRecoveringUSBAvailability ? nil : error.localizedDescription
            deviceStore.warningMessage = nil
        } else {
            surfaceTransientRefreshFailure(context, error: error)
        }
        return false
    }

    func surfaceTransientRefreshFailure(_ context: RefreshFailureContext, error: Error) {
        AppLog.debug("AppState", "refreshState transient-failure masked: \(error.localizedDescription)")
        if context.isRecoveringUSBAvailability {
            deviceStore.errorMessage = nil
        } else if context.failures >= 3 {
            if context.failures == 3 {
                AppLog.warning(
                    "AppState",
                    "device read unstable device=\(context.presentationDeviceID) failures=\(context.failures): \(error.localizedDescription)"
                )
            }
            deviceStore.errorMessage = "Device read is failing repeatedly (\(context.failures)x): \(error.localizedDescription)"
        } else {
            deviceStore.errorMessage = nil
        }
        deviceStore.warningMessage = "Using the last known values while live telemetry settles."
    }

    func shouldTreatPartialUSBTelemetryAsUnavailable(
        _ state: MouseState,
        device: MouseDevice,
        wasRecoveringUSBBackoff: Bool,
        hasCachedState: Bool
    ) -> Bool {
        guard device.transport == .usb else { return false }
        guard resolvedProfile(for: device) != nil else { return false }
        guard wasRecoveringUSBBackoff || !hasCachedState else { return false }
        return state.dpi_stages.values == nil || state.poll_rate == nil || state.led_value == nil
    }

    static func usbTelemetryUnavailableError() -> NSError {
        NSError(domain: "OpenSnek.AppStateDeviceController", code: 1, userInfo: [
            NSLocalizedDescriptionKey: usbTelemetryUnavailableMessage
        ])
    }
}
