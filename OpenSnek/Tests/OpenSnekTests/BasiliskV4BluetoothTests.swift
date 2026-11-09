import XCTest
import OpenSnekCore
import OpenSnekProtocols
@testable import OpenSnek

/// Covers the V4 Bluetooth identity and the captured read/edit/write contract.
final class BasiliskV4BluetoothTests: XCTestCase {
    private let baseline = Data([0x03, 0x05, 0x01, 0x90, 0x01, 0x90, 0x01, 0x90, 0x01, 0x02, 0x20, 0x03, 0x20, 0x03, 0x20, 0x03, 0x03, 0x40, 0x06, 0x40, 0x06, 0x40, 0x06, 0x04, 0x80, 0x0c, 0x80, 0x0c, 0x80, 0x0c, 0x05, 0x00, 0x19, 0x00, 0x19, 0x00])

    private var device: MouseDevice { MouseDevice(id: "v4-bt-test", vendor_id: 0x068E, product_id: 0x00EC, product_name: "BSK V4 HS", transport: .bluetooth, path_b64: "", serial: nil, firmware: nil, profile_id: .basiliskV4Hyperspeed) }

    func testIdentityCapabilitiesAndTransportIsolation() throws {
        let profile = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00EC, transport: .bluetooth))
        XCTAssertEqual(profile.id, .basiliskV4Hyperspeed)
        XCTAssertEqual(DeviceProfiles.resolveBluetoothFallback(name: "BSK V4 HS")?.id, profile.id)
        XCTAssertEqual(DeviceProfiles.resolveBluetoothFallback(name: "Razer Basilisk V4 HyperSpeed")?.id, profile.id)
        XCTAssertNotEqual(DeviceProfiles.resolveBluetoothFallback(name: "BSK V4 PRO")?.id, profile.id)
        XCTAssertNil(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00EC, transport: .usb))
        XCTAssertEqual(DeviceProfiles.maximumDPI(for: profile.id), 33_000)
        XCTAssertTrue(device.supportsLightingBrightnessControls)
        XCTAssertFalse(device.supportsLightingColorControls)
        XCTAssertTrue(profile.supportsIndependentXYDPI)
        XCTAssertFalse(profile.supportsMappedOnboardProfileCRUD)
        XCTAssertNil(profile.passiveDPIInput)
        XCTAssertEqual(profile.lightingLEDIDs(), [0x0A])
        XCTAssertEqual(Set(profile.buttonLayout.writableSlots), [1, 2, 3, 4, 5, 9, 10, 14, 52, 53, 57, 128])
        XCTAssertFalse(profile.buttonLayout.visibleSlots.contains { [96, 15].contains($0.slot) })
    }

    func testEditorPatchToWirePreservesHiddenStagesAcrossSingleAndMultipleStages() throws {
        let current = try XCTUnwrap(BLEVendorProtocol.parseDpiStageSnapshot(blob: baseline))
        let single = try BridgeClient.resolveBluetoothDpiStageWrite(device: device, patch: DevicePatch(dpiStages: [1200], activeStage: 0), current: current)
        let one = try XCTUnwrap(BLEVendorProtocol.buildPreservingDpiStagePayload(baseline: current.sourcePayload!, active: single.active, count: single.stages.count, pairs: single.pairs, profileID: .basiliskV4Hyperspeed))
        XCTAssertEqual(one.count, 38)
        XCTAssertEqual(one[0], 1)
        XCTAssertEqual(one[1], 1)
        XCTAssertEqual(one[7..<36], baseline[7..<36], "Opaque bytes and four hidden stages must survive single-stage mode")
        let short = try XCTUnwrap(BLEVendorProtocol.parseDpiStageSnapshot(blob: one.prefix(8)))
        let parsed = BLEVendorProtocol.preservingDpiWriteBaseline(short, previous: one)
        XCTAssertEqual(parsed.sourcePayload?.count, 8)
        let pairs = [DpiPair(x: 400, y: 400), DpiPair(x: 800, y: 800), DpiPair(x: 33_000, y: 32_000)]
        let multi = try BridgeClient.resolveBluetoothDpiStageWrite(device: device, patch: DevicePatch(dpiStages: pairs.map(\.x), dpiStagePairs: pairs, activeStage: 2), current: parsed)
        let three = try XCTUnwrap(BLEVendorProtocol.buildPreservingDpiStagePayload(baseline: parsed.writeBaseline!, active: multi.active, count: multi.stages.count, pairs: multi.pairs, profileID: .basiliskV4Hyperspeed))
        XCTAssertEqual(three[0], 3)
        XCTAssertEqual(three[1], 3)
        XCTAssertEqual(BLEVendorProtocol.parseDpiStageSnapshot(blob: three)?.pairs.prefix(3), pairs[...])
        for offset in [7, 8, 14, 15, 21, 22] { XCTAssertEqual(three[offset], baseline[offset]) }
        XCTAssertEqual(three[23..<36], baseline[23..<36])
    }

    func testPreservingBuilderRejectsIncompleteAndMalformedBaselineAndClamps33K() throws {
        let pair = [DpiPair(x: 50_000, y: 1)]
        XCTAssertNil(BLEVendorProtocol.buildPreservingDpiStagePayload(baseline: baseline.prefix(35), active: 0, count: 1, pairs: pair, profileID: .basiliskV4Hyperspeed))
        var malformed = baseline
        malformed[0] = 99
        XCTAssertNil(BLEVendorProtocol.buildPreservingDpiStagePayload(baseline: malformed, active: 0, count: 1, pairs: pair, profileID: .basiliskV4Hyperspeed))
        let data = try XCTUnwrap(BLEVendorProtocol.buildPreservingDpiStagePayload(baseline: baseline, active: 0, count: 1, pairs: pair, profileID: .basiliskV4Hyperspeed))
        XCTAssertEqual(BLEVendorProtocol.parseDpiStages(blob: data)?.pairs, [DpiPair(x: 33_000, y: 100)])
    }

    func testTiltDefaultAndCurrentBindingLane() {
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 52, kind: .default, hidKey: nil, profileID: .basiliskV4Hyperspeed)
        XCTAssertEqual(payload, Data([1, 52, 0, 0x0e, 1, 0x68, 0, 0x14, 0, 0]))
        let interleaved = Data([0x34, 0, 1, 0x0e, 1, 1, 2, 0x68, 0, 0, 0, 0x14, 0, 0, 0, 0])
        XCTAssertEqual(BLEVendorProtocol.extractBluetoothFunctionBlock(payload: interleaved, target: 1, slot: 52, profileID: .basiliskV4Hyperspeed), [1, 1, 2, 0, 0, 0, 0])
    }

    func testSpecialButtonDefaultsRoundTripOnBothTransports() throws {
        let native: [Int: [UInt8]] = [14: [7, 1, 4, 0, 0, 0, 0], 57: [12, 1, 57, 0, 0, 0, 0], 128: [0, 1, 0, 0, 0, 0, 0]]
        for (slot, block) in native {
            let profile: DeviceProfileID = .basiliskV4Hyperspeed
            XCTAssertTrue(ButtonBindingSupport.supportsDefaultRestore(for: slot, profileID: profile))
            let draft = try XCTUnwrap(ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(slot: slot, functionBlock: block, profileID: profile))
            XCTAssertEqual(draft.kind, .default)
            XCTAssertEqual(ButtonBindingSupport.usbFunctionBlockForWrite(slot: slot, draft: draft, profileID: profile), block)
            let payload = BLEVendorProtocol.buildButtonPayload(slot: UInt8(slot), kind: .default, hidKey: nil, profileID: profile)
            XCTAssertEqual(Array(payload), [1, UInt8(slot), 0] + block)
            XCTAssertTrue(DeviceProfiles.basiliskV4HyperspeedUSB.buttonLayout.isEditable(slot))
            XCTAssertTrue(DeviceProfiles.basiliskV4HyperspeedBluetooth.buttonLayout.isEditable(slot))
        }
        XCTAssertEqual(ButtonBindingSupport.defaultUSBFunctionBlock(for: 1, profileID: .basiliskV4Hyperspeed), [1, 1, 1, 0, 0, 0, 0])
        XCTAssertEqual(ButtonBindingSupport.defaultUSBFunctionBlock(for: 2, profileID: .basiliskV4Hyperspeed), [1, 1, 2, 0, 0, 0, 0])
    }

    func testBatteryUsesByteScaleAndDoesNotInferCharging() {
        let state = BridgeClient.resolveBluetoothBatteryState(device: device, vendorRaw: 105, vendorStatus: 1, usbFallback: nil)
        XCTAssertEqual(state.percent, 41)
        XCTAssertNil(state.charging)
        XCTAssertEqual(BridgeClient.resolveBluetoothBatteryState(device: device, vendorRaw: 90, vendorStatus: 1, usbFallback: nil).percent, 35)
    }
}
