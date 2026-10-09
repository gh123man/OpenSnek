import XCTest
import OpenSnekCore
@testable import OpenSnek

/// Exercises which device's battery drives a Battery Meter accessory.
final class BatteryMeterSourceResolutionTests: XCTestCase {
    // The dock and a mouse on it are the reported wiring: the dock has no battery of its own, an
    // explicitly selected source must win over any other connected device, and an unavailable
    // source must never be replaced by another device's level.

    func testSummaryUsesOwnBatteryWhenPresent() {
        let selection = summarySelection(
            BatteryMeterSourceSelectionInput(deviceID: dockDevice.id, ownState: makeState(deviceID: dockDevice.id, batteryPercent: 80), explicitSourceDeviceID: nagaPro.id, candidateDeviceIDs: [nagaPro.id], stateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 40)]))

        XCTAssertEqual(selection?.battery_percent, 80)
    }

    func testSummaryUsesExplicitSourceInsteadOfAnotherConnectedDevice() {
        let selection = summarySelection(
            BatteryMeterSourceSelectionInput(
                deviceID: dockDevice.id, explicitSourceDeviceID: nagaPro.id, candidateDeviceIDs: [nagaPro.id, nagaV2Pro.id], stateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 41), nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)]))

        XCTAssertEqual(selection?.battery_percent, 41)
    }

    func testSummaryDoesNotSubstituteAnotherDeviceWhenExplicitSourceIsOffline() {
        let selection = summarySelection(BatteryMeterSourceSelectionInput(deviceID: dockDevice.id, explicitSourceDeviceID: nagaPro.id, candidateDeviceIDs: [nagaPro.id, nagaV2Pro.id], stateByDeviceID: [nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)]))

        XCTAssertNil(selection)
    }

    func testSummaryHidesLastKnownStateWhenExplicitSourceLeftTheDeviceList() {
        let selection = summarySelection(
            BatteryMeterSourceSelectionInput(deviceID: dockDevice.id, explicitSourceDeviceID: nagaPro.id, candidateDeviceIDs: [nagaV2Pro.id], stateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 41), nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)]))

        XCTAssertNil(selection)
    }

    func testSummaryHidesStateOfUnreachableExplicitSource() {
        let selection = summarySelection(
            BatteryMeterSourceSelectionInput(
                deviceID: dockDevice.id, explicitSourceDeviceID: nagaPro.id, candidateDeviceIDs: [nagaPro.id, nagaV2Pro.id], unavailableSourceDeviceIDs: [nagaPro.id],
                stateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 41), nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)]))

        XCTAssertNil(selection)
    }

    func testSummaryFallsBackPastUnreachableCandidateWhenSourceIsAutomatic() {
        let selection = summarySelection(
            BatteryMeterSourceSelectionInput(
                deviceID: dockDevice.id, candidateDeviceIDs: [nagaPro.id, nagaV2Pro.id], unavailableSourceDeviceIDs: [nagaPro.id], stateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 41), nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)]))

        XCTAssertEqual(selection?.battery_percent, 92)
    }

    func testSummaryFallsBackToFirstCandidateWithBatteryWhenSourceIsAutomatic() {
        let selection = summarySelection(
            BatteryMeterSourceSelectionInput(deviceID: dockDevice.id, candidateDeviceIDs: [nagaPro.id, nagaV2Pro.id], stateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: nil), nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)]))

        XCTAssertEqual(selection?.battery_percent, 92)
    }

    func testLightingUsesOwnBatteryWhenAccessoryReportsOne() {
        let percent = lightingPercent(
            BatteryResolutionInput(device: dockDevice, sourceDeviceID: nagaPro.id, cachedDevices: [dockDevice, nagaPro], cachedStateByDeviceID: [dockDevice.id: makeState(deviceID: dockDevice.id, batteryPercent: 80), nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 40)]))

        XCTAssertEqual(percent, 80)
    }

    func testLightingUsesExplicitSourceInsteadOfAnotherConnectedDevice() {
        let percent = lightingPercent(
            BatteryResolutionInput(device: dockDevice, sourceDeviceID: nagaPro.id, cachedDevices: [dockDevice, nagaPro, nagaV2Pro], cachedStateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 41), nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)]))

        XCTAssertEqual(percent, 41)
    }

    func testLightingDoesNotUseLastKnownValueWhenExplicitSourceIsOffline() {
        let percent = lightingPercent(
            BatteryResolutionInput(
                device: dockDevice, sourceDeviceID: nagaPro.id, cachedDevices: [dockDevice, nagaV2Pro], cachedStateByDeviceID: [nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)], reconnectSeedStateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 33)]))

        XCTAssertNil(percent)
    }

    func testLightingKeepsOwnLastKnownValueWhileReconnecting() {
        let percent = lightingPercent(
            BatteryResolutionInput(device: dockDevice, cachedDevices: [dockDevice, nagaV2Pro], cachedStateByDeviceID: [nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)], reconnectSeedStateByDeviceID: [dockDevice.id: makeState(deviceID: dockDevice.id, batteryPercent: 80)]))

        XCTAssertEqual(percent, 80)
    }

    func testLightingDoesNotSubstituteAnotherDeviceWhenExplicitSourceIsUnknown() {
        let percent = lightingPercent(BatteryResolutionInput(device: dockDevice, sourceDeviceID: nagaPro.id, cachedDevices: [dockDevice, nagaV2Pro], cachedStateByDeviceID: [nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)]))

        XCTAssertNil(percent)
    }

    func testLightingDoesNotUseValueWhenExplicitSourceIsUnreachable() {
        let percent = lightingPercent(
            BatteryResolutionInput(
                device: dockDevice, sourceDeviceID: nagaPro.id, cachedDevices: [dockDevice, nagaPro, nagaV2Pro], cachedStateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 41), nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)],
                unreachableDeviceIDs: [nagaPro.id]))

        XCTAssertNil(percent)
    }

    func testLightingFallsBackToLowestDeviceIDWhenSourceIsAutomatic() {
        let percent = lightingPercent(BatteryResolutionInput(device: dockDevice, cachedDevices: [dockDevice, nagaV2Pro, nagaPro], cachedStateByDeviceID: [nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92), nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 41)]))

        XCTAssertEqual(percent, 41)
    }

    func testLightingSkipsUnreachableCandidateWhenSourceIsAutomatic() {
        let percent = lightingPercent(
            BatteryResolutionInput(device: dockDevice, cachedDevices: [dockDevice, nagaPro, nagaV2Pro], cachedStateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 41), nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)], unreachableDeviceIDs: [nagaPro.id]))

        XCTAssertEqual(percent, 92)
    }

    func testLightingIgnoresOtherBatteriesForNonAccessoryDevices() {
        let percent = lightingPercent(BatteryResolutionInput(device: nagaV2Pro, cachedDevices: [nagaV2Pro, nagaPro], cachedStateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 41)]))

        XCTAssertNil(percent)
    }

    func testLightingIgnoresReconnectSeedsForAutomaticSelection() {
        let percent = lightingPercent(BatteryResolutionInput(device: dockDevice, cachedDevices: [dockDevice], cachedStateByDeviceID: [:], reconnectSeedStateByDeviceID: [nagaPro.id: makeState(deviceID: nagaPro.id, batteryPercent: 33)]))

        XCTAssertNil(percent)
    }
}

