import Foundation
import OpenSnekAppSupport
import OpenSnekCore

@MainActor
final class AppStateApplyController {
    unowned let appState: AppState

    private let applyCoordinator = ApplyCoordinator()
    private var dpiApplyTask: Task<Void, Never>?
    private var pollApplyTask: Task<Void, Never>?
    private var powerApplyTask: Task<Void, Never>?
    private var deviceModeApplyTask: Task<Void, Never>?
    private var lowBatteryApplyTask: Task<Void, Never>?
    private var scrollModeApplyTask: Task<Void, Never>?
    private var scrollAccelerationApplyTask: Task<Void, Never>?
    private var scrollSmartReelApplyTask: Task<Void, Never>?
    private var ledApplyTask: Task<Void, Never>?
    private var colorApplyTask: Task<Void, Never>?
    private var lightingEffectApplyTask: Task<Void, Never>?
    private var buttonApplyTask: Task<Void, Never>?
    private var activeStageApplyTask: Task<Void, Never>?
    private(set) var hasPendingLocalEdits = false
    private var applyDrainTask: Task<Void, Never>?
    private var lastLocalEditAt: Date?
    private var localEditDeviceIdentityKey: String?

    init(appState: AppState) {
        self.appState = appState
    }

    func tearDown() {
        dpiApplyTask?.cancel()
        pollApplyTask?.cancel()
        powerApplyTask?.cancel()
        deviceModeApplyTask?.cancel()
        lowBatteryApplyTask?.cancel()
        scrollModeApplyTask?.cancel()
        scrollAccelerationApplyTask?.cancel()
        scrollSmartReelApplyTask?.cancel()
        ledApplyTask?.cancel()
        colorApplyTask?.cancel()
        lightingEffectApplyTask?.cancel()
        buttonApplyTask?.cancel()
        activeStageApplyTask?.cancel()
        applyDrainTask?.cancel()
    }

    var stateRevision: UInt64 {
        applyCoordinator.stateRevision
    }

    var shouldHydrateEditable: Bool {
        guard !appState.isApplying, !appState.isEditingDpiControl, !hasPendingLocalEdits else { return false }
        guard let lastLocalEditAt else { return true }
        return Date().timeIntervalSince(lastLocalEditAt) > 0.8
    }

    func updateStage(_ index: Int, value: Int) {
        guard index >= 0 && index < appState.editableStageValues.count else { return }
        appState.editableStageValues[index] = max(100, min(30000, value))
    }

    func stageValue(_ index: Int) -> Int {
        guard index >= 0 && index < appState.editableStageValues.count else { return 800 }
        return appState.editableStageValues[index]
    }

    func applyDpiStages() async {
        let count = max(1, min(5, appState.editableStageCount))
        let values = Array(appState.editableStageValues.prefix(count)).map { max(100, min(30000, $0)) }
        let active = max(0, min(count - 1, appState.editableActiveStage - 1))
        enqueueApply(DevicePatch(dpiStages: values, activeStage: active))
    }

