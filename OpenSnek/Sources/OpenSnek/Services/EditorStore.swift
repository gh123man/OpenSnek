import Foundation
import Observation
import OpenSnekAppSupport
import OpenSnekCore

@MainActor
@Observable
final class EditorStore {
    @ObservationIgnored let deviceStore: DeviceStore
    var editableStageValues: [Int] = [800, 1600, 3200, 6400, 12000] {
        didSet {
            guard !isSyncingEditableStageRepresentations else { return }
            syncEditableStagePairsFromValues()
        }
    }
    var editableStagePairs: [DpiPair] = [
        DpiPair(x: 800, y: 800),
        DpiPair(x: 1600, y: 1600),
        DpiPair(x: 3200, y: 3200),
        DpiPair(x: 6400, y: 6400),
        DpiPair(x: 12000, y: 12000)
    ] {
        didSet {
            guard !isSyncingEditableStageRepresentations else { return }
            isSyncingEditableStageRepresentations = true
            editableStageValues = editableStagePairs.map(\.x)
            isSyncingEditableStageRepresentations = false
        }
    }
    var editableStageCount = 3
    var editableActiveStage = 1 {
        didSet {
            guard oldValue != editableActiveStage else { return }
            logEditableActiveStageMutation(oldValue: oldValue, newValue: editableActiveStage)
        }
    }
    var expandedXYStageIndices: Set<Int> = []
    var editablePollRate = 1000
    var editableSleepTimeout = 300
    var editableDeviceMode = 0x00
    var editableLowBatteryThresholdRaw = 0x26
    var editableScrollMode = 0 {
        didSet {
            guard oldValue != editableScrollMode else { return }
            logEditableScrollMutation(field: "mode", oldValue: String(oldValue), newValue: String(editableScrollMode))
        }
    }
    var editableScrollAcceleration = false {
        didSet {
            guard oldValue != editableScrollAcceleration else { return }
            logEditableScrollMutation(
                field: "accel",
                oldValue: String(oldValue),
                newValue: String(editableScrollAcceleration)
            )
        }
    }
    var editableScrollSmartReel = false {
        didSet {
            guard oldValue != editableScrollSmartReel else { return }
            logEditableScrollMutation(
                field: "smart",
                oldValue: String(oldValue),
                newValue: String(editableScrollSmartReel)
            )
        }
    }
    var editableLedBrightness = 64
    var editableLightingEffect: LightingEffectKind = .staticColor
    var editableSoftwareLightingPreset: SoftwareLightingPresetID = .flame
    var editableSoftwareLightingSpeed = SoftwareLightingPresetID.flame.defaultSpeed
    var editableSoftwareLightingBrightness = 1.0
    var editableSoftwareLightingPalettes: [SoftwareLightingPresetID: [RGBColor]] = [:]
    var editableSoftwareLightingApplyOnConnect = false
    var editableUSBLightingZoneID: String = "all"
    var editableUSBButtonProfile = 1
    var editableLightingWaveDirection: LightingWaveDirection = .left
    var editableLightingReactiveSpeed = 2
    var editableColor = RGBColor(r: 0, g: 255, b: 0)
    var editableSecondaryColor = RGBColor(r: 0, g: 170, b: 255)
    var editableButtonBindings: [Int: ButtonBindingDraft] = [:]
    var lightingGradientRevision: UInt64 = 0
    var isEditingDpiControl = false
    var isButtonProfileOperationInFlight = false
    var buttonProfileOperationStatusText: String?
    var isOnboardProfileRefreshInFlight = false
    var onboardProfileRefreshErrorMessage: String?
    var isOnboardProfileLoadInFlight = false
    var onboardProfileLoadStatusText: String?
    var usbButtonProfilesRevision = 0
    var onboardProfilesRevision = 0
    var connectBehaviorRevision = 0

