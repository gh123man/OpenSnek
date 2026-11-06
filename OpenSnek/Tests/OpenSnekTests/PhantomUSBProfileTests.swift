import XCTest
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

/// Verifies the unvalidated Phantom USB mapping without opening hardware.
final class PhantomUSBProfileTests: XCTestCase {
    func testWiredAndReceiverResolveWithoutClaimingBluetoothOrValidation() throws {
        for productID in [0x00D6, 0x00D7] {
            let profile = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x1532, productID: productID, transport: .usb))
            XCTAssertEqual(profile.id, .basiliskV3Pro35K)
            XCTAssertFalse(profile.isLocallyValidated)
            XCTAssertEqual(profile.usbTransactionID, 0x1F)
            XCTAssertEqual(profile.buttonLayout, DeviceProfiles.basiliskV3ProUSB.buttonLayout)
            XCTAssertNil(DeviceProfiles.resolve(vendorID: 0x1532, productID: productID, transport: .bluetooth))
        }
        XCTAssertEqual(DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00D8, transport: .bluetooth), DeviceProfiles.basiliskV3Pro35KPhantomGreenBluetooth)
    }

    func testUSBStageEncodingPreservesIDsAndClampsBothAxesAt35K() throws {
        for productID in [0x00D6, 0x00D7] {
            let device = makeDevice(productID: productID)
            let args = try XCTUnwrap(BridgeClient.usbDPIStageWriteArgs(profileID: 1, activeStage: 1, pairs: [DpiPair(x: 35_000, y: 32_000), DpiPair(x: 40_000, y: 50)], stageIDs: [3, 7, 9, 11, 13], device: device))
            XCTAssertEqual(Array(args.prefix(17)), [1, 7, 2, 3, 0x88, 0xB8, 0x7D, 0x00, 0, 0, 7, 0x88, 0xB8, 0x00, 0x64, 0, 0])
        }
    }

    func testPassiveDPIAccepts35KButRejectsValuesAboveTheCeiling() throws {
        let descriptor = try XCTUnwrap(DeviceProfiles.basiliskV3Pro35KPhantomGreenUSB.passiveDPIInput)
        XCTAssertEqual(PassiveDPIParser.parse(report: [0x05, 0x02, 0x88, 0xB8, 0x7D, 0x00], descriptor: descriptor), PassiveDPIReading(dpiX: 35_000, dpiY: 32_000))
        XCTAssertNil(PassiveDPIParser.parse(report: [0x05, 0x02, 0x88, 0xB9, 0x7D, 0x00], descriptor: descriptor))
    }

    func testLightingTargetsExcludeLogoAndUnmappedCustomFrames() {
        let profile = DeviceProfiles.basiliskV3Pro35KPhantomGreenUSB
        XCTAssertEqual(profile.lightingLEDIDs(for: "all"), [0x01, 0x0A])
        XCTAssertEqual(profile.lightingLEDIDs(for: "scroll_wheel"), [0x01])
        XCTAssertEqual(profile.lightingLEDIDs(for: "underglow"), [0x0A])
        XCTAssertNil(profile.lightingLEDIDs(for: "logo"))
        XCTAssertEqual(profile.allUSBBrightnessLEDIDs, [0x01, 0x0A])
        XCTAssertEqual(profile.allUSBBrightnessReadLEDIDs, [0x01, 0x0A])
        for productID in [0x00D6, 0x00D7] {
            XCTAssertFalse(makeDevice(productID: productID).supportsSoftwareLightingEffects)
            XCTAssertNil(makeDevice(productID: productID).softwareLightingFrameLayout)
        }
    }

    func testCatalogKeepsUnprovenFeaturesDisabled() throws {
        let catalog = DeviceValidationCatalog()
        let profile = try XCTUnwrap(catalog.profiles.first { $0.id == "basilisk_v3_pro_35k" && $0.transport == "usb" })
        XCTAssertEqual(profile.productIDs, [0x00D6, 0x00D7])
        XCTAssertFalse(profile.isLocallyValidated)
        for feature in ["dpi_stages", "independent_xy", "poll_rate", "power_management", "button_remap", "lighting_brightness", "advanced_lighting_effects", "scroll_controls"] { XCTAssertEqual(profile.capabilities[feature], true, feature) }
        XCTAssertEqual(profile.capabilities["software_lighting"], false)
        XCTAssertEqual(profile.capabilities["onboard_profiles"], false)
    }

    private func makeDevice(productID: Int) -> MouseDevice {
        // Leave profile_id unset to exercise PID resolution at the bridge boundary.
        MouseDevice(id: "phantom-\(productID)", vendor_id: 0x1532, product_id: productID, product_name: "Basilisk V3 Pro 35K", transport: .usb, path_b64: "", serial: nil, firmware: nil)
    }
}
