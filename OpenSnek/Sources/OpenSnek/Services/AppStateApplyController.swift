import Foundation
import OpenSnekAppSupport
import OpenSnekCore

@MainActor
final class AppStateApplyController {
    private static let fastDpiApplySuppressionDuration: TimeInterval = 0.9
    private static let compactInteractionDurationAfterDpiApply: TimeInterval = 3.0
    private static let dpiApplyFailureStatusDuration: TimeInterval = 4.0

    private let environment: AppEnvironment
    let deviceStore: DeviceStore
    let editorStore: EditorStore
    private let runtimeStore: RuntimeStore
    @WeakBound("AppStateApplyController", dependency: "deviceController")
    var deviceController: AppStateDeviceController
    @WeakBound("AppStateApplyController", dependency: "editorController")
    var editorController: AppStateEditorController
    @WeakBound("AppStateApplyController", dependency: "runtimeController")
    private var runtimeController: AppStateRuntimeController

    let applyCoordinator = ApplyCoordinator()
    enum ApplyTaskKey: Hashable {
        case dpi
        case pollRate
        case power
        case lowBattery
        case scrollMode
        case scrollAcceleration
        case scrollSmartReel
        case ledBrightness
        case ledColor
        case lightingEffect
        case button(Int)
        case activeStage
    }

    struct ApplyBehavior {
        let markApplyingState: Bool
        let shouldFocusOnActivity: Bool
        let shouldSurfaceApplyFailure: Bool
        let persistLightingZoneID: String
        let clearLocalEditsOnSuccess: Bool
        let backendApplyOptions: ApplyOptions

        let validLocalEditGeneration: UInt64?
        let validSettingsRestoreRevision: Int?

        init(
            markApplyingState: Bool,
            shouldFocusOnActivity: Bool,
            shouldSurfaceApplyFailure: Bool,
            persistLightingZoneID: String,
            clearLocalEditsOnSuccess: Bool,
            backendApplyOptions: ApplyOptions,
            validLocalEditGeneration: UInt64? = nil,
            validSettingsRestoreRevision: Int? = nil
        ) {
            self.markApplyingState = markApplyingState
            self.shouldFocusOnActivity = shouldFocusOnActivity
            self.shouldSurfaceApplyFailure = shouldSurfaceApplyFailure
            self.persistLightingZoneID = persistLightingZoneID
            self.clearLocalEditsOnSuccess = clearLocalEditsOnSuccess
            self.backendApplyOptions = backendApplyOptions
            self.validLocalEditGeneration = validLocalEditGeneration
            self.validSettingsRestoreRevision = validSettingsRestoreRevision
        }
    }

    private struct SuccessfulApplyContext {
        let next: MouseState
        let targetDevice: MouseDevice
        let applyDeviceID: String
        let patch: DevicePatch
        let start: Date
        let behavior: ApplyBehavior
    }

    private var applyTasks: [ApplyTaskKey: Task<Void, Never>] = [:]
    var hasPendingLocalEdits = false
    private var applyDrainTask: Task<Void, Never>?
    private var localEditGeneration: UInt64 = 0
    private var hardwareApplyInFlight = false
    private var hardwareApplyWaiters: [CheckedContinuation<Void, Never>] = []
    var lastLocalEditAt: Date?
    var localEditDeviceIdentityKey: String?
    var pendingActiveStageSelectionByDeviceIdentityKey: [String: Int] = [:]

    init(
        environment: AppEnvironment,
        deviceStore: DeviceStore,
        editorStore: EditorStore,
        runtimeStore: RuntimeStore
    ) {
        self.environment = environment
        self.deviceStore = deviceStore
        self.editorStore = editorStore
        self.runtimeStore = runtimeStore
    }

    func tearDown() {
        for task in applyTasks.values {
            task.cancel()
        }
        applyTasks.removeAll()
        applyDrainTask?.cancel()
    }

    func bind(
        deviceController: AppStateDeviceController,
        editorController: AppStateEditorController,
        runtimeController: AppStateRuntimeController
    ) {
        _deviceController.bind(deviceController)
        _editorController.bind(editorController)
        _runtimeController.bind(runtimeController)
    }

    var stateRevision: UInt64 {
        applyCoordinator.stateRevision
    }

    var shouldHydrateEditable: Bool {
        shouldHydrateEditable(for: deviceStore.selectedDevice)
    }

    func shouldHydrateEditable(for device: MouseDevice?) -> Bool {
        guard !deviceStore.isApplying, !editorStore.isEditingDpiControl else { return false }
        guard let device else { return !hasPendingLocalEdits }
        guard pendingActiveStageSelection(for: device) == nil else { return false }
        guard !hasPendingLocalEditsAffecting(device) else { return false }
        guard let lastLocalEditAt else { return true }
        guard let localEditDeviceIdentityKey else { return true }
        guard localEditDeviceIdentityKey == deviceController.deviceIdentityKey(device) else { return true }
        return Date().timeIntervalSince(lastLocalEditAt) > 0.8
    }

