import Foundation
import Observation
import OpenSnekAppSupport
import OpenSnekCore
import SwiftUI

@MainActor
@Observable
final class AppState {
    var devices: [MouseDevice] = []
    var selectedDeviceID: String?
    var state: MouseState?
    var availableUpdate: ReleaseAvailability?

    var isLoading = false
    var isApplying = false
    var isRefreshingState = false
    var errorMessage: String?
    var warningMessage: String?
    var lastUpdated: Date?

    var editableStageValues: [Int] = [800, 1600, 3200, 6400, 12000]
    var editableStageCount = 3
    var editableActiveStage = 1
    var editablePollRate = 1000
    var editableSleepTimeout = 300
    var editableDeviceMode = 0x00
    var editableLowBatteryThresholdRaw = 0x26
    var editableScrollMode = 0
    var editableScrollAcceleration = false
    var editableScrollSmartReel = false
    var editableLedBrightness = 64
    var editableLightingEffect: LightingEffectKind = .staticColor
    var editableUSBLightingZoneID: String = "all"
    var editableUSBButtonProfile = 1
    var editableLightingWaveDirection: LightingWaveDirection = .left
    var editableLightingReactiveSpeed = 2
    var editableColor = RGBColor(r: 0, g: 255, b: 0)
    var editableSecondaryColor = RGBColor(r: 0, g: 170, b: 255)
    let buttonSlots = ButtonSlotDescriptor.defaults
    var editableButtonBindings: [Int: ButtonBindingDraft] = [:]
    var keyboardTextDraftBySlot: [Int: String] = [:]
    var backgroundServiceEnabled: Bool
    var launchAtStartupEnabled: Bool
    var serviceStatusMessage: String?
    var isEditingDpiControl = false

    var backend: any DeviceBackend
    let releaseUpdateChecker = ReleaseUpdateChecker()
    let launchRole: OpenSnekProcessRole
    let serviceCoordinator: BackgroundServiceCoordinator
    var hasCheckedForUpdates = false

    @ObservationIgnored private var deviceControllerStorage: AppStateDeviceController?
    @ObservationIgnored private var editorControllerStorage: AppStateEditorController?
    @ObservationIgnored private var applyControllerStorage: AppStateApplyController?
    @ObservationIgnored private var runtimeControllerStorage: AppStateRuntimeController?

    init(
        launchRole: OpenSnekProcessRole = .current,
        backend: (any DeviceBackend)? = nil,
        serviceCoordinator: BackgroundServiceCoordinator = .shared,
        autoStart: Bool = true
    ) {
        self.launchRole = launchRole
        self.serviceCoordinator = serviceCoordinator
        self.backgroundServiceEnabled = serviceCoordinator.backgroundServiceEnabled
        self.launchAtStartupEnabled = serviceCoordinator.launchAtStartupEnabled
        self.backend = backend ?? LocalBridgeBackend.shared

        runtimeController.installCrossProcessObservers()
        runtimeController.setBackendReady(launchRole.isService || backend != nil || !serviceCoordinator.backgroundServiceEnabled)
        Task { [weak self] in
            await self?.runtimeController.restartBackendStateUpdates()
        }
        if launchRole.isService, autoStart {
            Task { [weak self] in
                await self?.start()
            }
        }
    }

