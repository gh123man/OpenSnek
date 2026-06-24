import XCTest
import OpenSnekCore
@testable import OpenSnek

/// Exercises content notice presentation behavior.
final class ContentNoticePresentationTests: XCTestCase {
    func testTelemetryNoticeIsSuppressedDuringReconnectRecovery() {
        XCTAssertTrue(
            ContentNoticePresentation.shouldSuppressTelemetryNoticeDuringConnectionRecovery(
                connectionState: .reconnecting,
                isStrictlyUnsupported: false,
                isUnsupportedUSB: false
            )
        )
        XCTAssertTrue(
            ContentNoticePresentation.shouldSuppressTelemetryNoticeDuringConnectionRecovery(
                connectionState: .disconnected,
                isStrictlyUnsupported: false,
                isUnsupportedUSB: false
            )
        )
    }

    func testTelemetryNoticeIsNotSuppressedForConnectedErrorOrUnsupportedStates() {
        for connectionState in [DeviceConnectionState.connected, .error, .unsupported] {
            XCTAssertFalse(
                ContentNoticePresentation.shouldSuppressTelemetryNoticeDuringConnectionRecovery(
                    connectionState: connectionState,
                    isStrictlyUnsupported: false,
                    isUnsupportedUSB: false
                )
            )
        }

        XCTAssertFalse(
            ContentNoticePresentation.shouldSuppressTelemetryNoticeDuringConnectionRecovery(
                connectionState: .reconnecting,
                isStrictlyUnsupported: true,
                isUnsupportedUSB: false
            )
        )
        XCTAssertFalse(
            ContentNoticePresentation.shouldSuppressTelemetryNoticeDuringConnectionRecovery(
                connectionState: .reconnecting,
                isStrictlyUnsupported: false,
                isUnsupportedUSB: true
            )
        )
    }

    func testUSBTelemetryLimitedNoticeIsSuppressedForUSBSelection() {
        XCTAssertTrue(
            ContentNoticePresentation.shouldSuppressUSBTelemetryLimitedNotice(
                warningMessage: "USB telemetry is incomplete (missing poll rate). Controls stay visible, but values may be stale until readback succeeds.",
                selectedTransport: .usb
            )
        )
    }

    func testUSBTelemetryLimitedNoticeDoesNotSuppressOtherWarnings() {
        XCTAssertFalse(
            ContentNoticePresentation.shouldSuppressUSBTelemetryLimitedNotice(
                warningMessage: "Using the last known values while live telemetry settles.",
                selectedTransport: .usb
            )
        )
        XCTAssertFalse(
            ContentNoticePresentation.shouldSuppressUSBTelemetryLimitedNotice(
                warningMessage: "USB telemetry is incomplete (missing poll rate). Controls stay visible, but values may be stale until readback succeeds.",
                selectedTransport: .bluetooth
            )
        )
    }
}