    func applyDpiStages() async {
        let count = DeviceProfiles.clampDpiStageCount(editorStore.editableStageCount)
        let selectedDevice = deviceStore.selectedDevice
        let profileID = selectedDevice?.profile_id
        let values = Array(editorStore.editableStageValues.prefix(count)).map { DeviceProfiles.clampDPI($0, profileID: profileID) }
        let pairs = Array(editorStore.editableStagePairs.prefix(count)).map { pair in
            DpiPair(
                x: DeviceProfiles.clampDPI(pair.x, profileID: profileID),
                y: DeviceProfiles.clampDPI(pair.y, profileID: profileID)
            )
        }
        let active = max(0, min(count - 1, editorStore.editableActiveStage - 1))
        if let selectedDevice, supportsOnboardProfileEditorWrites(device: selectedDevice) {
            let scalar = pairs.indices.contains(active) ? pairs[active] : pairs.first
            let mutation = OnboardProfileMutation(
                dpi: OnboardDPIProfileSnapshot(
                    scalar: scalar,
                    activeStage: active,
                    pairs: pairs
                )
            )
            _ = await applyOnboardProfileMutationForCurrentSelection(mutation)
            return
        }
        enqueueApply(DevicePatch(dpiStages: values, dpiStagePairs: pairs, activeStage: active))
    }

    func scheduleAutoApplyDpi() {
        scheduleAutoApply(key: .dpi, delay: 320_000_000) { [weak self] in
            guard let self else { return }
            await self.applyDpiStages()
        }
    }

    func applyActiveStageOnly() async {
        let count = DeviceProfiles.clampDpiStageCount(editorStore.editableStageCount)
        let selectedDevice = deviceStore.selectedDevice
        let active = max(0, min(count - 1, editorStore.editableActiveStage - 1))
        AppLog.debug(
            "AppState",
            "applyActiveStageOnly device=\(selectedDevice?.id ?? "nil") editable=\(editorStore.editableActiveStage) " +
            "active=\(active) count=\(count) pending=\(pendingActiveStageSelection(for: selectedDevice).map(String.init) ?? "nil")"
        )
        if let selectedDevice, supportsOnboardProfileEditorWrites(device: selectedDevice) {
            let profileID = selectedDevice.profile_id
            let pairs = Array(editorStore.editableStagePairs.prefix(count)).map { pair in
                DpiPair(
                    x: DeviceProfiles.clampDPI(pair.x, profileID: profileID),
                    y: DeviceProfiles.clampDPI(pair.y, profileID: profileID)
                )
            }
            let scalar = pairs.indices.contains(active) ? pairs[active] : pairs.first
            _ = await applyOnboardProfileMutationForCurrentSelection(
                OnboardProfileMutation(
                    dpi: OnboardDPIProfileSnapshot(
                        scalar: scalar,
                        activeStage: active,
                        pairs: pairs
                    )
                )
            )
            return
        }
        enqueueApply(DevicePatch(activeStage: active))
    }

    func scheduleAutoApplyActiveStage() {
        guard !editorController.isHydrating else { return }
        rememberPendingActiveStageSelection(editorStore.editableActiveStage, for: deviceStore.selectedDevice)
        AppLog.debug(
            "AppState",
            "scheduleActiveStageApply device=\(deviceStore.selectedDevice?.id ?? "nil") " +
            "editable=\(editorStore.editableActiveStage) pending=\(pendingActiveStageSelection(for: deviceStore.selectedDevice).map(String.init) ?? "nil")"
        )
        scheduleAutoApply(key: .activeStage, delay: 80_000_000) { [weak self] in
            guard let self else { return }
            await self.applyActiveStageOnly()
        }
    }

    func applyPollRate() async {
        enqueueApply(DevicePatch(pollRate: editorStore.editablePollRate))
    }

    func scheduleAutoApplyPollRate() {
        scheduleAutoApply(key: .pollRate, delay: 250_000_000) { [weak self] in
            guard let self else { return }
            await self.applyPollRate()
        }
    }

    func applySleepTimeout() async {
        enqueueApply(DevicePatch(sleepTimeout: editorStore.editableSleepTimeout))
    }

    func scheduleAutoApplySleepTimeout() {
        scheduleAutoApply(key: .power, delay: 260_000_000) { [weak self] in
            guard let self else { return }
            await self.applySleepTimeout()
        }
    }

    func applyLowBatteryThreshold() async {
        let raw = max(0x0C, min(0x3F, editorStore.editableLowBatteryThresholdRaw))
        enqueueApply(DevicePatch(lowBatteryThresholdRaw: raw))
    }

    func scheduleAutoApplyLowBatteryThreshold() {
        scheduleAutoApply(key: .lowBattery, delay: 220_000_000) { [weak self] in
            guard let self else { return }
            await self.applyLowBatteryThreshold()
        }
    }

    func applyScrollMode() async {
        guard let selectedDevice = selectedDeviceForScrollModeApply() else { return }
        if supportsOnboardProfileCRUD(device: selectedDevice) {
            _ = await applyOnboardProfileMutationForCurrentSelection(
                OnboardProfileMutation(scrollMode: max(0, min(1, editorStore.editableScrollMode)))
            )
            return
        }
        enqueueApply(DevicePatch(scrollMode: max(0, min(1, editorStore.editableScrollMode))))
    }

    func scheduleAutoApplyScrollMode() {
        scheduleAutoApply(key: .scrollMode, delay: 220_000_000) { [weak self] in
            guard let self else { return }
            await self.applyScrollMode()
        }
    }

