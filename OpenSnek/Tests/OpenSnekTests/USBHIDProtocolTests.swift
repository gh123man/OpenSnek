import XCTest
import Foundation
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

    func testOnboardProfileMetadataReadArgsUseOpenRazerChunkHeaderOrder() {
        XCTAssertEqual(
            USBHIDProtocol.onboardProfileMetadataReadArgs(slot: 0x03, offset: 0x0040),
            [0x03, 0x00, 0x40, 0x00, 0xFA]
        )
        XCTAssertEqual(
            USBHIDProtocol.onboardProfileMetadataReadArgs(slot: 0x03, offset: 0x00C0),
            [0x03, 0x00, 0xC0, 0x00, 0xFA]
        )
    }

    func testActiveProfileIDParsesValidatedUSBReadShape() {
        var response = USBHIDProtocol.createReport(
            txn: 0x1F,
            classID: 0x05,
            cmdID: 0x84,
            size: 0x00,
            args: [0x03]
        )
        response[0] = 0x02

        XCTAssertEqual(USBHIDProtocol.activeProfileID(from: response), 0x03)
    }

    func testActiveProfileIDAlsoAcceptsSizedEcho() {
        var response = USBHIDProtocol.createReport(
            txn: 0x1F,
            classID: 0x05,
            cmdID: 0x84,
            size: 0x01,
            args: [0x01]
        )
        response[0] = 0x02

        XCTAssertEqual(USBHIDProtocol.activeProfileID(from: response), 0x01)
    }

    func testActiveProfileSetAcceptedRequiresSuccessEcho() {
        var accepted = USBHIDProtocol.createReport(
            txn: 0x1F,
            classID: 0x05,
            cmdID: 0x04,
            size: 0x01,
            args: USBHIDProtocol.activeProfileSetArgs(profile: 0x03)
        )
        accepted[0] = 0x02

        var rejected = accepted
        rejected[0] = 0x03

        XCTAssertEqual(USBHIDProtocol.activeProfileSetArgs(profile: 0x03), [0x03])
        XCTAssertTrue(USBHIDProtocol.activeProfileSetAccepted(from: accepted, profile: 0x03))
        XCTAssertFalse(USBHIDProtocol.activeProfileSetAccepted(from: accepted, profile: 0x02))
        XCTAssertFalse(USBHIDProtocol.activeProfileSetAccepted(from: rejected, profile: 0x03))
    }

    func testOnboardProfileMetadataChunkParsesEchoedHeaderAndData() {
        let chunkData: [UInt8] = [0x9E, 0xE3, 0xAA, 0xC7, 0xB0, 0x43]
        let args = USBHIDProtocol.onboardProfileMetadataReadArgs(slot: 0x03, offset: 0x0040) + chunkData
        var response = USBHIDProtocol.createReport(
            txn: 0x1F,
            classID: 0x05,
            cmdID: 0x88,
            size: UInt8(args.count),
            args: args
        )
        response[0] = 0x02

        let chunk = USBHIDProtocol.onboardProfileMetadataChunk(
            from: response,
            expectedSlot: 0x03,
            expectedOffset: 0x0040
        )

        XCTAssertEqual(chunk?.slot, 0x03)
        XCTAssertEqual(chunk?.offset, 0x0040)
        XCTAssertEqual(chunk?.totalLength, 0xFA)
        XCTAssertEqual(chunk?.data, chunkData)
    }

    func testParseOnboardProfileMetadataDecodesWindowsGUIDNameAndOwner() {
        var metadata = [UInt8](repeating: 0x00, count: USBHIDProtocol.onboardProfileMetadataLength)
        metadata.replaceSubrange(0..<16, with: [
            0x9E, 0xE3, 0xAA, 0xC7, 0xB0, 0x43, 0xAE, 0x41,
            0xBF, 0x46, 0xB4, 0xAE, 0x55, 0x6A, 0x4A, 0x02,
        ])
        metadata.replaceSubrange(0x10..<(0x10 + "OPENSNEK_RECREATE_SLOT_2".utf8.count), with: "OPENSNEK_RECREATE_SLOT_2".utf8)
        metadata.replaceSubrange(0x74..<(0x74 + 64), with: "31933b5452df5708882d4fb55d0b2905f16d829500fe936c56f98d5cd0241a76".utf8)

        let parsed = USBHIDProtocol.parseOnboardProfileMetadata(metadata)

        XCTAssertEqual(parsed.identifier, UUID(uuidString: "c7aae39e-43b0-41ae-bf46-b4ae556a4a02"))
        XCTAssertEqual(parsed.name, "OPENSNEK_RECREATE_SLOT_2")
        XCTAssertEqual(parsed.owner, "31933b5452df5708882d4fb55d0b2905f16d829500fe936c56f98d5cd0241a76")
    }

    func testWindowsGUIDBytesRoundTripsThroughMetadataParser() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "01234567-89ab-4cde-8f01-23456789abcd"))
        let bytes = USBHIDProtocol.windowsGUIDBytes(from: uuid)

        XCTAssertEqual(bytes, [
            0x67, 0x45, 0x23, 0x01, 0xAB, 0x89, 0xDE, 0x4C,
            0x8F, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD,
        ])
        XCTAssertEqual(USBHIDProtocol.uuidFromWindowsGUIDBytes(bytes), uuid)
    }

    func testMergeOnboardProfileMetadataChunksUsesOffsets() {
        let prefix = USBHIDProtocol.OnboardProfileMetadataChunk(
            slot: 0x03,
            offset: 0x0000,
            totalLength: 0xFA,
            data: [0xAA, 0xBB]
        )
        let later = USBHIDProtocol.OnboardProfileMetadataChunk(
            slot: 0x03,
            offset: 0x0040,
            totalLength: 0xFA,
            data: [0xCC, 0xDD]
        )

        let merged = USBHIDProtocol.mergeOnboardProfileMetadataChunks([later, prefix])

        XCTAssertEqual(merged.count, 0xFA)
        XCTAssertEqual(merged[0], 0xAA)
        XCTAssertEqual(merged[1], 0xBB)
        XCTAssertEqual(merged[0x40], 0xCC)
        XCTAssertEqual(merged[0x41], 0xDD)
    }
}