    @ObservationIgnored private weak var editorControllerStorage: AppStateEditorController?
    @ObservationIgnored private weak var applyControllerStorage: AppStateApplyController?
    @ObservationIgnored private var buttonProfileOperationIDs: Set<UUID> = []
    @ObservationIgnored private var buttonProfileOperationOrder: [UUID] = []
    @ObservationIgnored private var buttonProfileOperationStatusByID: [UUID: String] = [:]
    @ObservationIgnored private var onboardProfileLoadOperationIDs: Set<UUID> = []
    @ObservationIgnored private var onboardProfileLoadOperationOrder: [UUID] = []
    @ObservationIgnored private var onboardProfileLoadOperationStatusByID: [UUID: String] = [:]
    @ObservationIgnored private var isSyncingEditableStageRepresentations = false
    @ObservationIgnored private var editableActiveStageMutationSource: String?

    init(deviceStore: DeviceStore) {
        self.deviceStore = deviceStore
        editableSoftwareLightingPalettes = Self.defaultSoftwareLightingPalettes()
        syncEditableStagePairsFromValues()
    }

    private static func defaultSoftwareLightingPalettes() -> [SoftwareLightingPresetID: [RGBColor]] {
        Dictionary(
            uniqueKeysWithValues: SoftwareLightingPresetID.allCases.map { preset in
                (
                    preset,
                    preset.defaultPalette.map { RGBColor(r: $0.r, g: $0.g, b: $0.b) }
                )
            }
        )
    }

    private func syncEditableStagePairsFromValues() {
        guard !isSyncingEditableStageRepresentations else { return }
        isSyncingEditableStageRepresentations = true
        editableStagePairs = editableStageValues.map { DpiPair(x: $0, y: $0) }
        isSyncingEditableStageRepresentations = false
    }

    func setEditableActiveStage(_ stage: Int, source: String) {
        let previousSource = editableActiveStageMutationSource
        editableActiveStageMutationSource = source
        editableActiveStage = stage
        editableActiveStageMutationSource = previousSource
    }

    private func logEditableActiveStageMutation(oldValue: Int, newValue: Int) {
        let source = editableActiveStageMutationSource ?? "<direct>"
        let selectedDeviceID = deviceStore.selectedDeviceID ?? "nil"
        let stateActive = deviceStore.state?.dpi_stages.active_stage.map(String.init) ?? "nil"
        let stateValues = deviceStore.state?.dpi_stages.values?.map(String.init).joined(separator: ",") ?? "nil"
        let stateDpi = deviceStore.state?.dpi.map { "(\($0.x),\($0.y))" } ?? "nil"
        let pendingActive = applyControllerStorage?
            .pendingActiveStageSelection(for: deviceStore.selectedDevice)
            .map(String.init) ?? "nil"
        let pendingLocal = applyControllerStorage?.hasPendingLocalEdits ?? false
        let isHydrating = editorControllerStorage?.isHydrating ?? false

        AppLog.debug(
            "AppState",
            "editableActiveStage \(oldValue)->\(newValue) source=\(source) " +
            "selected=\(selectedDeviceID) hydrating=\(isHydrating) applying=\(deviceStore.isApplying) " +
            "pendingLocal=\(pendingLocal) pendingActive=\(pendingActive) " +
            "stateActive=\(stateActive) stateDpi=\(stateDpi) stateValues=\(stateValues) " +
            "editCount=\(editableStageCount)"
        )
    }

    private func logEditableScrollMutation(field: String, oldValue: String, newValue: String) {
        let selectedDeviceID = deviceStore.selectedDeviceID ?? "nil"
        let pendingActive = applyControllerStorage?
            .pendingActiveStageSelection(for: deviceStore.selectedDevice)
            .map(String.init) ?? "nil"
        let pendingLocal = applyControllerStorage?.hasPendingLocalEdits ?? false
        let isHydrating = editorControllerStorage?.isHydrating ?? false

        AppLog.debug(
            "AppState",
            "editableScroll \(field) \(oldValue)->\(newValue) " +
            "selected=\(selectedDeviceID) hydrating=\(isHydrating) applying=\(deviceStore.isApplying) " +
            "pendingLocal=\(pendingLocal) pendingActive=\(pendingActive) " +
            "stateScroll=\(Self.diagnosticScrollState(deviceStore.state)) " +
            "editorScroll=mode=\(editableScrollMode),accel=\(editableScrollAcceleration),smart=\(editableScrollSmartReel)"
        )
    }

