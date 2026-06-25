import Foundation
import OpenSnekAppSupport
import OpenSnekCore

/// Coordinates app state editor behavior.
@MainActor
final class AppStateEditorController {
    let environment: AppEnvironment
    let deviceStore: DeviceStore
    let editorStore: EditorStore
    let buttonSlots: [ButtonSlotDescriptor]
    @WeakBound("AppStateEditorController", dependency: "applyController")
    var applyController: AppStateApplyController

    let preferenceStore = DevicePreferenceStore()
    var isHydrating = false
    var hydratedLightingStateByDeviceID: Set<String> = []
    var hydratedSoftwareLightingPreferencesByDeviceID: Set<String> = []
    var hydratedButtonBindingsKey: String?
    var buttonBindingsCacheByHydrationKey: [String: [Int: ButtonBindingDraft]] = [:]
    var buttonBindingsReadbackAttemptedKeys: Set<String> = []
    var buttonBindingsReadbackInFlightKeys: Set<String> = []
    var buttonProfileSummaryHydrationInFlightDeviceIDs: Set<String> = []
    var buttonProfileWorkspaceSourceByDeviceID: [String: ButtonProfileSource] = [:]
    var buttonProfileLiveSourceByDeviceID: [String: ButtonProfileSource] = [:]
    var buttonProfileLiveBindingsByDeviceID: [String: [Int: ButtonBindingDraft]] = [:]
    var softwareActiveUSBButtonProfileOverrideByDeviceID: [String: Int] = [:]
    var softwareLightingAutoStartInFlightKeys: Set<String> = []
    var onboardProfileInventoryByDeviceID: [String: OnboardProfileInventory] = [:]
    var projectedOnboardProfileMetadataByDeviceID: [String: [Int: OnboardProfileMetadata]] = [:]
    var currentOnboardProfileSnapshotByDeviceID: [String: OnboardProfileSnapshot] = [:]
    var onboardProfileLightingColorsByDeviceID: [String: [String: RGBColor]] = [:]
    var selectedOnboardProfileIDByDeviceID: [String: Int] = [:]
    var selectedSingleSlotProfileNameByDeviceID: [String: String] = [:]
    var singleSlotProfileApplySyncSuppressedDeviceIDs: Set<String> = []
    var lastHardwareActiveOnboardProfileIDByDeviceID: [String: Int] = [:]
    var onboardProfileReloadRequiredDeviceIDs: Set<String> = []
    var onboardProfileRefreshInFlightDeviceIDs: Set<String> = []
    var selectedMouseSlotHydrationTasksByDeviceID: [String: Task<Void, Never>] = [:]
    var selectedMouseSlotHydrationTokensByDeviceID: [String: UUID] = [:]
    var activeOnboardProfileLoadTasksByDeviceID: [String: Task<Void, Never>] = [:]
    var activeOnboardProfileLoadTokensByDeviceID: [String: UUID] = [:]
    var activeOnboardProfileLoadOperationIDsByDeviceID: [String: UUID] = [:]
    var activeOnboardDPIProjectionTasksByDeviceID: [String: Task<Void, Never>] = [:]
    var activeOnboardDPIProjectionTokensByDeviceID: [String: UUID] = [:]
    var lastProjectedActiveOnboardDPISignatureByDeviceID: [String: String] = [:]
    var onboardProfileButtonHydrationTasksByDeviceID: [String: Task<Void, Never>] = [:]
    var onboardProfileButtonHydrationTokensByDeviceID: [String: UUID] = [:]
    var manualOnboardProfileActivationTargetByDeviceID: [String: Int] = [:]
    var buttonWorkspaceEditRevisionByHydrationKey: [String: UInt64] = [:]
    var activeOnboardProfileMutationCount = 0
    var maxConcurrentOnboardProfileMutationCount = 0
    var buttonWorkspaceEditRevision: UInt64 = 0
    var lastDPITraceLineByAction: [String: String] = [:]
    var isTearingDown = false

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
        isTearingDown = true
        selectedMouseSlotHydrationTasksByDeviceID.values.forEach { $0.cancel() }
        selectedMouseSlotHydrationTasksByDeviceID.removeAll()
        selectedMouseSlotHydrationTokensByDeviceID.removeAll()
        activeOnboardProfileLoadTasksByDeviceID.values.forEach { $0.cancel() }
        activeOnboardProfileLoadTasksByDeviceID.removeAll()
        activeOnboardProfileLoadTokensByDeviceID.removeAll()
        activeOnboardProfileLoadOperationIDsByDeviceID.values.forEach {
            editorStore.endOnboardProfileLoad($0)
        }
        activeOnboardProfileLoadOperationIDsByDeviceID.removeAll()
        activeOnboardDPIProjectionTasksByDeviceID.values.forEach { $0.cancel() }
        activeOnboardDPIProjectionTasksByDeviceID.removeAll()
        activeOnboardDPIProjectionTokensByDeviceID.removeAll()
        lastProjectedActiveOnboardDPISignatureByDeviceID.removeAll()
        onboardProfileButtonHydrationTasksByDeviceID.values.forEach { $0.cancel() }
        onboardProfileButtonHydrationTasksByDeviceID.removeAll()
        onboardProfileButtonHydrationTokensByDeviceID.removeAll()
        manualOnboardProfileActivationTargetByDeviceID.removeAll()
        singleSlotProfileApplySyncSuppressedDeviceIDs.removeAll()
        lastDPITraceLineByAction.removeAll()
    }

    func bind(applyController: AppStateApplyController) {
        _applyController.bind(applyController)
    }

    func bumpUSBButtonProfilesRevision() {
        editorStore.usbButtonProfilesRevision &+= 1
    }

    func bumpOnboardProfilesRevision() {
        editorStore.onboardProfilesRevision &+= 1
    }

    func cancelActiveOnboardProfileLoad(deviceID: String) {
        activeOnboardProfileLoadTasksByDeviceID.removeValue(forKey: deviceID)?.cancel()
        activeOnboardProfileLoadTokensByDeviceID.removeValue(forKey: deviceID)
        if let operationID = activeOnboardProfileLoadOperationIDsByDeviceID.removeValue(forKey: deviceID) {
            editorStore.endOnboardProfileLoad(operationID)
        }
    }

    func cancelOnboardProfileButtonHydration(deviceID: String) {
        onboardProfileButtonHydrationTasksByDeviceID.removeValue(forKey: deviceID)?.cancel()
        onboardProfileButtonHydrationTokensByDeviceID.removeValue(forKey: deviceID)
    }

    func clearButtonWorkspaceEditMarkers(deviceID: String) {
        buttonWorkspaceEditRevisionByHydrationKey = buttonWorkspaceEditRevisionByHydrationKey.filter { key, _ in
            guard let hydratedDeviceID = key.split(separator: "#").first else { return true }
            return String(hydratedDeviceID) != deviceID
        }
    }

    func bumpConnectBehaviorRevision() {
        editorStore.connectBehaviorRevision &+= 1
    }

    func normalizedButtonProfileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Profile" : trimmed
    }

    func buttonBindingsDebugSummary(_ bindings: [Int: ButtonBindingDraft]) -> String {
        guard !bindings.isEmpty else { return "<none>" }
        return bindings.keys.sorted().map { slot in
            guard let binding = bindings[slot] else { return "\(slot):<missing>" }
            var suffix = ""
            if binding.kind == .keyboardSimple {
                suffix = ":key\(binding.hidKey):mods\(binding.hidModifiers)"
            }
            return "\(slot):\(binding.kind.rawValue)\(suffix)"
        }.joined(separator: ",")
    }

    func forcesRestoreOpenSnekSettingsOnConnect(for device: MouseDevice) -> Bool {
        device.transport == .bluetooth && device.profile_id == .basiliskV3XHyperspeed
    }

    func hasOnboardProfileStorage(_ device: MouseDevice) -> Bool {
        device.onboard_profile_count > 1
    }

    func buttonProfileSource(for device: MouseDevice) -> ButtonProfileSource {
        if let source = buttonProfileWorkspaceSourceByDeviceID[device.id] {
            switch source {
            case .mouseSlot(let slot):
                return .mouseSlot(max(1, min(editorStore.visibleOnboardProfileCount, slot)))
            case .openSnekProfile(let id):
                if preferenceStore.loadOpenSnekButtonProfiles().contains(where: { $0.id == id }) {
                    return source
                }
            }
        }
        return .mouseSlot(defaultMouseButtonProfileSource(for: device))
    }

    func defaultMouseButtonProfileSource(for device: MouseDevice) -> Int {
        if editorStore.supportsMultipleOnboardProfiles {
            return liveUSBButtonProfile(for: device)
        }
        return 1
    }

    func setButtonProfileSource(_ source: ButtonProfileSource, for device: MouseDevice) {
        buttonProfileWorkspaceSourceByDeviceID[device.id] = source
        if case .mouseSlot(let slot) = source {
            editorStore.editableUSBButtonProfile = max(1, min(editorStore.visibleOnboardProfileCount, slot))
        }
        bumpUSBButtonProfilesRevision()
    }

    func setLiveButtonProfileSource(
        _ source: ButtonProfileSource,
        bindings: [Int: ButtonBindingDraft],
        for device: MouseDevice
    ) {
        buttonProfileLiveSourceByDeviceID[device.id] = source
        buttonProfileLiveBindingsByDeviceID[device.id] = bindings
        bumpUSBButtonProfilesRevision()
    }

    func currentSourceBindings(for device: MouseDevice) -> [Int: ButtonBindingDraft] {
        switch buttonProfileSource(for: device) {
        case .mouseSlot(let slot):
            return cachedButtonBindings(device: device, profile: slot)
        case .openSnekProfile(let id):
            return preferenceStore.loadOpenSnekButtonProfiles().first(where: { $0.id == id })?.bindings ?? [:]
        }
    }

    func sourceBindings(for source: ButtonProfileSource, device: MouseDevice) -> [Int: ButtonBindingDraft] {
        switch source {
        case .mouseSlot(let slot):
            return cachedButtonBindings(device: device, profile: slot)
        case .openSnekProfile(let id):
            return preferenceStore.loadOpenSnekButtonProfiles().first(where: { $0.id == id })?.bindings ?? [:]
        }
    }

    func liveBindings(for device: MouseDevice) -> [Int: ButtonBindingDraft] {
        buttonProfileLiveBindingsByDeviceID[device.id]
            ?? sourceBindings(for: liveButtonProfileSource(for: device), device: device)
    }

    func bindingComparisonSlots(
        for device: MouseDevice,
        lhs: [Int: ButtonBindingDraft],
        rhs: [Int: ButtonBindingDraft]
    ) -> [Int] {
        let visibleSlots = Set((device.button_layout?.visibleSlots ?? buttonSlots).map(\.slot))
        let extraSlots = Set(lhs.keys).union(rhs.keys)
        return Array(visibleSlots.union(extraSlots)).sorted()
    }

    func bindingsEqual(
        _ lhs: [Int: ButtonBindingDraft],
        _ rhs: [Int: ButtonBindingDraft],
        device: MouseDevice
    ) -> Bool {
        bindingComparisonSlots(for: device, lhs: lhs, rhs: rhs).allSatisfy { slot in
            let fallback = defaultButtonBinding(for: slot, device: device)
            return (lhs[slot] ?? fallback) == (rhs[slot] ?? fallback)
        }
    }

    func shouldPreserveLocalButtonWorkspace(device: MouseDevice) -> Bool {
        let hasInitializedWorkspace = hydratedButtonBindingsKey != nil || !editorStore.editableButtonBindings.isEmpty
        guard hasInitializedWorkspace else { return false }
        guard buttonWorkspaceBelongsToDevice(device) else { return false }
        return buttonWorkspaceHasUnsavedSourceChanges(device: device)
    }

    func buttonWorkspaceBelongsToDevice(_ device: MouseDevice) -> Bool {
        if let hydratedButtonBindingsKey,
           let hydratedDeviceID = hydratedButtonBindingsKey.split(separator: "#").first {
            return String(hydratedDeviceID) == device.id
        }
        return buttonProfileWorkspaceSourceByDeviceID[device.id] != nil
    }

    func workspaceSourceDisplayName(_ source: ButtonProfileSource) -> String {
        switch source {
        case .openSnekProfile(let id):
            return preferenceStore.loadOpenSnekButtonProfiles().first(where: { $0.id == id })?.name ?? "Deleted Profile"
        case .mouseSlot(let slot):
            if editorStore.supportsMultipleOnboardProfiles {
                return slot == 1 ? "Current Buttons" : "Stored Slot \(slot)"
            }
            return "This Mouse"
        }
    }

    func matchingSavedButtonProfiles(
        for bindings: [Int: ButtonBindingDraft],
        device: MouseDevice
    ) -> [OpenSnekButtonProfile] {
        savedButtonProfiles().filter { bindingsEqual($0.bindings, bindings, device: device) }
    }

    func savedButtonProfileMatchDescription(
        for bindings: [Int: ButtonBindingDraft],
        device: MouseDevice
    ) -> String? {
        let matches = matchingSavedButtonProfiles(for: bindings, device: device)
        guard let first = matches.first else { return nil }
        if matches.count == 1 {
            return first.name
        }
        return "\(first.name) +\(matches.count - 1)"
    }

    /// Stores persisted lighting restore plan data.
    struct PersistedLightingRestorePlan {
        let primaryColor: RGBColor?
        let lightingEffect: LightingEffectPatch?
        let usbLightingZoneID: String
    }

    /// Stores persisted settings restore plan data.
    struct PersistedSettingsRestorePlan {
        let snapshot: PersistedDeviceSettingsSnapshot
        let patch: DevicePatch
        let buttonBindings: [Int: ButtonBindingDraft]
    }

    func removeHydratedState(for removedDeviceIDs: Set<String>) {
        guard !removedDeviceIDs.isEmpty else { return }
        hydratedLightingStateByDeviceID.subtract(removedDeviceIDs)
        hydratedSoftwareLightingPreferencesByDeviceID.subtract(removedDeviceIDs)
        softwareActiveUSBButtonProfileOverrideByDeviceID = softwareActiveUSBButtonProfileOverrideByDeviceID.filter { key, _ in
            !removedDeviceIDs.contains(key)
        }
        buttonProfileWorkspaceSourceByDeviceID = buttonProfileWorkspaceSourceByDeviceID.filter { key, _ in
            !removedDeviceIDs.contains(key)
        }
        buttonProfileLiveSourceByDeviceID = buttonProfileLiveSourceByDeviceID.filter { key, _ in
            !removedDeviceIDs.contains(key)
        }
        buttonProfileLiveBindingsByDeviceID = buttonProfileLiveBindingsByDeviceID.filter { key, _ in
            !removedDeviceIDs.contains(key)
        }
        onboardProfileInventoryByDeviceID = onboardProfileInventoryByDeviceID.filter { key, _ in
            !removedDeviceIDs.contains(key)
        }
        projectedOnboardProfileMetadataByDeviceID = projectedOnboardProfileMetadataByDeviceID.filter { key, _ in
            !removedDeviceIDs.contains(key)
        }
        currentOnboardProfileSnapshotByDeviceID = currentOnboardProfileSnapshotByDeviceID.filter { key, _ in
            !removedDeviceIDs.contains(key)
        }
        onboardProfileLightingColorsByDeviceID = onboardProfileLightingColorsByDeviceID.filter { key, _ in
            !removedDeviceIDs.contains(key)
        }
        selectedOnboardProfileIDByDeviceID = selectedOnboardProfileIDByDeviceID.filter { key, _ in
            !removedDeviceIDs.contains(key)
        }
        selectedSingleSlotProfileNameByDeviceID = selectedSingleSlotProfileNameByDeviceID.filter { key, _ in
            !removedDeviceIDs.contains(key)
        }
        lastHardwareActiveOnboardProfileIDByDeviceID = lastHardwareActiveOnboardProfileIDByDeviceID.filter { key, _ in
            !removedDeviceIDs.contains(key)
        }
        onboardProfileReloadRequiredDeviceIDs.subtract(removedDeviceIDs)
        buttonBindingsCacheByHydrationKey = buttonBindingsCacheByHydrationKey.filter { key, _ in
            guard let hydratedDeviceID = key.split(separator: "#").first else { return true }
            return !removedDeviceIDs.contains(String(hydratedDeviceID))
        }
        buttonBindingsReadbackAttemptedKeys = buttonBindingsReadbackAttemptedKeys.filter { key in
            guard let hydratedDeviceID = key.split(separator: "#").first else { return true }
            return !removedDeviceIDs.contains(String(hydratedDeviceID))
        }
        buttonBindingsReadbackInFlightKeys = buttonBindingsReadbackInFlightKeys.filter { key in
            guard let hydratedDeviceID = key.split(separator: "#").first else { return true }
            return !removedDeviceIDs.contains(String(hydratedDeviceID))
        }
        buttonWorkspaceEditRevisionByHydrationKey = buttonWorkspaceEditRevisionByHydrationKey.filter { key, _ in
            guard let hydratedDeviceID = key.split(separator: "#").first else { return true }
            return !removedDeviceIDs.contains(String(hydratedDeviceID))
        }
        buttonProfileSummaryHydrationInFlightDeviceIDs.subtract(removedDeviceIDs)
        for deviceID in removedDeviceIDs {
            selectedMouseSlotHydrationTasksByDeviceID.removeValue(forKey: deviceID)?.cancel()
            selectedMouseSlotHydrationTokensByDeviceID.removeValue(forKey: deviceID)
            cancelActiveOnboardProfileLoad(deviceID: deviceID)
            cancelOnboardProfileButtonHydration(deviceID: deviceID)
        }
        if let hydratedButtonBindingsKey,
           let hydratedDeviceID = hydratedButtonBindingsKey.split(separator: "#").first,
           removedDeviceIDs.contains(String(hydratedDeviceID)) {
            self.hydratedButtonBindingsKey = nil
        }
        bumpUSBButtonProfilesRevision()
        bumpOnboardProfilesRevision()
    }

    func invalidateOnboardProfileState(for deviceIDs: Set<String>) {
        guard !deviceIDs.isEmpty else { return }
        onboardProfileInventoryByDeviceID = onboardProfileInventoryByDeviceID.filter { key, _ in
            !deviceIDs.contains(key)
        }
        projectedOnboardProfileMetadataByDeviceID = projectedOnboardProfileMetadataByDeviceID.filter { key, _ in
            !deviceIDs.contains(key)
        }
        currentOnboardProfileSnapshotByDeviceID = currentOnboardProfileSnapshotByDeviceID.filter { key, _ in
            !deviceIDs.contains(key)
        }
        onboardProfileLightingColorsByDeviceID = onboardProfileLightingColorsByDeviceID.filter { key, _ in
            !deviceIDs.contains(key)
        }
        selectedOnboardProfileIDByDeviceID = selectedOnboardProfileIDByDeviceID.filter { key, _ in
            !deviceIDs.contains(key)
        }
        selectedSingleSlotProfileNameByDeviceID = selectedSingleSlotProfileNameByDeviceID.filter { key, _ in
            !deviceIDs.contains(key)
        }
        lastHardwareActiveOnboardProfileIDByDeviceID = lastHardwareActiveOnboardProfileIDByDeviceID.filter { key, _ in
            !deviceIDs.contains(key)
        }
        onboardProfileReloadRequiredDeviceIDs.formUnion(deviceIDs)
        for deviceID in deviceIDs {
            cancelOnboardProfileButtonHydration(deviceID: deviceID)
        }
        bumpOnboardProfilesRevision()
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

    func connectBehavior(for device: MouseDevice) -> DeviceConnectBehavior {
        if hasOnboardProfileStorage(device) {
            return .useMouseSettings
        }
        if forcesRestoreOpenSnekSettingsOnConnect(for: device), !supportsProfilePicker(device: device) {
            return .restoreOpenSnekSettings
        }
        return preferenceStore.loadConnectBehavior(device: device) ?? .useMouseSettings
    }

    func showsConnectBehaviorCard(for device: MouseDevice) -> Bool {
        !supportsProfilePicker(device: device) &&
            !forcesRestoreOpenSnekSettingsOnConnect(for: device) &&
            !hasOnboardProfileStorage(device)
    }

    func updateConnectBehavior(_ behavior: DeviceConnectBehavior) {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        guard !hasOnboardProfileStorage(selectedDevice) else { return }
        guard !forcesRestoreOpenSnekSettingsOnConnect(for: selectedDevice) ||
            supportsProfilePicker(device: selectedDevice) else {
            return
        }
        preferenceStore.persistConnectBehavior(behavior, device: selectedDevice)
        updateSingleSlotProfilePresentationForConnectBehavior(behavior, device: selectedDevice)
        bumpConnectBehaviorRevision()
    }

    func shouldRestorePersistedSettingsOnConnect(for device: MouseDevice) -> Bool {
        connectBehavior(for: device) == .restoreOpenSnekSettings
    }

    func buildCurrentSettingsSnapshot(
        for device: MouseDevice,
        preservingStoredLighting: Bool = false,
        lightingZoneOverride: String? = nil
    ) -> PersistedDeviceSettingsSnapshot? {
        guard deviceStore.selectedDevice?.id == device.id else { return nil }
        let count = DeviceProfiles.clampDpiStageCount(editorStore.editableStageCount)
        let stageValues = Array(editorStore.editableStageValues.prefix(count)).map {
            DeviceProfiles.clampDPI($0, profileID: device.profile_id)
        }
        let stagePairs = Array(editorStore.editableStagePairs.prefix(count)).map { pair in
            DpiPair(
                x: DeviceProfiles.clampDPI(pair.x, profileID: device.profile_id),
                y: DeviceProfiles.clampDPI(pair.y, profileID: device.profile_id)
            )
        }
        let storedSnapshot = preservingStoredLighting ? loadPersistedSettingsSnapshot(device: device) : nil
        let primaryLightingColor: RGBColor
        let lightingEffect: LightingEffectPatch?
        let lightingZoneID: String
        if let storedSnapshot {
            primaryLightingColor = storedSnapshot.primaryLightingColor ?? editorStore.editableColor
            lightingEffect = storedSnapshot.lightingEffect
            lightingZoneID = lightingZoneOverride ?? storedSnapshot.usbLightingZoneID
        } else {
            primaryLightingColor = editorStore.editableColor
            lightingEffect = device.supports_advanced_lighting_effects ? currentLightingEffectPatch() : nil
            lightingZoneID = lightingZoneOverride ??
                (lightingEffect?.kind == .staticColor ? editorStore.editableUSBLightingZoneID : "all")
        }
        return PersistedDeviceSettingsSnapshot(
            stageCount: count,
            stageValues: stageValues,
            stagePairs: stagePairs,
            activeStage: max(1, min(count, editorStore.editableActiveStage)),
            pollRate: editorStore.editablePollRate,
            sleepTimeout: editorStore.editableSleepTimeout,
            lowBatteryThresholdRaw: editorStore.editableLowBatteryThresholdRaw,
            scrollMode: device.supportsScrollModeControls ? editorStore.editableScrollMode : nil,
            scrollAcceleration: device.supportsScrollModeControls ? editorStore.editableScrollAcceleration : nil,
            scrollSmartReel: device.supportsScrollModeControls ? editorStore.editableScrollSmartReel : nil,
            ledBrightness: device.supportsLightingBrightnessControls ? editorStore.editableLedBrightness : nil,
            primaryLightingColor: primaryLightingColor,
            lightingEffect: lightingEffect,
            usbLightingZoneID: lightingZoneID,
            buttonBindings: editorStore.editableButtonBindings
        )
    }

    func persistCurrentSettingsSnapshot(
        for device: MouseDevice,
        preservingStoredLighting: Bool = false,
        lightingZoneOverride: String? = nil
    ) {
        guard let snapshot = buildCurrentSettingsSnapshot(
            for: device,
            preservingStoredLighting: preservingStoredLighting,
            lightingZoneOverride: lightingZoneOverride
        ) else { return }
        persistSettingsSnapshot(snapshot, device: device)
    }

    func persistSettingsSnapshot(_ snapshot: PersistedDeviceSettingsSnapshot, device: MouseDevice) {
        preferenceStore.persistDeviceSettingsSnapshot(snapshot, device: device)
    }

    func loadPersistedSettingsSnapshot(device: MouseDevice) -> PersistedDeviceSettingsSnapshot? {
        preferenceStore.loadPersistedDeviceSettingsSnapshot(device: device)
    }

    func persistSuccessfulPatchFieldsInSettingsSnapshot(
        patch: DevicePatch,
        device: MouseDevice,
        lightingZoneID: String
    ) {
        guard patch.ledBrightness != nil || patch.ledRGB != nil || patch.lightingEffect != nil else { return }

        var snapshot = loadPersistedSettingsSnapshot(device: device)
        if snapshot == nil, deviceStore.selectedDevice?.id == device.id {
            persistCurrentSettingsSnapshot(for: device)
            snapshot = loadPersistedSettingsSnapshot(device: device)
        }
        guard var snapshot else { return }

        if let ledBrightness = patch.ledBrightness {
            snapshot.ledBrightness = ledBrightness
        }

        if let lightingEffect = patch.lightingEffect {
            snapshot.primaryLightingColor = RGBColor(
                r: lightingEffect.primary.r,
                g: lightingEffect.primary.g,
                b: lightingEffect.primary.b
            )
            snapshot.lightingEffect = lightingEffect
            snapshot.usbLightingZoneID = lightingEffect.kind == .staticColor
                ? normalizedLightingZoneID(for: device, preferredZoneID: lightingZoneID)
                : "all"
        } else if let ledRGB = patch.ledRGB {
            snapshot.primaryLightingColor = RGBColor(r: ledRGB.r, g: ledRGB.g, b: ledRGB.b)
            snapshot.lightingEffect = device.supports_advanced_lighting_effects
                ? LightingEffectPatch(kind: .staticColor, primary: ledRGB)
                : nil
            snapshot.usbLightingZoneID = normalizedLightingZoneID(for: device, preferredZoneID: lightingZoneID)
        }

        persistSettingsSnapshot(snapshot, device: device)
    }

    func hydrateEditable(from state: MouseState) {
        guard !isTearingDown else { return }
        isHydrating = true
        defer { isHydrating = false }

        handleActiveOnboardProfilePresentation(from: state)

        let activeOnboardSnapshot = currentActiveOnboardProfileSnapshot(for: state)
        let shouldHydrateRawDPI = shouldHydrateDPIFromRawStateWithoutActiveOnboardSnapshot(for: state)
        logDPITrace(
            "hydrateEditable start",
            state: state,
            snapshot: activeOnboardSnapshot,
            extra: "activeSnapshot=\(activeOnboardSnapshot.map { String($0.profileID) } ?? "nil") rawAllowed=\(shouldHydrateRawDPI)"
        )
        if let snapshot = activeOnboardSnapshot,
           let dpi = snapshot.dpi,
           let device = deviceStore.selectedDevice {
            hydrateEditableDPI(from: dpi, device: device, liveDPI: state.dpi, source: "hydrateEditable.snapshot")
        } else if shouldHydrateRawDPI,
                  let pairs = state.dpi_stages.pairs,
                  !pairs.isEmpty {
            editorStore.editableStageCount = DeviceProfiles.clampDpiStageCount(pairs.count)
            let profileID = deviceStore.selectedDevice?.profile_id
            for index in 0..<editorStore.editableStagePairs.count where index < pairs.count {
                editorStore.editableStagePairs[index] = DpiPair(
                    x: DeviceProfiles.clampDPI(pairs[index].x, profileID: profileID),
                    y: DeviceProfiles.clampDPI(pairs[index].y, profileID: profileID)
                )
            }
        } else if shouldHydrateRawDPI,
                  let values = state.dpi_stages.values,
                  !values.isEmpty {
            editorStore.editableStageCount = DeviceProfiles.clampDpiStageCount(values.count)
            let profileID = deviceStore.selectedDevice?.profile_id
            for index in 0..<editorStore.editableStageValues.count where index < values.count {
                editorStore.editableStageValues[index] = DeviceProfiles.clampDPI(values[index], profileID: profileID)
            }
        } else if shouldHydrateRawDPI,
                  let dpi = state.dpi?.x {
            editorStore.editableStageCount = 1
            let clampedX = DeviceProfiles.clampDPI(dpi, profileID: deviceStore.selectedDevice?.profile_id)
            let clampedY = DeviceProfiles.clampDPI(state.dpi?.y ?? dpi, profileID: deviceStore.selectedDevice?.profile_id)
            editorStore.editableStagePairs[0] = DpiPair(x: clampedX, y: clampedY)
        }

        if activeOnboardSnapshot?.dpi == nil {
            let maxStage = max(1, editorStore.editableStageCount)
            let liveMatchedStage = liveMatchedEditableStage(from: state, maxStage: maxStage)
            let stateStage = state.dpi_stages.active_stage.map { $0 + 1 }
            let nextStage = liveMatchedStage ?? stateStage ?? 1
            editorStore.setEditableActiveStage(
                max(1, min(maxStage, nextStage)),
                source: "hydrateEditable.state liveMatched=\(liveMatchedStage.map(String.init) ?? "nil") " +
                    "state=\(stateStage.map(String.init) ?? "nil")"
            )
        }
        editorStore.normalizeExpandedXYStages()

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

        if let snapshot = activeOnboardSnapshot,
           let device = deviceStore.selectedDevice {
            AppLog.debug(
                "AppState",
                "hydrateEditable.scroll source=stateWithActiveOnboardSnapshotFallback device=\(device.id) " +
                "profile=\(snapshot.profileID) state=\(Self.diagnosticScrollState(state)) " +
                "snapshot=\(Self.diagnosticScrollSnapshot(snapshot))"
            )
            hydrateEditableLighting(from: snapshot, device: device)
            hydrateEditableScroll(from: state, fallbackSnapshot: snapshot)
        } else {
            AppLog.debug(
                "AppState",
                "hydrateEditable.scroll source=state device=\(deviceStore.selectedDeviceID ?? "nil") " +
                "state=\(Self.diagnosticScrollState(state))"
            )
            hydrateEditableScroll(from: state)
            if let led = state.led_value {
                editorStore.editableLedBrightness = led
            }
        }

        syncUSBButtonProfileSelection(from: state)
        logDPITrace(
            "hydrateEditable end",
            state: state,
            snapshot: activeOnboardSnapshot,
            extra: "rawAllowed=\(shouldHydrateRawDPI)"
        )
    }

    private func shouldHydrateDPIFromRawStateWithoutActiveOnboardSnapshot(for state: MouseState) -> Bool {
        guard let device = deviceStore.selectedDevice else { return true }
        guard supportsOnboardProfileCRUD(device: device) else { return true }
        let hasProfileScopedDPI = device.onboard_profile_count > 1 ||
            state.active_onboard_profile != nil ||
            deviceStore.state?.active_onboard_profile != nil ||
            selectedOnboardProfileIDByDeviceID[device.id] != nil
        return !hasProfileScopedDPI
    }

    func hydrateLiveDpiPresentation(from state: MouseState) {
        guard !isTearingDown else { return }
        isHydrating = true
        defer {
            applyController.clearPendingActiveStageSelectionIfConfirmed(by: state, for: deviceStore.selectedDevice)
            isHydrating = false
        }

        handleActiveOnboardProfilePresentation(from: state)

        let pendingActiveStage = applyController.pendingActiveStageSelection(for: deviceStore.selectedDevice)
        let activeSnapshot = currentActiveOnboardProfileSnapshot(for: state)
        logDPITrace(
            "hydrateLiveDpi start",
            state: state,
            snapshot: activeSnapshot,
            extra: "pendingActive=\(pendingActiveStage.map(String.init) ?? "nil") shouldHydrateEditable=\(deviceStore.selectedDevice.map { applyController.shouldHydrateEditable(for: $0) } ?? false)"
        )
        if let snapshot = activeSnapshot,
           let dpi = snapshot.dpi,
           let device = deviceStore.selectedDevice {
            if applyController.shouldHydrateEditable(for: device) {
                hydrateEditableDPI(
                    from: dpi,
                    device: device,
                    liveDPI: state.dpi,
                    activeStageOverride: pendingActiveStage,
                    source: "hydrateLiveDpi.snapshot pending=\(pendingActiveStage.map(String.init) ?? "nil")"
                )
            } else {
                hydrateLiveDpiActiveStageOnly(
                    from: state,
                    snapshotDPI: dpi,
                    pendingActiveStage: pendingActiveStage,
                    source: "hydrateLiveDpi.pendingLocalSnapshot"
                )
            }
        } else if state.dpi_stages.active_stage != nil {
            let maxStage = max(1, editorStore.editableStageCount)
            let liveMatchedStage = liveMatchedEditableStage(from: state, maxStage: maxStage)
            let stateStage = state.dpi_stages.active_stage.map { $0 + 1 }
            let nextStage = pendingActiveStage ?? liveMatchedStage ?? stateStage ?? editorStore.editableActiveStage
            editorStore.setEditableActiveStage(
                max(1, min(maxStage, nextStage)),
                source: "hydrateLiveDpi.state pending=\(pendingActiveStage.map(String.init) ?? "nil") " +
                    "liveMatched=\(liveMatchedStage.map(String.init) ?? "nil") " +
                    "state=\(stateStage.map(String.init) ?? "nil")"
            )
        } else {
            let maxStage = max(1, editorStore.editableStageCount)
            let liveMatchedStage = liveMatchedEditableStage(from: state, maxStage: maxStage)
            editorStore.setEditableActiveStage(
                max(1, min(maxStage, pendingActiveStage ?? liveMatchedStage ?? 1)),
                source: "hydrateLiveDpi.state missing-active pending=\(pendingActiveStage.map(String.init) ?? "nil") " +
                    "liveMatched=\(liveMatchedStage.map(String.init) ?? "nil")"
            )
        }

        if applyController.shouldHydrateEditable,
           editorStore.editableStageCount == 1,
           let dpi = state.dpi?.x {
            let clampedX = DeviceProfiles.clampDPI(dpi, profileID: deviceStore.selectedDevice?.profile_id)
            let clampedY = DeviceProfiles.clampDPI(state.dpi?.y ?? dpi, profileID: deviceStore.selectedDevice?.profile_id)
            editorStore.editableStagePairs[0] = DpiPair(x: clampedX, y: clampedY)
        }

        editorStore.normalizeExpandedXYStages()
        logDPITrace(
            "hydrateLiveDpi end",
            state: state,
            snapshot: activeSnapshot,
            extra: "pendingActive=\(pendingActiveStage.map(String.init) ?? "nil")"
        )
    }

    func hydrateLiveDpiActiveStageOnly(
        from state: MouseState,
        snapshotDPI: OnboardDPIProfileSnapshot,
        pendingActiveStage: Int?,
        source: String
    ) {
        let maxStage = max(1, editorStore.editableStageCount)
        let liveMatchedStage = state.dpi.flatMap { liveDPI in
            Self.uniqueDPIStageIndex(matching: liveDPI, in: snapshotDPI.pairs)
        }.map { $0 + 1 }
        let snapshotStage = snapshotDPI.activeStage.map { $0 + 1 }
        let stateStage = state.dpi_stages.active_stage.map { $0 + 1 }
        let nextStage = pendingActiveStage ?? liveMatchedStage ?? snapshotStage ?? stateStage ?? editorStore.editableActiveStage
        let clampedStage = max(1, min(maxStage, nextStage))
        let pendingDescription = pendingActiveStage.map(String.init) ?? "nil"
        let liveMatchedDescription = liveMatchedStage.map(String.init) ?? "nil"
        let snapshotDescription = snapshotStage.map(String.init) ?? "nil"
        let stateDescription = stateStage.map(String.init) ?? "nil"
        let hydrationSource =
            "\(source) pending=\(pendingDescription) " +
            "liveMatched=\(liveMatchedDescription) " +
            "snapshot=\(snapshotDescription) " +
            "state=\(stateDescription)"
        editorStore.setEditableActiveStage(
            clampedStage,
            source: hydrationSource
        )
        logDPITrace(
            "hydrateLiveDpi active-stage-only",
            state: state,
            extra: "source=\(source) pending=\(pendingDescription) liveMatched=\(liveMatchedDescription) snapshot=\(snapshotDescription) state=\(stateDescription) chosen=\(clampedStage)"
        )
    }

    func liveMatchedEditableStage(from state: MouseState, maxStage: Int) -> Int? {
        guard maxStage > 0,
              let liveDPI = state.dpi else {
            return nil
        }
        let visiblePairs = Array(editorStore.editableStagePairs.prefix(maxStage))
        return Self.uniqueDPIStageIndex(matching: liveDPI, in: visiblePairs).map { $0 + 1 }
    }

    func logDPITrace(
        _ action: String,
        device: MouseDevice? = nil,
        state: MouseState? = nil,
        snapshot: OnboardProfileSnapshot? = nil,
        extra: String = ""
    ) {
        let resolvedDevice = device ?? deviceStore.selectedDevice
        let loadedSnapshot = snapshot ?? resolvedDevice.flatMap { currentOnboardProfileSnapshotByDeviceID[$0.id] }
        let extraSuffix = extra.isEmpty ? "" : " \(extra)"
        let processContext = "role=\(environment.launchRole.rawValue) pid=\(ProcessInfo.processInfo.processIdentifier)"
        let line = "\(action) \(processContext) device=\(resolvedDevice?.id ?? "nil") " +
            "state={\(Self.diagnosticDPIState(state ?? deviceStore.state))} " +
            "snapshot={\(diagnosticDPISnapshot(loadedSnapshot, device: resolvedDevice))} " +
            "visible={\(diagnosticDPIVisible(device: resolvedDevice))}" +
            extraSuffix
        guard lastDPITraceLineByAction[action] != line else { return }
        lastDPITraceLineByAction[action] = line
        AppLog.warning(
            "DPITrace",
            line
        )
    }

    func diagnosticDPIVisible(device: MouseDevice?) -> String {
        let deviceID = device?.id
        let selected = deviceID.flatMap { selectedOnboardProfileIDByDeviceID[$0] }
        let inventory = deviceID.flatMap { onboardProfileInventoryByDeviceID[$0] }
        let active = inventory?.activeProfileID ?? deviceStore.state?.active_onboard_profile
        let selectedName = selected.flatMap { inventory?.summary(for: $0)?.displayName } ?? "nil"
        let count = DeviceProfiles.clampDpiStageCount(editorStore.editableStageCount)
        let pairs = Array(editorStore.editableStagePairs.prefix(count))
        return [
            "selectedProfile=\(selected.map(String.init) ?? "nil")",
            "selectedName=\(selectedName)",
            "inventoryActive=\(active.map(String.init) ?? "nil")",
            "editorCount=\(count)",
            "editorActive=\(editorStore.editableActiveStage)",
            "editorPairs=\(Self.diagnosticDpiPairs(pairs))"
        ].joined(separator: " ")
    }

    func diagnosticDPISnapshot(_ snapshot: OnboardProfileSnapshot?, device: MouseDevice?) -> String {
        guard let snapshot else { return "nil" }
        let dpi = snapshot.dpi
        return [
            "profile=\(snapshot.profileID)",
            "name=\(snapshot.metadata.name)",
            "dpiCount=\(dpi?.stageCount ?? 0)",
            "dpiActive=\(dpi?.activeStage.map { String($0 + 1) } ?? "nil")",
            "dpiPairs=\(Self.diagnosticDpiPairs(dpi?.pairs ?? []))",
            "stageIDs=\(Self.diagnosticByteValues(dpi?.stageIDs ?? []))"
        ].joined(separator: " ")
    }

    nonisolated static func diagnosticDPIState(_ state: MouseState?) -> String {
        guard let state else { return "nil" }
        let activeProfile = state.active_onboard_profile.map(String.init) ?? "nil"
        let profileCount = state.onboard_profile_count.map(String.init) ?? "nil"
        let activeStage = state.dpi_stages.active_stage.map { String($0 + 1) } ?? "nil"
        let values = state.dpi_stages.values?.map(String.init).joined(separator: ",") ?? "nil"
        let pairs = diagnosticDpiPairs(state.dpi_stages.pairs ?? [])
        return [
            "activeProfile=\(activeProfile)",
            "profileCount=\(profileCount)",
            "liveDPI=\(diagnosticDpiPair(state.dpi))",
            "stageActive=\(activeStage)",
            "values=\(values)",
            "pairs=\(pairs)"
        ].joined(separator: " ")
    }

    nonisolated static func diagnosticDpiPair(_ pair: DpiPair?) -> String {
        guard let pair else { return "nil" }
        return pair.x == pair.y ? String(pair.x) : "\(pair.x)x\(pair.y)"
    }

    nonisolated static func diagnosticDpiPairs(_ pairs: [DpiPair]) -> String {
        guard !pairs.isEmpty else { return "nil" }
        return pairs.map(diagnosticDpiPair).joined(separator: ",")
    }

    nonisolated static func diagnosticByteValues(_ values: [UInt8]) -> String {
        guard !values.isEmpty else { return "nil" }
        return values.map { String(format: "%02X", $0) }.joined(separator: ",")
    }

    func hydrateLightingStateIfNeeded(device: MouseDevice) async {
        guard !isTearingDown else { return }
        hydrateSoftwareLightingPreferenceStateIfNeeded(device: device)
        guard device.showsLightingControls else {
            editorStore.editableUSBLightingZoneID = "all"
            editorStore.editableLightingEffect = .staticColor
            hydratedLightingStateByDeviceID.insert(device.id)
            return
        }

        if hydratePersistedLightingStateIfNeeded(device: device) {
            return
        }

        guard !hydratedLightingStateByDeviceID.contains(device.id) else { return }
        if device.transport == .bluetooth,
                  let rgb = try? await environment.backend.readLightingColor(device: device) {
            guard !isTearingDown else { return }
            editorStore.editableColor = RGBColor(r: rgb.r, g: rgb.g, b: rgb.b)
            persistLightingColor(editorStore.editableColor, device: device)
            editorStore.editableUSBLightingZoneID = "all"
            if !device.supports_advanced_lighting_effects {
                editorStore.editableLightingEffect = .staticColor
            }
            ensureEditableStaticLightingZoneSelection()
            AppLog.debug("AppState", "hydrated Bluetooth lighting color from device id=\(device.id) rgb=(\(rgb.r),\(rgb.g),\(rgb.b))")
        } else {
            editorStore.editableUSBLightingZoneID = "all"
            if !device.supports_advanced_lighting_effects {
                editorStore.editableLightingEffect = .staticColor
            }
            ensureEditableStaticLightingZoneSelection()
            AppLog.debug("AppState", "lighting color read unavailable for device id=\(device.id)")
        }

        hydratedLightingStateByDeviceID.insert(device.id)
    }

    @discardableResult
    func hydratePersistedLightingStateIfNeeded(device: MouseDevice) -> Bool {
        guard !isTearingDown else { return false }
        hydrateSoftwareLightingPreferenceStateIfNeeded(device: device)
        guard !hydratedLightingStateByDeviceID.contains(device.id) else { return false }
        let plan = persistedLightingPresentationPlan(device: device)
        guard let plan else { return false }

        applyPersistedLightingRestorePlanToEditor(plan)
        AppLog.debug(
            "AppState",
            "hydrated lighting restore plan from persisted cache id=\(device.id) " +
                "kind=\(plan.lightingEffect?.kind.rawValue ?? "static") zone=\(plan.usbLightingZoneID)"
        )
        hydratedLightingStateByDeviceID.insert(device.id)
        return true
    }

    @discardableResult
    func hydrateConnectPresentationIfNeeded(device: MouseDevice) -> Bool {
        guard !isTearingDown else { return false }
        hydrateSoftwareLightingPreferenceStateIfNeeded(device: device)
        guard shouldRestorePersistedSettingsOnConnect(for: device),
              let snapshot = loadPersistedSettingsSnapshot(device: device) else {
            _ = hydratePersistedLightingStateIfNeeded(device: device)
            return false
        }
        applyPersistedSettingsSnapshotToEditor(snapshot, device: device)
        markSingleSlotPersistedSettingsPresentedForRestore(snapshot: snapshot, device: device)
        return true
    }

    func applyPersistedSettingsSnapshotToEditor(_ snapshot: PersistedDeviceSettingsSnapshot, device: MouseDevice) {
        let count = DeviceProfiles.clampDpiStageCount(snapshot.stageCount)
        editorStore.editableStageCount = count
        for index in 0..<editorStore.editableStagePairs.count {
            if index < snapshot.stagePairs.count {
                let pair = snapshot.stagePairs[index]
                editorStore.editableStagePairs[index] = DpiPair(
                    x: DeviceProfiles.clampDPI(pair.x, profileID: device.profile_id),
                    y: DeviceProfiles.clampDPI(pair.y, profileID: device.profile_id)
                )
            } else if index < snapshot.stageValues.count {
                let value = DeviceProfiles.clampDPI(snapshot.stageValues[index], profileID: device.profile_id)
                editorStore.editableStagePairs[index] = DpiPair(x: value, y: value)
            }
        }
        editorStore.setEditableActiveStage(
            max(1, min(count, snapshot.activeStage)),
            source: "hydrateConnectPresentation.snapshot active=\(snapshot.activeStage)"
        )
        editorStore.normalizeExpandedXYStages()

        if let pollRate = snapshot.pollRate {
            editorStore.editablePollRate = pollRate
        }
        if let sleepTimeout = snapshot.sleepTimeout {
            editorStore.editableSleepTimeout = max(60, min(900, sleepTimeout))
        }
        if let lowBatteryThresholdRaw = snapshot.lowBatteryThresholdRaw {
            editorStore.editableLowBatteryThresholdRaw = max(0x0C, min(0x3F, lowBatteryThresholdRaw))
        }
        AppLog.debug(
            "AppState",
            "hydrateConnectPresentation.scroll source=persistedSnapshot device=\(device.id) " +
            "snapshot=\(Self.diagnosticScrollSnapshot(snapshot))"
        )
        if let scrollMode = snapshot.scrollMode {
            editorStore.editableScrollMode = max(0, min(1, scrollMode))
        }
        if let scrollAcceleration = snapshot.scrollAcceleration {
            editorStore.editableScrollAcceleration = scrollAcceleration
        }
        if let scrollSmartReel = snapshot.scrollSmartReel {
            editorStore.editableScrollSmartReel = scrollSmartReel
        }
        if let ledBrightness = snapshot.ledBrightness,
           device.supportsLightingBrightnessControls {
            editorStore.editableLedBrightness = ledBrightness
        }
        if let primaryColor = snapshot.primaryLightingColor {
            editorStore.editableColor = primaryColor
        }
        editorStore.editableUSBLightingZoneID = snapshot.usbLightingZoneID
        if let lightingEffect = snapshot.lightingEffect {
            editorStore.editableLightingEffect = lightingEffect.kind
            editorStore.editableLightingWaveDirection = lightingEffect.waveDirection
            editorStore.editableLightingReactiveSpeed = lightingEffect.reactiveSpeed
            editorStore.editableSecondaryColor = RGBColor(
                r: lightingEffect.secondary.r,
                g: lightingEffect.secondary.g,
                b: lightingEffect.secondary.b
            )
        } else {
            editorStore.editableLightingEffect = .staticColor
        }
        ensureEditableStaticLightingZoneSelection()

        editorStore.editableButtonBindings = snapshot.buttonBindings
        hydratedButtonBindingsKey = nil
        hydratedLightingStateByDeviceID.insert(device.id)
    }

    func persistLightingColor(_ color: RGBColor, device: MouseDevice, zoneID: String? = nil) {
        preferenceStore.persistLightingColor(color, device: device, zoneID: zoneID)
    }

    func loadPersistedLightingColor(device: MouseDevice, zoneID: String? = nil) -> RGBColor? {
        preferenceStore.loadPersistedLightingColor(device: device, zoneID: zoneID)
    }

    func persistLightingZoneID(_ zoneID: String, device: MouseDevice) {
        preferenceStore.persistLightingZoneID(zoneID, device: device)
    }

    func loadPersistedLightingZoneID(device: MouseDevice) -> String? {
        preferenceStore.loadPersistedLightingZoneID(device: device)
    }

    func persistLightingEffect(_ effect: LightingEffectPatch, device: MouseDevice) {
        preferenceStore.persistLightingEffect(effect, device: device)
    }

    func loadPersistedLightingEffect(device: MouseDevice) -> PersistedLightingEffectPreference? {
        preferenceStore.loadPersistedLightingEffect(device: device)
    }

    func hydrateSoftwareLightingPreferenceStateIfNeeded(device: MouseDevice) {
        guard !hydratedSoftwareLightingPreferencesByDeviceID.contains(device.id) else { return }
        defer { hydratedSoftwareLightingPreferencesByDeviceID.insert(device.id) }

        guard device.supportsSoftwareLightingEffects else {
            editorStore.editableSoftwareLightingApplyOnConnect = false
            return
        }

        editorStore.editableSoftwareLightingApplyOnConnect = preferenceStore
            .loadSoftwareLightingApplyOnConnect(device: device)
        if let request = preferenceStore.loadPersistedSoftwareLightingRequest(device: device) {
            editorStore.applySoftwareLightingEffectRequest(request)
        }
    }

    func updateSoftwareLightingApplyOnConnect(_ enabled: Bool) {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        guard selectedDevice.supportsSoftwareLightingEffects else {
            editorStore.editableSoftwareLightingApplyOnConnect = false
            return
        }

        editorStore.editableSoftwareLightingApplyOnConnect = enabled
        preferenceStore.persistSoftwareLightingApplyOnConnect(enabled, device: selectedDevice)
        if enabled {
            preferenceStore.persistSoftwareLightingRequest(
                editorStore.softwareLightingEffectRequest(),
                device: selectedDevice
            )
        }
    }

}
