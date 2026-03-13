import XCTest
@testable import OpenSnek

final class ServiceMenuBarPresentationTests: XCTestCase {
    func testCompactDpiTextFormatsCommonValues() {
        XCTAssertNil(ServiceMenuBarPresentation.compactDpiText(for: nil))
        XCTAssertEqual(ServiceMenuBarPresentation.compactDpiText(for: 800), "800")
        XCTAssertEqual(ServiceMenuBarPresentation.compactDpiText(for: 1600), "1.6k")
        XCTAssertEqual(ServiceMenuBarPresentation.compactDpiText(for: 2000), "2k")
        XCTAssertEqual(ServiceMenuBarPresentation.compactDpiText(for: 12_000), "12k")
    }

    func testBatteryIconUsesAdaptiveSymbolAndSharedPresentation() {
        let shared = BatteryPresentation.icon(percent: 33, charging: true)
        let compactMenu = ServiceMenuBarPresentation.batteryIcon(percent: 33, charging: true)

        XCTAssertEqual(shared, compactMenu)
        XCTAssertEqual(shared.symbolName, "battery.100percent.bolt")
        XCTAssertEqual(shared.variableValue, 0.33, accuracy: 0.001)
    }

    func testBatteryIconClampsVariableValueToPercentBounds() {
        XCTAssertEqual(BatteryPresentation.icon(percent: -10, charging: false).variableValue, 0.0, accuracy: 0.001)
        XCTAssertEqual(BatteryPresentation.icon(percent: 58, charging: nil).variableValue, 0.58, accuracy: 0.001)
        XCTAssertEqual(BatteryPresentation.icon(percent: 120, charging: false).variableValue, 1.0, accuracy: 0.001)
        XCTAssertEqual(BatteryPresentation.icon(percent: 58, charging: nil).symbolName, "battery.100percent")
    }
}