    func applyScrollAcceleration() async {
        guard let selectedDevice = selectedDeviceForScrollModeApply() else { return }
        if supportsOnboardProfileCRUD(device: selectedDevice) {
            _ = await applyOnboardProfileMutationForCurrentSelection(
                OnboardProfileMutation(scrollAcceleration: editorStore.editableScrollAcceleration)
            )
            return
        }
        enqueueApply(DevicePatch(scrollAcceleration: editorStore.editableScrollAcceleration))
    }

    func scheduleAutoApplyScrollAcceleration() {
        scheduleAutoApply(key: .scrollAcceleration, delay: 220_000_000) { [weak self] in
            guard let self else { return }
            await self.applyScrollAcceleration()
        }
    }

    func applyScrollSmartReel() async {
        guard let selectedDevice = selectedDeviceForScrollModeApply() else { return }
        if supportsOnboardProfileCRUD(device: selectedDevice) {
            _ = await applyOnboardProfileMutationForCurrentSelection(
                OnboardProfileMutation(scrollSmartReel: editorStore.editableScrollSmartReel)
            )
            return
        }
        enqueueApply(DevicePatch(scrollSmartReel: editorStore.editableScrollSmartReel))
    }

    private func selectedDeviceForScrollModeApply() -> MouseDevice? {
        guard let selectedDevice = deviceStore.selectedDevice,
              selectedDevice.supportsScrollModeControls else {
            return nil
        }
        return selectedDevice
    }

    func scheduleAutoApplyScrollSmartReel() {
        scheduleAutoApply(key: .scrollSmartReel, delay: 220_000_000) { [weak self] in
            guard let self else { return }
            await self.applyScrollSmartReel()
        }
    }

    func applyLedBrightness() async {
        guard let selectedDevice = deviceStore.selectedDevice,
              selectedDevice.supportsLightingBrightnessControls else {
            return
        }
        if supportsOnboardProfileLightingEditorWrites(device: selectedDevice) {
            let brightness = Dictionary(
                uniqueKeysWithValues: onboardProfileLEDIDs(for: selectedDevice).map { ledID in
                    (Int(ledID), editorStore.editableLedBrightness)
                }
            )
            if await applyOnboardProfileMutationForCurrentSelection(
                OnboardProfileMutation(brightnessByLEDID: brightness)
            ) {
                return
            }
            return
        }
        enqueueApply(DevicePatch(ledBrightness: editorStore.editableLedBrightness))
    }

    func scheduleAutoApplyLedBrightness() {
        scheduleAutoApply(key: .ledBrightness, delay: 180_000_000) { [weak self] in
            guard let self else { return }
            await self.applyLedBrightness()
        }
    }

    func applyLedColor() async {
        if let selectedDevice = deviceStore.selectedDevice,
           supportsOnboardProfileLightingEditorWrites(device: selectedDevice),
           editorStore.editableLightingEffect == .staticColor || !selectedDevice.supports_advanced_lighting_effects {
            _ = await applyOnboardProfileMutationForCurrentSelection(
                OnboardProfileMutation(staticColorByLEDID: currentStaticOnboardProfileColors(for: selectedDevice))
            )
            return
        }
        enqueueApply(
            DevicePatch(
                ledRGB: currentStaticLightingRGBPatch(),
                usbLightingZoneLEDIDs: editorController.currentUSBLightingZoneLEDIDs()
            )
        )
    }

    func scheduleAutoApplyLedColor() {
        scheduleAutoApply(key: .ledColor, delay: 200_000_000) { [weak self] in
            guard let self else { return }
            await self.applyLedColor()
        }
    }

    func applyLightingEffect() async {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        if !selectedDevice.supports_advanced_lighting_effects {
            editorStore.editableLightingEffect = .staticColor
            if supportsOnboardProfileLightingEditorWrites(device: selectedDevice) {
                _ = await applyCurrentStaticOnboardProfileColorsIfSupported(for: selectedDevice)
                return
            }
            enqueueApply(DevicePatch(ledRGB: currentStaticLightingRGBPatch()))
            return
        }
        if editorStore.editableLightingEffect == .staticColor {
            if supportsOnboardProfileLightingEditorWrites(device: selectedDevice) {
                _ = await applyCurrentStaticOnboardProfileColorsIfSupported(for: selectedDevice)
                return
            }
            enqueueApply(
                DevicePatch(
                    ledRGB: currentStaticLightingRGBPatch(),
                    usbLightingZoneLEDIDs: editorController.currentUSBLightingZoneLEDIDs()
                )
            )
            return
        }
        enqueueApply(
            DevicePatch(
                lightingEffect: editorController.currentLightingEffectPatch(),
                usbLightingZoneLEDIDs: editorController.currentUSBLightingZoneLEDIDs()
            )
        )
    }

    private func currentStaticLightingRGBPatch() -> RGBPatch {
        RGBPatch(
            r: editorStore.editableColor.r,
            g: editorStore.editableColor.g,
            b: editorStore.editableColor.b
        )
    }

    func scheduleAutoApplyLightingEffect() {
        scheduleAutoApply(key: .lightingEffect, delay: 200_000_000) { [weak self] in
            guard let self else { return }
            await self.applyLightingEffect()
        }
    }

    func scheduleAutoApplyCurrentStaticColorToAllZones() {
        scheduleAutoApply(key: .lightingEffect, delay: 200_000_000) { [weak self] in
            guard let self else { return }
            await self.applyCurrentStaticColorToAllZones()
        }
    }

