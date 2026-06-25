import AppKit
import XCTest
@testable import OpenSnek

/// Exercises OpenSnek branding behavior.
final class OpenSnekBrandingTests: XCTestCase {
    func testMenuIconUsesTemplateRendering() throws {
        let icon = try XCTUnwrap(OpenSnekBranding.menuTemplateIcon(from: menuTemplateResourceURL, size: NSSize(width: OpenSnekBranding.menuBarIconSide, height: OpenSnekBranding.menuBarIconSide)))

        XCTAssertTrue(icon.isTemplate)
        XCTAssertEqual(icon.size.width, OpenSnekBranding.menuBarIconSide, accuracy: 0.1)
        XCTAssertEqual(icon.size.height, OpenSnekBranding.menuBarIconSide, accuracy: 0.1)
    }

    func testDpiBadgeUsesTemplateRendering() {
        let badge = OpenSnekBranding.menuBarDpiBadge(dpi: 1600)

        XCTAssertTrue(badge.isTemplate)
        XCTAssertGreaterThan(badge.size.width, 0)
        XCTAssertGreaterThan(badge.size.height, 0)
    }

    func testStatusSymbolUsesTemplateRendering() throws {
        let icon = try XCTUnwrap(OpenSnekBranding.menuBarSymbolIcon(symbolName: "battery.25percent"))

        XCTAssertTrue(icon.isTemplate)
    }

    func testColoredStatusSymbolUsesOriginalRendering() throws {
        let icon = try XCTUnwrap(OpenSnekBranding.menuBarSymbolIcon(symbolName: "battery.25percent", color: BatteryPresentation.lowBatteryNSColor))

        XCTAssertFalse(icon.isTemplate)
    }

    private var menuTemplateResourceURL: URL { packageRoot.appendingPathComponent("App").appendingPathComponent("Resources").appendingPathComponent("snek-menu-template.png") }

    private var packageRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
}
