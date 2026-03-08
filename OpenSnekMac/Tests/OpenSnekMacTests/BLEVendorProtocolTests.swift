import XCTest
@testable import OpenSnekMac

final class BLEVendorProtocolTests: XCTestCase {
    func testReadHeaderEncoding() {
        let data = BLEVendorProtocol.buildReadHeader(req: 0x34, key: .dpiStagesGet)
        XCTAssertEqual(Array(data), [0x34, 0x00, 0x00, 0x00, 0x0B, 0x84, 0x01, 0x00])
    }

    func testWriteHeaderEncoding() {
        let data = BLEVendorProtocol.buildWriteHeader(req: 0x34, payloadLength: 0x26, key: .dpiStagesSet)
        XCTAssertEqual(Array(data), [0x34, 0x26, 0x00, 0x00, 0x0B, 0x04, 0x01, 0x00])
    }

    func testParsePayloadFramesSuccess() {
        let header = Data([0x40, 0x03, 0, 0, 0, 0, 0, 0x02] + Array(repeating: 0, count: 12))
        let payloadFrame = Data([0xAA, 0xBB, 0xCC] + Array(repeating: 0, count: 17))
        let parsed = BLEVendorProtocol.parsePayloadFrames(notifies: [header, payloadFrame], req: 0x40)
        XCTAssertEqual(Array(parsed ?? Data()), [0xAA, 0xBB, 0xCC])
    }

    func testParsePayloadFramesErrorStatusReturnsNil() {
        let header = Data([0x40, 0x03, 0, 0, 0, 0, 0, 0x03] + Array(repeating: 0, count: 12))
        let payloadFrame = Data([0xAA, 0xBB, 0xCC] + Array(repeating: 0, count: 17))
        let parsed = BLEVendorProtocol.parsePayloadFrames(notifies: [header, payloadFrame], req: 0x40)
        XCTAssertNil(parsed)
    }

    func testParseAndBuildDpiStagesRoundTrip() {
        let payload = BLEVendorProtocol.buildDpiStagePayload(active: 1, count: 3, values: [800, 1600, 3200], marker: 0x03)
        let parsed = BLEVendorProtocol.parseDpiStages(blob: payload)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.active, 1)
        XCTAssertEqual(parsed?.count, 3)
        XCTAssertEqual(parsed?.values.prefix(3), [800, 1600, 3200])
    }

    func testButtonPayloadKeyboardSimple() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x02, kind: .keyboardSimple, hidKey: 0x2C)
        XCTAssertEqual(Array(payload), [0x01, 0x02, 0x00, 0x02, 0x02, 0x00, 0x2C, 0x00, 0x00, 0x00])
    }
}