    func applyCurrentStaticColorToAllZones() async {
        guard editorStore.editableLightingEffect == .staticColor else { return }
        guard deviceStore.selectedDevice != nil else {
            deviceStore.errorMessage = "No device selected"
            return
        }

        cancelScheduledApply(for: .ledColor)
        cancelScheduledApply(for: .lightingEffect)

        if let selectedDevice = deviceStore.selectedDevice,
           await applyCurrentStaticOnboardProfileColorsIfSupported(for: selectedDevice, allZones: true) {
            return
        }

        if deviceStore.selectedDevice?.supports_advanced_lighting_effects == true {
            enqueueApply(DevicePatch(lightingEffect: editorController.currentLightingEffectPatch()))
        } else {
            enqueueApply(
                DevicePatch(
                    ledRGB: RGBPatch(
                        r: editorStore.editableColor.r,
                        g: editorStore.editableColor.g,
                        b: editorStore.editableColor.b
                    )
                )
            )
        }
    }

    func scheduleAutoApply(
        key: ApplyTaskKey,
        delay: UInt64 = 220_000_000,
        action: @escaping @MainActor () async -> Void
    ) {
        guard !editorController.isHydrating else { return }
        markLocalEditsPending()
        let generation = localEditGeneration
        applyTasks[key]?.cancel()
        applyTasks[key] = Task {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await runScheduledApplyIfCurrent(generation: generation, action)
        }
    }

    private func runScheduledApplyIfCurrent(
        generation: UInt64,
        _ action: @escaping @MainActor () async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        guard generation == localEditGeneration else { return }
        await action()
    }

    private func cancelScheduledApply(for key: ApplyTaskKey) {
        applyTasks[key]?.cancel()
        applyTasks.removeValue(forKey: key)
    }

    func markLocalEditsPending() {
        hasPendingLocalEdits = true
        lastLocalEditAt = Date()
        localEditDeviceIdentityKey = deviceStore.selectedDevice.map(deviceController.deviceIdentityKey)
    }

    func hasPendingLocalEditsAffecting(_ device: MouseDevice) -> Bool {
        guard hasPendingLocalEdits else { return false }
        guard let localEditDeviceIdentityKey else { return false }
        return localEditDeviceIdentityKey == deviceController.deviceIdentityKey(device)
    }

    func pendingActiveStageSelection(for device: MouseDevice?) -> Int? {
        guard let device else { return nil }
        return pendingActiveStageSelectionByDeviceIdentityKey[deviceController.deviceIdentityKey(device)]
    }

    func clearPendingActiveStageSelectionIfConfirmed(by state: MouseState, for device: MouseDevice?) {
        guard let pendingStage = pendingActiveStageSelection(for: device) else { return }
        guard stateConfirmsPendingActiveStage(pendingStage, state: state) else { return }
        clearPendingActiveStageSelection(matching: pendingStage, for: device)
    }

    private func stateConfirmsPendingActiveStage(_ stage: Int, state: MouseState) -> Bool {
        if state.dpi_stages.active_stage == stage - 1 {
            return true
        }

        guard let liveDPI = state.dpi else { return false }
        let count = DeviceProfiles.clampDpiStageCount(editorStore.editableStageCount)
        guard stage >= 1, stage <= count else { return false }
        let visiblePairs = Array(editorStore.editableStagePairs.prefix(count))
        let matchingStages = visiblePairs.enumerated().compactMap { index, pair in
            pair == liveDPI ? index + 1 : nil
        }
        return matchingStages == [stage]
    }

    func cancelPendingLocalEditsForSelectionChange() {
        _ = cancelPendingLocalEditsForSelectionChangeReturningDrainTask()
    }

    func cancelAndDrainPendingLocalEditsForSelectionChange() async {
        let drainTask = cancelPendingLocalEditsForSelectionChangeReturningDrainTask()
        await drainTask?.value
    }

    private func cancelPendingLocalEditsForSelectionChangeReturningDrainTask() -> Task<Void, Never>? {
        localEditGeneration &+= 1
        for task in applyTasks.values {
            task.cancel()
        }
        applyTasks.removeAll()
        applyCoordinator.clearPending()
        hasPendingLocalEdits = false
        lastLocalEditAt = nil
        localEditDeviceIdentityKey = nil
        pendingActiveStageSelectionByDeviceIdentityKey.removeAll()
        return applyDrainTask
    }

    func cancelPendingPersistedSettingsRestore(for device: MouseDevice) {
        deviceController.cancelPendingSettingsRestore(for: device)
    }

    func enqueueApply(_ patch: DevicePatch) {
        _ = applyCoordinator.enqueue(patch, generation: localEditGeneration)
        markLocalEditsPending()

        if applyDrainTask == nil {
            applyDrainTask = Task { [weak self] in
                await self?.drainApplyQueue()
            }
        }
    }

