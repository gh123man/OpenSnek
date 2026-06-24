import XCTest
import Foundation
import OpenSnekCore
import OpenSnekProtocols

/// Exercises USB HID protocol behavior.
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
        XCTAssertEqual(USBHIDProtocol.onboardProfileMetadataChunkDataLength, 0x4B)
        XCTAssertEqual(USBHIDProtocol.onboardProfileMetadataChunkOffsets, [0x0000, 0x004B, 0x0096, 0x00E1])
        XCTAssertEqual(USBHIDProtocol.onboardProfileMetadataKnownFieldLength, 0x00B4)
        XCTAssertEqual(USBHIDProtocol.onboardProfileMetadataWritableChunkOffsets, [0x0000, 0x004B, 0x0096, 0x00E1])
        XCTAssertEqual(USBHIDProtocol.onboardProfileMetadataReadArgs(slot: 0x03, offset: 0x0040), [0x03, 0x00, 0x40, 0x00, 0xFA])
        XCTAssertEqual(USBHIDProtocol.onboardProfileMetadataReadArgs(slot: 0x03, offset: 0x00C0), [0x03, 0x00, 0xC0, 0x00, 0xFA])
    }

    func testActiveProfileIDParsesValidatedUSBReadShape() {
        var response = USBHIDProtocol.createReport(txn: 0x1F, classID: 0x05, cmdID: 0x84, size: 0x00, args: [0x03])
        response[0] = 0x02

        XCTAssertEqual(USBHIDProtocol.activeProfileID(from: response), 0x03)
    }

    func testActiveProfileIDAlsoAcceptsSizedEcho() {
        var response = USBHIDProtocol.createReport(txn: 0x1F, classID: 0x05, cmdID: 0x84, size: 0x01, args: [0x01])
        response[0] = 0x02

        XCTAssertEqual(USBHIDProtocol.activeProfileID(from: response), 0x01)
    }

    func testActiveProfileSetAcceptedRequiresSuccessEcho() {
        var accepted = USBHIDProtocol.createReport(txn: 0x1F, classID: 0x05, cmdID: 0x04, size: 0x01, args: USBHIDProtocol.activeProfileSetArgs(profile: 0x03))
        accepted[0] = 0x02

        var rejected = accepted
        rejected[0] = 0x03

        XCTAssertEqual(USBHIDProtocol.activeProfileSetArgs(profile: 0x03), [0x03])
        XCTAssertTrue(USBHIDProtocol.activeProfileSetAccepted(from: accepted, profile: 0x03))
        XCTAssertFalse(USBHIDProtocol.activeProfileSetAccepted(from: accepted, profile: 0x02))
        XCTAssertFalse(USBHIDProtocol.activeProfileSetAccepted(from: rejected, profile: 0x03))
    }

    func testOnboardProfileInventoryParsesMaxAndAssignedProfiles() {
        var response = USBHIDProtocol.createReport(txn: 0x1F, classID: 0x05, cmdID: 0x81, size: 0x05, args: [0x05, 0x01, 0x03, 0x04, 0x05])
        response[0] = 0x02

        XCTAssertEqual(USBHIDProtocol.onboardProfileInventory(from: response), USBHIDProtocol.OnboardProfileInventory(maxProfileID: 0x05, assignedProfiles: [0x01, 0x03, 0x04, 0x05]))
    }

    func testOnboardProfileCountParsesPayloadByteEvenWhenResponseSizeIsZero() {
        var response = USBHIDProtocol.createReport(txn: 0x1F, classID: 0x05, cmdID: 0x80, size: 0x00, args: [0x02])
        response[0] = 0x02

        XCTAssertEqual(USBHIDProtocol.onboardProfileCount(from: response), 0x02)
    }

    func testProfileLightingEffectReadAndStaticWriteArgs() {
        XCTAssertEqual(USBHIDProtocol.profileLightingEffectReadArgs(profile: 0x02, ledID: 0x0A), [0x02, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(USBHIDProtocol.profileLightingStaticColorSetArgs(profile: 0x02, ledID: 0x04, color: RGBPatch(r: 0x23, g: 0x45, b: 0x67)), [0x02, 0x04, 0x01, 0x00, 0x00, 0x01, 0x23, 0x45, 0x67])
    }

    func testLightingCustomFrameArgsUseRGBTripletsAfterReservedPad() {
        XCTAssertEqual(USBHIDProtocol.lightingCustomFrameArgs(storage: 0x01, row: 0x00, startColumn: 0x00, colors: [RGBPatch(r: 0x11, g: 0x22, b: 0x33), RGBPatch(r: 0x44, g: 0x55, b: 0x66)]), [0x01, 0x00, 0x00, 0x01, 0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66])
    }

    func testLightingCustomFrameArgsCanAddressSingleOffsetCell() { XCTAssertEqual(USBHIDProtocol.lightingCustomFrameArgs(storage: 0x00, row: 0x01, startColumn: 0x0D, colors: [RGBPatch(r: 0xFF, g: 0x00, b: 0x00)]), [0x00, 0x01, 0x0D, 0x0D, 0x00, 0xFF, 0x00, 0x00]) }

    func testLightingCustomFrameArgsCanAddressFourteenCellV3FamilyFrame() {
        let colors = (0..<14).map { index in RGBPatch(r: index, g: index + 1, b: index + 2) }
        let args = USBHIDProtocol.lightingCustomFrameArgs(storage: 0x01, row: 0x00, startColumn: 0x00, colors: colors)

        XCTAssertEqual(args.count, 47)
        XCTAssertEqual(Array(args.prefix(5)), [0x01, 0x00, 0x00, 0x0D, 0x00])
        XCTAssertEqual(Array(args.suffix(3)), [0x0D, 0x0E, 0x0F])
    }

    func testProfileLightingEffectStateParsesStaticColorReadback() throws {
        var response = USBHIDProtocol.createReport(txn: 0x1F, classID: 0x0F, cmdID: 0x82, size: 0x0C, args: [0x00, 0x04, 0x01, 0x00, 0x00, 0x01, 0x23, 0x45, 0x67, 0x00, 0x00, 0x00])
        response[0] = 0x02

        let state = try XCTUnwrap(USBHIDProtocol.profileLightingEffectState(from: response, expectedLEDID: 0x04))

        XCTAssertEqual(state.storageEcho, 0x00)
        XCTAssertEqual(state.ledID, 0x04)
        XCTAssertEqual(state.effectID, 0x01)
        XCTAssertEqual(state.staticColor, RGBPatch(r: 0x23, g: 0x45, b: 0x67))
        XCTAssertNil(USBHIDProtocol.profileLightingEffectState(from: response, expectedLEDID: 0x01))
    }

    func testProfileLightingEffectStateKeepsNonStaticPayloadRaw() throws {
        var response = USBHIDProtocol.createReport(txn: 0x1F, classID: 0x0F, cmdID: 0x82, size: 0x0C, args: [0x00, 0x01, 0x03, 0x01, 0x28, 0x01, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00])
        response[0] = 0x02

        let state = try XCTUnwrap(USBHIDProtocol.profileLightingEffectState(from: response, expectedLEDID: 0x01))

        XCTAssertEqual(state.effectID, 0x03)
        XCTAssertEqual(state.payload, [0x00, 0x01, 0x03, 0x01, 0x28, 0x01, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00])
        XCTAssertNil(state.staticColor)
    }

    func testOnboardProfileMetadataChunkParsesEchoedHeaderAndData() {
        let chunkData: [UInt8] = [0x9E, 0xE3, 0xAA, 0xC7, 0xB0, 0x43]
        let args = USBHIDProtocol.onboardProfileMetadataReadArgs(slot: 0x03, offset: 0x0040) + chunkData
        var response = USBHIDProtocol.createReport(txn: 0x1F, classID: 0x05, cmdID: 0x88, size: UInt8(args.count), args: args)
        response[0] = 0x02

        let chunk = USBHIDProtocol.onboardProfileMetadataChunk(from: response, expectedSlot: 0x03, expectedOffset: 0x0040)

        XCTAssertEqual(chunk?.slot, 0x03)
        XCTAssertEqual(chunk?.offset, 0x0040)
        XCTAssertEqual(chunk?.totalLength, 0xFA)
        XCTAssertEqual(chunk?.data, chunkData)
    }

    func testParseOnboardProfileMetadataDecodesWindowsGUIDNameAndOwner() {
        var metadata = [UInt8](repeating: 0x00, count: USBHIDProtocol.onboardProfileMetadataLength)
        metadata.replaceSubrange(0..<16, with: [0x9E, 0xE3, 0xAA, 0xC7, 0xB0, 0x43, 0xAE, 0x41, 0xBF, 0x46, 0xB4, 0xAE, 0x55, 0x6A, 0x4A, 0x02])
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

        XCTAssertEqual(bytes, [0x67, 0x45, 0x23, 0x01, 0xAB, 0x89, 0xDE, 0x4C, 0x8F, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD])
        XCTAssertEqual(USBHIDProtocol.uuidFromWindowsGUIDBytes(bytes), uuid)
    }

    func testAllFFProfileMetadataUUIDIsInvalid() {
        XCTAssertNil(USBHIDProtocol.uuidFromWindowsGUIDBytes([UInt8](repeating: 0xFF, count: 16)))

        var metadata = [UInt8](repeating: 0x00, count: USBHIDProtocol.onboardProfileMetadataLength)
        metadata.replaceSubrange(0..<16, with: [UInt8](repeating: 0xFF, count: 16))
        metadata.replaceSubrange(0x10..<(0x10 + "Corrupt".utf8.count), with: "Corrupt".utf8)

        let parsed = USBHIDProtocol.parseOnboardProfileMetadata(metadata)

        XCTAssertNil(parsed.identifier)
        XCTAssertEqual(parsed.name, "Corrupt")
    }

    func testMergeOnboardProfileMetadataChunksUsesOffsets() {
        let prefix = USBHIDProtocol.OnboardProfileMetadataChunk(slot: 0x03, offset: 0x0000, totalLength: 0xFA, data: [0xAA, 0xBB])
        let later = USBHIDProtocol.OnboardProfileMetadataChunk(slot: 0x03, offset: 0x0040, totalLength: 0xFA, data: [0xCC, 0xDD])

        let merged = USBHIDProtocol.mergeOnboardProfileMetadataChunks([later, prefix])

        XCTAssertEqual(merged.count, 0xFA)
        XCTAssertEqual(merged[0], 0xAA)
        XCTAssertEqual(merged[1], 0xBB)
        XCTAssertEqual(merged[0x40], 0xCC)
        XCTAssertEqual(merged[0x41], 0xDD)
    }

    func testOnboardProfileMetadataWriteArgsUseFullUSBChunkShape() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "01234567-89ab-4cde-8f01-23456789abcd"))
        let metadata = USBHIDProtocol.buildOnboardProfileMetadata(identifier: uuid, name: "Slot 2", owner: "OpenSnek")
        let args = USBHIDProtocol.onboardProfileMetadataWriteArgs(slot: 0x02, offset: 0x004B, metadata: metadata)

        XCTAssertEqual(args.count, 0x50)
        XCTAssertEqual(Array(args.prefix(5)), [0x02, 0x00, 0x4B, 0x00, 0xFA])
        XCTAssertEqual(USBHIDProtocol.parseOnboardProfileMetadata(metadata).identifier, uuid)
        XCTAssertEqual(USBHIDProtocol.parseOnboardProfileMetadata(metadata).name, "Slot 2")
        XCTAssertEqual(USBHIDProtocol.parseOnboardProfileMetadata(metadata).owner, "OpenSnek")
    }

    func testOnboardProfileCreateAndDeleteAckParsing() {
        var create = USBHIDProtocol.createReport(txn: 0x1F, classID: 0x05, cmdID: 0x02, size: 0x01, args: USBHIDProtocol.onboardProfileCreateArgs(profile: 0x02))
        create[0] = 0x02
        var delete = USBHIDProtocol.createReport(txn: 0x20, classID: 0x05, cmdID: 0x03, size: 0x01, args: USBHIDProtocol.onboardProfileDeleteArgs(profile: 0x02))
        delete[0] = 0x02

        XCTAssertTrue(USBHIDProtocol.onboardProfileCreateAccepted(from: create, profile: 0x02))
        XCTAssertFalse(USBHIDProtocol.onboardProfileCreateAccepted(from: create, profile: 0x03))
        XCTAssertTrue(USBHIDProtocol.onboardProfileDeleteAccepted(from: delete, profile: 0x02))
        XCTAssertFalse(USBHIDProtocol.onboardProfileDeleteAccepted(from: delete, profile: 0x03))
    }
}
