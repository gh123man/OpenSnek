import XCTest
import OpenSnekCore

/// Exercises supported device presentation behavior.
final class SupportedDevicePresentationTests: XCTestCase {
    func testSupportedDeviceCatalogProfilesHavePresentationInputs() {
        let profiles = DeviceProfiles.all

        XCTAssertFalse(profiles.isEmpty)
        XCTAssertTrue(profiles.allSatisfy { !$0.productName.isEmpty })
        XCTAssertTrue(profiles.allSatisfy { !$0.supportedProducts.isEmpty })

        let uniqueRows = Set(profiles.map { "\($0.id.rawValue):\($0.transport.rawValue)" })
        XCTAssertEqual(uniqueRows.count, profiles.count)
    }
}
