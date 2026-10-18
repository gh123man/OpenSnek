import XCTest
import OpenSnekCore
@testable import OpenSnek

/// Verifies the USB lighting zone-mode mapping that keeps the picker and the apply path in agreement.
final class LightingZoneEditModeTests: XCTestCase {
    private let zones = [USBLightingZoneDescriptor(id: "scroll_wheel", label: "Scroll Wheel", ledIDs: [0x01]), USBLightingZoneDescriptor(id: "logo", label: "Logo", ledIDs: [0x04]), USBLightingZoneDescriptor(id: "side_panel", label: "Side Panel", ledIDs: [0x05])]

    func testModeIsDerivedFromTheStoredZoneID() {
        XCTAssertEqual(LightingZoneEditMode(zoneID: "all"), .allZones)
        for zoneID in ["scroll_wheel", "logo", "side_panel"] { XCTAssertEqual(LightingZoneEditMode(zoneID: zoneID), .individualZones, zoneID) }
    }

    func testSelectingAllZonesStoresTheAllSentinel() { XCTAssertEqual(LightingZoneEditMode.allZones.resolvedZoneID(currentZoneID: "logo", availableZoneIDs: zones.map(\.id)), "all") }

    func testSelectingIndividualZonesKeepsTheCurrentZoneOrFallsBackToTheFirst() {
        XCTAssertEqual(LightingZoneEditMode.individualZones.resolvedZoneID(currentZoneID: "logo", availableZoneIDs: zones.map(\.id)), "logo")
        XCTAssertEqual(LightingZoneEditMode.individualZones.resolvedZoneID(currentZoneID: "all", availableZoneIDs: zones.map(\.id)), "scroll_wheel")
        XCTAssertEqual(LightingZoneEditMode.individualZones.resolvedZoneID(currentZoneID: "stale_zone", availableZoneIDs: zones.map(\.id)), "scroll_wheel")
        XCTAssertEqual(LightingZoneEditMode.individualZones.resolvedZoneID(currentZoneID: "all", availableZoneIDs: []), "all")
    }

    func testStaticColorTargetsEveryLEDOnlyInAllZonesMode() {
        // The "Off then Static only lit the wheel" bug: a stale per-zone id narrowed the apply to one LED.
        XCTAssertNil(LightingZoneEditMode.staticColorLEDIDs(zoneID: "all", zones: zones))
        XCTAssertEqual(LightingZoneEditMode.staticColorLEDIDs(zoneID: "logo", zones: zones), [0x04])
        XCTAssertEqual(LightingZoneEditMode.staticColorLEDIDs(zoneID: "side_panel", zones: zones), [0x05])
        XCTAssertNil(LightingZoneEditMode.staticColorLEDIDs(zoneID: "stale_zone", zones: zones))
    }
}