    deinit {
        let deviceController = deviceControllerStorage
        let applyController = applyControllerStorage
        let editorController = editorControllerStorage
        let runtimeController = runtimeControllerStorage
        @MainActor
        func tearDownControllers() {
            deviceController?.tearDown()
            applyController?.tearDown()
            editorController?.tearDown()
            runtimeController?.tearDown()
        }

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                tearDownControllers()
            }
        } else {
            let group = DispatchGroup()
            group.enter()
            Task { @MainActor in
                tearDownControllers()
                group.leave()
            }
            group.wait()
        }
    }

    var deviceController: AppStateDeviceController {
        if let deviceControllerStorage {
            return deviceControllerStorage
        }
        let controller = AppStateDeviceController(appState: self)
        deviceControllerStorage = controller
        return controller
    }

    var editorController: AppStateEditorController {
        if let editorControllerStorage {
            return editorControllerStorage
        }
        let controller = AppStateEditorController(appState: self)
        editorControllerStorage = controller
        return controller
    }

    var applyController: AppStateApplyController {
        if let applyControllerStorage {
            return applyControllerStorage
        }
        let controller = AppStateApplyController(appState: self)
        applyControllerStorage = controller
        return controller
    }

    var runtimeController: AppStateRuntimeController {
        if let runtimeControllerStorage {
            return runtimeControllerStorage
        }
        let controller = AppStateRuntimeController(appState: self)
        runtimeControllerStorage = controller
        return controller
    }

    var selectedDevice: MouseDevice? {
        guard let selectedDeviceID else { return nil }
        return devices.first(where: { $0.id == selectedDeviceID })
    }

    var selectedDeviceProfile: DeviceProfile? {
        guard let selectedDevice else { return nil }
        return resolvedProfile(for: selectedDevice)
    }

    var selectedDeviceIsStrictlyUnsupported: Bool {
        guard let selectedDevice else { return false }
        return deviceController.isStrictlyUnsupported(selectedDevice)
    }

    var selectedDeviceIsUnsupportedUSB: Bool {
        guard let selectedDevice else { return false }
        return selectedDevice.transport == .usb && resolvedProfile(for: selectedDevice) == nil
    }

    var selectedDeviceControlsEnabled: Bool {
        guard let selectedDevice else { return false }
        return deviceController.connectionState(for: selectedDevice).allowsInteraction
    }

    var selectedDeviceInteractionMessage: String? {
        guard let selectedDevice else { return nil }
        switch deviceController.connectionState(for: selectedDevice) {
        case .reconnecting:
            return "Reconnecting to live telemetry. Controls will unlock automatically."
        case .disconnected:
            return "This device is disconnected. Controls will unlock after it reconnects."
        case .error:
            return errorMessage ?? "Live telemetry is unavailable right now."
        case .unsupported, .connected:
            return nil
        }
    }

    var visibleButtonSlots: [ButtonSlotDescriptor] {
        selectedDevice?.button_layout?.visibleSlots ?? buttonSlots
    }

    var hiddenUnsupportedButtonSlots: [DocumentedButtonSlot] {
        guard let layout = selectedDevice?.button_layout else { return [] }
        let visible = Set(layout.visibleSlots.map(\.slot))
        return layout.documentedSlots.filter { slot in
            slot.access != .editable && !visible.contains(slot.slot)
        }
    }

    var visibleUSBLightingZones: [USBLightingZoneDescriptor] {
        guard let selectedDevice else { return [] }
        return DeviceProfiles
            .resolve(vendorID: selectedDevice.vendor_id, productID: selectedDevice.product_id, transport: selectedDevice.transport)?
            .usbLightingZones ?? []
    }

    var visibleLightingEffects: [LightingEffectKind] {
        guard let selectedDevice else { return [.staticColor] }
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

    var visibleOnboardProfileCount: Int {
        let deviceCount = selectedDevice?.onboard_profile_count ?? 1
        let stateCount = state?.onboard_profile_count ?? 1
        return max(1, max(deviceCount, stateCount))
    }

    var activeOnboardProfile: Int {
        max(1, min(visibleOnboardProfileCount, state?.active_onboard_profile ?? 1))
    }

    var supportsMultipleOnboardProfiles: Bool {
        selectedDevice?.transport == .usb && visibleOnboardProfileCount > 1
    }

    var currentDeviceStatusIndicator: DeviceStatusIndicator {
        guard let selectedDevice else { return DeviceConnectionState.disconnected.indicator }
        return deviceController.statusIndicator(for: selectedDevice)
    }

    func isButtonSlotEditable(_ slot: Int) -> Bool {
        selectedDevice?.button_layout?.isEditable(slot) ?? true
    }

    func buttonSlotNotice(_ slot: Int) -> String? {
        selectedDevice?.button_layout?.notice(for: slot)
    }

    func diagnosticsDump(for device: MouseDevice, state explicitState: MouseState? = nil) -> String {
        let resolvedProfile = resolvedProfile(for: device)
        let liveState = explicitState ?? deviceController.cachedState(for: device.id) ?? (device.id == selectedDeviceID ? state : nil)
        let deviceStatusIndicator = deviceController.statusIndicator(for: device)
        let deviceConnectionState = deviceController.connectionState(for: device)
        let deviceLastUpdated = deviceController.lastUpdatedTimestamp(for: device)
        var appContextLines: [String] = [
            "App version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")",
            "Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")",
            "Selected device ID: \(selectedDeviceID ?? "none")",
            "Refreshing state: \(isRefreshingState ? "Yes" : "No")",
            "Applying changes: \(isApplying ? "Yes" : "No")",
            "Pending local edits: \(applyController.hasPendingLocalEdits ? "Yes" : "No")",
            "Current status badge: \(deviceStatusIndicator.label)",
            "Physical presence: \(devices.contains(where: { $0.id == device.id }) ? "Detected by macOS" : "Not detected")",
            "Telemetry status: \(deviceConnectionState.diagnosticsLabel)",
            "Controls enabled: \(deviceConnectionState.allowsInteraction ? "Yes" : "No")",
            "DPI update path: \(deviceController.dpiUpdateTransportStatus(for: device).diagnosticsLabel)",
            "Last updated: \(deviceLastUpdated.map(Self.diagnosticsTimestamp) ?? "Unknown")",
            "Warning: \(device.id == selectedDeviceID ? (warningMessage ?? "None") : "None")",
            "Error: \(device.id == selectedDeviceID ? (errorMessage ?? "None") : "None")",
        ]

        if device.id == selectedDeviceID {
            appContextLines.append("Editable lighting effect: \(editableLightingEffect.label)")
            appContextLines.append("Editable lighting zone: \(editableUSBLightingZoneID)")
            appContextLines.append("Editable button profile: \(editableUSBButtonProfile)")
            appContextLines.append("Editable color: \(Self.diagnosticsRGB(editableColor))")
            appContextLines.append("Editable secondary color: \(Self.diagnosticsRGB(editableSecondaryColor))")
        }

        return DeviceDiagnosticsFormatter.format(
            device: device,
            state: liveState,
            profile: resolvedProfile,
            appContextLines: appContextLines
        )
    }

    func githubIssueDiagnosticsPayload() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let deviceEntries = devices.map { device in
            let resolvedProfile = resolvedProfile(for: device)
            let summary = "\(device.product_name) (\(device.transport.connectionLabel), " +
                "\(String(format: "0x%04X", device.vendor_id)):\(String(format: "0x%04X", device.product_id)), " +
                "profile \(resolvedProfile?.id.rawValue ?? "generic"))"
            let stateForDevice = device.id == selectedDeviceID ? state : deviceController.cachedState(for: device.id)
            return IssueReportDeviceEntry(
                title: "\(device.product_name) [\(device.transport.connectionLabel)]",
                summary: summary,
                diagnostics: diagnosticsDump(for: device, state: stateForDevice)
            )
        }

        return IssueReportFormatter.format(
            appVersion: appVersion,
            build: build,
            logLevel: AppLog.currentLevel.label,
            logPath: AppLog.path,
            selectedDevice: selectedDevice.map { "\($0.product_name) [\($0.transport.connectionLabel)]" },
            warning: warningMessage,
            error: errorMessage,
            devices: deviceEntries
        )
    }

    var isServiceProcess: Bool {
        launchRole.isService
    }

    var compactStatusMessage: String? {
        runtimeController.compactStatusMessage
    }

    var compactActiveStageIndex: Int {
        max(0, min(max(0, editableStageCount - 1), editableActiveStage - 1))
    }

    var compactActiveStageValue: Int {
        stageValue(compactActiveStageIndex)
    }

    var currentPollingProfile: PollingProfile {
        pollingProfile(at: Date())
    }

    func pollingProfile(at now: Date) -> PollingProfile {
        runtimeController.pollingProfile(at: now)
    }

    var usesRemoteServiceUpdates: Bool {
        !launchRole.isService && backend.usesRemoteServiceTransport
    }

    func diagnosticsConnectionLines(for device: MouseDevice) -> [String] {
        deviceController.diagnosticsConnectionLines(for: device)
    }

    func refreshConnectionDiagnostics(for device: MouseDevice) async {
        await deviceController.refreshConnectionDiagnostics(for: device)
    }

    func activeFastPollingDeviceIDs(at now: Date) -> [String] {
        runtimeController.activeFastPollingDeviceIDs(at: now)
    }

    func recordRemoteClientPresence(_ presence: CrossProcessClientPresence, now: Date = Date()) {
        runtimeController.recordRemoteClientPresence(presence, now: now)
    }

    func applyRemoteServiceSnapshot(_ snapshot: SharedServiceSnapshot) {
        deviceController.applyRemoteServiceSnapshot(snapshot)
    }

    func start() async {
        await runtimeController.start()
    }

    func setCompactMenuPresented(_ isPresented: Bool) {
        runtimeController.setCompactMenuPresented(isPresented)
    }

    func setBackgroundServiceEnabled(_ enabled: Bool) async {
        await runtimeController.setBackgroundServiceEnabled(enabled)
    }

    func setLaunchAtStartupEnabled(_ enabled: Bool) {
        runtimeController.setLaunchAtStartupEnabled(enabled)
    }

    func openFullAppFromService() {
        runtimeController.openFullAppFromService()
    }

    func openSettingsFromService() {
        runtimeController.openSettingsFromService()
    }

    func prepareForCurrentServiceProcessTermination() {
        runtimeController.prepareForCurrentServiceProcessTermination()
    }

    func terminateServiceProcess() {
        runtimeController.terminateServiceProcess()
    }

    func refreshNow() async {
        await runtimeController.refreshNow()
    }

    func sendRemoteClientPresence() {
        runtimeController.sendRemoteClientPresence()
    }

    func runtimeSleepInterval(after now: Date) -> TimeInterval {
        runtimeController.runtimeSleepInterval(after: now)
    }

    func refreshDevices() async {
        await deviceController.refreshDevices()
    }

    func checkForUpdates(force: Bool = false) async {
        guard force || !hasCheckedForUpdates else { return }
        hasCheckedForUpdates = true

        guard let currentVersion = ReleaseUpdateChecker.currentAppVersion() else { return }

        do {
            availableUpdate = try await releaseUpdateChecker.checkForUpdate(currentVersion: currentVersion)
            if let availableUpdate {
                AppLog.event("AppState", "update available current=\(currentVersion) latest=\(availableUpdate.latestVersion)")
            }
        } catch {
            AppLog.debug("AppState", "checkForUpdates failed: \(error.localizedDescription)")
        }
    }

    func pollDevicePresence() async {
        await deviceController.pollDevicePresence()
    }

    func selectDevice(_ deviceID: String) {
        deviceController.selectDevice(deviceID)
    }

    func refreshState() async {
        await deviceController.refreshState()
    }

    func updateStage(_ index: Int, value: Int) {
        applyController.updateStage(index, value: value)
    }

    func stageValue(_ index: Int) -> Int {
        applyController.stageValue(index)
    }

    func applyDpiStages() async {
        await applyController.applyDpiStages()
    }

    func scheduleAutoApplyDpi() {
        applyController.scheduleAutoApplyDpi()
    }

    func applyActiveStageOnly() async {
        await applyController.applyActiveStageOnly()
    }

    func scheduleAutoApplyActiveStage() {
        applyController.scheduleAutoApplyActiveStage()
    }

    func applyPollRate() async {
        await applyController.applyPollRate()
    }

    func scheduleAutoApplyPollRate() {
        applyController.scheduleAutoApplyPollRate()
    }

    func applySleepTimeout() async {
        await applyController.applySleepTimeout()
    }

    func scheduleAutoApplySleepTimeout() {
        applyController.scheduleAutoApplySleepTimeout()
    }

    func applyDeviceMode() async {
        await applyController.applyDeviceMode()
    }

    func scheduleAutoApplyDeviceMode() {
        applyController.scheduleAutoApplyDeviceMode()
    }

    func applyLowBatteryThreshold() async {
        await applyController.applyLowBatteryThreshold()
    }

    func scheduleAutoApplyLowBatteryThreshold() {
        applyController.scheduleAutoApplyLowBatteryThreshold()
    }

    func applyScrollMode() async {
        await applyController.applyScrollMode()
    }

    func scheduleAutoApplyScrollMode() {
        applyController.scheduleAutoApplyScrollMode()
    }

    func applyScrollAcceleration() async {
        await applyController.applyScrollAcceleration()
    }

    func scheduleAutoApplyScrollAcceleration() {
        applyController.scheduleAutoApplyScrollAcceleration()
    }

    func applyScrollSmartReel() async {
        await applyController.applyScrollSmartReel()
    }

    func scheduleAutoApplyScrollSmartReel() {
        applyController.scheduleAutoApplyScrollSmartReel()
    }

    func applyLedBrightness() async {
        await applyController.applyLedBrightness()
    }

    func scheduleAutoApplyLedBrightness() {
        applyController.scheduleAutoApplyLedBrightness()
    }

    func applyLedColor() async {
        await applyController.applyLedColor()
    }

    func scheduleAutoApplyLedColor() {
        applyController.scheduleAutoApplyLedColor()
    }

    func applyLightingEffect() async {
        await applyController.applyLightingEffect()
    }

    func scheduleAutoApplyLightingEffect() {
        applyController.scheduleAutoApplyLightingEffect()
    }

    func updateLightingEffect(_ kind: LightingEffectKind) {
        editorController.updateLightingEffect(kind)
    }

    func updateUSBLightingZoneID(_ zoneID: String) {
        editorController.updateUSBLightingZoneID(zoneID)
    }

    func updateUSBButtonProfile(_ profile: Int) {
        editorController.updateUSBButtonProfile(profile)
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

    func buttonBindingHidKey(for slot: Int) -> Int {
        editorController.buttonBindingHidKey(for: slot)
    }

    func buttonBindingTurboEnabled(for slot: Int) -> Bool {
        editorController.buttonBindingTurboEnabled(for: slot)
    }

    func buttonBindingTurboRate(for slot: Int) -> Int {
        editorController.buttonBindingTurboRate(for: slot)
    }

    func buttonBindingTurboRatePressesPerSecond(for slot: Int) -> Int {
        Self.turboRawToPressesPerSecond(buttonBindingTurboRate(for: slot))
    }

    func buttonBindingClutchDPI(for slot: Int) -> Int {
        editorController.buttonBindingClutchDPI(for: slot)
    }

    func updateButtonBindingKind(slot: Int, kind: ButtonBindingKind) {
        editorController.updateButtonBindingKind(slot: slot, kind: kind)
    }

    func updateButtonBindingHidKey(slot: Int, hidKey: Int) {
        editorController.updateButtonBindingHidKey(slot: slot, hidKey: hidKey)
    }

    func updateButtonBindingTurboEnabled(slot: Int, enabled: Bool) {
        editorController.updateButtonBindingTurboEnabled(slot: slot, enabled: enabled)
    }

    func updateButtonBindingTurboRate(slot: Int, rate: Int) {
        editorController.updateButtonBindingTurboRate(slot: slot, rate: rate)
    }

    func updateButtonBindingTurboPressesPerSecond(slot: Int, pressesPerSecond: Int) {
        let pps = max(1, min(20, pressesPerSecond))
        updateButtonBindingTurboRate(slot: slot, rate: Self.turboPressesPerSecondToRaw(pps))
    }

    func updateButtonBindingClutchDPI(slot: Int, dpi: Int) {
        editorController.updateButtonBindingClutchDPI(slot: slot, dpi: dpi)
    }

    func keyboardTextDraft(for slot: Int) -> String {
        editorController.keyboardTextDraft(for: slot)
    }

    func updateKeyboardTextDraft(slot: Int, text: String) {
        editorController.updateKeyboardTextDraft(slot: slot, text: text)
    }

    func refreshDpiFast() async {
        await deviceController.refreshDpiFast()
    }

    func resolvedProfile(for device: MouseDevice) -> DeviceProfile? {
        DeviceProfiles.resolve(
            vendorID: device.vendor_id,
            productID: device.product_id,
            transport: device.transport
        )
    }

    static func turboRawToPressesPerSecond(_ rawRate: Int) -> Int {
        ButtonBindingSupport.turboRawToPressesPerSecond(rawRate)
    }

    static func turboPressesPerSecondToRaw(_ pressesPerSecond: Int) -> Int {
        ButtonBindingSupport.turboPressesPerSecondToRaw(pressesPerSecond)
    }

    private static func diagnosticsTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func diagnosticsRGB(_ color: RGBColor) -> String {
        String(format: "#%02X%02X%02X", color.r, color.g, color.b)
    }
}
