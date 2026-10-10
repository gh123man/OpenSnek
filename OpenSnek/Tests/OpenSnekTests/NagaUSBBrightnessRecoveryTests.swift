import XCTest
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

/// Replays the Naga brightness-address mismatch through service startup and recovery.
@MainActor final class NagaUSBBrightnessRecoveryTests: XCTestCase {
    private let logoLED: UInt8 = 0x04
    private let wholeDeviceLED: UInt8 = 0x00
    private let capturedBrightness = 0x58
    private let productIDs = [0x00A7, 0x00A8]

    func testNagaReadsLogoBrightnessWithoutChangingWholeDeviceWriteAddress() {
        let client = BridgeClient(startHIDMonitoring: false)
        for productID in productIDs {
            let device = makeDevice(productID: productID)
            var queriedLEDs: [UInt8] = []
            let brightness = client.readUSBBrightness(device: device) { ledID in
                queriedLEDs.append(ledID)
                return self.capturedResponse(ledID: ledID)
            }
            XCTAssertEqual(queriedLEDs, [logoLED])
            XCTAssertEqual(brightness, capturedBrightness)
            XCTAssertEqual(client.usbBrightnessLEDIDs(for: device), [wholeDeviceLED])
        }
    }

    func testServiceStartsConnectedAndRecoversAfterReceiverUnplugReplug() async {
        for productID in productIDs {
            let device = makeDevice(productID: productID)
            let state = replayState(device: device)
            let backend = DeviceListUpdatingStubBackend(devices: [device], stateByDeviceID: [device.id: state])
            let appState = makeService(device: device, backend: backend)

            let initialRead = await appState.deviceController.refreshState(for: device)
            XCTAssertTrue(initialRead, "A healthy Naga must hydrate without opening the main window")
            assertConnected(appState, device: device)

            appState.deviceController.applyDeviceList([], source: "test.unplug")
            XCTAssertNil(appState.deviceStore.selectedDevice)
            XCTAssertEqual(appState.deviceController.connectionState(for: device), .disconnected)
            XCTAssertFalse(appState.deviceStore.selectedDeviceControlsEnabled)
            appState.deviceController.applyDeviceList([device], source: "test.replug")
            let recovered = await appState.deviceController.refreshState(for: device)
            XCTAssertTrue(recovered)
            assertConnected(appState, device: device)
        }
    }

    func testRealTelemetryLossStillDisconnectsAndWakeRecovers() async {
        let device = makeDevice(productID: 0x00A8)
        let state = replayState(device: device)
        let backend = DeviceListUpdatingStubBackend(devices: [device], stateByDeviceID: [device.id: state])
        let appState = makeService(device: device, backend: backend)
        let initialRead = await appState.deviceController.refreshState(for: device)
        XCTAssertTrue(initialRead)

        await backend.setTransientReadFailures([BridgeError.usbMouseUnavailable.localizedDescription], for: device.id)
        let sleepingRead = await appState.deviceController.refreshState(for: device)
        XCTAssertFalse(sleepingRead)
        XCTAssertEqual(appState.deviceController.connectionState(for: device), .disconnected)
        XCTAssertFalse(appState.deviceStore.selectedDeviceControlsEnabled)
        // Let the normal recovery read run while retaining the recovery classification.
        appState.deviceController.stateRefreshSuppressedUntilByDeviceID[device.id] = .distantPast
        appState.deviceController.setUSBControlAvailability(.receiverPresentMouseReachable, for: device.id)
        let awakeRead = await appState.deviceController.refreshState(for: device)
        XCTAssertTrue(awakeRead)
        assertConnected(appState, device: device)
    }

