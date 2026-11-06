import Foundation
import OpenSnekAppSupport
import OpenSnekCore

/// Seeds illustrative device data without constructing a hardware backend.
@MainActor enum ScreenshotFixtures {
    static func makeState(defaults: UserDefaults) -> AppState {
        let preferences = DevicePreferenceStore(defaults: defaults)
        let coordinator = BackgroundServiceCoordinator(defaults: defaults, defaultsDomainName: nil, preferencesNotificationCenter: NotificationCenter())
        let app = AppState(launchRole: .app, backend: BootstrapPendingBackend.shared, shouldCheckForReleaseUpdates: false, serviceCoordinator: coordinator, softwareUpdateInstaller: DisabledSoftwareUpdateInstaller.shared, autoStart: false, preferenceStore: preferences)
        let mouse = device(id: "screenshot-basilisk", productID: 0x00AB, transport: .usb)
        let bluetooth = device(id: "screenshot-v3x", productID: 0x00BA, transport: .bluetooth)
        app.deviceStore.devices = [mouse, bluetooth]
        app.deviceStore.selectedDeviceID = mouse.id
        let state = mouseState(mouse)
        seedDeviceState(app, mouse: mouse, state: state)
        seedEditor(app)
        seedProfiles(app, mouse: mouse, preferences: preferences)
        return app
    }

    private static func mouseState(_ mouse: MouseDevice) -> MouseState {
        MouseState(
            device: DeviceSummary(id: mouse.id, product_name: mouse.product_name, serial: nil, transport: .usb, firmware: "1.04"), connection: "USB", battery_percent: 86, charging: false, dpi: DpiPair(x: 1600, y: 1600), dpi_stages: DpiStages(active_stage: 2, values: [800, 1600, 3200]),
            poll_rate: 1000, sleep_timeout: 300, device_mode: DeviceMode(mode: 0, param: 0), low_battery_threshold_raw: 38, scroll_mode: 0, scroll_acceleration: false, scroll_smart_reel: true, active_onboard_profile: 2, onboard_profile_count: 5, led_value: 191,
            capabilities: Capabilities(dpi_stages: true, poll_rate: true, power_management: true, button_remap: true, lighting: true))
    }

    private static func seedDeviceState(_ app: AppState, mouse: MouseDevice, state: MouseState) {
        app.deviceStore.state = state
        app.deviceStore.stateByDeviceID = [mouse.id: state]
        app.deviceStore.lastUpdated = Date(timeIntervalSince1970: 1_700_000_000)
        app.deviceController.lastUpdatedByDeviceID[mouse.id] = app.deviceStore.lastUpdated
        app.deviceController.usbControlAvailabilityByDeviceID[mouse.id] = .receiverPresentMouseReachable
    }

    private static func seedEditor(_ app: AppState) {
        app.editorStore.editableStageValues = [800, 1600, 3200]
        app.editorStore.editableStageCount = 3
        app.editorStore.editableActiveStage = 2
        app.editorStore.editableLedBrightness = 191
        app.editorStore.editableColor = RGBColor(r: 112, g: 255, b: 148)
        app.editorStore.editableScrollSmartReel = true
        app.editorStore.editableButtonBindings = Dictionary(uniqueKeysWithValues: DeviceProfiles.basiliskV3FamilyButtonSlots.map { ($0.slot, ButtonBindingDraft(kind: .default, hidKey: 4, turboEnabled: false, turboRate: 10)) })
        app.editorStore.editableButtonBindings[4] = ButtonBindingDraft(kind: .keyboardSimple, hidKey: 6, hidModifiers: 8, turboEnabled: false, turboRate: 10)
        app.editorStore.editableButtonBindings[5] = ButtonBindingDraft(kind: .keyboardSimple, hidKey: 25, hidModifiers: 8, turboEnabled: false, turboRate: 10)
    }

    private static func device(id: String, productID: Int, transport: DeviceTransportKind) -> MouseDevice {
        let profile = DeviceProfiles.resolve(vendorID: 0x1532, productID: productID, transport: transport)!
        return MouseDevice(
            id: id, vendor_id: 0x1532, product_id: productID, product_name: "Razer " + profile.productName, transport: transport, path_b64: "", serial: nil, firmware: "1.04", profile_id: profile.id, button_layout: profile.buttonLayout,
            supports_advanced_lighting_effects: profile.supportsAdvancedLightingEffects, onboard_profile_count: profile.onboardProfileCount)
    }

    private static func seedProfiles(_ app: AppState, mouse: MouseDevice, preferences: DevicePreferenceStore) {
        let names = ["Base Profile", "Everyday", "Precision", "Gaming", "Travel"]
        let profiles = names.enumerated().map { index, name in
            OnboardProfileSummary(profileID: index + 1, metadata: OnboardProfileMetadata(identifier: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!, name: name), isAssigned: true, isActive: index == 1, isBaseProfile: index == 0)
        }
        app.editorController.onboardProfileInventoryByDeviceID[mouse.id] = OnboardProfileInventory(activeProfileID: 2, maxProfileID: 5, assignedProfileIDs: [1, 2, 3, 4, 5], profiles: profiles)
        app.editorController.selectedOnboardProfileIDByDeviceID[mouse.id] = 2
        let content = OpenSnekLocalProfileContent(dpi: OnboardDPIProfileSnapshot(scalar: DpiPair(x: 800, y: 800), activeStage: 1, pairs: [DpiPair(x: 400, y: 400), DpiPair(x: 800, y: 800), DpiPair(x: 1600, y: 1600)]))
        preferences.createOpenSnekLocalProfile(name: "Design", content: content)
        preferences.createOpenSnekLocalProfile(name: "FPS", content: content)
    }
}
