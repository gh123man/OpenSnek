import XCTest
import OpenSnekCore
@testable import OpenSnek

/// Verifies that USB telemetry warnings only report controls a device actually exposes.
final class USBTelemetryExpectationTests: XCTestCase {
    func testLightingOnlyAccessoryDoesNotReportMouseTelemetryAsMissing() {
        // The Mouse Dock Pro exposes brightness reads but no DPI or poll rate. Its DPI-stage
        // fallback is an empty list rather than nil, matching what readUSBState publishes.
        let state = makeState(profileID: .mouseDockPro, dpiStages: DpiStages(active_stage: 0, values: []), pollRate: nil, ledValue: 255)
        XCTAssertEqual(USBTelemetryExpectation.missingTelemetry(state: state, profile: DeviceProfiles.mouseDockProUSB), [])
    }

    func testUnreadableLightingAccessoryDoesNotReportLightingAsMissing() {
        // The original Mouse Dock cannot read effect or brightness state, so a nil led value is
        // expected rather than degraded.
        let state = makeState(profileID: .mouseDock, dpiStages: DpiStages(active_stage: 0, values: []), pollRate: nil, ledValue: nil)
        XCTAssertEqual(USBTelemetryExpectation.missingTelemetry(state: state, profile: DeviceProfiles.mouseDockUSB), [])
    }

    func testMouseReportsOnlyTheTelemetryItSupportsAndIsMissing() {
        let state = makeState(profileID: .nagaV3Pro, dpiStages: DpiStages(active_stage: 0, values: [1600]), pollRate: 1000, ledValue: 85)
        XCTAssertEqual(USBTelemetryExpectation.missingTelemetry(state: state, profile: DeviceProfiles.nagaV3ProUSB), [])

        let missingPollRate = makeState(profileID: .nagaV3Pro, dpiStages: DpiStages(active_stage: 0, values: [1600]), pollRate: nil, ledValue: 85)
        XCTAssertEqual(USBTelemetryExpectation.missingTelemetry(state: missingPollRate, profile: DeviceProfiles.nagaV3ProUSB), ["poll rate"])

        let missingLighting = makeState(profileID: .nagaV3Pro, dpiStages: DpiStages(active_stage: 0, values: [1600]), pollRate: 1000, ledValue: nil)
        XCTAssertEqual(USBTelemetryExpectation.missingTelemetry(state: missingLighting, profile: DeviceProfiles.nagaV3ProUSB), ["lighting"])
    }

    func testUnprofiledDeviceKeepsTheHistoricalFullExpectation() {
        // An unknown product ID must keep reporting every gap so unsupported hardware still looks
        // degraded instead of silently healthy.
        let state = makeState(profileID: nil, dpiStages: DpiStages(active_stage: nil, values: nil), pollRate: nil, ledValue: nil)
        XCTAssertEqual(USBTelemetryExpectation.missingTelemetry(state: state, profile: nil), ["DPI stages", "poll rate", "lighting"])
    }

    private func makeState(profileID: DeviceProfileID?, dpiStages: DpiStages, pollRate: Int?, ledValue: Int?) -> MouseState {
        MouseState(
            device: DeviceSummary(id: "telemetry-test", product_name: "Telemetry Test Device", serial: nil, transport: .usb, firmware: nil), connection: "USB", battery_percent: nil, charging: nil, dpi: DpiPair(x: 1600, y: 1600), dpi_stages: dpiStages, poll_rate: pollRate, device_mode: nil,
            led_value: ledValue, capabilities: Capabilities(dpi_stages: dpiStages.values != nil, poll_rate: pollRate != nil, button_remap: true, lighting: ledValue != nil))
    }
}
