import XCTest

final class OnboardProfilePopoverUITests: OpenSnekHardwareUITestCase {
    private let actionTimeout: TimeInterval = 15
    private var originalActiveProfileID: Int?
    private var createdProfileID: Int?
    private var didDeleteCreatedProfile = false

    override var expectedScope: HardwareDeviceScope {
        .v3ProUSB
    }

    override func restoreHardwareStateIfNeeded() {
        deleteCreatedProfileIfNeeded()
        restoreOriginalActiveProfileIfNeeded()
    }

    func testProfileManagerCoversCRUDSwitchingAndRestoresActiveProfile() throws {
        let appReadyStartedAt = Date()
        let deviceName = try XCTUnwrap(launchAndWaitForScopedDevice(timeout: 10))
        XCTAssertLessThanOrEqual(Date().timeIntervalSince(appReadyStartedAt), 10)
        if let expectedProductName = expectedScope.productName {
            assertElementText(deviceName, equals: expectedProductName, context: "selected device name")
        }
        try keepMouseAwakeForUITest()

        let initialState = try XCTUnwrap(
            latestExpectedScopedState(),
            "Expected \(expectedScope.description) to publish hydrated state before profile CRUD coverage"
        )
        let initialActiveProfileID = try XCTUnwrap(
            initialState.activeOnboardProfile,
            "Expected \(expectedScope.description) state to include the active onboard profile"
        )
        originalActiveProfileID = initialActiveProfileID

        try assertProfilePillMatchesStatusPillHeight()
        try openProfileManager()

        let profileIDs = visibleProfileIDs()
        XCTAssertGreaterThanOrEqual(profileIDs.count, 2, "Expected multiple onboard profile slots")
        for profileID in profileIDs {
            XCTAssertTrue(profileRow(profileID).exists, "Profile row \(profileID) should be listed")
        }

        guard let targetProfileID = profileIDs.first(where: { $0 > 1 && isProfileEmpty($0) }) else {
            throw XCTSkip("No empty non-base onboard profile slot is available for safe CRUD coverage")
        }
        let suffix = String(UUID().uuidString.prefix(4))
        let createdName = "OS CRUD \(suffix)"
        let renamedName = "OS Ren \(suffix)"

        try selectProfile(targetProfileID)
        let createButton = try requireElement("onboard-profile-create-button", timeout: 2)
        XCTAssertTrue(
            app.descendants(matching: .any)["onboard-profile-copy-from-picker"].waitForExistence(timeout: 2),
            "Empty profile details should expose the copy source picker"
        )
        XCTAssertTrue(
            waitForElementDisabled(createButton, timeout: 2),
            "Create should be disabled until a profile name is entered"
        )

        try replaceProfileName(with: createdName)
        let enabledCreateButton = try requireElement("onboard-profile-create-button", timeout: 2)
        XCTAssertTrue(waitForElementEnabled(enabledCreateButton, timeout: 2), "Create should enable after entering a name")
        createdProfileID = targetProfileID
        clickElement(enabledCreateButton)
        XCTAssertTrue(
            waitForProfileRow(targetProfileID, containing: createdName, timeout: actionTimeout),
            "Created profile row did not show \(createdName)"
        )
        XCTAssertTrue(
            waitForActiveProfile(targetProfileID, timeout: actionTimeout),
            "Created profile \(targetProfileID) did not become active"
        )
        XCTAssertTrue(
            waitForPill(containing: createdName, timeout: 2),
            "Profile pill did not reflect the created profile name"
        )

        try replaceProfileName(with: renamedName)
        let renameButton = try requireElement("onboard-profile-rename-button", timeout: 2)
        XCTAssertTrue(waitForElementEnabled(renameButton, timeout: 2), "Rename should be enabled for the created profile")
        clickElement(renameButton)
        XCTAssertTrue(
            waitForProfileRow(targetProfileID, containing: renamedName, timeout: actionTimeout),
            "Renamed profile row did not show \(renamedName)"
        )
        XCTAssertTrue(
            waitForPill(containing: renamedName, timeout: 2),
            "Profile pill did not reflect the renamed profile name"
        )

        try selectProfile(initialActiveProfileID)
        XCTAssertTrue(
            waitForActiveProfile(initialActiveProfileID, timeout: actionTimeout),
            "Original profile \(initialActiveProfileID) did not become active when selected"
        )

        try selectProfile(targetProfileID)
        XCTAssertTrue(
            waitForActiveProfile(targetProfileID, timeout: actionTimeout),
            "Created profile \(targetProfileID) did not become active when reselected"
        )

        let deleteButton = try requireElement("onboard-profile-delete-button", timeout: 2)
        XCTAssertTrue(waitForElementEnabled(deleteButton, timeout: 2), "Delete should be enabled for the created profile")
        clickElement(deleteButton)
        XCTAssertTrue(
            waitForProfileRow(targetProfileID, containing: "None", timeout: actionTimeout),
            "Deleted profile \(targetProfileID) did not return to an empty slot"
        )
        didDeleteCreatedProfile = true
        createdProfileID = nil

        try selectProfile(initialActiveProfileID)
        XCTAssertTrue(
            waitForActiveProfile(initialActiveProfileID, timeout: actionTimeout),
            "Failed to restore original active profile \(initialActiveProfileID)"
        )
        originalActiveProfileID = nil
    }

    private func assertProfilePillMatchesStatusPillHeight() throws {
        let profilePill = try requireElement("onboard-profile-pill-button", timeout: 3)
        let statusPill = try requireElement("device-status-badge", timeout: 3)
        XCTAssertEqual(
            profilePill.frame.height,
            statusPill.frame.height,
            accuracy: 1,
            "Profile pill should use the same vertical sizing as the connected status pill"
        )
    }

