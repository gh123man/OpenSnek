import Foundation
import OpenSnekAppSupport
import OpenSnekCore

@MainActor
final class AppStateApplyController {
    private static let fastDpiApplySuppressionDuration: TimeInterval = 0.9
    private static let compactInteractionDurationAfterDpiApply: TimeInterval = 3.0
    private static let dpiApplyFailureStatusDuration: TimeInterval = 4.0

    private let environment: AppEnvironment
    private let deviceStore: DeviceStore
    private let editorStore: EditorStore
    private let runtimeStore: RuntimeStore
    @WeakBound("AppStateApplyController", dependency: "deviceController")
    private var deviceController: AppStateDeviceController
    @WeakBound("AppStateApplyController", dependency: "editorController")
    private var editorController: AppStateEditorController
    @WeakBound("AppStateApplyController", dependency: "runtimeController")
    private var runtimeController: AppStateRuntimeController

    private let applyCoordinator = ApplyCoordinator()
    private enum ApplyTaskKey: Hashable {
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

    private struct ApplyBehavior {
        let markApplyingState: Bool
        let shouldFocusOnActivity: Bool
        let shouldSurfaceApplyFailure: Bool
        let persistLightingZoneID: String
        let clearLocalEditsOnSuccess: Bool
        let backendApplyOptions: ApplyOptions
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
    private(set) var hasPendingLocalEdits = false
    private var applyDrainTask: Task<Void, Never>?
    private var lastLocalEditAt: Date?
    private var localEditDeviceIdentityKey: String?
    private var pendingActiveStageSelectionByDeviceIdentityKey: [String: Int] = [:]

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
        if let selectedDevice = deviceStore.selectedDevice,
           supportsOnboardProfileCRUD(device: selectedDevice),
           selectedDevice.transport == .usb {
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
        if let selectedDevice = deviceStore.selectedDevice,
           supportsOnboardProfileCRUD(device: selectedDevice),
           selectedDevice.transport == .usb {
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
        if let selectedDevice = deviceStore.selectedDevice,
           supportsOnboardProfileCRUD(device: selectedDevice),
           selectedDevice.transport == .usb {
            _ = await applyOnboardProfileMutationForCurrentSelection(
                OnboardProfileMutation(scrollSmartReel: editorStore.editableScrollSmartReel)
            )
            return
        }
        enqueueApply(DevicePatch(scrollSmartReel: editorStore.editableScrollSmartReel))
    }

    func scheduleAutoApplyScrollSmartReel() {
        scheduleAutoApply(key: .scrollSmartReel, delay: 220_000_000) { [weak self] in
            guard let self else { return }
            await self.applyScrollSmartReel()
        }
    }

    func applyLedBrightness() async {
        if let selectedDevice = deviceStore.selectedDevice,
           supportsOnboardProfileLightingEditorWrites(device: selectedDevice) {
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
                ledRGB: RGBPatch(r: editorStore.editableColor.r, g: editorStore.editableColor.g, b: editorStore.editableColor.b),
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
            enqueueApply(DevicePatch(ledRGB: RGBPatch(r: editorStore.editableColor.r, g: editorStore.editableColor.g, b: editorStore.editableColor.b)))
            return
        }
        if editorStore.editableLightingEffect == .staticColor,
           supportsOnboardProfileLightingEditorWrites(device: selectedDevice) {
            _ = await applyCurrentStaticOnboardProfileColorsIfSupported(for: selectedDevice)
            return
        }
        enqueueApply(
            DevicePatch(
                lightingEffect: editorController.currentLightingEffectPatch(),
                usbLightingZoneLEDIDs: editorController.currentUSBLightingZoneLEDIDs()
            )
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

    private func makeButtonBindingPatch(
        slot: Int,
        persistentProfile: Int,
        writePersistentLayer: Bool = true,
        writeDirectLayer: Bool
    ) -> ButtonBindingPatch {
        let resolved = editorStore.editableButtonBindings[slot] ?? editorController.defaultButtonBinding(for: slot)
        let applied: ButtonBindingDraft
        if resolved.kind == .default {
            applied = ButtonBindingSupport.semanticDefaultButtonBinding(
                for: slot,
                profileID: deviceStore.selectedDevice?.profile_id
            ) ?? resolved
        } else {
            applied = resolved
        }
        return ButtonBindingPatch(
            slot: slot,
            kind: applied.kind,
            hidKey: applied.kind == .keyboardSimple ? applied.hidKey : nil,
            hidModifiers: applied.kind == .keyboardSimple ? applied.hidModifiers : nil,
            turboEnabled: applied.kind.supportsTurbo ? applied.turboEnabled : false,
            turboRate: applied.kind.supportsTurbo && applied.turboEnabled ? applied.turboRate : nil,
            clutchDPI: applied.kind == .dpiClutch ? applied.clutchDPI ?? ButtonBindingSupport.defaultDPIClutchDPI(for: deviceStore.selectedDevice?.profile_id) : nil,
            persistentProfile: persistentProfile,
            writePersistentLayer: writePersistentLayer,
            writeDirectLayer: writeDirectLayer
        )
    }

    private func makeButtonBindingPatch(
        slot: Int,
        draft: ButtonBindingDraft,
        profileID: DeviceProfileID?,
        persistentProfile: Int,
        writePersistentLayer: Bool = true,
        writeDirectLayer: Bool
    ) -> ButtonBindingPatch {
        let applied: ButtonBindingDraft
        if draft.kind == .default {
            applied = ButtonBindingSupport.semanticDefaultButtonBinding(
                for: slot,
                profileID: profileID
            ) ?? draft
        } else {
            applied = draft
        }
        return ButtonBindingPatch(
            slot: slot,
            kind: applied.kind,
            hidKey: applied.kind == .keyboardSimple ? applied.hidKey : nil,
            hidModifiers: applied.kind == .keyboardSimple ? applied.hidModifiers : nil,
            turboEnabled: applied.kind.supportsTurbo ? applied.turboEnabled : false,
            turboRate: applied.kind.supportsTurbo && applied.turboEnabled ? applied.turboRate : nil,
            clutchDPI: applied.kind == .dpiClutch
                ? applied.clutchDPI ?? ButtonBindingSupport.defaultDPIClutchDPI(for: profileID)
                : nil,
            persistentProfile: persistentProfile,
            writePersistentLayer: writePersistentLayer,
            writeDirectLayer: writeDirectLayer
        )
    }

    func applyButtonBinding(slot: Int) async {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        if supportsOnboardProfileEditorWrites(device: selectedDevice) {
            let draft = editorStore.editableButtonBindings[slot] ?? editorController.defaultButtonBinding(for: slot)
            _ = await applyOnboardProfileMutationForCurrentSelection(
                OnboardProfileMutation(buttonBindings: [slot: draft])
            )
            return
        }
        let binding = makeButtonBindingPatch(
            slot: slot,
            persistentProfile: persistentProfileForSingleButtonApply(device: selectedDevice),
            writeDirectLayer: true
        )
        enqueueApply(DevicePatch(buttonBinding: binding))
    }

    func scheduleAutoApplyButton(slot: Int) {
        scheduleAutoApply(key: .button(slot), delay: 120_000_000) { [weak self] in
            guard let self else { return }
            await self.applyButtonBinding(slot: slot)
        }
    }

    private func writableButtonSlots(for device: MouseDevice) -> [Int] {
        device.button_layout?.writableSlots ?? deviceStore.visibleButtonSlots.map(\.slot)
    }

    private func supportsOnboardProfileCRUD(device: MouseDevice) -> Bool {
        guard device.onboard_profile_count > 1 else { return false }
        return DeviceProfiles.resolve(
            vendorID: device.vendor_id,
            productID: device.product_id,
            transport: device.transport
        )?.supportsMappedOnboardProfileCRUD == true
    }

    private func supportsOnboardProfileEditorWrites(device: MouseDevice) -> Bool {
        supportsOnboardProfileCRUD(device: device)
    }

    private func supportsOnboardProfileLightingEditorWrites(device: MouseDevice) -> Bool {
        supportsOnboardProfileCRUD(device: device)
    }

    private func onboardProfileLEDIDs(for device: MouseDevice) -> [UInt8] {
        let ids = DeviceProfiles.resolve(
            vendorID: device.vendor_id,
            productID: device.product_id,
            transport: device.transport
        )?.allUSBLightingLEDIDs ?? [0x01]
        return ids.isEmpty ? [0x01] : ids
    }

    private func currentStaticOnboardProfileColors(for device: MouseDevice, allZones: Bool = false) -> [Int: RGBPatch] {
        let targetLEDIDs: [UInt8]
        if allZones {
            targetLEDIDs = onboardProfileLEDIDs(for: device)
        } else if let zoneLEDIDs = editorController.currentUSBLightingZoneLEDIDs(), !zoneLEDIDs.isEmpty {
            targetLEDIDs = zoneLEDIDs
        } else {
            targetLEDIDs = onboardProfileLEDIDs(for: device)
        }

        return Dictionary(
            uniqueKeysWithValues: targetLEDIDs.map { ledID in
                (
                    Int(ledID),
                    RGBPatch(
                        r: editorStore.editableColor.r,
                        g: editorStore.editableColor.g,
                        b: editorStore.editableColor.b
                    )
                )
            }
        )
    }

    private func applyCurrentStaticOnboardProfileColorsIfSupported(
        for device: MouseDevice,
        allZones: Bool = false
    ) async -> Bool {
        guard supportsOnboardProfileLightingEditorWrites(device: device),
              editorStore.editableLightingEffect == .staticColor || !device.supports_advanced_lighting_effects else {
            return false
        }
        return await applyOnboardProfileMutationForCurrentSelection(
            OnboardProfileMutation(staticColorByLEDID: currentStaticOnboardProfileColors(for: device, allZones: allZones))
        )
    }

    private func applyOnboardProfileMutationForCurrentSelection(_ mutation: OnboardProfileMutation) async -> Bool {
        let start = Date()
        let succeeded = await editorController.applyOnboardProfileMutationForCurrentSelection(mutation)
        if !succeeded, let activeStage = mutation.dpi?.activeStage {
            clearPendingActiveStageSelection(matching: activeStage + 1, for: deviceStore.selectedDevice)
        }
        if succeeded {
            clearPendingLocalEditsIfUnchanged(since: start)
        }
        return succeeded
    }

    private func clearPendingLocalEditsIfUnchanged(since start: Date) {
        guard !applyCoordinator.hasPending else { return }
        guard (lastLocalEditAt ?? .distantPast) <= start else { return }
        hasPendingLocalEdits = false
        lastLocalEditAt = nil
        localEditDeviceIdentityKey = nil
    }

    private func rememberPendingActiveStageSelection(_ stage: Int, for device: MouseDevice?) {
        guard let device else { return }
        let count = DeviceProfiles.clampDpiStageCount(editorStore.editableStageCount)
        pendingActiveStageSelectionByDeviceIdentityKey[deviceController.deviceIdentityKey(device)] = max(1, min(count, stage))
        AppLog.debug(
            "AppState",
            "rememberPendingActiveStage device=\(device.id) requested=\(stage) " +
            "stored=\(pendingActiveStageSelection(for: device).map(String.init) ?? "nil") count=\(count)"
        )
    }

    private func clearPendingActiveStageSelection(matching stage: Int, for device: MouseDevice?) {
        guard let device else { return }
        let key = deviceController.deviceIdentityKey(device)
        guard pendingActiveStageSelectionByDeviceIdentityKey[key] == stage else { return }
        pendingActiveStageSelectionByDeviceIdentityKey.removeValue(forKey: key)
        AppLog.debug("AppState", "clearPendingActiveStage device=\(device.id) stage=\(stage)")
    }

    private func shouldTreatCurrentSourceAsExactMouseSlot(device: MouseDevice) -> Int? {
        guard case .mouseSlot(let slot)? = editorController.currentButtonProfileSource(),
              !editorController.buttonWorkspaceHasUnsavedSourceChanges(device: device) else {
            return nil
        }
        return slot
    }

    private func persistentProfileForSingleButtonApply(device: MouseDevice) -> Int {
        guard device.transport == .usb, editorStore.supportsMultipleOnboardProfiles else {
            return editorStore.editableUSBButtonProfile
        }
        return 1
    }

    private func persistentProfileForRestoredLiveButtons(device: MouseDevice) -> Int {
        guard device.transport == .usb, device.onboard_profile_count > 1 else {
            return 1
        }
        return 1
    }

    func applyCurrentButtonWorkspaceToLive() async {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        let slots = writableButtonSlots(for: selectedDevice)
        let persistentProfile = selectedDevice.transport == .usb && editorStore.supportsMultipleOnboardProfiles
            ? 1
            : (shouldTreatCurrentSourceAsExactMouseSlot(device: selectedDevice) ?? editorStore.activeOnboardProfile)

        for slot in slots {
            let patch = DevicePatch(
                buttonBinding: makeButtonBindingPatch(
                    slot: slot,
                    persistentProfile: persistentProfile,
                    writePersistentLayer: true,
                    writeDirectLayer: true
                )
            )
            let succeeded = await apply(
                device: selectedDevice,
                patch: patch,
                behavior: ApplyBehavior(
                    markApplyingState: true,
                    shouldFocusOnActivity: true,
                    shouldSurfaceApplyFailure: true,
                    persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                    clearLocalEditsOnSuccess: false,
                    backendApplyOptions: ApplyOptions()
                )
            )
            guard succeeded else { return }
        }

        if selectedDevice.transport == .usb && editorStore.supportsMultipleOnboardProfiles {
            editorController.setLiveUSBButtonProfileOverride(1, for: selectedDevice)
        } else {
            if let exactSlot = shouldTreatCurrentSourceAsExactMouseSlot(device: selectedDevice) {
                editorController.setLiveUSBButtonProfileOverride(exactSlot, for: selectedDevice)
            } else {
                editorController.setLiveUSBButtonProfileOverride(editorStore.activeOnboardProfile, for: selectedDevice)
            }
        }
        editorController.markButtonWorkspaceAppliedToLive(
            bindings: editorStore.editableButtonBindings,
            exactSource: editorController.currentButtonProfileSource()
        )
    }

    func writeCurrentButtonWorkspaceToMouseSlot(_ targetProfile: Int) async {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        let clampedTarget = max(1, min(editorStore.visibleOnboardProfileCount, targetProfile))

        for slot in writableButtonSlots(for: selectedDevice) {
            let patch = DevicePatch(
                buttonBinding: makeButtonBindingPatch(
                    slot: slot,
                    persistentProfile: clampedTarget,
                    writePersistentLayer: true,
                    writeDirectLayer: false
                )
            )
            let succeeded = await apply(
                device: selectedDevice,
                patch: patch,
                behavior: ApplyBehavior(
                    markApplyingState: true,
                    shouldFocusOnActivity: false,
                    shouldSurfaceApplyFailure: true,
                    persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                    clearLocalEditsOnSuccess: false,
                    backendApplyOptions: ApplyOptions()
                )
            )
            guard succeeded else { return }
        }

        editorController.saveCachedButtonBindings(device: selectedDevice, bindings: editorStore.editableButtonBindings, profile: clampedTarget)
    }

    func projectSelectedUSBButtonProfileToDirectLayer() async {
        guard let selectedDevice = deviceStore.selectedDevice, editorStore.supportsMultipleOnboardProfiles else { return }
        let patch = DevicePatch(
            usbButtonProfileAction: USBButtonProfileActionPatch(
                kind: .projectToDirectLayer,
                targetProfile: editorStore.editableUSBButtonProfile
            )
        )
        let succeeded = await apply(
            device: selectedDevice,
            patch: patch,
            behavior: ApplyBehavior(
                markApplyingState: true,
                shouldFocusOnActivity: true,
                shouldSurfaceApplyFailure: true,
                persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                clearLocalEditsOnSuccess: false,
                backendApplyOptions: ApplyOptions()
            )
        )
        guard succeeded else { return }
        editorController.setLiveUSBButtonProfileOverride(editorStore.editableUSBButtonProfile, for: selectedDevice)
        let bindings = editorController.cachedButtonBindings(device: selectedDevice, profile: editorStore.editableUSBButtonProfile)
        editorController.markButtonWorkspaceAppliedToLive(bindings: bindings, exactSource: .mouseSlot(editorStore.editableUSBButtonProfile))
    }

    func duplicateSelectedUSBButtonProfile() async {
        guard deviceStore.selectedDevice != nil, editorStore.supportsMultipleOnboardProfiles else { return }
        guard let targetProfile = editorStore.duplicateTargetProfiles.first?.profile else {
            return
        }
        await duplicateSelectedUSBButtonProfile(to: targetProfile)
    }

    func duplicateSelectedUSBButtonProfile(to targetProfile: Int) async {
        guard let selectedDevice = deviceStore.selectedDevice, editorStore.supportsMultipleOnboardProfiles else { return }
        guard targetProfile != editorStore.editableUSBButtonProfile else { return }
        if editorStore.selectedUSBButtonProfileHasUnsavedChanges {
            await saveSelectedUSBButtonProfile()
            guard !editorStore.selectedUSBButtonProfileHasUnsavedChanges else { return }
        }

        let sourceProfile = editorStore.editableUSBButtonProfile
        let patch = DevicePatch(
            usbButtonProfileAction: USBButtonProfileActionPatch(
                kind: .duplicateToPersistentSlot,
                sourceProfile: sourceProfile,
                targetProfile: targetProfile
            )
        )
        let succeeded = await apply(
            device: selectedDevice,
            patch: patch,
            behavior: ApplyBehavior(
                markApplyingState: true,
                shouldFocusOnActivity: true,
                shouldSurfaceApplyFailure: true,
                persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                clearLocalEditsOnSuccess: false,
                backendApplyOptions: ApplyOptions()
            )
        )
        guard succeeded else { return }

        let copiedBindings = editorController.cachedButtonBindings(device: selectedDevice, profile: sourceProfile)
        editorController.saveCachedButtonBindings(device: selectedDevice, bindings: copiedBindings, profile: targetProfile)
        editorController.updateUSBButtonProfile(targetProfile)
    }

    func resetSelectedUSBButtonProfile() async {
        await resetUSBButtonProfile(editorStore.editableUSBButtonProfile)
    }

    func resetUSBButtonProfile(_ targetProfile: Int) async {
        guard let selectedDevice = deviceStore.selectedDevice, editorStore.supportsMultipleOnboardProfiles else { return }
        let clampedTarget = max(1, min(editorStore.visibleOnboardProfileCount, targetProfile))
        let patch = DevicePatch(
            usbButtonProfileAction: USBButtonProfileActionPatch(
                kind: .resetPersistentSlot,
                targetProfile: clampedTarget
            )
        )
        let succeeded = await apply(
            device: selectedDevice,
            patch: patch,
            behavior: ApplyBehavior(
                markApplyingState: true,
                shouldFocusOnActivity: true,
                shouldSurfaceApplyFailure: true,
                persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                clearLocalEditsOnSuccess: false,
                backendApplyOptions: ApplyOptions()
            )
        )
        guard succeeded else { return }

        editorController.saveCachedButtonBindings(device: selectedDevice, bindings: [:], profile: clampedTarget)
        if clampedTarget == editorStore.liveUSBButtonProfile {
            await projectSelectedUSBButtonProfileToDirectLayer()
        }
    }

    func saveSelectedUSBButtonProfile(activateAfterSave: Bool = false) async {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        let profile = editorStore.editableUSBButtonProfile
        let liveProfile = editorStore.liveUSBButtonProfile
        let writableSlots = selectedDevice.button_layout?.writableSlots ?? deviceStore.visibleButtonSlots.map(\.slot)
        let persistedBindings = editorController.cachedButtonBindings(device: selectedDevice, profile: profile)
        let slotsToSave = writableSlots.filter { slot in
            let fallback = editorController.defaultButtonBinding(for: slot, device: selectedDevice)
            let draft = editorStore.editableButtonBindings[slot] ?? fallback
            let persisted = persistedBindings[slot] ?? fallback
            return draft != persisted
        }

        if slotsToSave.isEmpty {
            if activateAfterSave && profile != liveProfile {
                await projectSelectedUSBButtonProfileToDirectLayer()
            }
            return
        }

        let shouldWriteDirectLayer = !editorStore.supportsMultipleOnboardProfiles || profile == liveProfile
        for slot in slotsToSave {
            let patch = DevicePatch(
                buttonBinding: makeButtonBindingPatch(
                    slot: slot,
                    persistentProfile: profile,
                    writeDirectLayer: shouldWriteDirectLayer
                )
            )
            let succeeded = await apply(
                device: selectedDevice,
                patch: patch,
                behavior: ApplyBehavior(
                    markApplyingState: true,
                    shouldFocusOnActivity: true,
                    shouldSurfaceApplyFailure: true,
                    persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                    clearLocalEditsOnSuccess: false,
                    backendApplyOptions: ApplyOptions()
                )
            )
            guard succeeded else { return }
        }

        if activateAfterSave && profile != liveProfile {
            await projectSelectedUSBButtonProfileToDirectLayer()
        }
    }

    private func scheduleAutoApply(
        key: ApplyTaskKey,
        delay: UInt64 = 220_000_000,
        action: @escaping @MainActor () async -> Void
    ) {
        guard !editorController.isHydrating else { return }
        markLocalEditsPending()
        applyTasks[key]?.cancel()
        applyTasks[key] = Task {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await action()
        }
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
        for task in applyTasks.values {
            task.cancel()
        }
        applyTasks.removeAll()
        applyCoordinator.clearPending()
        hasPendingLocalEdits = false
        lastLocalEditAt = nil
        localEditDeviceIdentityKey = nil
        pendingActiveStageSelectionByDeviceIdentityKey.removeAll()
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

    @discardableResult
    func applyPersistedSettingsRestore(
        _ plan: AppStateEditorController.PersistedSettingsRestorePlan,
        to device: MouseDevice
    ) async -> Bool {
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
                    backendApplyOptions: ApplyOptions()
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
                    backendApplyOptions: restoreButtonApplyOptions
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
        while let patch = applyCoordinator.dequeue() {
            await applySelectedPatch(patch)
            hasPendingLocalEdits = applyCoordinator.hasPending
        }
        hasPendingLocalEdits = false
        localEditDeviceIdentityKey = nil
        applyDrainTask = nil
    }

    private func applySelectedPatch(_ patch: DevicePatch) async {
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
                backendApplyOptions: ApplyOptions()
            )
        )
    }

    @discardableResult
    private func apply(
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

        do {
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
        if deviceStore.selectedDeviceID == presentationDeviceID {
            editorController.persistCurrentSettingsSnapshot(
                for: presentationDevice,
                preservingStoredLighting: preserveStoredLighting,
                lightingZoneOverride: snapshotLightingZoneOverride
            )
        }
        editorController.persistSuccessfulPatchFieldsInSettingsSnapshot(
            patch: patch,
            device: presentationDevice,
            lightingZoneID: snapshotLightingZoneOverride ?? persistLightingZoneID
        )

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
