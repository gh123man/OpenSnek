import XCTest
@testable import OpenSnekHardware

final class USBHIDControlSessionTests: XCTestCase {
    func testPreferredTransactionIDBypassesCachedCandidateAndRescan() {
        XCTAssertEqual(
            USBHIDControlSession.transactionCandidates(
                preferredTransactionID: 0x1F,
                cachedTransactionID: 0x3F,
                allowTxnRescan: true
            ),
            [0x1F]
        )
        XCTAssertEqual(
            USBHIDControlSession.transactionCandidates(
                preferredTransactionID: 0x1F,
                cachedTransactionID: nil,
                allowTxnRescan: false
            ),
            [0x1F]
        )
    }

    func testFallbackTransactionCandidatesUseCacheThenKnownDefaults() {
        XCTAssertEqual(
            USBHIDControlSession.transactionCandidates(
                preferredTransactionID: nil,
                cachedTransactionID: 0x3F,
                allowTxnRescan: true
            ),
            [0x3F, 0x1F, 0xFF]
        )
        XCTAssertEqual(
            USBHIDControlSession.transactionCandidates(
                preferredTransactionID: nil,
                cachedTransactionID: 0x3F,
                allowTxnRescan: false
            ),
            [0x3F]
        )
        XCTAssertEqual(
            USBHIDControlSession.transactionCandidates(
                preferredTransactionID: nil,
                cachedTransactionID: nil,
                allowTxnRescan: true
            ),
            [0x1F, 0x3F, 0xFF]
        )
    }
}