    @discardableResult
    func applyPersistedSettingsRestore(
        _ plan: AppStateEditorController.PersistedSettingsRestorePlan,
        to device: MouseDevice
    ) async -> Bool {
        if editorController.singleSlotProfileApplySyncSuppressedDeviceIDs.contains(device.id) {
            AppLog.debug("AppState", "restore skipped during single-slot profile replacement device=\(device.id)")
            return true
        }
        let restoreRevision = deviceController.settingsRestoreRevision(for: device)
        let selectedIdentity = deviceStore.selectedDevice.map(deviceController.deviceIdentityKey)
        let targetIdentity = deviceController.deviceIdentityKey(device)
        let targetsSelectedDevice = selectedIdentity == targetIdentity
        let restoresStaticLighting = plan.patch.ledRGB != nil || plan.snapshot.lightingEffect?.kind == .staticColor
        let persistLightingZoneID = restoresStaticLighting
            ? plan.snapshot.usbLightingZoneID
            : "all"

        if !plan.patch.isEmpty {
            let restoredState = await apply(
                device: device,
                patch: plan.patch,
                behavior: ApplyBehavior(
                    markApplyingState: targetsSelectedDevice,
                    shouldFocusOnActivity: false,
                    shouldSurfaceApplyFailure: targetsSelectedDevice,
                    persistLightingZoneID: persistLightingZoneID,
                    clearLocalEditsOnSuccess: false,
                    backendApplyOptions: ApplyOptions(),
                    validSettingsRestoreRevision: restoreRevision
                )
            )
            guard restoredState else { return false }
        }

        let persistentProfile = persistentProfileForRestoredLiveButtons(device: device)
        let writableSlots = (device.button_layout?.writableSlots ?? ButtonSlotDescriptor.defaults.map(\.slot)).sorted()
        let restoreButtonApplyOptions = ApplyOptions(readbackPolicy: .skipStateReadback)
        for slot in writableSlots {
            let draft = plan.buttonBindings[slot] ?? editorController.defaultButtonBinding(for: slot, device: device)
            let restoredButton = await apply(
                device: device,
                patch: DevicePatch(
                    buttonBinding: makeButtonBindingPatch(
                        slot: slot,
                        draft: draft,
                        profileID: device.profile_id,
                        persistentProfile: persistentProfile,
                        writePersistentLayer: true,
                        writeDirectLayer: true
                    )
                ),
                behavior: ApplyBehavior(
                    markApplyingState: targetsSelectedDevice,
                    shouldFocusOnActivity: false,
                    shouldSurfaceApplyFailure: targetsSelectedDevice,
                    persistLightingZoneID: persistLightingZoneID,
                    clearLocalEditsOnSuccess: false,
                    backendApplyOptions: restoreButtonApplyOptions,
                    validSettingsRestoreRevision: restoreRevision
                )
            )
            guard restoredButton else { return false }
        }

        await verifyRestoreStateAfterDeferredButtonWrites(
            device: device,
            targetsSelectedDevice: targetsSelectedDevice
        )

        if targetsSelectedDevice {
            editorController.setLiveUSBButtonProfileOverride(1, for: device)
            editorController.markButtonWorkspaceAppliedToLive(bindings: plan.buttonBindings, exactSource: nil)
        } else {
            editorController.persistSettingsSnapshot(plan.snapshot, device: device)
        }
        return true
    }

    private func drainApplyQueue() async {
        while let entry = applyCoordinator.dequeueEntry() {
            guard entry.generation == localEditGeneration else {
                hasPendingLocalEdits = applyCoordinator.hasPending
                continue
            }
            await applySelectedPatch(entry.patch, generation: entry.generation)
            hasPendingLocalEdits = applyCoordinator.hasPending
        }
        hasPendingLocalEdits = false
        localEditDeviceIdentityKey = nil
        applyDrainTask = nil
    }

    private func applySelectedPatch(_ patch: DevicePatch, generation: UInt64) async {
        guard generation == localEditGeneration else { return }
        guard let selectedDevice = deviceStore.selectedDevice else {
            AppLog.warning("AppState", "apply skipped with no selected device patch=\(patch.describe)")
            deviceStore.errorMessage = "No device selected"
            return
        }
        _ = await apply(
            device: selectedDevice,
            patch: patch,
            behavior: ApplyBehavior(
                markApplyingState: true,
                shouldFocusOnActivity: true,
                shouldSurfaceApplyFailure: true,
                persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                clearLocalEditsOnSuccess: true,
                backendApplyOptions: ApplyOptions(),
                validLocalEditGeneration: generation
            )
        )
    }

    @discardableResult
    func apply(
        device targetDevice: MouseDevice,
        patch: DevicePatch,
        behavior: ApplyBehavior
    ) async -> Bool {
        applyCoordinator.bumpRevision()
        AppLog.event("AppState", "apply start device=\(targetDevice.id) patch=\(patch.describe)")
        if behavior.markApplyingState {
            deviceStore.isApplying = true
        }
        defer {
            if behavior.markApplyingState {
                deviceStore.isApplying = false
            }
        }

        let start = Date()
        let applyDeviceID = targetDevice.id

        await stopSoftwareLightingIfNormalLightingPatch(patch, device: targetDevice)
        guard applyIsStillCurrent(behavior: behavior, targetDevice: targetDevice, patch: patch) else { return false }

        do {
            await enterHardwareApplyGate()
            defer { leaveHardwareApplyGate() }
            guard applyIsStillCurrent(behavior: behavior, targetDevice: targetDevice, patch: patch) else { return false }
            let next = try await applyBackendState(
                device: targetDevice,
                patch: patch,
                options: behavior.backendApplyOptions
            )
            return handleSuccessfulApply(
                SuccessfulApplyContext(
                    next: next,
                    targetDevice: targetDevice,
                    applyDeviceID: applyDeviceID,
                    patch: patch,
                    start: start,
                    behavior: behavior
                )
            )
        } catch {
            handleApplyFailure(
                error,
                targetDevice: targetDevice,
                patch: patch,
                start: start,
                shouldSurfaceApplyFailure: behavior.shouldSurfaceApplyFailure
            )
            return false
        }
    }