    func testRejectedBrightnessRemainsIncompleteTelemetryWithoutRetries() async {
        let device = makeDevice(productID: 0x00A8)
        let client = BridgeClient(startHIDMonitoring: false)
        var queriedLEDs: [UInt8] = []
        let brightness = client.readUSBBrightness(device: device) { ledID in
            queriedLEDs.append(ledID)
            return self.capturedResponse(ledID: self.wholeDeviceLED)
        }
        XCTAssertNil(brightness)
        XCTAssertEqual(queriedLEDs, [logoLED])
        let state = makeState(device: device, brightness: brightness)
        let backend = DeviceListUpdatingStubBackend(devices: [device], stateByDeviceID: [device.id: state])
        let appState = makeService(device: device, backend: backend)
        let refreshed = await appState.deviceController.refreshState(for: device)
        XCTAssertFalse(refreshed)
        XCTAssertEqual(appState.deviceController.connectionState(for: device), .disconnected)
        XCTAssertFalse(appState.deviceStore.selectedDeviceControlsEnabled)
    }

    func testHardwareNagaStateIncludesBrightness() async throws {
        guard ProcessInfo.processInfo.environment["OPEN_SNEK_HW"] == "1" else { throw XCTSkip("Set OPEN_SNEK_HW=1 for the read-only Naga brightness check.") }
        let client = BridgeClient()
        let devices = try await client.listDevices()
        let device = try XCTUnwrap(devices.first { $0.transport == .usb && self.productIDs.contains($0.product_id) })
        let state = try await client.readState(device: device)
        XCTAssertNotNil(state.led_value)
        XCTAssertNotNil(state.dpi_stages.values)
        XCTAssertNotNil(state.poll_rate)
        let backend = DeviceListUpdatingStubBackend(devices: [device], stateByDeviceID: [device.id: state])
        let appState = makeService(device: device, backend: backend)
        let refreshed = await appState.deviceController.refreshState(for: device)
        XCTAssertTrue(refreshed)
        assertConnected(appState, device: device)
    }

    private func makeDevice(productID: Int) -> MouseDevice { MouseDevice(id: "naga-brightness-\(productID)", vendor_id: 0x1532, product_id: productID, product_name: "Razer Naga V2 Pro", transport: .usb, path_b64: "", serial: "NAGA-BRIGHTNESS-\(productID)", firmware: nil, profile_id: .nagaV2Pro) }

    private func capturedResponse(ledID: UInt8) -> [UInt8] {
        // Live read-only capture: LED 0x00 returns status 0x03; logo 0x04 returns 0x02 / 0x58.
        var response = [UInt8](repeating: 0, count: 90)
        response[0] = ledID == logoLED ? 0x02 : 0x03
        response[10] = UInt8(capturedBrightness)
        return response
    }

    private func replayState(device: MouseDevice) -> MouseState {
        let client = BridgeClient(startHIDMonitoring: false)
        let brightness = client.readUSBBrightness(device: device) { self.capturedResponse(ledID: $0) }
        return makeState(device: device, brightness: brightness)
    }

    private func makeState(device: MouseDevice, brightness: Int?) -> MouseState {
        MouseState(
            device: DeviceSummary(id: device.id, product_name: device.product_name, serial: device.serial, transport: .usb, firmware: nil), connection: "USB", battery_percent: 83, charging: false, dpi: DpiPair(x: 2200, y: 2200), dpi_stages: DpiStages(active_stage: 1, values: [1100, 2200]),
            poll_rate: 1000, sleep_timeout: 300, device_mode: DeviceMode(mode: 0, param: 0), led_value: brightness, capabilities: Capabilities(dpi_stages: true, poll_rate: true, power_management: true, button_remap: true, lighting: true))
    }

    private func makeService(device: MouseDevice, backend: DeviceListUpdatingStubBackend) -> AppState {
        let appState = AppState(launchRole: .service, backend: backend, autoStart: false)
        appState.deviceStore.devices = [device]
        appState.deviceStore.selectedDeviceID = device.id
        return appState
    }

    private func assertConnected(_ appState: AppState, device: MouseDevice) {
        XCTAssertEqual(appState.deviceStore.currentDeviceStatusIndicator.label, "Connected")
        XCTAssertTrue(appState.deviceStore.selectedDeviceControlsEnabled)
        XCTAssertNotNil(appState.deviceStore.state?.led_value)
        XCTAssertFalse(appState.deviceController.usbTelemetryUnavailableBackoffDeviceIDs.contains(device.id))
    }
}
