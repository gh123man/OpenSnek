import XCTest
@testable import OpenSnek

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
}