    private func applyIsStillCurrent(
        behavior: ApplyBehavior,
        targetDevice: MouseDevice,
        patch: DevicePatch
    ) -> Bool {
        if shouldSuppressApplyDuringSingleSlotReplacement(behavior: behavior, targetDevice: targetDevice) {
            AppLog.debug(
                "AppState",
                "apply skipped during single-slot profile replacement device=\(targetDevice.id) patch=\(patch.describe)"
            )
            return false
        }
        if let generation = behavior.validLocalEditGeneration, generation != localEditGeneration {
            AppLog.debug("AppState", "local edit apply skipped after invalidation device=\(targetDevice.id) patch=\(patch.describe)")
            return false
        }
        if let revision = behavior.validSettingsRestoreRevision,
           revision != deviceController.settingsRestoreRevision(for: targetDevice) {
            AppLog.debug(
                "AppState",
                "settings restore apply skipped after invalidation device=\(targetDevice.id) patch=\(patch.describe)"
            )
            return false
        }
        return true
    }

    private func shouldSuppressApplyDuringSingleSlotReplacement(
        behavior: ApplyBehavior,
        targetDevice: MouseDevice
    ) -> Bool {
        guard behavior.validLocalEditGeneration != nil || behavior.validSettingsRestoreRevision != nil else {
            return false
        }
        return editorController.singleSlotProfileApplySyncSuppressedDeviceIDs.contains(targetDevice.id)
    }

    private func enterHardwareApplyGate() async {
        if !hardwareApplyInFlight {
            hardwareApplyInFlight = true
            return
        }
        await withCheckedContinuation { continuation in
            hardwareApplyWaiters.append(continuation)
        }
    }

    private func leaveHardwareApplyGate() {
        guard !hardwareApplyWaiters.isEmpty else {
            hardwareApplyInFlight = false
            return
        }
        hardwareApplyWaiters.removeFirst().resume()
    }

    private func applyBackendState(
        device targetDevice: MouseDevice,
        patch: DevicePatch,
        options: ApplyOptions
    ) async throws -> MouseState {
        if let configurableBackend = environment.backend as? any ApplyOptionsSupportingBackend {
            return try await configurableBackend.apply(
                device: targetDevice,
                patch: patch,
                options: options
            )
        }
        return try await environment.backend.apply(device: targetDevice, patch: patch)
    }

    private func handleSuccessfulApply(_ context: SuccessfulApplyContext) -> Bool {
        let next = context.next
        let targetDevice = context.targetDevice
        let applyDeviceID = context.applyDeviceID
        let patch = context.patch
        let start = context.start
        let behavior = context.behavior
        guard let presentationDevice = deviceController.presentationDevice(for: targetDevice) else {
            let merged = next.merged(with: deviceController.cachedState(for: applyDeviceID))
            deviceController.storeState(merged, for: applyDeviceID, updatedAt: Date())
            AppLog.debug("AppState", "apply result cached for missing-presentation device=\(applyDeviceID)")
            return true
        }

        let presentationDeviceID = presentationDevice.id
        let merged = next.merged(
            with: deviceController.cachedState(for: presentationDeviceID) ?? deviceController.cachedState(for: applyDeviceID)
        )
        deviceController.cacheState(merged, sourceDeviceID: applyDeviceID, presentationDeviceID: presentationDeviceID)
        if behavior.shouldFocusOnActivity {
            deviceController.focusServiceSelectionOnActivity(deviceID: presentationDeviceID)
        }

        if deviceStore.selectedDeviceID == presentationDeviceID, deviceStore.state != merged {
            deviceStore.state = merged
        }

        let localEditsChangedDuringApply = behavior.clearLocalEditsOnSuccess && (lastLocalEditAt ?? .distantPast) > start
        let shouldHydrateEditableState = behavior.clearLocalEditsOnSuccess && !localEditsChangedDuringApply && !applyCoordinator.hasPending
        suppressFastDpiAfterSuccessfulApplyIfNeeded(
            patch: patch,
            applyDeviceID: applyDeviceID,
            presentationDeviceID: presentationDeviceID
        )
        if let activeStage = patch.activeStage {
            clearPendingActiveStageSelection(matching: activeStage + 1, for: presentationDevice)
        }

        hydrateAfterSuccessfulApplyIfNeeded(
            merged,
            presentationDeviceID: presentationDeviceID,
            shouldHydrateEditableState: shouldHydrateEditableState,
            localEditsChangedDuringApply: localEditsChangedDuringApply
        )
        persistSuccessfulApply(
            patch: patch,
            presentationDevice: presentationDevice,
            presentationDeviceID: presentationDeviceID,
            merged: merged,
            persistLightingZoneID: behavior.persistLightingZoneID
        )

        AppLog.event(
            "AppState",
            "apply ok device=\(presentationDevice.id) active=\(merged.dpi_stages.active_stage.map(String.init) ?? "nil") " +
            "values=\(merged.dpi_stages.values?.map(String.init).joined(separator: ",") ?? "nil") " +
            "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
        )
        return true
    }