    private func openProfileManager(timeout: TimeInterval = 5) throws {
        if app.descendants(matching: .any)["onboard-profiles-card"].exists {
            return
        }

        let pill = try requireElement("onboard-profile-pill-button", timeout: 3)
        scrollElementToVisible(pill)
        XCTAssertTrue(pill.isHittable, "Onboard profile pill was not hittable")
        clickElement(pill)

        XCTAssertTrue(
            app.descendants(matching: .any)["onboard-profiles-card"].waitForExistence(timeout: timeout),
            "Onboard profile manager popover did not appear"
        )
        XCTAssertTrue(
            profileRow(1).waitForExistence(timeout: timeout),
            "Base onboard profile row did not appear in the popover"
        )
    }

    private func openProfileManagerIfPossible(timeout: TimeInterval = 2) -> Bool {
        if app.descendants(matching: .any)["onboard-profiles-card"].exists {
            return true
        }
        let pill = app.descendants(matching: .any)["onboard-profile-pill-button"]
        guard pill.waitForExistence(timeout: timeout) else {
            return false
        }
        scrollElementToVisible(pill)
        clickElement(pill)
        return app.descendants(matching: .any)["onboard-profiles-card"].waitForExistence(timeout: timeout)
    }

    private func visibleProfileIDs() -> [Int] {
        (1...8).filter { profileRow($0).exists }
    }

    private func profileRow(_ profileID: Int) -> XCUIElement {
        app.descendants(matching: .any)["onboard-profile-row-\(profileID)"]
    }

    private func selectProfile(_ profileID: Int) throws {
        try openProfileManager()
        let row = profileRow(profileID)
        XCTAssertTrue(row.waitForExistence(timeout: 2), "Profile row \(profileID) did not exist")
        XCTAssertTrue(
            waitForElementEnabled(row, timeout: actionTimeout),
            "Profile row \(profileID) was not enabled for selection"
        )
        clickElement(row)
        XCTAssertTrue(
            app.descendants(matching: .any)["onboard-profile-name-field"].waitForExistence(timeout: 2),
            "Profile details did not appear after selecting profile \(profileID)"
        )
    }

    private func requireElement(
        _ identifier: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing UI element \(identifier)", file: file, line: line)
        return element
    }

    private func replaceProfileName(with name: String) throws {
        let field = try requireElement("onboard-profile-name-field", timeout: 2)
        clickElement(field)
        field.typeKey("a", modifierFlags: .command)
        field.typeText(name)
    }

    private func isProfileEmpty(_ profileID: Int) -> Bool {
        profileRowText(profileID).contains("None")
    }

    private func profileRowText(_ profileID: Int) -> String {
        elementText(profileRow(profileID))
    }

    private func waitForProfileRow(
        _ profileID: Int,
        containing expectedText: String,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) {
            let row = profileRow(profileID)
            return row.exists && elementText(row).contains(expectedText)
        }
    }

    private func waitForActiveProfile(_ profileID: Int, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            let row = profileRow(profileID)
            guard row.exists else { return false }
            return elementText(row).lowercased().contains("active")
        }
    }

    private func waitForPill(containing expectedText: String, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            let pill = app.descendants(matching: .any)["onboard-profile-pill-button"]
            return pill.exists && elementText(pill).contains(expectedText)
        }
    }

    private func waitForElementEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            element.exists && element.isEnabled
        }
    }

    private func waitForElementDisabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            element.exists && !element.isEnabled
        }
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return condition()
    }

    private func deleteCreatedProfileIfNeeded() {
        guard let createdProfileID, !didDeleteCreatedProfile else {
            return
        }
        guard openProfileManagerIfPossible() else {
            XCTFail("Could not reopen profile manager to delete temporary profile \(createdProfileID)")
            return
        }
        guard profileRow(createdProfileID).waitForExistence(timeout: 2),
              !isProfileEmpty(createdProfileID) else {
            return
        }

        guard waitForElementEnabled(profileRow(createdProfileID), timeout: actionTimeout) else {
            XCTFail("Temporary profile row \(createdProfileID) was not enabled during cleanup")
            return
        }
        clickElement(profileRow(createdProfileID))
        let deleteButton = app.descendants(matching: .any)["onboard-profile-delete-button"]
        guard deleteButton.waitForExistence(timeout: 2),
              waitForElementEnabled(deleteButton, timeout: 2) else {
            XCTFail("Could not delete temporary profile \(createdProfileID) during cleanup")
            return
        }

        clickElement(deleteButton)
        if waitForProfileRow(createdProfileID, containing: "None", timeout: actionTimeout) {
            didDeleteCreatedProfile = true
            self.createdProfileID = nil
        } else {
            XCTFail("Temporary profile \(createdProfileID) was not deleted during cleanup")
        }
    }

    private func restoreOriginalActiveProfileIfNeeded() {
        guard let originalActiveProfileID else {
            return
        }
        guard openProfileManagerIfPossible() else {
            XCTFail("Could not reopen profile manager to restore active profile \(originalActiveProfileID)")
            return
        }
        guard profileRow(originalActiveProfileID).waitForExistence(timeout: 2) else {
            XCTFail("Original active profile row \(originalActiveProfileID) was unavailable during cleanup")
            return
        }

        guard waitForElementEnabled(profileRow(originalActiveProfileID), timeout: actionTimeout) else {
            XCTFail("Original active profile row \(originalActiveProfileID) was not enabled during cleanup")
            return
        }
        clickElement(profileRow(originalActiveProfileID))
        if waitForActiveProfile(originalActiveProfileID, timeout: actionTimeout) {
            self.originalActiveProfileID = nil
        } else {
            XCTFail("Could not restore original active profile \(originalActiveProfileID) during cleanup")
        }
    }
}
