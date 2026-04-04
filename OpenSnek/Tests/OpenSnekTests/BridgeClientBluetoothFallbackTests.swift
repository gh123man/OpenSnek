import XCTest
@testable import OpenSnek
import OpenSnekCore
import OpenSnekHardware

final class BridgeClientBluetoothFallbackTests: XCTestCase {
    private func makeBluetoothDevice(
        productID: Int,
        profileID: DeviceProfileID?
    ) -> MouseDevice {
        MouseDevice(
            id: "bt-device-\(productID)",
            vendor_id: 0x068E,
            product_id: productID,
            product_name: "Test Device",
            transport: .bluetooth,
            path_b64: "",
            serial: nil,
            firmware: nil,
            profile_id: profileID
        )
    }

    func testResolveBluetoothBatteryStateIgnoresVendorChargingForBasiliskV3ProBluetooth() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro),
            vendorRaw: 77,
            vendorStatus: 1,
            usbFallback: (12, false)
        )

        XCTAssertEqual(resolved.percent, 77)
        XCTAssertEqual(resolved.charging, false)
    }

    func testResolveBluetoothBatteryStateForcesNotChargingForBasiliskV3XBluetooth() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00BA, profileID: .basiliskV3XHyperspeed),
            vendorRaw: 77,
            vendorStatus: 1,
            usbFallback: (12, true)
        )

        XCTAssertEqual(resolved.percent, 77)
        XCTAssertEqual(resolved.charging, false)
    }

    func testResolveBluetoothBatteryStateKeepsChargingUnknownWhenStatusMissing() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro),
            vendorRaw: 87,
            vendorStatus: nil,
            usbFallback: nil
        )

        XCTAssertEqual(resolved.percent, 87)
        XCTAssertNil(resolved.charging)
    }

    func testResolveBluetoothBatteryStateFillsOnlyMissingFieldsFromUSBFallback() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro),
            vendorRaw: 240,
            vendorStatus: nil,
            usbFallback: (20, true)
        )

        XCTAssertEqual(resolved.percent, 94)
        XCTAssertEqual(resolved.charging, true)
    }

    func testResolveBluetoothBatteryStateKeepsV3ProChargingUnknownWithoutUSBFallback() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro),
            vendorRaw: 77,
            vendorStatus: 1,
            usbFallback: nil
        )

        XCTAssertEqual(resolved.percent, 77)
        XCTAssertNil(resolved.charging)
    }

    func testResolveBluetoothBatteryStateUsesUSBFallbackWhenVendorBatteryMissing() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro),
            vendorRaw: nil,
            vendorStatus: 0,
            usbFallback: (64, true)
        )

        XCTAssertEqual(resolved.percent, 64)
        XCTAssertEqual(resolved.charging, true)
    }

    func testSupportedBluetoothFallbackUsesResolvedProfile() {
        let summary = BLEVendorTransportClient.ConnectedPeripheralSummary(
            name: "Razer Basilisk V3 X HyperSpeed",
            identifier: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        )

        let device = BridgeClient.makeBluetoothFallbackDevice(summary: summary)

        XCTAssertEqual(device.vendor_id, 0x068E)
        XCTAssertEqual(device.product_id, 0x00BA)
        XCTAssertEqual(device.profile_id, .basiliskV3XHyperspeed)
        XCTAssertEqual(device.product_name, "Razer Basilisk V3 X HyperSpeed")
        XCTAssertEqual(device.transport, .bluetooth)
        XCTAssertNotNil(device.button_layout)
    }

    func testSupportedBluetoothFallbackUsesResolvedProfileForBasiliskV3ProAlias() {
        let summary = BLEVendorTransportClient.ConnectedPeripheralSummary(
            name: "BSK V3 PRO",
            identifier: UUID(uuidString: "99999999-2222-3333-4444-555555555555")!
        )

        let device = BridgeClient.makeBluetoothFallbackDevice(summary: summary)

        XCTAssertEqual(device.vendor_id, 0x068E)
        XCTAssertEqual(device.product_id, 0x00AC)
        XCTAssertEqual(device.profile_id, .basiliskV3Pro)
        XCTAssertEqual(device.product_name, "BSK V3 PRO")
        XCTAssertEqual(device.transport, .bluetooth)
        XCTAssertNotNil(device.button_layout)
    }

    func testUnsupportedBluetoothFallbackRemainsGeneric() {
        let summary = BLEVendorTransportClient.ConnectedPeripheralSummary(
            name: "Razer Cobra Pro",
            identifier: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        )

        let device = BridgeClient.makeBluetoothFallbackDevice(summary: summary)

        XCTAssertEqual(device.vendor_id, 0x068E)
        XCTAssertEqual(device.product_id, 0x0000)
        XCTAssertNil(device.profile_id)
        XCTAssertEqual(device.product_name, "Razer Cobra Pro")
        XCTAssertEqual(device.transport, .bluetooth)
        XCTAssertNil(device.button_layout)
        XCTAssertFalse(device.supports_advanced_lighting_effects)
    }

    func testPreferredBluetoothControlWarmupNameUsesResolvedProfile() {
        let preferredName = BridgeClient.preferredBluetoothControlWarmupName(
            vendorID: 0x068E,
            productID: 0x00BA,
            transport: .bluetooth
        )

        XCTAssertEqual(preferredName, "Basilisk V3 X HyperSpeed")
    }

    func testPreferredBluetoothControlWarmupNameUsesResolvedProfileForBasiliskV3Pro() {
        let preferredName = BridgeClient.preferredBluetoothControlWarmupName(
            vendorID: 0x068E,
            productID: 0x00AC,
            transport: .bluetooth
        )

        XCTAssertEqual(preferredName, "Basilisk V3 Pro")
    }

    func testPreferredBluetoothControlWarmupNameSkipsNonBluetoothDevices() {
        let preferredName = BridgeClient.preferredBluetoothControlWarmupName(
            vendorID: 0x1532,
            productID: 0x00B9,
            transport: .usb
        )

        XCTAssertNil(preferredName)
    }
}