    private func suppressFastDpiAfterSuccessfulApplyIfNeeded(
        patch: DevicePatch,
        applyDeviceID: String,
        presentationDeviceID: String
    ) {
        guard patch.affectsDpiStages else { return }
        let suppressedUntil = Date().addingTimeInterval(Self.fastDpiApplySuppressionDuration)
        deviceController.setFastDpiSuppressed(until: suppressedUntil, for: applyDeviceID)
        deviceController.setFastDpiSuppressed(until: suppressedUntil, for: presentationDeviceID)
        runtimeController.setCompactInteraction(until: Date().addingTimeInterval(Self.compactInteractionDurationAfterDpiApply))
    }

    private func hydrateAfterSuccessfulApplyIfNeeded(
        _ merged: MouseState,
        presentationDeviceID: String,
        shouldHydrateEditableState: Bool,
        localEditsChangedDuringApply: Bool
    ) {
        guard deviceStore.selectedDeviceID == presentationDeviceID else { return }
        if shouldHydrateEditableState {
            lastLocalEditAt = nil
            editorController.hydrateEditable(from: merged)
        } else {
            editorController.hydrateLiveDpiPresentation(from: merged)
            AppLog.debug(
                "AppState",
                "apply hydrate skipped pending=\(applyCoordinator.hasPending) localEditsDuringApply=\(localEditsChangedDuringApply)"
            )
        }
    }

    private func persistSuccessfulApply(
        patch: DevicePatch,
        presentationDevice: MouseDevice,
        presentationDeviceID: String,
        merged: MouseState,
        persistLightingZoneID: String
    ) {
        persistSuccessfulLightingPatch(
            patch,
            device: presentationDevice,
            usbLightingZoneID: persistLightingZoneID
        )
        if let buttonBinding = patch.buttonBinding {
            editorController.persistButtonBinding(buttonBinding, device: presentationDevice, profile: buttonBinding.persistentProfile)
            editorController.cachePersistedButtonBinding(buttonBinding, device: presentationDevice, profile: buttonBinding.persistentProfile)
        }
        let preserveStoredLighting = patch.ledRGB == nil && patch.lightingEffect == nil
        let snapshotLightingZoneOverride = snapshotLightingZoneOverride(
            for: patch,
            device: presentationDevice,
            defaultZoneID: persistLightingZoneID
        )
        let suppressSingleSlotProfileSync = editorController.singleSlotProfileApplySyncSuppressedDeviceIDs
            .contains(presentationDeviceID)
        if deviceStore.selectedDeviceID == presentationDeviceID {
            if !suppressSingleSlotProfileSync {
                editorController.persistCurrentSettingsSnapshot(
                    for: presentationDevice,
                    preservingStoredLighting: preserveStoredLighting,
                    lightingZoneOverride: snapshotLightingZoneOverride
                )
            }
            if editorController.supportsOnboardProfileCRUD(device: presentationDevice) {
                editorController.syncSelectedMappedLocalProfileFromEditor(device: presentationDevice)
            } else if !suppressSingleSlotProfileSync {
                editorController.syncSelectedSingleSlotLocalProfileFromEditor(device: presentationDevice)
            }
        }
        if !suppressSingleSlotProfileSync {
            editorController.persistSuccessfulPatchFieldsInSettingsSnapshot(
                patch: patch,
                device: presentationDevice,
                lightingZoneID: snapshotLightingZoneOverride ?? persistLightingZoneID
            )
        }

        if deviceStore.selectedDeviceID == presentationDeviceID {
            deviceStore.errorMessage = nil
            deviceController.setTelemetryWarning(
                editorController.telemetryWarning(for: merged, device: presentationDevice),
                device: presentationDevice
            )
        }
    }

    private func handleApplyFailure(
        _ error: Error,
        targetDevice: MouseDevice,
        patch: DevicePatch,
        start: Date,
        shouldSurfaceApplyFailure: Bool
    ) {
        AppLog.error(
            "AppState",
            "command apply failed device=\(targetDevice.id) patch=\(patch.describe) " +
            "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s: \(error.localizedDescription)"
        )
        guard shouldSurfaceApplyFailure else {
            AppLog.debug("AppState", "apply failure masked for non-selected restore device=\(targetDevice.id)")
            return
        }
        guard shouldShowApplyFailure(for: targetDevice) else {
            AppLog.debug("AppState", "apply failure masked for no-longer-selected device=\(targetDevice.id)")
            return
        }

        deviceStore.errorMessage = Self.commandFailureMessage(error)
        deviceStore.warningMessage = nil
        handleDpiApplyFailureIfNeeded(patch: patch, targetDevice: targetDevice)
    }

    private func shouldShowApplyFailure(for targetDevice: MouseDevice) -> Bool {
        guard let currentSelectedDevice = deviceStore.selectedDevice else { return false }
        return deviceController.deviceIdentityKey(currentSelectedDevice) == deviceController.deviceIdentityKey(targetDevice)
    }

    private func handleDpiApplyFailureIfNeeded(patch: DevicePatch, targetDevice: MouseDevice) {
        guard patch.affectsDpiStages else { return }
        if let activeStage = patch.activeStage {
            clearPendingActiveStageSelection(matching: activeStage + 1, for: targetDevice)
        }
        runtimeStore.serviceStatusMessage = "DPI update failed"
        runtimeController.setTransientStatus(until: Date().addingTimeInterval(Self.dpiApplyFailureStatusDuration))
    }

