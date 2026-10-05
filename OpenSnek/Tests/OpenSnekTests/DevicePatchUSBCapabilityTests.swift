import XCTest
import OpenSnekCore

/// Verifies mixed backend patches retain lighting while omitting unsupported USB commands.
final class DevicePatchUSBCapabilityTests: XCTestCase {
    func testLightingOnlyProfilesKeepOnlyLightingFromMousePatch() throws {
        let patch = makeMixedPatch()
        let expected = DevicePatch(ledBrightness: patch.ledBrightness, ledRGB: patch.ledRGB, lightingEffect: patch.lightingEffect, usbLightingZoneLEDIDs: patch.usbLightingZoneLEDIDs)
        for profile in [DeviceProfiles.huntsmanMiniUSB, DeviceProfiles.tartarusProUSB] {
            let device = try makeDevice(profile: profile)
            XCTAssertEqual(patch.supportedUSBControls(for: device), expected)
            XCTAssertEqual(DevicePatch(activeStage: 1).supportedUSBControls(for: device), DevicePatch())
        }
    }

    func testFullyCapableMouseKeepsMixedPatch() throws {
        let patch = makeMixedPatch()
        XCTAssertEqual(patch.supportedUSBControls(for: try makeDevice(profile: DeviceProfiles.basiliskV3ProUSB)), patch)
    }

    func testWiredMouseKeepsDPIAndPollRateWithoutPowerOrRemapping() throws {
        let patch = makeMixedPatch()
        let supported = patch.supportedUSBControls(for: try makeDevice(profile: DeviceProfiles.basiliskUSB))
        XCTAssertEqual(supported.dpiStages, patch.dpiStages)
        XCTAssertEqual(supported.dpiStagePairs, patch.dpiStagePairs)
        XCTAssertEqual(supported.activeStage, patch.activeStage)
        XCTAssertEqual(supported.pollRate, patch.pollRate)
        XCTAssertNil(supported.sleepTimeout)
        XCTAssertNil(supported.lowBatteryThresholdRaw)
        XCTAssertNil(supported.buttonBinding)
        XCTAssertNil(supported.usbButtonProfileAction)
    }

    func testUnprofiledAndBluetoothDevicesKeepExistingPatchBehavior() throws {
        let patch = makeMixedPatch()
        let unprofiled = MouseDevice(id: "unknown-usb", vendor_id: 0x1532, product_id: 0xFFFF, product_name: "Unknown", transport: .usb, path_b64: "", serial: nil, firmware: nil)
        XCTAssertEqual(patch.supportedUSBControls(for: unprofiled), patch)
        XCTAssertEqual(patch.supportedUSBControls(for: try makeDevice(profile: DeviceProfiles.basiliskV3ProBluetooth)), patch)
    }

    func testWithoutOnboardLightingWritesClearsLightingOnly() {
        let patch = makeMixedPatch()
        let stripped = patch.withoutOnboardLightingWrites

        XCTAssertNil(stripped.ledRGB)
        XCTAssertNil(stripped.lightingEffect)
        XCTAssertNil(stripped.usbLightingZoneLEDIDs)
        XCTAssertEqual(stripped.ledBrightness, patch.ledBrightness)
        XCTAssertEqual(stripped.dpiStages, patch.dpiStages)
        XCTAssertEqual(stripped.buttonBinding, patch.buttonBinding)
    }

    private func makeDevice(profile: DeviceProfile) throws -> MouseDevice {
        MouseDevice(id: profile.id.rawValue, vendor_id: profile.transport == .usb ? 0x1532 : 0x068E, product_id: try XCTUnwrap(profile.supportedProducts.first), product_name: profile.productName, transport: profile.transport, path_b64: "", serial: nil, firmware: nil, profile_id: profile.id)
    }

    private func makeMixedPatch() -> DevicePatch {
        DevicePatch(
            pollRate: 500, sleepTimeout: 420, lowBatteryThresholdRaw: 0x20, dpiStages: [900, 1800], dpiStagePairs: [DpiPair(x: 900, y: 1000), DpiPair(x: 1800, y: 2000)], activeStage: 1, ledBrightness: 77, ledRGB: RGBPatch(r: 11, g: 22, b: 33), lightingEffect: LightingEffectPatch(kind: .wave),
            usbLightingZoneLEDIDs: [0x05], buttonBinding: ButtonBindingPatch(slot: 4, kind: .keyboardSimple, hidKey: 4), usbButtonProfileAction: USBButtonProfileActionPatch(kind: .resetPersistentSlot, targetProfile: 1))
    }
}