    private static func diagnosticScrollState(_ state: MouseState?) -> String {
        guard let state else { return "nil" }
        return "mode=\(state.scroll_mode.map(String.init) ?? "nil")," +
            "accel=\(state.scroll_acceleration.map(String.init) ?? "nil")," +
            "smart=\(state.scroll_smart_reel.map(String.init) ?? "nil")"
    }

    func bind(
        editorController: AppStateEditorController,
        applyController: AppStateApplyController
    ) {
        self.editorControllerStorage = editorController
        self.applyControllerStorage = applyController
    }

    private var editorController: AppStateEditorController {
        guard let editorControllerStorage else {
            preconditionFailure("EditorStore accessed before editorController was bound")
        }
        return editorControllerStorage
    }

    private var applyController: AppStateApplyController {
        guard let applyControllerStorage else {
            preconditionFailure("EditorStore accessed before applyController was bound")
        }
        return applyControllerStorage
    }

    @discardableResult
    func beginButtonProfileOperation(statusText: String) -> UUID {
        let operationID = UUID()
        buttonProfileOperationIDs.insert(operationID)
        buttonProfileOperationOrder.append(operationID)
        buttonProfileOperationStatusByID[operationID] = statusText
        refreshButtonProfileOperationPresentation()
        return operationID
    }

    func endButtonProfileOperation(_ operationID: UUID) {
        guard buttonProfileOperationIDs.remove(operationID) != nil else { return }
        buttonProfileOperationStatusByID.removeValue(forKey: operationID)
        buttonProfileOperationOrder.removeAll { $0 == operationID }
        refreshButtonProfileOperationPresentation()
    }

    private func refreshButtonProfileOperationPresentation() {
        guard let operationID = buttonProfileOperationOrder.last(where: { buttonProfileOperationIDs.contains($0) }) else {
            isButtonProfileOperationInFlight = false
            buttonProfileOperationStatusText = nil
            return
        }
        isButtonProfileOperationInFlight = true
        buttonProfileOperationStatusText = buttonProfileOperationStatusByID[operationID]
    }

    private func withButtonProfileOperation<T>(
        statusText: String,
        _ operation: @escaping @MainActor () async -> T
    ) async -> T {
        let operationID = beginButtonProfileOperation(statusText: statusText)
        defer {
            endButtonProfileOperation(operationID)
        }
        return await operation()
    }

    @discardableResult
    func beginOnboardProfileLoad(statusText: String) -> UUID {
        let operationID = UUID()
        onboardProfileLoadOperationIDs.insert(operationID)
        onboardProfileLoadOperationOrder.append(operationID)
        onboardProfileLoadOperationStatusByID[operationID] = statusText
        refreshOnboardProfileLoadPresentation()
        return operationID
    }

    func endOnboardProfileLoad(_ operationID: UUID) {
        guard onboardProfileLoadOperationIDs.remove(operationID) != nil else { return }
        onboardProfileLoadOperationStatusByID.removeValue(forKey: operationID)
        onboardProfileLoadOperationOrder.removeAll { $0 == operationID }
        refreshOnboardProfileLoadPresentation()
    }

    private func refreshOnboardProfileLoadPresentation() {
        guard let operationID = onboardProfileLoadOperationOrder.last(where: { onboardProfileLoadOperationIDs.contains($0) }) else {
            isOnboardProfileLoadInFlight = false
            onboardProfileLoadStatusText = nil
            return
        }
        isOnboardProfileLoadInFlight = true
        onboardProfileLoadStatusText = onboardProfileLoadOperationStatusByID[operationID]
    }

    private func withOnboardProfileLoad<T>(
        statusText: String,
        _ operation: @escaping @MainActor () async -> T
    ) async -> T {
        let operationID = beginOnboardProfileLoad(statusText: statusText)
        defer {
            endOnboardProfileLoad(operationID)
        }
        return await operation()
    }

