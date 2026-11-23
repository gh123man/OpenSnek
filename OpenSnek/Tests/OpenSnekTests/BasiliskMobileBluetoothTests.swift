import XCTest
import OpenSnekCore
import OpenSnekProtocols
@testable import OpenSnek

/// Covers the Basilisk Mobile Bluetooth identity, its control scope, captured payloads, and the stored-target lighting mirror.
final class BasiliskMobileBluetoothTests: XCTestCase {
    private var device: MouseDevice { MouseDevice(id: "basilisk-mobile-bt-test", vendor_id: 0x068E, product_id: 0x00D5, product_name: "Razer Basilisk Mobile", transport: .bluetooth, path_b64: "", serial: nil, firmware: nil, profile_id: .basiliskMobile) }

    func testIdentityResolvesOnBluetoothAndCable() throws {
        let profile = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00D5, transport: .bluetooth))
        XCTAssertEqual(profile.id, .basiliskMobile)
        XCTAssertEqual(profile.productName, "Basilisk Mobile")
        XCTAssertFalse(profile.isLocallyValidated)
        // The cable (00D3) and HyperSpeed receiver (00D4) share one USB profile.
        let cable = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00D3, transport: .usb))
        XCTAssertEqual(cable.id, .basiliskMobile)
        let receiver = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00D4, transport: .usb))
        XCTAssertEqual(receiver.id, .basiliskMobile)
        XCTAssertEqual(receiver.usbTransactionID, 0x1F)
        XCTAssertNil(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00D5, transport: .usb))
    }

    func testBluetoothNameFallbackMatchesAdvertisedName() {
        XCTAssertEqual(DeviceProfiles.resolveBluetoothFallback(name: "BSK MOBILE")?.id, .basiliskMobile)
        XCTAssertEqual(DeviceProfiles.resolveBluetoothFallback(name: "Razer Basilisk Mobile")?.id, .basiliskMobile)
        XCTAssertNotEqual(DeviceProfiles.resolveBluetoothFallback(name: "BSK V4 HS")?.id, .basiliskMobile)
    }

    func testScopeExposesProbedControlsOnly() throws {
        let profile = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00D5, transport: .bluetooth))
        XCTAssertEqual(profile.lightingLEDIDs(), [0x04])
        XCTAssertEqual(profile.usbLightingZones.map(\.id), ["logo"])
        XCTAssertEqual(profile.supportedLightingEffects, [.off, .staticColor, .spectrum, .reactive, .pulseRandom, .pulseSingle, .pulseDual])
        XCTAssertTrue(profile.supportsAdvancedLightingEffects)
        XCTAssertTrue(profile.supportsDPIControls)
        XCTAssertTrue(profile.supportsIndependentXYDPI)
        XCTAssertTrue(profile.supportsPowerManagementControls)
        XCTAssertEqual(DeviceProfiles.maximumDPI(for: profile.id), 18_000)
        XCTAssertTrue(DeviceProfiles.supportsIndependentXYDPI(for: DeviceProfileID.basiliskMobile))
        XCTAssertTrue(profile.supportsLightingBrightnessControls)
        XCTAssertTrue(profile.supportsButtonRemapControls)
        XCTAssertEqual(Set(profile.buttonLayout.writableSlots), [1, 2, 3, 4, 5, 9, 10, 52, 53, 128])
        // One onboard slot and no metadata probe, so profile management stays hidden.
        XCTAssertFalse(profile.supportsMappedOnboardProfileCRUD)
        XCTAssertNil(profile.passiveDPIInput)
        XCTAssertTrue(device.showsLightingControls)
        XCTAssertTrue(device.supportsLightingColorControls)
        XCTAssertTrue(device.supportsLightingBrightnessControls)
        XCTAssertTrue(device.supportsDPIControls)
        XCTAssertTrue(DeviceProfileID.basiliskMobile.usesBluetoothZoneEffectBodies)
    }

    func testBluetoothStateCapabilitiesFollowProfileFlags() {
        let mobile = BridgeClient.resolvedBluetoothStateCapabilities(profile: DeviceProfiles.basiliskMobileBluetooth, supportsLighting: true)
        XCTAssertTrue(mobile.dpi_stages)
        XCTAssertFalse(mobile.poll_rate)
        XCTAssertTrue(mobile.power_management)
        XCTAssertTrue(mobile.button_remap)
        XCTAssertTrue(mobile.lighting)

        // Existing Bluetooth profiles and unprofiled devices keep every card visible.
        for profile in [DeviceProfiles.basiliskV3ProBluetooth, DeviceProfiles.basiliskV4HyperspeedBluetooth, nil] {
            let capabilities = BridgeClient.resolvedBluetoothStateCapabilities(profile: profile, supportsLighting: true)
            XCTAssertTrue(capabilities.dpi_stages)
            XCTAssertFalse(capabilities.poll_rate)
            XCTAssertTrue(capabilities.power_management)
            XCTAssertTrue(capabilities.button_remap)
        }
    }

    func testUsesZoneStateLighting() async {
        let client = BridgeClient(startHIDMonitoring: false)
        let byProfile = await client.usesBluetoothZoneStateLighting(device)
        let byProductID = await client.usesBluetoothZoneStateLighting(MouseDevice(id: "basilisk-mobile-bt-pid", vendor_id: 0x068E, product_id: 0x00D5, product_name: "BSK MOBILE", transport: .bluetooth, path_b64: "", serial: nil, firmware: nil))
        XCTAssertTrue(byProfile)
        XCTAssertTrue(byProductID)
    }

    func testLightingWritesMirrorToStoredTargetOne() {
        // Captured: 10 03 00 04 changed live lighting only; 10 03 01 04 survived a power cycle.
        let keys = BridgeClient.bluetoothZoneStateWriteKeys(profile: DeviceProfiles.basiliskMobileBluetooth, ledID: 0x04)
        XCTAssertEqual(keys.map(\.bytes), [[0x10, 0x03, 0x00, 0x04], [0x10, 0x03, 0x01, 0x04]])

        // Profiles without a stored target still write the live key only.
        let v3Pro = BridgeClient.bluetoothZoneStateWriteKeys(profile: DeviceProfiles.basiliskV3ProBluetooth, ledID: 0x04)
        XCTAssertEqual(v3Pro.map(\.bytes), [[0x10, 0x03, 0x00, 0x04]])
    }

    func testCapturedStaticPayloadRoundTrips() throws {
        // Payload written and read back on hardware for static red.
        let payload = BLEVendorProtocol.buildV3ProLightingZoneStatePayload(r: 0xFF, g: 0x00, b: 0x00)
        XCTAssertEqual([UInt8](payload), [0x01, 0x00, 0x00, 0x01, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00])
        let parsed = try XCTUnwrap(BLEVendorProtocol.parseV3ProLightingZoneStatePayload(payload))
        XCTAssertEqual(parsed, RGBPatch(r: 0xFF, g: 0x00, b: 0x00))
    }

    func testBatteryIsByteScaled() {
        // Byte scale: OpenSnek and macOS agreed at 77%; values at or below 100 must not be read as a percentage.
        XCTAssertEqual(BridgeClient.resolveBluetoothBatteryState(device: device, vendorRaw: 0xFF, vendorStatus: nil, usbFallback: nil).percent, 100)
        XCTAssertEqual(BridgeClient.resolveBluetoothBatteryState(device: device, vendorRaw: 0xC4, vendorStatus: nil, usbFallback: nil).percent, 76)
        // A transient 0x00 from a mouse that is still answering is unknown, not empty.
        XCTAssertNil(BridgeClient.resolveBluetoothBatteryState(device: device, vendorRaw: 0x00, vendorStatus: nil, usbFallback: nil).percent)
        XCTAssertEqual(BridgeClient.resolveBluetoothBatteryState(device: device, vendorRaw: 90, vendorStatus: nil, usbFallback: nil).percent, 35)
        let byProductID = MouseDevice(id: "basilisk-mobile-bt-pid", vendor_id: 0x068E, product_id: 0x00D5, product_name: "BSK MOBILE", transport: .bluetooth, path_b64: "", serial: nil, firmware: nil)
        XCTAssertEqual(BridgeClient.resolveBluetoothBatteryState(device: byProductID, vendorRaw: 90, vendorStatus: nil, usbFallback: nil).percent, 35)
    }

    func testEffectBodiesMatchCapturedPayloads() {
        // Each payload was written to 10 03 00 04, read back unchanged, and rendered on hardware.
        let green = RGBPatch(r: 0x00, g: 0xFF, b: 0x00)
        let cases: [(LightingEffectPatch, [UInt8])] = [
            (LightingEffectPatch(kind: .off), [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]), (LightingEffectPatch(kind: .spectrum), [0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            (LightingEffectPatch(kind: .wave, waveDirection: .left), [0x04, 0x01, 0x28, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]), (LightingEffectPatch(kind: .pulseRandom), [0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            (LightingEffectPatch(kind: .pulseSingle, primary: green), [0x02, 0x01, 0x00, 0x01, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00]),
            (LightingEffectPatch(kind: .pulseDual, primary: RGBPatch(r: 0xFF, g: 0, b: 0), secondary: RGBPatch(r: 0, g: 0, b: 0xFF)), [0x02, 0x02, 0x00, 0x02, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF]),
            (LightingEffectPatch(kind: .reactive, primary: green, reactiveSpeed: 2), [0x05, 0x00, 0x02, 0x01, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00])
        ]
        for (effect, expected) in cases { XCTAssertEqual([UInt8](BLEVendorProtocol.buildBluetoothZoneEffectPayload(effect: effect)), expected, effect.kind.rawValue) }
    }

    func testDpiTableRoundTripsCapturedWrite() throws {
        // Captured 36-byte read: stage IDs 1-5 at 400/800/1600/3200/6400, active ID 3.
        let read = Data([0x03, 0x05, 0x01, 0x90, 0x01, 0x90, 0x01, 0x00, 0x00, 0x02, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00, 0x03, 0x40, 0x06, 0x40, 0x06, 0x00, 0x00, 0x04, 0x80, 0x0C, 0x80, 0x0C, 0x00, 0x00, 0x05, 0x00, 0x19, 0x00, 0x19, 0x00])
        let snapshot = try XCTUnwrap(BLEVendorProtocol.parseDpiStageSnapshot(blob: read))
        XCTAssertEqual(snapshot.active, 2)
        XCTAssertEqual(snapshot.count, 5)
        XCTAssertEqual(snapshot.stageIDs, [1, 2, 3, 4, 5])
        XCTAssertEqual(snapshot.pairs, [400, 800, 1600, 3200, 6400].map { DpiPair(x: $0, y: $0) })

        // Captured 38-byte write that changed stage 3 to 1700 x 1800 and read back exactly.
        var pairs = snapshot.pairs
        pairs[2] = DpiPair(x: 1700, y: 1800)
        let written = BLEVendorProtocol.buildDpiStagePayload(active: snapshot.active, count: snapshot.count, pairs: pairs, marker: snapshot.marker, stageIDs: snapshot.stageIDs, profileID: .basiliskMobile)
        let captured: [UInt8] = [0x03, 0x05, 0x01, 0x90, 0x01, 0x90, 0x01, 0x00, 0x00, 0x02, 0x20, 0x03, 0x20, 0x03, 0x00, 0x00, 0x03, 0xA4, 0x06, 0x08, 0x07, 0x00, 0x00, 0x04, 0x80, 0x0C, 0x80, 0x0C, 0x00, 0x00, 0x05, 0x00, 0x19, 0x00, 0x19, 0x00, 0x00, 0x00]
        XCTAssertEqual([UInt8](written), captured)
    }

    func testButtonFactoryDefaultsMatchCapturedFactoryLane() {
        // Factory lane of 08 84 <target> <slot> on owner hardware.
        let factory: [Int: [UInt8]] = [
            1: [0x01, 0x01, 0x01, 0, 0, 0, 0], 2: [0x01, 0x01, 0x02, 0, 0, 0, 0], 3: [0x01, 0x01, 0x03, 0, 0, 0, 0], 4: [0x01, 0x01, 0x04, 0, 0, 0, 0], 5: [0x01, 0x01, 0x05, 0, 0, 0, 0], 128: [0x00, 0x01, 0x00, 0, 0, 0, 0], 52: [0x0E, 0x01, 0x68, 0x00, 0x14, 0, 0],
            53: [0x0E, 0x01, 0x69, 0x00, 0x14, 0, 0], 9: [0x01, 0x01, 0x09, 0, 0, 0, 0], 10: [0x01, 0x01, 0x0A, 0, 0, 0, 0]
        ]
        for (slot, block) in factory {
            XCTAssertEqual(ButtonBindingSupport.defaultUSBFunctionBlock(for: slot, profileID: .basiliskMobile), block, "slot \(slot)")
            XCTAssertTrue(ButtonBindingSupport.supportsDefaultRestore(for: slot, profileID: .basiliskMobile), "slot \(slot)")
        }
        XCTAssertTrue(DeviceProfileID.basiliskMobile.usesBasiliskV4BluetoothButtonProtocol)
    }

    func testButtonReadUsesCurrentLane() {
        // Slot 0x05 after the owner's Synapse remap: current 500 DPI clutch, factory forward, interleaved.
        let read = Data([0x05, 0x00, 0x06, 0x01, 0x05, 0x01, 0x05, 0x05, 0x01, 0x00, 0xF4, 0x00, 0x01, 0x00, 0xF4, 0x00])
        XCTAssertEqual(BLEVendorProtocol.extractBluetoothFunctionBlock(payload: read, target: 1, slot: 0x05, profileID: .basiliskMobile), [0x06, 0x05, 0x05, 0x01, 0xF4, 0x01, 0xF4])
        // Slot 0x80 (AI Prompt Master) remapped to back.
        let ai = Data([0x80, 0x00, 0x01, 0x00, 0x01, 0x01, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(BLEVendorProtocol.extractBluetoothFunctionBlock(payload: ai, target: 1, slot: 0x80, profileID: .basiliskMobile), [0x01, 0x01, 0x04, 0x00, 0x00, 0x00, 0x00])
    }

    func testButtonWriteMatchesCapturedPayload() {
        // Written to 08 04 01 05, read back on both targets, and press-checked as right click.
        let payload = BLEVendorProtocol.buildButtonPayload(slot: 0x05, kind: .rightClick, hidKey: nil, profileID: .basiliskMobile)
        XCTAssertEqual([UInt8](payload), [0x01, 0x05, 0x00, 0x01, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00])
    }

    func testCableProfileMatchesProbedUSBCommands() throws {
        let profile = try XCTUnwrap(DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00D3, transport: .usb))
        XCTAssertEqual(profile.usbTransactionID, 0x1F)
        XCTAssertEqual(profile.lightingLEDIDs(), [0x04])
        XCTAssertEqual(profile.supportedLightingEffects, [.off, .staticColor, .spectrum, .reactive, .pulseRandom, .pulseSingle, .pulseDual])
        XCTAssertTrue(profile.supportsLightingBrightnessControls)
        XCTAssertTrue(profile.supportsDPIControls)
        XCTAssertTrue(profile.supportsIndependentXYDPI)
        XCTAssertTrue(profile.supportsPollRateControls)
        XCTAssertTrue(profile.supportsPowerManagementControls)
        XCTAssertTrue(profile.supportsButtonRemapControls)
        XCTAssertEqual(Set(profile.buttonLayout.writableSlots), [1, 2, 3, 4, 5, 9, 10, 52, 53, 128])
        XCTAssertNil(profile.bluetoothStoredLightingTarget)
        XCTAssertFalse(profile.isLocallyValidated)
    }

    func testBrightnessWritesNeverReachZero() {
        // Firmware latches the LED off at brightness 0 until an effect is re-sent.
        let cable = MouseDevice(id: "basilisk-mobile-usb-test", vendor_id: 0x1532, product_id: 0x00D3, product_name: "Razer Basilisk Mobile", transport: .usb, path_b64: "", serial: nil, firmware: nil, profile_id: .basiliskMobile)
        for mouse in [device, cable] {
            XCTAssertEqual(mouse.clampedLightingBrightness(0), 1)
            XCTAssertEqual(mouse.clampedLightingBrightness(1), 1)
            XCTAssertEqual(mouse.clampedLightingBrightness(255), 255)
        }
        let other = MouseDevice(id: "basilisk-v3-test", vendor_id: 0x1532, product_id: 0x0099, product_name: "Razer Basilisk V3", transport: .usb, path_b64: "", serial: nil, firmware: nil)
        XCTAssertEqual(other.clampedLightingBrightness(0), 0)
    }
}