    func scheduleAutoApplyDpi() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        dpiApplyTask?.cancel()
        dpiApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 320_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyDpiStages()
        }
    }

    func applyActiveStageOnly() async {
        let count = max(1, min(5, appState.editableStageCount))
        let values = Array(appState.editableStageValues.prefix(count)).map { max(100, min(30000, $0)) }
        let active = max(0, min(count - 1, appState.editableActiveStage - 1))
        enqueueApply(DevicePatch(dpiStages: values, activeStage: active))
    }

    func scheduleAutoApplyActiveStage() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        activeStageApplyTask?.cancel()
        activeStageApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyActiveStageOnly()
        }
    }

    func applyPollRate() async {
        enqueueApply(DevicePatch(pollRate: appState.editablePollRate))
    }

    func scheduleAutoApplyPollRate() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        pollApplyTask?.cancel()
        pollApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyPollRate()
        }
    }

    func applySleepTimeout() async {
        enqueueApply(DevicePatch(sleepTimeout: appState.editableSleepTimeout))
    }

    func scheduleAutoApplySleepTimeout() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        powerApplyTask?.cancel()
        powerApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 260_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applySleepTimeout()
        }
    }

    func applyDeviceMode() async {
        let mode = appState.editableDeviceMode == 0x03 ? 0x03 : 0x00
        enqueueApply(DevicePatch(deviceMode: DeviceMode(mode: mode, param: 0x00)))
    }

    func scheduleAutoApplyDeviceMode() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        deviceModeApplyTask?.cancel()
        deviceModeApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyDeviceMode()
        }
    }

    func applyLowBatteryThreshold() async {
        let raw = max(0x0C, min(0x3F, appState.editableLowBatteryThresholdRaw))
        enqueueApply(DevicePatch(lowBatteryThresholdRaw: raw))
    }

    func scheduleAutoApplyLowBatteryThreshold() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        lowBatteryApplyTask?.cancel()
        lowBatteryApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 220_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyLowBatteryThreshold()
        }
    }

    func applyScrollMode() async {
        enqueueApply(DevicePatch(scrollMode: max(0, min(1, appState.editableScrollMode))))
    }

    func scheduleAutoApplyScrollMode() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        scrollModeApplyTask?.cancel()
        scrollModeApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 220_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyScrollMode()
        }
    }

    func applyScrollAcceleration() async {
        enqueueApply(DevicePatch(scrollAcceleration: appState.editableScrollAcceleration))
    }

    func scheduleAutoApplyScrollAcceleration() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        scrollAccelerationApplyTask?.cancel()
        scrollAccelerationApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 220_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyScrollAcceleration()
        }
    }

    func applyScrollSmartReel() async {
        enqueueApply(DevicePatch(scrollSmartReel: appState.editableScrollSmartReel))
    }

    func scheduleAutoApplyScrollSmartReel() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        scrollSmartReelApplyTask?.cancel()
        scrollSmartReelApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 220_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyScrollSmartReel()
        }
    }

    func applyLedBrightness() async {
        enqueueApply(DevicePatch(ledBrightness: appState.editableLedBrightness))
    }

    func scheduleAutoApplyLedBrightness() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        ledApplyTask?.cancel()
        ledApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyLedBrightness()
        }
    }

    func applyLedColor() async {
        enqueueApply(
            DevicePatch(
                ledRGB: RGBPatch(r: appState.editableColor.r, g: appState.editableColor.g, b: appState.editableColor.b),
                usbLightingZoneLEDIDs: appState.editorController.currentUSBLightingZoneLEDIDs()
            )
        )
    }

    func scheduleAutoApplyLedColor() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        colorApplyTask?.cancel()
        colorApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyLedColor()
        }
    }

    func applyLightingEffect() async {
        guard let selectedDevice = appState.selectedDevice else { return }
        if !selectedDevice.supports_advanced_lighting_effects {
            appState.editableLightingEffect = .staticColor
            enqueueApply(DevicePatch(ledRGB: RGBPatch(r: appState.editableColor.r, g: appState.editableColor.g, b: appState.editableColor.b)))
            return
        }
        enqueueApply(
            DevicePatch(
                lightingEffect: appState.editorController.currentLightingEffectPatch(),
                usbLightingZoneLEDIDs: appState.editorController.currentUSBLightingZoneLEDIDs()
            )
        )
    }

    func scheduleAutoApplyLightingEffect() {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        lightingEffectApplyTask?.cancel()
        lightingEffectApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyLightingEffect()
        }
    }

    func applyButtonBinding(slot: Int) async {
        let resolved = appState.editableButtonBindings[slot] ?? appState.editorController.defaultButtonBinding(for: slot)
        let binding = ButtonBindingPatch(
            slot: slot,
            kind: resolved.kind,
            hidKey: resolved.kind == .keyboardSimple ? resolved.hidKey : nil,
            turboEnabled: resolved.kind.supportsTurbo ? resolved.turboEnabled : false,
            turboRate: resolved.kind.supportsTurbo && resolved.turboEnabled ? resolved.turboRate : nil,
            clutchDPI: resolved.kind == .dpiClutch ? resolved.clutchDPI ?? ButtonBindingSupport.defaultDPIClutchDPI(for: appState.selectedDevice?.profile_id) : nil,
            persistentProfile: appState.editableUSBButtonProfile,
            writeDirectLayer: !appState.supportsMultipleOnboardProfiles || appState.editableUSBButtonProfile == appState.activeOnboardProfile
        )
        enqueueApply(DevicePatch(buttonBinding: binding))
    }

    func scheduleAutoApplyButton(slot: Int) {
        guard !appState.editorController.isHydrating else { return }
        markLocalEditsPending()
        buttonApplyTask?.cancel()
        buttonApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 260_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyButtonBinding(slot: slot)
        }
    }

    func markLocalEditsPending() {
        hasPendingLocalEdits = true
        lastLocalEditAt = Date()
        localEditDeviceIdentityKey = appState.selectedDevice.map(appState.deviceController.deviceIdentityKey)
    }

    func hasPendingLocalEditsAffecting(_ device: MouseDevice) -> Bool {
        guard hasPendingLocalEdits else { return false }
        guard let localEditDeviceIdentityKey else { return false }
        return localEditDeviceIdentityKey == appState.deviceController.deviceIdentityKey(device)
    }

    func enqueueApply(_ patch: DevicePatch) {
        _ = applyCoordinator.enqueue(patch)
        markLocalEditsPending()

        if applyDrainTask == nil {
            applyDrainTask = Task { [weak self] in
                await self?.drainApplyQueue()
            }
        }
    }

    private func drainApplyQueue() async {
        while let patch = applyCoordinator.dequeue() {
            await applyNow(patch: patch)
            hasPendingLocalEdits = applyCoordinator.hasPending
        }
        hasPendingLocalEdits = false
        localEditDeviceIdentityKey = nil
        applyDrainTask = nil
    }

    private func applyNow(patch: DevicePatch) async {
        guard let selectedDevice = appState.selectedDevice else {
            AppLog.warning("AppState", "apply skipped with no selected device patch=\(patch.describe)")
            appState.errorMessage = "No device selected"
            return
        }

        applyCoordinator.bumpRevision()
        AppLog.event("AppState", "apply start device=\(selectedDevice.id) patch=\(patch.describe)")
        appState.isApplying = true
        defer { appState.isApplying = false }

        let start = Date()
        let applyDeviceID = selectedDevice.id

        do {
            let next = try await appState.backend.apply(device: selectedDevice, patch: patch)
            guard let presentationDevice = appState.deviceController.presentationDevice(for: selectedDevice) else {
                let merged = next.merged(with: appState.deviceController.cachedState(for: applyDeviceID))
                appState.deviceController.storeState(merged, for: applyDeviceID, updatedAt: Date())
                AppLog.debug("AppState", "apply result cached for missing-presentation device=\(applyDeviceID)")
                return
            }

            let presentationDeviceID = presentationDevice.id
            let merged = next.merged(
                with: appState.deviceController.cachedState(for: presentationDeviceID) ?? appState.deviceController.cachedState(for: applyDeviceID)
            )
            appState.deviceController.cacheState(merged, sourceDeviceID: applyDeviceID, presentationDeviceID: presentationDeviceID)
            appState.deviceController.focusServiceSelectionOnActivity(deviceID: presentationDeviceID)

            if appState.selectedDeviceID == presentationDeviceID, appState.state != merged {
                appState.state = merged
            }

            let localEditsChangedDuringApply = (lastLocalEditAt ?? .distantPast) > start
            let shouldHydrateEditableState = !localEditsChangedDuringApply && !applyCoordinator.hasPending
            if patch.dpiStages != nil || patch.activeStage != nil {
                let suppressedUntil = Date().addingTimeInterval(0.9)
                appState.deviceController.setFastDpiSuppressed(until: suppressedUntil, for: applyDeviceID)
                appState.deviceController.setFastDpiSuppressed(until: suppressedUntil, for: presentationDeviceID)
                appState.runtimeController.setCompactInteraction(until: Date().addingTimeInterval(3.0))
            }

            if shouldHydrateEditableState, appState.selectedDeviceID == presentationDeviceID {
                lastLocalEditAt = nil
                appState.editorController.hydrateEditable(from: merged)
            } else if appState.selectedDeviceID == presentationDeviceID {
                AppLog.debug(
                    "AppState",
                    "apply hydrate skipped pending=\(applyCoordinator.hasPending) localEditsDuringApply=\(localEditsChangedDuringApply)"
                )
            }

            if patch.ledRGB != nil {
                appState.editorController.persistLightingColor(appState.editableColor, device: presentationDevice)
                appState.editorController.markLightingHydrated(deviceID: presentationDevice.id)
            }
            if let lightingEffect = patch.lightingEffect {
                appState.editorController.persistLightingEffect(lightingEffect, device: presentationDevice)
                appState.editorController.persistLightingColor(
                    RGBColor(r: lightingEffect.primary.r, g: lightingEffect.primary.g, b: lightingEffect.primary.b),
                    device: presentationDevice
                )
                appState.editorController.markLightingHydrated(deviceID: presentationDevice.id)
            }
            if let buttonBinding = patch.buttonBinding {
                appState.editorController.persistButtonBinding(buttonBinding, device: presentationDevice, profile: buttonBinding.persistentProfile)
                appState.editorController.markButtonBindingsHydrated(device: presentationDevice)
            }

            if appState.selectedDeviceID == presentationDeviceID {
                appState.errorMessage = nil
                appState.deviceController.setTelemetryWarning(
                    appState.editorController.telemetryWarning(for: merged, device: presentationDevice),
                    device: presentationDevice
                )
            }

            AppLog.event(
                "AppState",
                "apply ok device=\(presentationDevice.id) active=\(merged.dpi_stages.active_stage.map(String.init) ?? "nil") " +
                "values=\(merged.dpi_stages.values?.map(String.init).joined(separator: ",") ?? "nil") " +
                "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
            )
        } catch {
            AppLog.error("AppState", "apply failed device=\(selectedDevice.id): \(error.localizedDescription)")
            let shouldShowApplyFailure: Bool
            if let currentSelectedDevice = appState.selectedDevice {
                shouldShowApplyFailure = appState.deviceController.deviceIdentityKey(currentSelectedDevice) ==
                    appState.deviceController.deviceIdentityKey(selectedDevice)
            } else {
                shouldShowApplyFailure = false
            }
            if shouldShowApplyFailure {
                appState.errorMessage = error.localizedDescription
                appState.warningMessage = nil
                if patch.dpiStages != nil || patch.activeStage != nil {
                    appState.serviceStatusMessage = "DPI update failed"
                    appState.runtimeController.setTransientStatus(until: Date().addingTimeInterval(4.0))
                }
            } else {
                AppLog.debug("AppState", "apply failure masked for no-longer-selected device=\(selectedDevice.id)")
            }
        }
    }
}