    var visibleUSBLightingZones: [USBLightingZoneDescriptor] {
        guard let selectedDevice = deviceStore.selectedDevice else { return [] }
        return DeviceProfiles
            .resolve(
                vendorID: selectedDevice.vendor_id,
                productID: selectedDevice.product_id,
                transport: selectedDevice.transport
            )?
            .usbLightingZones ?? []
    }

    var lightingGradientDisplayColors: [RGBColor] {
        _ = lightingGradientRevision
        return editorController.lightingGradientDisplayColors()
    }

    var visibleLightingEffects: [LightingEffectKind] {
        guard let selectedDevice = deviceStore.selectedDevice else { return [.staticColor] }
        guard let profile = DeviceProfiles.resolve(
            vendorID: selectedDevice.vendor_id,
            productID: selectedDevice.product_id,
            transport: selectedDevice.transport
        ) else {
            return selectedDevice.supports_advanced_lighting_effects ? LightingEffectKind.allCases : [.staticColor]
        }
        if selectedDevice.supports_advanced_lighting_effects {
            return profile.supportedLightingEffects
        }
        return [.staticColor]
    }

    var visibleSoftwareLightingPresets: [SoftwareLightingPresetID] {
        guard let selectedDevice = deviceStore.selectedDevice else {
            return SoftwareLightingPresetID.animatedPresets
        }
        return selectedDevice.supportedSoftwareLightingPresets
    }

    var visibleOnboardProfileCount: Int {
        let deviceCount = deviceStore.selectedDevice?.onboard_profile_count ?? 1
        let stateCount = deviceStore.state?.onboard_profile_count ?? 1
        return max(1, max(deviceCount, stateCount))
    }

    var activeOnboardProfile: Int {
        max(1, min(visibleOnboardProfileCount, deviceStore.state?.active_onboard_profile ?? 1))
    }

    var liveUSBButtonProfile: Int {
        editorController.liveUSBButtonProfile()
    }

    var supportsMultipleOnboardProfiles: Bool {
        deviceStore.selectedDevice?.transport == .usb && visibleOnboardProfileCount > 1
    }

    var supportsOnboardProfileCRUD: Bool {
        guard let selectedDevice = deviceStore.selectedDevice else { return false }
        return DeviceProfiles
            .resolve(
                vendorID: selectedDevice.vendor_id,
                productID: selectedDevice.product_id,
                transport: selectedDevice.transport
            )?
            .supportsMappedOnboardProfileCRUD == true
    }

    var onboardProfileSummaries: [OnboardProfileSummary] {
        _ = onboardProfilesRevision
        return editorController.onboardProfileSummaries()
    }

    var selectedOnboardProfileID: Int? {
        _ = onboardProfilesRevision
        return editorController.selectedOnboardProfileID()
    }

    var selectedOnboardProfileName: String {
        _ = onboardProfilesRevision
        return editorController.selectedOnboardProfileName()
    }

    var selectedOnboardProfileIsActive: Bool {
        _ = onboardProfilesRevision
        return editorController.selectedOnboardProfileIsActive()
    }

    var visibleUSBButtonProfiles: [USBButtonProfileSummary] {
        _ = usbButtonProfilesRevision
        return editorController.usbButtonProfileSummaries()
    }

    var savedButtonProfiles: [OpenSnekButtonProfile] {
        _ = usbButtonProfilesRevision
        return editorController.savedButtonProfiles()
    }

    var currentButtonProfileSource: ButtonProfileSource? {
        _ = usbButtonProfilesRevision
        return editorController.currentButtonProfileSource()
    }

    var connectBehavior: DeviceConnectBehavior {
        _ = connectBehaviorRevision
        guard let selectedDevice = deviceStore.selectedDevice else { return .useMouseSettings }
        return editorController.connectBehavior(for: selectedDevice)
    }

    var showsConnectBehaviorCard: Bool {
        _ = connectBehaviorRevision
        guard let selectedDevice = deviceStore.selectedDevice else { return false }
        return editorController.showsConnectBehaviorCard(for: selectedDevice)
    }

    var currentButtonProfileDisplayName: String {
        _ = usbButtonProfilesRevision
        return editorController.currentButtonProfileDisplayName()
    }

