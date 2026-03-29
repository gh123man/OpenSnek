import XCTest
import OpenSnekProtocols

final class USBHIDProtocolTests: XCTestCase {
    func testIsValidResponseAcceptsMatchingTransactionID() {
        var response = USBHIDProtocol.createReport(txn: 0x1F, classID: 0x07, cmdID: 0x80, size: 0x02, args: [0x01, 0xF0])
        response[0] = 0x02

        XCTAssertTrue(USBHIDProtocol.isValidResponse(response, txn: 0x1F, classID: 0x07, cmdID: 0x80))
    }

    func testIsValidResponseRejectsMismatchedTransactionID() {
        var response = USBHIDProtocol.createReport(txn: 0x3F, classID: 0x07, cmdID: 0x80, size: 0x02, args: [0x01, 0xF0])
        response[0] = 0x02

        XCTAssertFalse(USBHIDProtocol.isValidResponse(response, txn: 0x1F, classID: 0x07, cmdID: 0x80))
    }
}
