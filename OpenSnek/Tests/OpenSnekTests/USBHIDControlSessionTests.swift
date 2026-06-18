import XCTest
@testable import OpenSnekHardware

final class USBHIDControlSessionTests: XCTestCase {
    func testInterprocessLockFileNameSanitizesDeviceID() {
        XCTAssertEqual(
            USBHIDControlSession.interprocessLockFileName(for: "1532:00ab:00130000:usb"),
            "1532_00ab_00130000_usb.lock"
        )
        XCTAssertEqual(
            USBHIDControlSession.interprocessLockFileName(for: ""),
            "unknown-usb-device.lock"
        )
    }

    func testPreferredTransactionIDBypassesCachedCandidateAndRescan() {
        XCTAssertEqual(
            USBHIDControlSession.transactionCandidates(
                preferredTransactionID: 0x1F,
                cachedTransactionID: 0x3F
            ),
            [0x1F]
        )
        XCTAssertEqual(
            USBHIDControlSession.transactionCandidates(
                preferredTransactionID: 0x1F,
                cachedTransactionID: nil
            ),
            [0x1F]
        )
    }

    func testFallbackTransactionCandidateUsesSingleValue() {
        XCTAssertEqual(
            USBHIDControlSession.transactionCandidates(
                preferredTransactionID: nil,
                cachedTransactionID: 0x3F
            ),
            [0x3F]
        )
        XCTAssertEqual(
            USBHIDControlSession.transactionCandidates(
                preferredTransactionID: nil,
                cachedTransactionID: nil
            ),
            [0x1F]
        )
    }
}