    var liveButtonProfileDisplayName: String {
        _ = usbButtonProfilesRevision
        return editorController.liveButtonProfileDisplayName()
    }

    var loadableMouseButtonSources: [ButtonProfileSource] {
        _ = usbButtonProfilesRevision
        return editorController.loadableMouseButtonSources()
    }

    var writableMouseButtonSources: [ButtonProfileSource] {
        _ = usbButtonProfilesRevision
        return editorController.writableMouseButtonSources()
    }

    func buttonProfileSourceMatchDescription(_ source: ButtonProfileSource) -> String? {
        _ = usbButtonProfilesRevision
        return editorController.buttonProfileSourceMatchDescription(source)
    }

    func refreshButtonProfilePresentation() {
        editorController.refreshButtonProfilePresentation()
    }

    func refreshOnboardProfiles() async {
        let ownsRefreshPresentation = !isOnboardProfileRefreshInFlight
        if ownsRefreshPresentation {
            isOnboardProfileRefreshInFlight = true
            onboardProfileRefreshErrorMessage = nil
        }
        defer {
            if ownsRefreshPresentation {
                isOnboardProfileRefreshInFlight = false
            }
        }
        await editorController.refreshOnboardProfiles()
        if ownsRefreshPresentation,
           onboardProfileSummaries.isEmpty,
           let errorMessage = deviceStore.errorMessage,
           errorMessage.hasPrefix("Failed to refresh onboard profiles:") {
            onboardProfileRefreshErrorMessage = errorMessage
        }
    }

    func selectOnboardProfile(_ profileID: Int) async {
        await withOnboardProfileLoad(statusText: "Loading profile...") { [self] in
            await self.editorController.selectOnboardProfile(profileID)
        }
    }

    func createOnboardProfile(
        name: String,
        targetProfileID: Int? = nil,
        copyFromProfileID: Int? = nil
    ) async {
        await withButtonProfileOperation(statusText: "Creating profile...") { [self] in
            await self.editorController.createOnboardProfile(
                name: name,
                targetProfileID: targetProfileID,
                copyFromProfileID: copyFromProfileID
            )
        }
    }

    func renameSelectedOnboardProfile(name: String) async {
        await withButtonProfileOperation(statusText: "Renaming profile...") { [self] in
            await self.editorController.renameSelectedOnboardProfile(name: name)
        }
    }

    func deleteSelectedOnboardProfile() async {
        await withButtonProfileOperation(statusText: "Deleting profile...") { [self] in
            await self.editorController.deleteSelectedOnboardProfile()
        }
    }

    var canDuplicateSelectedUSBButtonProfile: Bool {
        visibleUSBButtonProfiles.contains { $0.profile != editableUSBButtonProfile }
    }

    var selectedUSBButtonProfileHasUnsavedChanges: Bool {
        _ = usbButtonProfilesRevision
        return editorController.selectedUSBButtonProfileHasUnsavedChanges()
    }

    var duplicateTargetProfiles: [USBButtonProfileSummary] {
        visibleUSBButtonProfiles.filter { $0.profile != editableUSBButtonProfile }
    }

    var compactActiveStageIndex: Int {
        max(0, min(max(0, editableStageCount - 1), editableActiveStage - 1))
    }

    var compactActiveStageValue: Int {
        stageValue(compactActiveStageIndex)
    }

    var selectedDeviceProfileID: DeviceProfileID? {
        deviceStore.selectedDevice?.profile_id
    }

    func updateStage(_ index: Int, value: Int) {
        guard index >= 0 && index < editableStageValues.count else { return }
        let clamped = DeviceProfiles.clampDPI(value, profileID: selectedDeviceProfileID)
        editableStageValues[index] = clamped
        editableStagePairs[index] = DpiPair(x: clamped, y: clamped)
    }

    func stageValue(_ index: Int) -> Int {
        guard index >= 0 && index < editableStageValues.count else { return 800 }
        return editableStageValues[index]
    }

    func stagePair(_ index: Int) -> DpiPair {
        guard index >= 0 && index < editableStagePairs.count else { return DpiPair(x: 800, y: 800) }
        return editableStagePairs[index]
    }

