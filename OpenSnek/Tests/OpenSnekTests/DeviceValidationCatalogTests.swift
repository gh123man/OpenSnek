import XCTest
import OpenSnekCore

/// Verifies that validation tooling reads effective capabilities from canonical Swift profiles.
final class DeviceValidationCatalogTests: XCTestCase {
    func testCatalogExportsIDsAndTransportSpecificCapabilitiesWithoutHardware() throws {
        let catalog = DeviceValidationCatalog(profiles: [DeviceProfiles.basiliskV3ProUSB, DeviceProfiles.basiliskV3Pro35KPhantomGreenBluetooth])
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.profiles.count, 2)
        let usb = try XCTUnwrap(catalog.profiles.first(where: { $0.transport == "usb" }))
        XCTAssertEqual(usb.id, "basilisk_v3_pro")
        XCTAssertTrue(usb.productIDs.contains(0x00AB))
        XCTAssertEqual(usb.capabilities["poll_rate"], true)
        let bluetooth = try XCTUnwrap(catalog.profiles.first(where: { $0.transport == "bluetooth" }))
        XCTAssertEqual(bluetooth.productIDs, [0x00D8])
        XCTAssertEqual(bluetooth.capabilities["poll_rate"], false)
        XCTAssertFalse(bluetooth.isLocallyValidated)
        XCTAssertNoThrow(try JSONEncoder().encode(catalog))
    }
}