    private func stopSoftwareLightingIfNormalLightingPatch(_ patch: DevicePatch, device: MouseDevice) async {
        guard patch.ledRGB != nil || patch.lightingEffect != nil else { return }
        guard device.supportsSoftwareLightingEffects else { return }

        let status = await environment.backend.stopSoftwareLighting(device: device)
        if let status {
            deviceStore.softwareLightingStatusByDeviceID[device.id] = status
        } else {
            deviceStore.softwareLightingStatusByDeviceID.removeValue(forKey: device.id)
        }
    }

    private static func commandFailureMessage(_ error: any Error) -> String {
        if AppLog.currentLevel == .debug {
            return "Command failed: \(error.localizedDescription)"
        }
        return error.localizedDescription
    }

    private func verifyRestoreStateAfterDeferredButtonWrites(
        device targetDevice: MouseDevice,
        targetsSelectedDevice: Bool
    ) async {
        do {
            let next = try await environment.backend.readState(device: targetDevice)
            guard let presentationDevice = deviceController.presentationDevice(for: targetDevice) else {
                let merged = next.merged(with: deviceController.cachedState(for: targetDevice.id))
                deviceController.storeState(merged, for: targetDevice.id, updatedAt: Date())
                return
            }

            let presentationDeviceID = presentationDevice.id
            let merged = next.merged(
                with: deviceController.cachedState(for: presentationDeviceID) ?? deviceController.cachedState(for: targetDevice.id)
            )
            deviceController.cacheState(merged, sourceDeviceID: targetDevice.id, presentationDeviceID: presentationDeviceID)

            if deviceStore.selectedDeviceID == presentationDeviceID, deviceStore.state != merged {
                deviceStore.state = merged
            }

            if deviceStore.selectedDeviceID == presentationDeviceID {
                if shouldHydrateEditable(for: presentationDevice) {
                    editorController.hydrateEditable(from: merged)
                } else {
                    editorController.hydrateLiveDpiPresentation(from: merged)
                }
            }

            if targetsSelectedDevice {
                deviceStore.errorMessage = nil
                deviceController.setTelemetryWarning(
                    editorController.telemetryWarning(for: merged, device: presentationDevice),
                    device: presentationDevice
                )
            }

            AppLog.debug("AppState", "restore final state verify ok device=\(presentationDeviceID)")
        } catch {
            AppLog.debug(
                "AppState",
                "restore final state verify skipped device=\(targetDevice.id): \(error.localizedDescription)"
            )
        }
    }

    private func persistSuccessfulLightingPatch(
        _ patch: DevicePatch,
        device: MouseDevice,
        usbLightingZoneID: String
    ) {
        if let rgb = patch.ledRGB {
            let color = RGBColor(r: rgb.r, g: rgb.g, b: rgb.b)
            if patch.usbLightingZoneLEDIDs == nil && editorStore.visibleUSBLightingZones.count > 1 {
                persistLightingColorForAllZones(color, device: device)
            } else {
                let colorZoneID = usbLightingZoneID == "all" ? nil : usbLightingZoneID
                editorController.persistLightingColor(color, device: device, zoneID: colorZoneID)
            }
            editorController.persistLightingZoneID(usbLightingZoneID, device: device)
            editorStore.noteLightingGradientColorsChanged()
        }
        if let lightingEffect = patch.lightingEffect {
            editorController.persistLightingEffect(lightingEffect, device: device)
            let color = RGBColor(r: lightingEffect.primary.r, g: lightingEffect.primary.g, b: lightingEffect.primary.b)
            if lightingEffect.kind == .staticColor,
               patch.usbLightingZoneLEDIDs == nil,
               editorStore.visibleUSBLightingZones.count > 1 {
                persistLightingColorForAllZones(color, device: device)
            } else {
                let colorZoneID = lightingEffect.kind == .staticColor && usbLightingZoneID != "all"
                    ? usbLightingZoneID
                    : nil
                editorController.persistLightingColor(color, device: device, zoneID: colorZoneID)
            }
            editorController.persistLightingZoneID(
                lightingEffect.kind == .staticColor ? usbLightingZoneID : "all",
                device: device
            )
            if lightingEffect.kind == .staticColor {
                editorStore.noteLightingGradientColorsChanged()
            }
        }
    }

    private func persistLightingColorForAllZones(_ color: RGBColor, device: MouseDevice) {
        editorController.persistLightingColor(color, device: device)
        for zone in editorStore.visibleUSBLightingZones {
            editorController.persistLightingColor(color, device: device, zoneID: zone.id)
        }
    }

    private func snapshotLightingZoneOverride(
        for patch: DevicePatch,
        device: MouseDevice,
        defaultZoneID: String
    ) -> String? {
        guard device.showsLightingControls else { return nil }
        guard patch.ledRGB != nil || patch.lightingEffect != nil else { return nil }

        let writesStaticColor = patch.ledRGB != nil || patch.lightingEffect?.kind == .staticColor
        guard writesStaticColor else { return "all" }

        if patch.usbLightingZoneLEDIDs == nil, editorStore.visibleUSBLightingZones.count > 1 {
            return "all"
        }
        return defaultZoneID
    }
}
