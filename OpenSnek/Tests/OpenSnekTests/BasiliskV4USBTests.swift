import XCTest
import OpenSnekCore
import OpenSnekProtocols
@testable import OpenSnek

/// Covers the receiver's observed addresses and preservation across stage-count changes.
final class BasiliskV4USBTests: XCTestCase {
    private let baseline: [UInt8] = [1, 3, 5, 1, 1, 0x90, 1, 0x90, 1, 0x90, 2, 3, 0x20, 3, 0x20, 3, 0x20, 3, 6, 0x40, 6, 0x40, 6, 0x40, 4, 0x0c, 0x80, 0x0c, 0x80, 0x0c, 0x80, 5, 0x19, 0, 0x19, 0, 0, 0]

    func testReceiverIdentityAndScopedCapabilities() throws {
        let profile = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00EA, transport: .usb))
        XCTAssertEqual(profile.id, .basiliskV4Hyperspeed)
        XCTAssertEqual(profile.usbTransactionID, 0x1F)
        XCTAssertEqual(profile.allUSBBrightnessLEDIDs, [0])
        XCTAssertEqual(profile.allUSBBrightnessReadLEDIDs, [10])
        XCTAssertEqual(profile.lightingLEDIDs(), [0])
        XCTAssertEqual(Set(profile.buttonLayout.writableSlots), [1, 2, 3, 4, 5, 9, 10, 14, 52, 53, 57, 128])
        XCTAssertEqual(Set(profile.supportedLightingEffects), [.off, .staticColor, .spectrum, .pulseRandom, .pulseSingle, .pulseDual])
        XCTAssertFalse(profile.supportsScrollModeControls)
        XCTAssertFalse(profile.supportsMappedOnboardProfileCRUD)
        XCTAssertNil(profile.softwareLightingFrameLayout)
        XCTAssertNil(profile.passiveDPIInput)
        XCTAssertNil(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00EB, transport: .usb))
        XCTAssertNil(DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00EA, transport: .bluetooth))
    }

    func testSingleToMultipleStageTransitionPreservesObservedRowsAndOpaqueBytes() throws {
        let one = try XCTUnwrap(USBHIDProtocol.basiliskV4DPIWriteArgs(baseline: baseline, active: 0, pairs: [DpiPair(x: 1200, y: 1300)]))
        XCTAssertEqual(one[1], 1)
        XCTAssertEqual(one[2], 1)
        XCTAssertEqual(one[8...], baseline[8...])
        // Receiver pads omitted hidden rows with zeroes; they are not new stage data.
        let shortRead = Array(one.prefix(10)) + Array(repeating: UInt8(0), count: 28)
        XCTAssertNil(USBHIDProtocol.basiliskV4DPIBaseline(payload: shortRead, previous: nil))
        let retained = try XCTUnwrap(USBHIDProtocol.basiliskV4DPIBaseline(payload: shortRead, previous: one))
        let pairs = [DpiPair(x: 800, y: 900), DpiPair(x: 1600, y: 1700), DpiPair(x: 50_000, y: 32_000)]
        let three = try XCTUnwrap(USBHIDProtocol.basiliskV4DPIWriteArgs(baseline: retained, active: 2, pairs: pairs))
        XCTAssertEqual(three[1], 3)
        XCTAssertEqual(three[2], 3)
        XCTAssertEqual(Array(three[18...21]), [0x80, 0xe8, 0x7d, 0])
        for offset in [8, 9, 15, 16, 22, 23] { XCTAssertEqual(three[offset], baseline[offset]) }
        XCTAssertEqual(three[24...], baseline[24...])
        var bad = baseline
        bad[1] = 99
        XCTAssertNil(USBHIDProtocol.basiliskV4DPIWriteArgs(baseline: bad, active: 0, pairs: pairs))
        bad = baseline
        bad[10] = bad[3]
        XCTAssertNil(USBHIDProtocol.basiliskV4DPIWriteArgs(baseline: bad, active: 0, pairs: pairs))
    }

    func testEffectReadbackUsesPhysicalLEDEchoAndComparesChangedFields() {
        let args = BLEVendorProtocol.buildScrollLEDEffectArgs(effect: LightingEffectPatch(kind: .staticColor, primary: RGBPatch(r: 32, g: 160, b: 96)), ledID: 0)
        var response = USBHIDProtocol.createReport(txn: 0x1F, classID: 15, cmdID: 0x82, size: 12, args: [0, 10] + Array(args.dropFirst(2)))
        response[0] = 2
        XCTAssertTrue(USBHIDProtocol.basiliskV4LightingWriteMatches(response: response, args: args))
        response[14] = 255
        XCTAssertFalse(USBHIDProtocol.basiliskV4LightingWriteMatches(response: response, args: args))
        response[0] = 3
        XCTAssertFalse(USBHIDProtocol.basiliskV4LightingWriteMatches(response: response, args: args))
    }
}
