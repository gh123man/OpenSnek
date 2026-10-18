import XCTest
import OpenSnekCore
@testable import OpenSnek

/// Exercises content notice presentation behavior.
final class ContentNoticePresentationTests: XCTestCase {
    func testTelemetryNoticeIsSuppressedDuringReconnectRecovery() {
        XCTAssertTrue(ContentNoticePresentation.shouldSuppressTelemetryNoticeDuringConnectionRecovery(connectionState: .reconnecting, isStrictlyUnsupported: false, isUnsupportedUSB: false))
        XCTAssertTrue(ContentNoticePresentation.shouldSuppressTelemetryNoticeDuringConnectionRecovery(connectionState: .disconnected, isStrictlyUnsupported: false, isUnsupportedUSB: false))
    }

    func testTelemetryNoticeIsNotSuppressedForConnectedErrorOrUnsupportedStates() {
        for connectionState in [DeviceConnectionState.connected, .error, .unsupported] { XCTAssertFalse(ContentNoticePresentation.shouldSuppressTelemetryNoticeDuringConnectionRecovery(connectionState: connectionState, isStrictlyUnsupported: false, isUnsupportedUSB: false)) }

        XCTAssertFalse(ContentNoticePresentation.shouldSuppressTelemetryNoticeDuringConnectionRecovery(connectionState: .reconnecting, isStrictlyUnsupported: true, isUnsupportedUSB: false))
        XCTAssertFalse(ContentNoticePresentation.shouldSuppressTelemetryNoticeDuringConnectionRecovery(connectionState: .reconnecting, isStrictlyUnsupported: false, isUnsupportedUSB: true))
    }

    func testUSBTelemetryLimitedNoticeIsSuppressedForUSBSelection() {
        XCTAssertTrue(ContentNoticePresentation.shouldSuppressUSBTelemetryLimitedNotice(warningMessage: "USB telemetry is incomplete (missing poll rate). Controls stay visible, but values may be stale until readback succeeds.", selectedTransport: .usb))
    }

    func testUSBTelemetryLimitedNoticeDoesNotSuppressOtherWarnings() {
        XCTAssertFalse(ContentNoticePresentation.shouldSuppressUSBTelemetryLimitedNotice(warningMessage: "Using the last known values while live telemetry settles.", selectedTransport: .usb))
        XCTAssertFalse(ContentNoticePresentation.shouldSuppressUSBTelemetryLimitedNotice(warningMessage: "USB telemetry is incomplete (missing poll rate). Controls stay visible, but values may be stale until readback succeeds.", selectedTransport: .bluetooth))
    }

    func testUSBTelemetryLimitedCalloutIgnoresTelemetryTheProfileOmits() {
        // A lighting-only accessory reports no DPI stages or poll rate by design, so it must not be
        // flagged as telemetry limited while its brightness is readable.
        let accessory = makeState(dpiStages: DpiStages(active_stage: 0, values: []), pollRate: nil, ledValue: 255)
        XCTAssertFalse(ContentNoticePresentation.shouldShowUSBTelemetryLimitedCallout(state: accessory, profile: DeviceProfiles.mouseDockProUSB))

        // A mouse that does support those controls is still flagged when they are missing.
        let mouse = makeState(dpiStages: DpiStages(active_stage: 0, values: [1600]), pollRate: nil, ledValue: 85)
        XCTAssertTrue(ContentNoticePresentation.shouldShowUSBTelemetryLimitedCallout(state: mouse, profile: DeviceProfiles.nagaV3ProUSB))
    }

    private func makeState(dpiStages: DpiStages, pollRate: Int?, ledValue: Int?) -> MouseState {
        MouseState(
            device: DeviceSummary(id: "notice-test", product_name: "Notice Test Device", serial: nil, transport: .usb, firmware: nil), connection: "USB", battery_percent: nil, charging: nil, dpi: DpiPair(x: 1600, y: 1600), dpi_stages: dpiStages, poll_rate: pollRate, device_mode: nil,
            led_value: ledValue, capabilities: Capabilities(dpi_stages: dpiStages.values != nil, poll_rate: pollRate != nil, button_remap: true, lighting: ledValue != nil))
    }
}