/// Exercises which devices are refreshed to keep a Battery Meter source current.
final class BatteryMeterSourceRefreshTests: XCTestCase {
    func testRunningExplicitMeterReturnsItsSource() {
        let status = runningMeter(sourceDeviceID: nagaPro.id)

        let sourceIDs = AppStateRuntimeController.softwareLightingBatterySourceDeviceIDs(statuses: [dockDevice.id: status], devices: [dockDevice, nagaPro, nagaV2Pro], stateByDeviceID: [:])

        XCTAssertEqual(sourceIDs, [nagaPro.id])
    }

    func testStoppedMeterReturnsNoSources() {
        let status = SoftwareLightingEngineStatus(deviceID: dockDevice.id, state: .stopped, request: SoftwareLightingEffectRequest(presetID: .batteryMeter, batterySourceDeviceID: nagaPro.id))

        XCTAssertEqual(AppStateRuntimeController.softwareLightingBatterySourceDeviceIDs(statuses: [dockDevice.id: status], devices: [dockDevice, nagaPro, nagaV2Pro], stateByDeviceID: [:]), [])
    }

    func testAutomaticMeterReturnsConnectedDevicesWithBattery() {
        let status = runningMeter()

        let sourceIDs = AppStateRuntimeController.softwareLightingBatterySourceDeviceIDs(statuses: [dockDevice.id: status], devices: [dockDevice, nagaPro, nagaV2Pro], stateByDeviceID: [nagaV2Pro.id: makeState(deviceID: nagaV2Pro.id, batteryPercent: 92)])

        XCTAssertEqual(sourceIDs, [nagaV2Pro.id])
    }

    func testDisconnectedExplicitSourceIsNotRefreshed() {
        let status = runningMeter(sourceDeviceID: nagaPro.id)

        XCTAssertEqual(AppStateRuntimeController.softwareLightingBatterySourceDeviceIDs(statuses: [dockDevice.id: status], devices: [dockDevice, nagaV2Pro], stateByDeviceID: [:]), [])
    }

    private func runningMeter(sourceDeviceID: String? = nil) -> SoftwareLightingEngineStatus { SoftwareLightingEngineStatus(deviceID: dockDevice.id, state: .running, request: SoftwareLightingEffectRequest(presetID: .batteryMeter, batterySourceDeviceID: sourceDeviceID)) }
}

private typealias BatteryResolutionInput = LocalBridgeBackend.SoftwareLightingBatteryResolutionInput

private func summarySelection(_ input: BatteryMeterSourceSelectionInput) -> MouseState? { BatteryMeterSourceSelection.state(input) }

private func lightingPercent(_ input: BatteryResolutionInput) -> Int? { LocalBridgeBackend.resolveSoftwareLightingBatteryPercent(input) }

private var dockDevice: MouseDevice { makeDevice(id: "dock", productID: 0x007E, productName: "Mouse Dock") }
private var nagaPro: MouseDevice { makeDevice(id: "naga-pro", productID: 0x008F, productName: "Naga Pro") }
private var nagaV2Pro: MouseDevice { makeDevice(id: "naga-v2-pro", productID: 0x00A7, productName: "Naga V2 Pro") }

private func makeDevice(id: String, productID: Int, productName: String) -> MouseDevice { MouseDevice(id: id, vendor_id: 0x1532, product_id: productID, product_name: productName, transport: .usb, path_b64: "", serial: nil, firmware: nil) }

private func makeState(deviceID: String, batteryPercent: Int?) -> MouseState {
    MouseState(
        device: DeviceSummary(id: deviceID, product_name: "Battery Source", serial: "BATTERY-SOURCE", transport: .usb, firmware: "1.0.0"), connection: "USB", battery_percent: batteryPercent, charging: false, dpi: DpiPair(x: 800, y: 800),
        dpi_stages: DpiStages(active_stage: 0, values: [800, 1600, 3200]), poll_rate: 1000, device_mode: nil, low_battery_threshold_raw: nil, led_value: 64, capabilities: Capabilities(dpi_stages: true, poll_rate: true, power_management: true, button_remap: true, lighting: true))
}
