import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

/// Exercises DPI gating behavior for lighting-only (keyboard/keypad) device profiles.
final class LightingOnlyDeviceGatingTests: XCTestCase {
    private func makeKeyboardDevice() -> MouseDevice { MouseDevice(id: "usb-huntsman-mini", vendor_id: 0x1532, product_id: 0x0257, product_name: "Razer Huntsman Mini", transport: .usb, path_b64: "", serial: "KB-GATING-TEST", firmware: nil, profile_id: .huntsmanMini) }

    private func makeKeypadDevice() -> MouseDevice { MouseDevice(id: "usb-tartarus-pro", vendor_id: 0x1532, product_id: 0x0244, product_name: "Razer Tartarus Pro", transport: .usb, path_b64: "", serial: "PAD-GATING-TEST", firmware: nil, profile_id: .tartarusPro) }

    func testLightingOnlyDevicesReportNoDPIControls() {
        XCTAssertFalse(makeKeyboardDevice().supportsDPIControls)
        XCTAssertFalse(makeKeypadDevice().supportsDPIControls)
    }

    func testMenuBarDpiControlsAreHiddenForLightingOnlyDevices() async {
        let dock = makeTestDevice(
            id: "usb-mouse-dock-menu-gating", productName: "Mouse Dock", identity: MultiDeviceTestIdentity(transport: .usb, serial: "USB-MOUSE-DOCK-MENU", locationID: 1), profile: .mouseDock, productID: 0x007E)
        let mouse = makeTestDevice(id: "usb-v3pro-menu-gating", productName: "Razer Basilisk V3 Pro", identity: MultiDeviceTestIdentity(transport: .usb, serial: "USB-V3PRO-MENU", locationID: 2), profile: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(devices: [dock, mouse], stateByDeviceID: [:])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await MainActor.run {
            appState.deviceStore.devices = [dock, mouse]
            appState.deviceStore.selectedDeviceID = dock.id
        }
        let dockSupportsDPI = await MainActor.run { appState.deviceStore.selectedDeviceSupportsDPIControls }
        let dockIsLightingOnly = await MainActor.run { appState.deviceStore.selectedDeviceIsLightingOnly }
        XCTAssertFalse(dockSupportsDPI)
        XCTAssertTrue(dockIsLightingOnly)

        await MainActor.run { appState.deviceStore.selectedDeviceID = mouse.id }
        let mouseSupportsDPI = await MainActor.run { appState.deviceStore.selectedDeviceSupportsDPIControls }
        let mouseIsLightingOnly = await MainActor.run { appState.deviceStore.selectedDeviceIsLightingOnly }
        XCTAssertTrue(mouseSupportsDPI)
        XCTAssertFalse(mouseIsLightingOnly)
    }

    func testFastDPIPollingIsDisabledForLightingOnlyDevices() {
        let keyboard = makeKeyboardDevice()
        let keypad = makeKeypadDevice()

        XCTAssertFalse(BridgeClient.shouldUseFastDPIPolling(device: keyboard, armedPassiveDpiDeviceIDs: [], observedPassiveDpiDeviceIDs: []))
        XCTAssertFalse(BridgeClient.shouldUseFastDPIPolling(device: keypad, armedPassiveDpiDeviceIDs: [], observedPassiveDpiDeviceIDs: []))
    }

    func testFastDPIBackendReadReturnsNilForLightingOnlyDevices() async throws {
        let client = BridgeClient(startHIDMonitoring: false)
        let snapshot = try await client.readDpiStagesFast(device: makeKeyboardDevice())
        XCTAssertNil(snapshot)
    }

    func testLocalProfileAdaptationStripsDPIForLightingOnlyDevices() async {
        let keyboard = makeKeyboardDevice()
        let backend = AppStateRefactorStubBackend(devices: [keyboard], stateByDeviceID: [:])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        let pairs = [DpiPair(x: 800, y: 800), DpiPair(x: 1600, y: 1600)]
        let content = OpenSnekLocalProfileContent(
            dpi: OnboardDPIProfileSnapshot(scalar: pairs.first, activeStage: 0, pairs: pairs), buttonBindings: [:], brightnessByLEDID: [1: 200], staticColorByLEDID: [1: RGBPatch(r: 0, g: 255, b: 0)], lightingEffect: LightingEffectPatch(kind: .staticColor, primary: RGBPatch(r: 0, g: 255, b: 0)))

        let adapted = await MainActor.run { appState.editorController.adaptedLocalProfileContent(content, for: keyboard) }
        XCTAssertNil(adapted.dpi)
        XCTAssertEqual(adapted.brightnessByLEDID.isEmpty, false)

        let mouse = MouseDevice(id: "usb-v3pro", vendor_id: 0x1532, product_id: 0x00AB, product_name: "Razer Basilisk V3 Pro", transport: .usb, path_b64: "", serial: "MOUSE-GATING-TEST", firmware: nil, profile_id: .basiliskV3Pro)
        let adaptedForMouse = await MainActor.run { appState.editorController.adaptedLocalProfileContent(content, for: mouse) }
        XCTAssertNotNil(adaptedForMouse.dpi)
    }
}