    func updateStageX(_ index: Int, value: Int) {
        guard index >= 0 && index < editableStagePairs.count else { return }
        let clamped = DeviceProfiles.clampDPI(value, profileID: selectedDeviceProfileID)
        let current = editableStagePairs[index]
        editableStagePairs[index] = DpiPair(x: clamped, y: current.y)
    }

    func updateStageY(_ index: Int, value: Int) {
        guard index >= 0 && index < editableStagePairs.count else { return }
        let clamped = DeviceProfiles.clampDPI(value, profileID: selectedDeviceProfileID)
        let current = editableStagePairs[index]
        editableStagePairs[index] = DpiPair(x: current.x, y: clamped)
    }

    var selectedDeviceSupportsIndependentXYDPI: Bool {
        DeviceProfiles.supportsIndependentXYDPI(for: deviceStore.selectedDevice)
    }

    func isStageXYExpanded(_ index: Int) -> Bool {
        expandedXYStageIndices.contains(index)
    }

    @discardableResult
    func toggleStageXYExpansion(_ index: Int) -> Bool {
        guard index >= 0 && index < editableStageCount else { return false }
        if expandedXYStageIndices.contains(index) {
            expandedXYStageIndices.remove(index)
            let scalar = stageValue(index)
            editableStagePairs[index] = DpiPair(x: scalar, y: scalar)
            return true
        } else {
            expandedXYStageIndices.insert(index)
            return false
        }
    }

    func normalizeExpandedXYStages() {
        guard selectedDeviceSupportsIndependentXYDPI else {
            expandedXYStageIndices.removeAll()
            return
        }
        expandedXYStageIndices = expandedXYStageIndices.filter { $0 >= 0 && $0 < editableStageCount }
    }

    func scheduleAutoApplyDpi() {
        applyController.scheduleAutoApplyDpi()
    }

    func applyDpiStages() async {
        await applyController.applyDpiStages()
    }

    func scheduleAutoApplyActiveStage() {
        applyController.scheduleAutoApplyActiveStage()
    }

    func scheduleAutoApplyPollRate() {
        applyController.scheduleAutoApplyPollRate()
    }

    func applyPollRate() async {
        await applyController.applyPollRate()
    }

    func scheduleAutoApplySleepTimeout() {
        applyController.scheduleAutoApplySleepTimeout()
    }

    func scheduleAutoApplyLowBatteryThreshold() {
        applyController.scheduleAutoApplyLowBatteryThreshold()
    }

    func scheduleAutoApplyScrollMode() {
        applyController.scheduleAutoApplyScrollMode()
    }

    func scheduleAutoApplyScrollAcceleration() {
        applyController.scheduleAutoApplyScrollAcceleration()
    }

    func scheduleAutoApplyScrollSmartReel() {
        applyController.scheduleAutoApplyScrollSmartReel()
    }

    func scheduleAutoApplyLedBrightness() {
        applyController.scheduleAutoApplyLedBrightness()
    }

    func scheduleAutoApplyLedColor() {
        applyController.scheduleAutoApplyLedColor()
    }

    func scheduleAutoApplyLightingEffect() {
        applyController.scheduleAutoApplyLightingEffect()
    }

    func applyCurrentStaticColorToAllZones() async {
        await applyController.applyCurrentStaticColorToAllZones()
    }

    func scheduleAutoApplyCurrentStaticColorToAllZones() {
        applyController.scheduleAutoApplyCurrentStaticColorToAllZones()
    }

    func noteLightingGradientColorsChanged() {
        lightingGradientRevision &+= 1
    }

    func updateLightingEffect(_ kind: LightingEffectKind) {
        editorController.updateLightingEffect(kind)
    }

    func startSoftwareLighting() async {
        await editorController.startSoftwareLighting()
    }

    func updateEditableSoftwareLightingPreset(_ preset: SoftwareLightingPresetID) {
        let supportedPresets = visibleSoftwareLightingPresets
        let resolvedPreset = supportedPresets.contains(preset)
            ? preset
            : (supportedPresets.first ?? .flame)
        guard editableSoftwareLightingPreset != resolvedPreset else { return }
        editableSoftwareLightingPreset = resolvedPreset
        editableSoftwareLightingSpeed = resolvedPreset.defaultSpeed
    }

