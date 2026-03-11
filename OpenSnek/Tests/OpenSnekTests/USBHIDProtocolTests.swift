import XCTest
import OpenSnekProtocols

final class USBHIDProtocolTests: XCTestCase {
    func testIsValidResponseAcceptsMatchingTxnAndArgsPrefix() {
        let response = makeResponse(
            txn: 0x3F,
            classID: 0x02,
            cmdID: 0x8C,
            args: [0x01, 0x6A, 0x00, 0x12, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00]
        )

        XCTAssertTrue(
            USBHIDProtocol.isValidResponse(
                response,
                txn: 0x3F,
                classID: 0x02,
                cmdID: 0x8C,
                expectedArgsPrefix: [0x01, 0x6A, 0x00]
            )
        )
    }

    func testIsValidResponseRejectsMismatchedTxn() {
        let response = makeResponse(
            txn: 0x1F,
            classID: 0x02,
            cmdID: 0x0C,
            args: [0x01, 0x04, 0x00, 0x01, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00]
        )

        XCTAssertFalse(
            USBHIDProtocol.isValidResponse(
                response,
                txn: 0x3F,
                classID: 0x02,
                cmdID: 0x0C,
                expectedArgsPrefix: [0x01, 0x04, 0x00]
            )
        )
    }

    func testIsValidResponseRejectsMismatchedEchoedArgsPrefix() {
        let response = makeResponse(
            txn: 0x1F,
            classID: 0x02,
            cmdID: 0x8C,
            args: [0x02, 0x34, 0x00, 0x0E, 0x01, 0x68, 0x00, 0x14, 0x00, 0x00]
        )

        XCTAssertFalse(
            USBHIDProtocol.isValidResponse(
                response,
                txn: 0x1F,
                classID: 0x02,
                cmdID: 0x8C,
                expectedArgsPrefix: [0x01, 0x6A, 0x00]
            )
        )
    }

    private func makeResponse(txn: UInt8, classID: UInt8, cmdID: UInt8, args: [UInt8]) -> [UInt8] {
        var response = USBHIDProtocol.createReport(
            txn: txn,
            classID: classID,
            cmdID: cmdID,
            size: UInt8(args.count),
            args: args
        )
        response[0] = 0x02
        response[88] = USBHIDProtocol.crc(for: response)
        return response
    }
}
