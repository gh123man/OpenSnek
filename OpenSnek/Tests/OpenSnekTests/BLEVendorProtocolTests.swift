import XCTest
import OpenSnekCore
import OpenSnekProtocols

/// Exercises BLE vendor protocol behavior.
final class BLEVendorProtocolTests: XCTestCase {
    func testReadHeaderEncoding() {
        let data = BLEVendorProtocol.buildReadHeader(req: 0x34, key: .dpiStagesGet)
        XCTAssertEqual(Array(data), [0x34, 0x00, 0x00, 0x00, 0x0B, 0x84, 0x01, 0x00])
    }

    func testWriteHeaderEncoding() {
        let data = BLEVendorProtocol.buildWriteHeader(req: 0x34, payloadLength: 0x26, key: .dpiStagesSet)
        XCTAssertEqual(Array(data), [0x34, 0x26, 0x00, 0x00, 0x0B, 0x04, 0x01, 0x00])
    }

    func testWriteFramesChunkLargePayloads() {
        let payload = Data((0..<0x4C).map(UInt8.init))
        let frames = BLEVendorProtocol.buildWriteFrames(
            req: 0x44,
            key: .profileMetadataSet(target: 0x02),
            payload: payload
        )

        XCTAssertEqual(Array(frames[0]), [0x44, 0x4C, 0x00, 0x00, 0x03, 0x04, 0x02, 0x00])
        XCTAssertEqual(frames.map(\.count), [8, 20, 20, 20, 16])
        XCTAssertEqual(frames.dropFirst().reduce(into: Data()) { $0.append($1) }, payload)
    }

    func testLightingBrightnessKeyBuildersSupportPerZoneIDs() {
        XCTAssertEqual(BLEVendorProtocol.Key.lightingBrightnessGet(ledID: 0x04).bytes, [0x10, 0x85, 0x01, 0x04])
        XCTAssertEqual(BLEVendorProtocol.Key.lightingBrightnessSet(ledID: 0x0A).bytes, [0x10, 0x05, 0x01, 0x0A])
    }

    func testV3ProLightingZoneStateKeyBuilders() {
        XCTAssertEqual(BLEVendorProtocol.Key.lightingZoneStateGet(ledID: 0x01).bytes, [0x10, 0x83, 0x00, 0x01])
        XCTAssertEqual(BLEVendorProtocol.Key.lightingZoneStateSet(ledID: 0x04).bytes, [0x10, 0x03, 0x00, 0x04])
    }