    func updateSoftwareLightingApplyOnConnect(_ enabled: Bool) {
        editorController.updateSoftwareLightingApplyOnConnect(enabled)
    }

    func editableSoftwareLightingPalette(for preset: SoftwareLightingPresetID) -> [RGBColor] {
        editableSoftwareLightingPalettes[preset] ?? Self.defaultSoftwareLightingPalettes()[preset] ?? []
    }

    func setEditableSoftwareLightingPalette(_ palette: [RGBColor], for preset: SoftwareLightingPresetID) {
        let fallback = Self.defaultSoftwareLightingPalettes()[preset] ?? []
        let source = palette.isEmpty ? fallback : palette
        editableSoftwareLightingPalettes[preset] = Array(source.prefix(preset.maximumPaletteColorCount))
    }

    func addEditableSoftwareLightingPaletteColor(for preset: SoftwareLightingPresetID) {
        var palette = editableSoftwareLightingPalette(for: preset)
        guard palette.count < preset.maximumPaletteColorCount else { return }
        palette.append(palette.last ?? RGBColor(r: 255, g: 255, b: 255))
        setEditableSoftwareLightingPalette(palette, for: preset)
    }

    func removeEditableSoftwareLightingPaletteColor(at index: Int, for preset: SoftwareLightingPresetID) {
        var palette = editableSoftwareLightingPalette(for: preset)
        guard palette.count > 1, palette.indices.contains(index) else { return }
        palette.remove(at: index)
        setEditableSoftwareLightingPalette(palette, for: preset)
    }

    func resetEditableSoftwareLightingPalette(for preset: SoftwareLightingPresetID) {
        editableSoftwareLightingPalettes[preset] = Self.defaultSoftwareLightingPalettes()[preset]
    }

    func applySoftwareLightingEffectRequest(_ request: SoftwareLightingEffectRequest) {
        let supportedPresets = visibleSoftwareLightingPresets
        let resolvedPreset = supportedPresets.contains(request.presetID)
            ? request.presetID
            : (supportedPresets.first ?? .flame)
        let usesPersistedPreset = resolvedPreset == request.presetID
        let resolvedPalette = usesPersistedPreset ? request.palette : resolvedPreset.defaultPalette
        editableSoftwareLightingPreset = resolvedPreset
        editableSoftwareLightingSpeed = usesPersistedPreset ? request.speed : resolvedPreset.defaultSpeed
        editableSoftwareLightingBrightness = request.intensity
        editableSoftwareLightingPalettes[resolvedPreset] = resolvedPalette.map {
            RGBColor(r: $0.r, g: $0.g, b: $0.b)
        }
    }

    func softwareLightingEffectRequest() -> SoftwareLightingEffectRequest {
        let palette = editableSoftwareLightingPalette(for: editableSoftwareLightingPreset).map {
            RGBPatch(r: $0.r, g: $0.g, b: $0.b)
        }
        return SoftwareLightingEffectRequest(
            presetID: editableSoftwareLightingPreset,
            intensity: editableSoftwareLightingBrightness,
            speed: editableSoftwareLightingSpeed,
            palette: palette
        )
    }

    func stopSoftwareLighting() async {
        await editorController.stopSoftwareLighting()
    }

    func updateConnectBehavior(_ behavior: DeviceConnectBehavior) {
        editorController.updateConnectBehavior(behavior)
    }

    func updateUSBLightingZoneID(_ zoneID: String) {
        editorController.updateUSBLightingZoneID(zoneID)
    }

    func updateUSBButtonProfile(_ profile: Int) {
        editorController.updateUSBButtonProfile(profile)
    }

    func selectButtonProfileSource(_ source: ButtonProfileSource) {
        editorController.selectButtonProfileSource(source)
    }

    func loadButtonProfileSourceIntoLive(_ source: ButtonProfileSource) async {
        await withButtonProfileOperation(statusText: "Loading profile…") { [self] in
            await self.editorController.loadButtonProfileSourceIntoLive(source)
        }
    }

