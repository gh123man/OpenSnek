import XCTest

final class OnboardProfilePopoverUITests: OpenSnekHardwareUITestCase {
    override var expectedScope: HardwareDeviceScope {
        .v3ProUSB
    }

    func testProfilePillOpensOnboardProfileManagerPopover() throws {
        let appReadyStartedAt = Date()
        let deviceName = try XCTUnwrap(launchAndWaitForScopedDevice(timeout: 10))
        XCTAssertLessThanOrEqual(Date().timeIntervalSince(appReadyStartedAt), 10)
        if let expectedProductName = expectedScope.productName {
            assertElementText(deviceName, equals: expectedProductName, context: "selected device name")
        }
        try keepMouseAwakeForUITest()

        let pill = app.descendants(matching: .any)["onboard-profile-pill-button"]
        XCTAssertTrue(pill.waitForExistence(timeout: 3), "Onboard profile pill did not appear")
        XCTAssertTrue(pill.isHittable, "Onboard profile pill was not hittable")

        clickElement(pill)

        let manager = app.descendants(matching: .any)["onboard-profiles-card"]
        XCTAssertTrue(manager.waitForExistence(timeout: 5), "Onboard profile manager popover did not appear")

        let baseProfile = app.descendants(matching: .any)["onboard-profile-row-1"]
        XCTAssertTrue(baseProfile.waitForExistence(timeout: 5), "Base onboard profile row did not appear in the popover")
        clickElement(baseProfile)

        XCTAssertTrue(
            app.descendants(matching: .any)["onboard-profile-name-field"].waitForExistence(timeout: 2),
            "Onboard profile name field did not appear in the popover"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["onboard-profile-rename-button"].waitForExistence(timeout: 1),
            "Onboard profile rename action did not appear in the popover"
        )
    }
}
