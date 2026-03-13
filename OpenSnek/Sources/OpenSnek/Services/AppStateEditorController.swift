import Foundation
import OpenSnekAppSupport
import OpenSnekCore

@MainActor
final class AppStateEditorController {
    private let environment: AppEnvironment
    private unowned let deviceStore: DeviceStore
    private unowned let editorStore: EditorStore
    private let buttonSlots: [ButtonSlotDescriptor]
    private weak var applyControllerStorage: AppStateApplyController?

    private let preferenceStore = DevicePreferenceStore()
    private(set) var isHydrating = false
    private var hydratedLightingStateByDeviceID: Set<String> = []
    private var hydratedButtonBindingsKey: String?
    private var manualUSBButtonProfileSelectionByDeviceID: Set<String> = []
    private var keyboardDraftApplyTaskBySlot: [Int: Task<Void, Never>] = [:]

    init(
        environment: AppEnvironment,
        deviceStore: DeviceStore,
        editorStore: EditorStore,
        buttonSlots: [ButtonSlotDescriptor]
    ) {
        self.environment = environment
        self.deviceStore = deviceStore
        self.editorStore = editorStore
        self.buttonSlots = buttonSlots
    }

    func tearDown() {
        for task in keyboardDraftApplyTaskBySlot.values {
            task.cancel()
        }
        keyboardDraftApplyTaskBySlot.removeAll()
    }

    func bind(applyController: AppStateApplyController) {
        self.applyControllerStorage = applyController
    }

    private var applyController: AppStateApplyController {
        guard let applyControllerStorage else {
            preconditionFailure("AppStateEditorController accessed before applyController was bound")
        }
        return applyControllerStorage
    }

    func removeHydratedState(for removedDeviceIDs: Set<String>) {
        guard !removedDeviceIDs.isEmpty else { return }
        hydratedLightingStateByDeviceID.subtract(removedDeviceIDs)
        manualUSBButtonProfileSelectionByDeviceID.subtract(removedDeviceIDs)
        if let hydratedButtonBindingsKey,
           let hydratedDeviceID = hydratedButtonBindingsKey.split(separator: "#").first,
           removedDeviceIDs.contains(String(hydratedDeviceID)) {
            self.hydratedButtonBindingsKey = nil
        }
    }

    func telemetryWarning(for state: MouseState, device: MouseDevice) -> String? {
        guard device.transport == .usb else { return nil }
        var missing: [String] = []
        if state.dpi_stages.values == nil { missing.append("DPI stages") }
        if state.poll_rate == nil { missing.append("poll rate") }
        if state.led_value == nil { missing.append("lighting") }
        guard !missing.isEmpty else { return nil }
        return "USB telemetry is incomplete (missing \(missing.joined(separator: ", "))). " +
            "Controls stay visible, but values may be stale until readback succeeds."
    }

    func hydrateEditable(from state: MouseState) {
        isHydrating = true
        defer { isHydrating = false }

        if let values = state.dpi_stages.values, !values.isEmpty {
            editorStore.editableStageCount = max(1, min(5, values.count))
            for index in 0..<editorStore.editableStageValues.count {
                if index < values.count {
                    editorStore.editableStageValues[index] = max(100, min(30000, values[index]))
                }
            }
        } else if let dpi = state.dpi?.x {
            editorStore.editableStageCount = 1
            editorStore.editableStageValues[0] = max(100, min(30000, dpi))
        }

        if let active = state.dpi_stages.active_stage {
            let maxStage = max(1, editorStore.editableStageCount)
            editorStore.editableActiveStage = max(1, min(maxStage, active + 1))
        } else {
            editorStore.editableActiveStage = 1
        }

        if let poll = state.poll_rate {
            editorStore.editablePollRate = poll
        }

        if let timeout = state.sleep_timeout {
            editorStore.editableSleepTimeout = max(60, min(900, timeout))
        }

        if let mode = state.device_mode?.mode {
            editorStore.editableDeviceMode = mode == 0x03 ? 0x03 : 0x00
        }

        if let lowBatteryRaw = state.low_battery_threshold_raw {
            editorStore.editableLowBatteryThresholdRaw = max(0x0C, min(0x3F, lowBatteryRaw))
        }

        if let scrollMode = state.scroll_mode {
            editorStore.editableScrollMode = max(0, min(1, scrollMode))
        }

        if let scrollAcceleration = state.scroll_acceleration {
            editorStore.editableScrollAcceleration = scrollAcceleration
        }

        if let scrollSmartReel = state.scroll_smart_reel {
            editorStore.editableScrollSmartReel = scrollSmartReel
        }

        if let led = state.led_value {
            editorStore.editableLedBrightness = led
        }

        syncUSBButtonProfileSelection(from: state)
    }