    func testProfileTargetKeyBuilders() {
        XCTAssertEqual(BLEVendorProtocol.Key.profileTargetsGet().bytes, [0x03, 0x80, 0x00, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.profileActiveTargetGet().bytes, [0x03, 0x82, 0x00, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.profileActiveTargetSet().bytes, [0x03, 0x02, 0x00, 0x00])
        XCTAssertEqual(Array(BLEVendorProtocol.Key.profileActiveTargetSetPayload(target: 0x03)), [0x03])
        XCTAssertEqual(BLEVendorProtocol.Key.profileMetadataGet(target: 0x03).bytes, [0x03, 0x84, 0x03, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.profileMetadataSet(target: 0x02).bytes, [0x03, 0x04, 0x02, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.profileTargetDelete(target: 0x02).bytes, [0x03, 0x06, 0x02, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.profileTargetCommit(target: 0x02).bytes, [0x03, 0x05, 0x02, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.profileTargetStatusGet(target: 0x02).bytes, [0x01, 0x8C, 0x02, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.profileTargetPrepare(target: 0x02).bytes, [0x08, 0x05, 0x02, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.profileTargetApply(target: 0x02).bytes, [0x08, 0x07, 0x02, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.buttonBindGet(target: 0x03, slot: 0x05).bytes, [0x08, 0x84, 0x03, 0x05])
        XCTAssertEqual(BLEVendorProtocol.Key.buttonBindSet(target: 0x05, slot: 0x05).bytes, [0x08, 0x04, 0x05, 0x05])
        XCTAssertEqual(BLEVendorProtocol.Key.dpiScalarGet(target: 0x00).bytes, [0x0B, 0x81, 0x00, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.dpiPairListGet(target: 0x02).bytes, [0x0B, 0x82, 0x02, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.dpiStageTokenGet(target: 0x05).bytes, [0x0B, 0x83, 0x05, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.dpiProjectionGet(target: 0x01).bytes, [0x0B, 0x84, 0x01, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.storedDpiScalarSet(target: 0x02).bytes, [0x0B, 0x01, 0x02, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.storedDpiStagesSet(target: 0x02).bytes, [0x0B, 0x04, 0x02, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.storedLightingBrightnessSet(target: 0x02).bytes, [0x10, 0x05, 0x02, 0x00])
        XCTAssertEqual(BLEVendorProtocol.Key.profileLightingBrightnessGet(target: 0x03, ledID: 0x04).bytes, [0x10, 0x85, 0x03, 0x04])
        XCTAssertEqual(BLEVendorProtocol.Key.profileLightingZoneStateGet(target: 0x03, ledID: 0x01).bytes, [0x10, 0x83, 0x03, 0x01])
        XCTAssertEqual(BLEVendorProtocol.Key.profileLightingZoneStateSet(target: 0x03, ledID: 0x0A).bytes, [0x10, 0x03, 0x03, 0x0A])
    }

    func testBluetoothButtonReadPrefersAuthoritativeEvenLaneOverDefaultOddLane() {
        let payload = Data([
            0x09, 0x00,
            0x01, 0x01,
            0x01, 0x01,
            0x0A, 0x09,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00,
            0x00, 0x00
        ])

        let block = BLEVendorProtocol.extractBluetoothFunctionBlock(
            payload: payload,
            target: 0x02,
            slot: 0x09,
            profileID: .basiliskV3Pro
        )
        let draft = block.flatMap {
            ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(
                slot: 9,
                functionBlock: $0,
                profileID: .basiliskV3Pro
            )
        }

        XCTAssertEqual(block, [0x01, 0x01, 0x0A, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(draft?.kind, .scrollDown)
    }

    func testBluetoothButtonReadTreatsShortWheelTiltBlockAsSlotDefault() {
        let payload = Data([
            0x34, 0x00,
            0x0E, 0x0E,
            0x01, 0x01,
            0x68, 0x68,
            0x00, 0x00,
            0x14, 0x14,
            0x00, 0x00,
            0x00, 0x00
        ])

        let block = BLEVendorProtocol.extractBluetoothFunctionBlock(
            payload: payload,
            target: 0x02,
            slot: 0x34,
            profileID: .basiliskV3Pro
        )
        let draft = block.flatMap {
            ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(
                slot: 52,
                functionBlock: $0,
                profileID: .basiliskV3Pro
            )
        }

        XCTAssertEqual(block, [0x0E, 0x01, 0x68, 0x00, 0x14, 0x00, 0x00])
        XCTAssertEqual(draft?.kind, .default)
    }

    func testParsePayloadFramesSuccess() {
        let header = Data([0x40, 0x03, 0, 0, 0, 0, 0, 0x02] + Array(repeating: 0, count: 12))
        let payloadFrame = Data([0xAA, 0xBB, 0xCC] + Array(repeating: 0, count: 17))
        let parsed = BLEVendorProtocol.parsePayloadFrames(notifies: [header, payloadFrame], req: 0x40)
        XCTAssertEqual(Array(parsed ?? Data()), [0xAA, 0xBB, 0xCC])
    }

    func testParsePayloadFramesSupportsEightByteHeaderAndShortFinalFrame() {
        let header = Data([0x30, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02])
        let firstPayload = Data([
            0x03, 0x05, 0x01, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00, 0x02,
            0x84, 0x03, 0x84, 0x03, 0x00, 0x00, 0x03, 0xD0, 0x07, 0xD0
        ])
        let finalPayload = Data([
            0x07, 0x00, 0x00, 0x04, 0x4C, 0x04, 0x4C, 0x04,
            0x00, 0x00, 0x05, 0xB0, 0x04, 0xB0, 0x04, 0x00
        ])

        let parsed = BLEVendorProtocol.parsePayloadFrames(
            notifies: [header, firstPayload, finalPayload],
            req: 0x30
        )

        XCTAssertEqual(parsed?.count, 0x24)
        XCTAssertEqual(
            parsed,
            firstPayload + finalPayload
        )
    }

    func testParsePayloadFramesSupportsEightByteHeaderScalarPayload() {
        let header = Data([0x32, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02])
        let payload = Data([0xFF])

        let parsed = BLEVendorProtocol.parsePayloadFrames(notifies: [header, payload], req: 0x32)

        XCTAssertEqual(parsed, payload)
    }

    func testParseLightingLEDIDsPreservesOrderAndDeduplicates() {
        let ids = BLEVendorProtocol.parseLightingLEDIDs(blob: Data([0x04, 0x01, 0x0A, 0x04]))
        XCTAssertEqual(ids, [0x04, 0x01, 0x0A])
    }

    func testParsePayloadFramesErrorStatusReturnsNil() {
        let header = Data([0x40, 0x03, 0, 0, 0, 0, 0, 0x03] + Array(repeating: 0, count: 12))
        let payloadFrame = Data([0xAA, 0xBB, 0xCC] + Array(repeating: 0, count: 17))
        let parsed = BLEVendorProtocol.parsePayloadFrames(notifies: [header, payloadFrame], req: 0x40)
        XCTAssertNil(parsed)
    }

    func testParseAndBuildDpiStagesRoundTrip() {
        let payload = BLEVendorProtocol.buildDpiStagePayload(active: 1, count: 3, slots: [800, 1600, 3200, 6400, 12000], marker: 0x03)
        let parsed = BLEVendorProtocol.parseDpiStages(blob: payload)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.active, 1)
        XCTAssertEqual(parsed?.count, 3)
        XCTAssertEqual(parsed?.values.prefix(3), [800, 1600, 3200])
        XCTAssertEqual(parsed?.pairs.prefix(3), [DpiPair(x: 800, y: 800), DpiPair(x: 1600, y: 1600), DpiPair(x: 3200, y: 3200)])
    }

    func testParseFlatDpiPairListFromProfileTargetPayload() {
        let payload = Data([
            0x20, 0x03, 0x20, 0x03, 0x00, 0x00,
            0x84, 0x03, 0x84, 0x03, 0x00, 0x00,
            0xD0, 0x07, 0xD0, 0x07, 0x00, 0x00
        ])

        XCTAssertEqual(
            BLEVendorProtocol.parseDpiPairList(blob: payload),
            [
                DpiPair(x: 800, y: 800),
                DpiPair(x: 900, y: 900),
                DpiPair(x: 2000, y: 2000)
            ]
        )
        XCTAssertEqual(BLEVendorProtocol.parseDpiScalarPair(blob: payload), DpiPair(x: 800, y: 800))
    }

    func testBuildDpiStagesRoundTripPreservesIndependentXYPairs() {
        let payload = BLEVendorProtocol.buildDpiStagePayload(
            active: 1,
            count: 2,
            pairs: [DpiPair(x: 1600, y: 2000), DpiPair(x: 3200, y: 3600)],
            marker: 0x03,
            stageIDs: [0x07, 0x09]
        )
        let parsed = BLEVendorProtocol.parseDpiStages(blob: payload)
        XCTAssertEqual(parsed?.active, 1)
        XCTAssertEqual(parsed?.values, [1600, 3200])
        XCTAssertEqual(parsed?.pairs, [DpiPair(x: 1600, y: 2000), DpiPair(x: 3200, y: 3600)])
    }

    func testMergedStageSlotsSingleModeMirrors() {
        let merged = BLEVendorProtocol.mergedStageSlots(
            currentSlots: [400, 800, 1600, 3200, 6400],
            requestedCount: 1,
            requestedValues: [1800]
        )
        XCTAssertEqual(merged, [1800, 1800, 1800, 1800, 1800])
    }

    func testMergedStageSlotsMultiModePreservesTail() {
        let merged = BLEVendorProtocol.mergedStageSlots(
            currentSlots: [400, 800, 1600, 3200, 6400],
            requestedCount: 3,
            requestedValues: [500, 900, 1700]
        )
        XCTAssertEqual(merged, [500, 900, 1700, 3200, 6400])
    }

    func testButtonPayloadKeyboardSimple() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x02, kind: .keyboardSimple, hidKey: 0x2C)
        XCTAssertEqual(Array(payload), [0x01, 0x02, 0x00, 0x02, 0x02, 0x00, 0x2C, 0x00, 0x00, 0x00])
    }

    func testRetargetButtonPayloadForStoredProfileTargets() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x05, kind: .keyboardSimple, hidKey: 0x09)
        let storedTargetPayload = BLEVendorProtocol.retargetButtonPayload(payload, target: 0x05, slot: 0x05)
        XCTAssertEqual(Array(storedTargetPayload), [0x05, 0x05, 0x00, 0x02, 0x02, 0x00, 0x09, 0x00, 0x00, 0x00])
    }

    func testProfileInventoryAndActiveTargetParsing() {
        XCTAssertEqual(BLEVendorProtocol.parseProfileTargets(payload: Data([0x01, 0x03, 0x00, 0x09]), maxProfileID: 5), [1, 3])
        XCTAssertEqual(BLEVendorProtocol.parseActiveTarget(payload: Data([0x03])), 3)
        XCTAssertNil(BLEVendorProtocol.parseActiveTarget(payload: Data([0x09])))
    }

    func testProfileMetadataReadAndWriteChunkHelpers() throws {
        let uuid = try XCTUnwrap(UUID(uuidString: "01234567-89ab-4cde-8f01-23456789abcd"))
        let metadata = BLEVendorProtocol.buildProfileMetadata(identifier: uuid, name: "BT Slot", owner: "OpenSnek")
        let readRequest = BLEVendorProtocol.profileMetadataReadRequest(offset: 0x0098, length: 0x4C)
        let writePayload = BLEVendorProtocol.profileMetadataWritePayload(offset: 0x0098, metadata: metadata)
        let responsePayload = Data([0x98, 0x00]) + Data(metadata[0x0098..<(0x0098 + 0x04)])
        let chunk = BLEVendorProtocol.profileMetadataChunk(from: responsePayload, expectedOffset: 0x0098)

        XCTAssertEqual(Array(readRequest), [0x98, 0x00, 0x4C, 0x00])
        XCTAssertEqual(Array(writePayload.prefix(4)), [0xFA, 0x00, 0x98, 0x00])
        XCTAssertEqual(chunk?.offset, 0x0098)
        XCTAssertEqual(chunk?.data, Array(metadata[0x0098..<(0x0098 + 0x04)]))
        XCTAssertEqual(BLEVendorProtocol.parseProfileMetadata(metadata).identifier, uuid)
        XCTAssertEqual(BLEVendorProtocol.parseProfileMetadata(metadata).name, "BT Slot")
    }

    func testBluetoothButtonReadbackExtractsInterleavedFunctionBlock() {
        let functionBlock: [UInt8] = [0x01, 0x01, 0x05, 0x00, 0x00, 0x00, 0x00]
        let previousBlock: [UInt8] = [0x01, 0x01, 0x04, 0x00, 0x00, 0x00, 0x00]
        var interleaved: [UInt8] = [0x05, 0x00]
        for index in functionBlock.indices {
            interleaved.append(functionBlock[index])
            interleaved.append(previousBlock[index])
        }

        XCTAssertEqual(
            BLEVendorProtocol.extractBluetoothFunctionBlock(
                payload: Data(interleaved),
                target: 0x02,
                slot: 0x05,
                profileID: .basiliskV3Pro
            ),
            functionBlock
        )
    }

    func testButtonPayloadKeyboardShortcutIncludesModifiers() {
        let payload = BLEVendorProtocol.buildButtonPayload(
            slot: 0x02,
            kind: .keyboardSimple,
            hidKey: 0x2F,
            hidModifiers: 0x08
        )
        XCTAssertEqual(Array(payload), [0x01, 0x02, 0x00, 0x02, 0x02, 0x08, 0x2F, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadKeyboardTurbo() {
        let payload = BLEVendorProtocol.buildButtonPayload(
            slot: 0x03,
            kind: .keyboardSimple,
            hidKey: 0x08,
            turboEnabled: true,
            turboRate: 0x008E
        )
        XCTAssertEqual(Array(payload), [0x01, 0x03, 0x00, 0x0D, 0x04, 0x00, 0x08, 0x00, 0x8E, 0x00])
    }

    func testButtonPayloadKeyboardTurboShortcutIncludesModifiers() {
        let payload = BLEVendorProtocol.buildButtonPayload(
            slot: 0x03,
            kind: .keyboardSimple,
            hidKey: 0x2F,
            hidModifiers: 0x08,
            turboEnabled: true,
            turboRate: 0x008E
        )
        XCTAssertEqual(Array(payload), [0x01, 0x03, 0x00, 0x0D, 0x04, 0x08, 0x2F, 0x00, 0x8E, 0x00])
    }

    func testButtonPayloadMiddleClick() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x03, kind: .middleClick, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x03, 0x00, 0x01, 0x01, 0x03, 0x00, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadScrollUp() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x09, kind: .scrollUp, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x09, 0x00, 0x01, 0x01, 0x09, 0x00, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadScrollDown() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x0A, kind: .scrollDown, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x0A, 0x00, 0x01, 0x01, 0x0A, 0x00, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadScrollLeft() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x34, kind: .scrollLeft, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x34, 0x00, 0x0E, 0x03, 0x68, 0x00, 0x14, 0x00, 0x00])
    }

    func testButtonPayloadScrollRight() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x35, kind: .scrollRight, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x35, 0x00, 0x0E, 0x03, 0x69, 0x00, 0x14, 0x00, 0x00])
    }

    func testButtonPayloadMouseBack() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x05, kind: .mouseBack, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x05, 0x00, 0x01, 0x01, 0x04, 0x00, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadMouseForward() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x04, kind: .mouseForward, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x04, 0x00, 0x01, 0x01, 0x05, 0x00, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadRightClickTurbo() {
        let payload = BLEVendorProtocol.buildButtonPayload(
            slot: 0x02,
            kind: .rightClick,
            hidKey: nil,
            turboEnabled: true,
            turboRate: 0x003E
        )
        XCTAssertEqual(Array(payload), [0x01, 0x02, 0x00, 0x0E, 0x03, 0x01, 0x3E, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadDefaultSlot2UsesExplicitRightClickRestore() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x02, kind: .default, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x02, 0x00, 0x01, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadDefaultSlot1UsesLeftClickRestore() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x01, kind: .default, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x01, 0x00, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadDefaultSlot4UsesBackRestore() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x04, kind: .default, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x04, 0x00, 0x01, 0x01, 0x04, 0x00, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadDefaultWheelTiltSlotsRestoreHorizontalScroll() {
        let leftPayload = BLEVendorProtocol.buildButtonPayload(slot: 0x34, kind: .default, hidKey: nil)
        let rightPayload = BLEVendorProtocol.buildButtonPayload(slot: 0x35, kind: .default, hidKey: nil)
        XCTAssertEqual(Array(leftPayload), [0x01, 0x34, 0x00, 0x0E, 0x03, 0x68, 0x00, 0x14, 0x00, 0x00])
        XCTAssertEqual(Array(rightPayload), [0x01, 0x35, 0x00, 0x0E, 0x03, 0x69, 0x00, 0x14, 0x00, 0x00])
    }

    func testButtonPayloadTurboHorizontalScrollUsesRawTurboForm() {
        let payload = BLEVendorProtocol.buildButtonPayload(
            slot: 0x34,
            kind: .scrollLeft,
            hidKey: nil,
            turboEnabled: true,
            turboRate: 0x0032
        )

        XCTAssertEqual(Array(payload), [0x01, 0x34, 0x00, 0x0E, 0x03, 0x68, 0x00, 0x32, 0x00, 0x00])
    }

    func testButtonPayloadDefaultSlot60UsesCaptureBackedDpiRestore() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x60, kind: .default, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x60, 0x00, 0x06, 0x01, 0x06, 0x00, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadDPICycleUsesCaptureBackedAction() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x04, kind: .dpiCycle, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x04, 0x00, 0x06, 0x01, 0x06, 0x00, 0x00, 0x00, 0x00])
    }

    func testButtonPayloadDPIClutchUsesV3ProCaptureBackedDefault() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x0F, kind: .dpiClutch, hidKey: nil)
        XCTAssertEqual(Array(payload), [0x01, 0x0F, 0x00, 0x06, 0x05, 0x05, 0x01, 0x90, 0x01, 0x90])
    }

    func testButtonPayloadDPIClutchUsesBigEndianConfiguredDPI() {
        let payload = BLEVendorProtocol.buildButtonPayload(
            slot: 0x0F,
            kind: .dpiClutch,
            hidKey: nil,
            clutchDPI: 800
        )
        XCTAssertEqual(Array(payload), [0x01, 0x0F, 0x00, 0x06, 0x05, 0x05, 0x03, 0x20, 0x03, 0x20])
    }

    func testButtonPayloadDPIClutchRetargetsToStoredProfile() {
        let livePayload = BLEVendorProtocol.buildButtonPayload(
            slot: 0x0F,
            kind: .dpiClutch,
            hidKey: nil,
            clutchDPI: 800
        )
        let storedPayload = BLEVendorProtocol.retargetButtonPayload(livePayload, target: 0x04, slot: 0x0F)
        XCTAssertEqual(Array(storedPayload), [0x04, 0x0F, 0x00, 0x06, 0x05, 0x05, 0x03, 0x20, 0x03, 0x20])
    }

    func testBluetoothClutchReadbackPreservesConfiguredDPI() {
        let payload = Data([0x0F, 0x00, 0x06, 0x06, 0x05, 0x05, 0x05, 0x05, 0x03, 0x03, 0x20, 0x20, 0x03, 0x03, 0x20, 0x20])
        let block = BLEVendorProtocol.extractBluetoothFunctionBlock(
            payload: payload,
            target: 0x01,
            slot: 0x0F,
            profileID: .basiliskV3Pro
        )
        let draft = block.flatMap {
            ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(
                slot: 15,
                functionBlock: $0,
                profileID: .basiliskV3Pro
            )
        }

        XCTAssertEqual(block, [0x06, 0x05, 0x05, 0x03, 0x20, 0x03, 0x20])
        XCTAssertEqual(draft?.kind, .dpiClutch)
        XCTAssertEqual(draft?.clutchDPI, 800)
    }

    func testScrollLEDEffectStaticArgs() {
        let args = BLEVendorProtocol.buildScrollLEDEffectArgs(
            effect: LightingEffectPatch(
                kind: .staticColor,
                primary: RGBPatch(r: 0x12, g: 0x34, b: 0x56)
            )
        )
        XCTAssertEqual(args, [0x01, 0x01, 0x01, 0x00, 0x00, 0x01, 0x12, 0x34, 0x56])
    }

    func testScrollLEDEffectOffArgs() {
        let args = BLEVendorProtocol.buildScrollLEDEffectArgs(
            effect: LightingEffectPatch(kind: .off)
        )
        XCTAssertEqual(args, [0x01, 0x01, 0x00, 0x00, 0x00, 0x00])
    }

    func testScrollLEDEffectSpectrumArgs() {
        let args = BLEVendorProtocol.buildScrollLEDEffectArgs(
            effect: LightingEffectPatch(kind: .spectrum)
        )
        XCTAssertEqual(args, [0x01, 0x01, 0x03, 0x00, 0x00, 0x00])
    }

    func testScrollLEDEffectWaveArgs() {
        let args = BLEVendorProtocol.buildScrollLEDEffectArgs(
            effect: LightingEffectPatch(
                kind: .wave,
                waveDirection: .right
            )
        )
        XCTAssertEqual(args, [0x01, 0x01, 0x04, 0x02, 0x28, 0x00])
    }

    func testScrollLEDEffectReactiveArgsClampSpeed() {
        let args = BLEVendorProtocol.buildScrollLEDEffectArgs(
            effect: LightingEffectPatch(
                kind: .reactive,
                primary: RGBPatch(r: 0xAA, g: 0xBB, b: 0xCC),
                reactiveSpeed: 9
            )
        )
        XCTAssertEqual(args, [0x01, 0x01, 0x05, 0x00, 0x04, 0x01, 0xAA, 0xBB, 0xCC])
    }

    func testScrollLEDEffectPulseRandomArgs() {
        let args = BLEVendorProtocol.buildScrollLEDEffectArgs(
            effect: LightingEffectPatch(kind: .pulseRandom)
        )
        XCTAssertEqual(args, [0x01, 0x01, 0x02, 0x00, 0x00, 0x00])
    }

    func testScrollLEDEffectPulseSingleArgs() {
        let args = BLEVendorProtocol.buildScrollLEDEffectArgs(
            effect: LightingEffectPatch(
                kind: .pulseSingle,
                primary: RGBPatch(r: 0x11, g: 0x22, b: 0x33)
            )
        )
        XCTAssertEqual(args, [0x01, 0x01, 0x02, 0x01, 0x00, 0x01, 0x11, 0x22, 0x33])
    }

    func testScrollLEDEffectPulseDualArgs() {
        let args = BLEVendorProtocol.buildScrollLEDEffectArgs(
            effect: LightingEffectPatch(
                kind: .pulseDual,
                primary: RGBPatch(r: 0x01, g: 0x02, b: 0x03),
                secondary: RGBPatch(r: 0x10, g: 0x20, b: 0x30)
            )
        )
        XCTAssertEqual(args, [0x01, 0x01, 0x02, 0x02, 0x00, 0x02, 0x01, 0x02, 0x03, 0x10, 0x20, 0x30])
    }

    func testV3ProLightingZoneStatePayloadRoundTrip() {
        let payload = BLEVendorProtocol.buildV3ProLightingZoneStatePayload(r: 0xFF, g: 0x40, b: 0x00)
        XCTAssertEqual(Array(payload), [0x01, 0x00, 0x00, 0x01, 0xFF, 0x40, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(
            BLEVendorProtocol.parseV3ProLightingZoneStatePayload(payload),
            RGBPatch(r: 0xFF, g: 0x40, b: 0x00)
        )
    }

    func testParseVariableLengthDpiBlob() {
        // [active=0][count=2]
        // stage0: [00][20 03][20 03][00][00] -> 800
        // stage1: [01][00 19][00 19][00][00] -> 6400
        let blob = Data([0x00, 0x02, 0x00, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00, 0x01, 0x00, 0x19, 0x00, 0x19, 0x00, 0x00])
        let parsed = BLEVendorProtocol.parseDpiStages(blob: blob)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.active, 0)
        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(parsed?.values, [800, 6400])
    }

    func testParseVariableLengthDpiBlobPreservesWireEntryOrder() {
        // [active=1][count=3]
        // entries are intentionally out of order by stage id:
        // stage2 -> 3200, stage0 -> 800, stage1 -> 1600
        let blob = Data([
            0x01, 0x03,
            0x02, 0x80, 0x0C, 0x80, 0x0C, 0x00, 0x00,
            0x00, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00,
            0x01, 0x40, 0x06, 0x40, 0x06, 0x00, 0x03
        ])
        let parsed = BLEVendorProtocol.parseDpiStages(blob: blob)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.active, 2)
        XCTAssertEqual(parsed?.count, 3)
        XCTAssertEqual(parsed?.values, [3200, 800, 1600])
    }

    func testParseVariableLengthDpiBlobPadsFromLastWireEntry() {
        // [active=2][count=3]
        // stage entries present: 800 then 3200.
        // Parser should preserve wire order and pad the missing trailing entry.
        let blob = Data([
            0x02, 0x03,
            0x00, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00,
            0x02, 0x80, 0x0C, 0x80, 0x0C, 0x00, 0x03
        ])
        let parsed = BLEVendorProtocol.parseDpiStages(blob: blob)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.count, 3)
        XCTAssertEqual(parsed?.values, [800, 3200, 3200])
        XCTAssertEqual(parsed?.active, 1)
    }

    func testParseDpiBlobLengthShortByOneStillParsesTwoStages() {
        // Some capture-backed read headers report payload length one byte short.
        // Here count=2 with second entry marker omitted (15 bytes total).
        let blob = Data([
            0x01, 0x02,
            0x01, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00,
            0x02, 0x00, 0x19, 0x00, 0x19, 0x00
        ])
        let parsed = BLEVendorProtocol.parseDpiStages(blob: blob)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.active, 0)
        XCTAssertEqual(parsed?.count, 2)
        XCTAssertEqual(parsed?.values, [800, 6400])
    }

    func testParseDpiBlobLengthShortByOneStillParsesThreeStages() {
        // count=3 with final entry marker omitted (22 bytes total).
        let blob = Data([
            0x02, 0x03,
            0x01, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00,
            0x02, 0x40, 0x06, 0x40, 0x06, 0x00, 0x00,
            0x03, 0x80, 0x0C, 0x80, 0x0C, 0x00
        ])
        let parsed = BLEVendorProtocol.parseDpiStages(blob: blob)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.active, 1)
        XCTAssertEqual(parsed?.count, 3)
        XCTAssertEqual(parsed?.values, [800, 1600, 3200])
    }

    func testParseStoredProfileProjectionUsesDeclaredCount() {
        let blob = Data([
            0x03, 0x03,
            0x01, 0x90, 0x01, 0x90, 0x01, 0x00, 0x00,
            0x02, 0xB0, 0x04, 0xB0, 0x04, 0x00, 0x00,
            0x03, 0x14, 0x05, 0x14, 0x05, 0x00
        ])
        let parsed = BLEVendorProtocol.parseDpiStages(blob: blob)

        XCTAssertEqual(parsed?.count, 3)
        XCTAssertEqual(parsed?.values, [400, 1200, 1300])
        XCTAssertEqual(parsed?.pairs, [
            DpiPair(x: 400, y: 400),
            DpiPair(x: 1200, y: 1200),
            DpiPair(x: 1300, y: 1300)
        ])
        XCTAssertEqual(parsed?.active, 2)
    }
}