    func selectNextOnboardButtonProfile() {
        editorController.selectNextOnboardButtonProfile()
    }

    func duplicateSelectedUSBButtonProfile() async {
        await withButtonProfileOperation(statusText: "Saving profile…") { [self] in
            await self.applyController.duplicateSelectedUSBButtonProfile()
        }
    }

    func resetSelectedUSBButtonProfile() async {
        await withButtonProfileOperation(statusText: "Removing profile…") { [self] in
            await self.applyController.resetSelectedUSBButtonProfile()
        }
    }

    func projectSelectedUSBButtonProfileToDirectLayer() async {
        await withButtonProfileOperation(statusText: "Applying profile…") { [self] in
            await self.applyController.projectSelectedUSBButtonProfileToDirectLayer()
        }
    }

    func saveSelectedUSBButtonProfile(activateAfterSave: Bool = false) async {
        await withButtonProfileOperation(statusText: "Saving profile…") { [self] in
            await self.applyController.saveSelectedUSBButtonProfile(activateAfterSave: activateAfterSave)
        }
    }

    func applyCurrentButtonWorkspaceToLive() async {
        await withButtonProfileOperation(statusText: "Applying profile…") { [self] in
            await self.applyController.applyCurrentButtonWorkspaceToLive()
        }
    }

    func writeCurrentButtonWorkspaceToMouseSlot(_ slot: Int) async {
        await withButtonProfileOperation(statusText: "Saving profile…") { [self] in
            await self.applyController.writeCurrentButtonWorkspaceToMouseSlot(slot)
        }
    }

    @discardableResult
    func saveCurrentButtonWorkspaceAsNewProfile(name: String) -> OpenSnekButtonProfile {
        editorController.saveCurrentButtonWorkspaceAsNewProfile(name: name)
    }

    func updateLightingWaveDirection(_ direction: LightingWaveDirection) {
        editorController.updateLightingWaveDirection(direction)
    }

    func updateLightingReactiveSpeed(_ speed: Int) {
        editorController.updateLightingReactiveSpeed(speed)
    }

    func buttonBindingKind(for slot: Int) -> ButtonBindingKind {
        editorController.buttonBindingKind(for: slot)
    }

    func buttonBindingTurboEnabled(for slot: Int) -> Bool {
        editorController.buttonBindingTurboEnabled(for: slot)
    }

    func buttonBindingTurboRatePressesPerSecond(for slot: Int) -> Int {
        ButtonBindingSupport.turboRawToPressesPerSecond(editorController.buttonBindingTurboRate(for: slot))
    }

    func buttonBindingHidKey(for slot: Int) -> Int {
        editorController.buttonBindingHidKey(for: slot)
    }

    func buttonBindingHidModifiers(for slot: Int) -> Int {
        editorController.buttonBindingHidModifiers(for: slot)
    }

    func buttonBindingClutchDPI(for slot: Int) -> Int {
        editorController.buttonBindingClutchDPI(for: slot)
    }

    func updateButtonBindingKind(slot: Int, kind: ButtonBindingKind) {
        editorController.updateButtonBindingKind(slot: slot, kind: kind)
    }

    func updateButtonBindingKeyboardShortcut(slot: Int, hidKey: Int, hidModifiers: Int) {
        editorController.updateButtonBindingKeyboardShortcut(
            slot: slot,
            hidKey: hidKey,
            hidModifiers: hidModifiers
        )
    }

    func updateButtonBindingTurboEnabled(slot: Int, enabled: Bool) {
        editorController.updateButtonBindingTurboEnabled(slot: slot, enabled: enabled)
    }

    func updateButtonBindingTurboPressesPerSecond(slot: Int, pressesPerSecond: Int) {
        let clamped = max(1, min(20, pressesPerSecond))
        editorController.updateButtonBindingTurboRate(
            slot: slot,
            rate: ButtonBindingSupport.turboPressesPerSecondToRaw(clamped)
        )
    }

    func updateButtonBindingClutchDPI(slot: Int, dpi: Int) {
        editorController.updateButtonBindingClutchDPI(slot: slot, dpi: dpi)
    }
}