    func hydrateLightingStateIfNeeded(device: MouseDevice) async {
        guard !hydratedLightingStateByDeviceID.contains(device.id) else { return }
        var loadedPersistedColor = false
        editorStore.editableUSBLightingZoneID = "all"

        if device.transport == .bluetooth,
           let persisted = loadPersistedLightingColor(device: device) {
            editorStore.editableColor = persisted
            loadedPersistedColor = true
            AppLog.debug(
                "AppState",
                "hydrated Bluetooth lighting color from persisted cache id=\(device.id) rgb=(\(persisted.r),\(persisted.g),\(persisted.b))"
            )
        } else if device.transport == .bluetooth,
                  let rgb = try? await environment.backend.readLightingColor(device: device) {
            editorStore.editableColor = RGBColor(r: rgb.r, g: rgb.g, b: rgb.b)
            persistLightingColor(editorStore.editableColor, device: device)
            AppLog.debug("AppState", "hydrated Bluetooth lighting color from device id=\(device.id) rgb=(\(rgb.r),\(rgb.g),\(rgb.b))")
        } else if let persisted = loadPersistedLightingColor(device: device) {
            editorStore.editableColor = persisted
            loadedPersistedColor = true
            AppLog.debug(
                "AppState",
                "hydrated lighting color from persisted cache id=\(device.id) rgb=(\(persisted.r),\(persisted.g),\(persisted.b))"
            )
        } else {
            AppLog.debug("AppState", "lighting color read unavailable for device id=\(device.id)")
        }

        if device.supports_advanced_lighting_effects, let persistedEffect = loadPersistedLightingEffect(device: device) {
            let supportedEffects = DeviceProfiles
                .resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)?
                .supportedLightingEffects ?? LightingEffectKind.allCases
            editorStore.editableLightingEffect = supportedEffects.contains(persistedEffect.kind)
                ? persistedEffect.kind
                : (supportedEffects.first ?? .staticColor)
            editorStore.editableLightingWaveDirection = persistedEffect.waveDirection
            editorStore.editableLightingReactiveSpeed = persistedEffect.reactiveSpeed
            editorStore.editableSecondaryColor = persistedEffect.secondaryColor
            AppLog.debug(
                "AppState",
                "hydrated lighting effect from persisted cache id=\(device.id) kind=\(persistedEffect.kind.rawValue)"
            )
        } else if !device.supports_advanced_lighting_effects {
            editorStore.editableLightingEffect = .staticColor
        }

        if loadedPersistedColor, device.transport == .bluetooth {
            applyController.enqueueApply(
                DevicePatch(ledRGB: RGBPatch(r: editorStore.editableColor.r, g: editorStore.editableColor.g, b: editorStore.editableColor.b))
            )
            AppLog.debug("AppState", "queued persisted lighting color reapply id=\(device.id)")
        }

        hydratedLightingStateByDeviceID.insert(device.id)
    }

    func markLightingHydrated(deviceID: String) {
        hydratedLightingStateByDeviceID.insert(deviceID)
    }

    func persistLightingColor(_ color: RGBColor, device: MouseDevice) {
        preferenceStore.persistLightingColor(color, device: device)
    }

    func loadPersistedLightingColor(device: MouseDevice) -> RGBColor? {
        preferenceStore.loadPersistedLightingColor(device: device)
    }

    func persistLightingEffect(_ effect: LightingEffectPatch, device: MouseDevice) {
        preferenceStore.persistLightingEffect(effect, device: device)
    }

    func loadPersistedLightingEffect(device: MouseDevice) -> (
        kind: LightingEffectKind,
        waveDirection: LightingWaveDirection,
        reactiveSpeed: Int,
        secondaryColor: RGBColor
    )? {
        preferenceStore.loadPersistedLightingEffect(device: device)
    }

    func hydrateButtonBindingsIfNeeded(device: MouseDevice) async {
        let hydrationKey = buttonBindingsHydrationKey(device: device)
        guard hydratedButtonBindingsKey != hydrationKey else { return }

        var hydrated = loadPersistedButtonBindings(device: device, profile: editorStore.editableUSBButtonProfile)
        if device.transport == .usb, let fromDevice = await loadUSBButtonBindingsFromDevice(device: device) {
            hydrated.merge(fromDevice) { _, readback in readback }
            savePersistedButtonBindings(device: device, bindings: hydrated, profile: editorStore.editableUSBButtonProfile)
            AppLog.debug(
                "AppState",
                "hydrated button bindings from USB readback id=\(device.id) profile=\(editorStore.editableUSBButtonProfile) slots=\(fromDevice.keys.sorted())"
            )
        } else {
            AppLog.debug(
                "AppState",
                "hydrated button bindings from persisted cache id=\(device.id) profile=\(editorStore.editableUSBButtonProfile) slots=\(hydrated.keys.sorted())"
            )
        }

        editorStore.editableButtonBindings = hydrated
        editorStore.keyboardTextDraftBySlot = hydrated.reduce(into: [:]) { partialResult, pair in
            if pair.value.kind == .keyboardSimple {
                partialResult[pair.key] = AppStateKeyboardSupport.keyboardText(forHidKey: pair.value.hidKey) ?? ""
            }
        }
        hydratedButtonBindingsKey = hydrationKey
    }

    func markButtonBindingsHydrated(device: MouseDevice) {
        hydratedButtonBindingsKey = buttonBindingsHydrationKey(device: device)
    }

    func loadUSBButtonBindingsFromDevice(device: MouseDevice) async -> [Int: ButtonBindingDraft]? {
        let slots = (device.button_layout?.visibleSlots ?? buttonSlots)
            .map(\.slot)
            .filter { $0 != 6 }
        var bindings: [Int: ButtonBindingDraft] = [:]
        var readAnyBlock = false
        let persistentProfile = max(1, min(editorStore.visibleOnboardProfileCount, editorStore.editableUSBButtonProfile))
        let shouldReadDirect = !editorStore.supportsMultipleOnboardProfiles || persistentProfile == editorStore.activeOnboardProfile

        for slot in slots {
            do {
                let persistentBlock = try await environment.backend.debugUSBReadButtonBinding(
                    device: device,
                    slot: slot,
                    profile: persistentProfile
                )
                let directBlock = shouldReadDirect
                    ? try await environment.backend.debugUSBReadButtonBinding(device: device, slot: slot, profile: 0x00)
                    : nil
                let block = directBlock ?? persistentBlock
                if let block {
                    readAnyBlock = true
                    if let draft = ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(
                        slot: slot,
                        functionBlock: block,
                        profileID: device.profile_id
                    ) {
                        bindings[slot] = draft
                    }
                }
            } catch {
                AppLog.debug(
                    "AppState",
                    "usb button hydration read failed id=\(device.id) slot=\(slot): \(error.localizedDescription)"
                )
            }
        }

        guard readAnyBlock else { return nil }
        return bindings
    }

    func persistButtonBinding(_ binding: ButtonBindingPatch, device: MouseDevice, profile: Int) {
        preferenceStore.persistButtonBinding(binding, device: device, profile: profile)
    }

    func savePersistedButtonBindings(device: MouseDevice, bindings: [Int: ButtonBindingDraft], profile: Int) {
        preferenceStore.savePersistedButtonBindings(device: device, bindings: bindings, profile: profile)
    }

    func loadPersistedButtonBindings(device: MouseDevice, profile: Int) -> [Int: ButtonBindingDraft] {
        preferenceStore.loadPersistedButtonBindings(device: device, profile: profile)
    }

    func defaultButtonBinding(for slot: Int) -> ButtonBindingDraft {
        ButtonBindingSupport.defaultButtonBinding(for: slot, profileID: deviceStore.selectedDevice?.profile_id)
    }

    func currentLightingEffectPatch() -> LightingEffectPatch {
        LightingEffectPatch(
            kind: editorStore.editableLightingEffect,
            primary: RGBPatch(r: editorStore.editableColor.r, g: editorStore.editableColor.g, b: editorStore.editableColor.b),
            secondary: RGBPatch(r: editorStore.editableSecondaryColor.r, g: editorStore.editableSecondaryColor.g, b: editorStore.editableSecondaryColor.b),
            waveDirection: editorStore.editableLightingWaveDirection,
            reactiveSpeed: editorStore.editableLightingReactiveSpeed
        )
    }

    func currentUSBLightingZoneLEDIDs() -> [UInt8]? {
        guard editorStore.editableLightingEffect == .staticColor else { return nil }
        guard editorStore.editableUSBLightingZoneID != "all" else { return nil }
        return editorStore.visibleUSBLightingZones.first(where: { $0.id == editorStore.editableUSBLightingZoneID })?.ledIDs
    }

    func syncUSBButtonProfileSelection(from state: MouseState) {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        let count = max(1, max(selectedDevice.onboard_profile_count, state.onboard_profile_count ?? 1))
        let active = max(1, min(count, state.active_onboard_profile ?? 1))
        let selected: Int
        if manualUSBButtonProfileSelectionByDeviceID.contains(selectedDevice.id) {
            selected = max(1, min(count, editorStore.editableUSBButtonProfile))
        } else {
            selected = active
        }
        if editorStore.editableUSBButtonProfile != selected {
            editorStore.editableUSBButtonProfile = selected
            hydratedButtonBindingsKey = nil
        }
    }

    func buttonBindingsHydrationKey(device: MouseDevice) -> String {
        "\(device.id)#\(editorStore.editableUSBButtonProfile)"
    }

    func updateLightingEffect(_ kind: LightingEffectKind) {
        guard deviceStore.selectedDevice?.supports_advanced_lighting_effects == true else {
            editorStore.editableLightingEffect = .staticColor
            editorStore.editableUSBLightingZoneID = "all"
            return
        }
        let supportedEffects = editorStore.visibleLightingEffects
        editorStore.editableLightingEffect = supportedEffects.contains(kind) ? kind : (supportedEffects.first ?? .staticColor)
        if kind != .staticColor {
            editorStore.editableUSBLightingZoneID = "all"
        }
    }

    func updateUSBLightingZoneID(_ zoneID: String) {
        editorStore.editableUSBLightingZoneID = zoneID
    }

    func updateUSBButtonProfile(_ profile: Int) {
        guard let selectedDevice = deviceStore.selectedDevice, editorStore.supportsMultipleOnboardProfiles else { return }
        let clamped = max(1, min(editorStore.visibleOnboardProfileCount, profile))
        editorStore.editableUSBButtonProfile = clamped
        manualUSBButtonProfileSelectionByDeviceID.insert(selectedDevice.id)
        hydratedButtonBindingsKey = nil
        Task { [weak self] in
            await self?.hydrateButtonBindingsIfNeeded(device: selectedDevice)
        }
    }

    func updateLightingWaveDirection(_ direction: LightingWaveDirection) {
        editorStore.editableLightingWaveDirection = direction
    }

    func updateLightingReactiveSpeed(_ speed: Int) {
        editorStore.editableLightingReactiveSpeed = max(1, min(4, speed))
    }

    func buttonBindingKind(for slot: Int) -> ButtonBindingKind {
        editorStore.editableButtonBindings[slot]?.kind ?? defaultButtonBinding(for: slot).kind
    }

    func buttonBindingHidKey(for slot: Int) -> Int {
        editorStore.editableButtonBindings[slot]?.hidKey ?? defaultButtonBinding(for: slot).hidKey
    }

    func buttonBindingTurboEnabled(for slot: Int) -> Bool {
        editorStore.editableButtonBindings[slot]?.turboEnabled ?? defaultButtonBinding(for: slot).turboEnabled
    }

    func buttonBindingTurboRate(for slot: Int) -> Int {
        editorStore.editableButtonBindings[slot]?.turboRate ?? defaultButtonBinding(for: slot).turboRate
    }

    func buttonBindingClutchDPI(for slot: Int) -> Int {
        editorStore.editableButtonBindings[slot]?.clutchDPI
            ?? ButtonBindingSupport.defaultDPIClutchDPI(for: deviceStore.selectedDevice?.profile_id)
            ?? 400
    }

    func updateButtonBindingKind(slot: Int, kind: ButtonBindingKind) {
        guard deviceStore.visibleButtonSlots.contains(where: { $0.slot == slot }) else { return }
        var next = editorStore.editableButtonBindings[slot] ?? defaultButtonBinding(for: slot)
        next.kind = kind
        if kind != .keyboardSimple {
            keyboardDraftApplyTaskBySlot[slot]?.cancel()
            keyboardDraftApplyTaskBySlot[slot] = nil
            next.hidKey = 4
            editorStore.keyboardTextDraftBySlot[slot] = nil
        } else {
            editorStore.keyboardTextDraftBySlot[slot] = AppStateKeyboardSupport.keyboardText(forHidKey: next.hidKey) ?? ""
        }
        if kind == .dpiClutch {
            next.clutchDPI = next.clutchDPI ?? ButtonBindingSupport.defaultDPIClutchDPI(for: deviceStore.selectedDevice?.profile_id)
        }
        if !kind.supportsTurbo {
            next.turboEnabled = false
        }
        editorStore.editableButtonBindings[slot] = next
        applyController.scheduleAutoApplyButton(slot: slot)
    }

    func updateButtonBindingHidKey(slot: Int, hidKey: Int) {
        guard deviceStore.visibleButtonSlots.contains(where: { $0.slot == slot }) else { return }
        var next = editorStore.editableButtonBindings[slot] ?? defaultButtonBinding(for: slot)
        next.kind = .keyboardSimple
        next.hidKey = max(4, min(231, hidKey))
        editorStore.editableButtonBindings[slot] = next
        editorStore.keyboardTextDraftBySlot[slot] = AppStateKeyboardSupport.keyboardText(forHidKey: next.hidKey) ?? ""
        applyController.scheduleAutoApplyButton(slot: slot)
    }

    func updateButtonBindingTurboEnabled(slot: Int, enabled: Bool) {
        guard deviceStore.visibleButtonSlots.contains(where: { $0.slot == slot }) else { return }
        var next = editorStore.editableButtonBindings[slot] ?? defaultButtonBinding(for: slot)
        guard next.kind.supportsTurbo else { return }
        next.turboEnabled = enabled
        editorStore.editableButtonBindings[slot] = next
        applyController.scheduleAutoApplyButton(slot: slot)
    }

    func updateButtonBindingTurboRate(slot: Int, rate: Int) {
        guard deviceStore.visibleButtonSlots.contains(where: { $0.slot == slot }) else { return }
        var next = editorStore.editableButtonBindings[slot] ?? defaultButtonBinding(for: slot)
        guard next.kind.supportsTurbo else { return }
        next.turboRate = max(1, min(255, rate))
        editorStore.editableButtonBindings[slot] = next
        applyController.scheduleAutoApplyButton(slot: slot)
    }

    func updateButtonBindingClutchDPI(slot: Int, dpi: Int) {
        guard deviceStore.visibleButtonSlots.contains(where: { $0.slot == slot }) else { return }
        var next = editorStore.editableButtonBindings[slot] ?? defaultButtonBinding(for: slot)
        guard next.kind == .dpiClutch else { return }
        next.clutchDPI = max(100, min(30_000, dpi))
        editorStore.editableButtonBindings[slot] = next
        applyController.scheduleAutoApplyButton(slot: slot)
    }

    func keyboardTextDraft(for slot: Int) -> String {
        if let draft = editorStore.keyboardTextDraftBySlot[slot] {
            return draft
        }
        let hidKey = buttonBindingHidKey(for: slot)
        return AppStateKeyboardSupport.keyboardText(forHidKey: hidKey) ?? ""
    }

    func updateKeyboardTextDraft(slot: Int, text: String) {
        guard deviceStore.visibleButtonSlots.contains(where: { $0.slot == slot }) else { return }
        editorStore.keyboardTextDraftBySlot[slot] = text
        keyboardDraftApplyTaskBySlot[slot]?.cancel()
        keyboardDraftApplyTaskBySlot[slot] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 320_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.applyKeyboardTextDraft(slot: slot)
        }
    }

    private func applyKeyboardTextDraft(slot: Int) {
        guard let text = editorStore.keyboardTextDraftBySlot[slot] else { return }
        guard let hidKey = AppStateKeyboardSupport.hidKey(fromKeyboardText: text) else { return }
        updateButtonBindingHidKey(slot: slot, hidKey: hidKey)
    }
}
