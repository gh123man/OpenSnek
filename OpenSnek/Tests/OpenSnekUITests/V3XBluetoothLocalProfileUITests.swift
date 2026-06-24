import XCTest

/// Exercises V3 X Bluetooth local profile UI behavior.
final class V3XBluetoothLocalProfileUITests: V3XLocalProfileUITestSupport {
    override var expectedScope: HardwareDeviceScope {
        .v3XBluetooth
    }

    func testV3XBluetoothLocalProfilePickerReflectsCreateReplaceRenameDeleteFlows() throws {
        try runLocalProfilePickerReflectsCreateReplaceRenameDeleteFlows()
    }

    func testV3XBluetoothLocalProfileSwitchesDPIStagesAndButtonBindings() throws {
        try runLocalProfileSwitchesDPIStagesAndButtonBindings()
    }

    func testV3XBluetoothRestoreLastProfileSelectionReflectsKnownProfile() throws {
        try runRestoreLastProfileSelectionReflectsKnownProfile()
    }

    func testV3XBluetoothRestoreLastProfileColdLaunchReflectsKnownProfile() throws {
        try runRestoreLastProfileColdLaunchReflectsKnownProfile()
    }
}

/// Exercises V3 X USB local profile UI behavior.
final class V3XUSBLocalProfileUITests: V3XLocalProfileUITestSupport {
    override var expectedScope: HardwareDeviceScope {
        .v3XUSB
    }

    func testV3XUSBLocalProfilePickerReflectsCreateReplaceRenameDeleteFlows() throws {
        try runLocalProfilePickerReflectsCreateReplaceRenameDeleteFlows()
    }

    func testV3XUSBLocalProfileSwitchesDPIStagesAndButtonBindings() throws {
        try runLocalProfileSwitchesDPIStagesAndButtonBindings()
    }

    func testV3XUSBRestoreLastProfileSelectionReflectsKnownProfile() throws {
        try runRestoreLastProfileSelectionReflectsKnownProfile()
    }

    func testV3XUSBRestoreLastProfileColdLaunchReflectsKnownProfile() throws {
        try runRestoreLastProfileColdLaunchReflectsKnownProfile()
    }
}

/// Stores V3 X local profile UI test support test data.
class V3XLocalProfileUITestSupport: OpenSnekHardwareUITestCase {
    /// Stores temporary local profile test data.
    private struct TemporaryLocalProfile: Equatable {
        var name: String
        let replaceIdentifier: String
        let manageIdentifier: String
        let isRestoreProfile: Bool
    }

    /// Stores profile switch settings test data.
    private struct ProfileSwitchSettings {
        let dpiStages: [Int]
        let buttonSlot: Int
        let buttonLabel: String
        let buttonKindRaw: String
    }

    private let actionTimeout: TimeInterval = 20
    private let testProfileNamePrefix = "000UITest"
    private var originalProfileName: String?
    private var temporaryProfiles: [TemporaryLocalProfile] = []

    override func restoreHardwareStateIfNeeded() {
        restoreAndDeleteTemporaryProfiles()
    }

    func runLocalProfilePickerReflectsCreateReplaceRenameDeleteFlows() throws {
        let deviceName = try XCTUnwrap(launchAndWaitForScopedDevice(timeout: 10))
        if let expectedProductName = expectedScope.productName {
            assertElementText(deviceName, equals: expectedProductName, context: "selected device name")
        }
        try keepMouseAwakeForUITest(timeout: actionTimeout)

        XCTAssertFalse(
            app.descendants(matching: .any)["on-connect-card"].waitForExistence(timeout: 0.5),
            "Single-slot devices should use the picker On Connect controls, not the standalone card"
        )

        try openProfilePicker()
        try assertSingleSlotPickerSurface()
        try deleteAllUITestProfiles()
        originalProfileName = try selectedSingleSlotProfileName()

        let suffix = String(UUID().uuidString.prefix(4))
        let restoreName = "\(testProfileNamePrefix) Restore \(suffix)"
        let freshName = "\(testProfileNamePrefix) Fresh \(suffix)"
        let renamedName = "\(testProfileNamePrefix) Renamed \(suffix)"

        try createProfileFromCurrentMouse(named: restoreName)
        _ = try recordTemporaryProfile(named: restoreName, isRestoreProfile: true)

        try createFreshProfile(named: freshName)
        let freshProfile = try recordTemporaryProfile(named: freshName, isRestoreProfile: false)
        let freshButton = try localProfileButton(named: freshName)
        XCTAssertTrue(freshButton.isEnabled, "New fresh profile should be applicable, not permanently disabled")

        clickLeftSideOfCell(freshButton)
        XCTAssertTrue(
            waitForLoadingFeedbackOrSelectedProfile(named: freshName, timeout: 1),
            "Replacing a local profile should either show loading feedback or update the selected profile promptly"
        )
        try assertSelectedProfile(named: freshName)

        try renameTemporaryProfile(freshProfile, to: renamedName)
        XCTAssertFalse(localProfileExists(named: freshName), "Renaming should remove the old local profile row label")
        XCTAssertTrue(
            waitForLocalProfile(named: renamedName, enabled: true, timeout: 2),
            "Renamed local profile row did not appear enabled"
        )

        let renamedButton = try requireButton(freshProfile.replaceIdentifier, timeout: 2)
        clickLeftSideOfCell(renamedButton)
        try assertSelectedProfile(named: renamedName)

        try deleteTemporaryProfile(matching: freshProfile.manageIdentifier)
        XCTAssertFalse(localProfileExists(named: renamedName), "Deleted local profile row should disappear")

        try restoreAndDeleteTemporaryProfilesThrowing()
    }

    func runLocalProfileSwitchesDPIStagesAndButtonBindings() throws {
        _ = try XCTUnwrap(
            launchAndWaitForScopedDevice(timeout: 15),
            "Expected connected \(expectedScope.description)"
        )
        try keepMouseAwakeForUITest(timeout: actionTimeout)

        try openProfilePicker()
        try assertSingleSlotPickerSurface()
        try deleteAllUITestProfiles()
        originalProfileName = try selectedSingleSlotProfileName()

        let suffix = String(UUID().uuidString.prefix(4))
        let restoreName = "\(testProfileNamePrefix) Restore \(suffix)"
        let alphaName = "\(testProfileNamePrefix) Switch Alpha \(suffix)"
        let betaName = "\(testProfileNamePrefix) Switch Beta \(suffix)"
        let alphaSettings = ProfileSwitchSettings(
            dpiStages: [800, 1400, 2000],
            buttonSlot: 4,
            buttonLabel: "Mouse Forward",
            buttonKindRaw: "mouse_forward"
        )
        let betaSettings = ProfileSwitchSettings(
            dpiStages: [600, 1000],
            buttonSlot: 4,
            buttonLabel: "Mouse Back",
            buttonKindRaw: "mouse_back"
        )

        try createProfileFromCurrentMouse(named: restoreName)
        _ = try recordTemporaryProfile(named: restoreName, isRestoreProfile: true)
        closeProfilePickerIfNeeded()

        try applySwitchSettings(alphaSettings)
        let alphaProfile = try createSnapshotProfile(named: alphaName)

        try applySwitchSettings(betaSettings)
        let betaProfile = try createSnapshotProfile(named: betaName)

        try switchToLocalProfile(alphaProfile)
        try assertVisibleSettings(alphaSettings)

        try switchToLocalProfile(betaProfile)
        try assertVisibleSettings(betaSettings)

        try switchToLocalProfile(alphaProfile)
        try assertVisibleSettings(alphaSettings)

        try restoreAndDeleteTemporaryProfilesThrowing()
    }

    func runRestoreLastProfileSelectionReflectsKnownProfile() throws {
        _ = try XCTUnwrap(
            launchAndWaitForScopedDevice(timeout: 15),
            "Expected connected \(expectedScope.description)"
        )
        try keepMouseAwakeForUITest(timeout: actionTimeout)

        try openProfilePicker()
        try assertSingleSlotPickerSurface()
        try deleteAllUITestProfiles()
        originalProfileName = try selectedSingleSlotProfileName()

        let suffix = String(UUID().uuidString.prefix(4))
        let restoreName = "\(testProfileNamePrefix) Restore Toggle \(suffix)"

        try createProfileFromCurrentMouse(named: restoreName)
        let restoreProfile = try recordTemporaryProfile(named: restoreName, isRestoreProfile: true)
        try switchToLocalProfile(restoreProfile)

        try selectOnConnectOption(named: "Use Mouse Settings")
        try assertSelectedProfile(named: "Base Profile")

        try selectOnConnectOption(named: "Restore Last Profile")
        try assertSelectedProfile(named: restoreName)

        try restoreAndDeleteTemporaryProfilesThrowing()
    }

    func runRestoreLastProfileColdLaunchReflectsKnownProfile() throws {
        _ = try XCTUnwrap(
            launchAndWaitForScopedDevice(timeout: 15),
            "Expected connected \(expectedScope.description)"
        )
        try keepMouseAwakeForUITest(timeout: actionTimeout)

        try openProfilePicker()
        try assertSingleSlotPickerSurface()
        try deleteAllUITestProfiles()
        originalProfileName = try selectedSingleSlotProfileName()

        let suffix = String(UUID().uuidString.prefix(4))
        let restoreName = "\(testProfileNamePrefix) Restore Launch \(suffix)"

        try createProfileFromCurrentMouse(named: restoreName)
        let restoreProfile = try recordTemporaryProfile(named: restoreName, isRestoreProfile: true)
        try switchToLocalProfile(restoreProfile)
        try selectOnConnectOption(named: "Restore Last Profile")

        app.terminate()
        _ = try XCTUnwrap(
            launchAndWaitForScopedDevice(timeout: 15),
            "Expected connected \(expectedScope.description) after relaunch"
        )
        try keepMouseAwakeForUITest(timeout: actionTimeout)

        try openProfilePicker()
        // The real single-slot hardware path used to relaunch with Restore Last Profile
        // selected but present Base Profile. Keep this assertion on the visible UI state.
        XCTAssertTrue(
            onConnectPresentationMatchesSelectedOption("Restore Last Profile"),
            "Restore Last Profile should still be the saved On Connect policy after relaunch"
        )
        try assertSelectedProfile(named: restoreName)

        try restoreAndDeleteTemporaryProfilesThrowing()
    }

    private func assertSingleSlotPickerSurface() throws {
        XCTAssertTrue(try requireElement("onboard-profiles-card", timeout: 2).exists)
        XCTAssertTrue(try requireElement("onboard-profile-row-1", timeout: 2).exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["onboard-profile-row-2"].waitForExistence(timeout: 0.5),
            "HyperSpeed should expose exactly one onboard slot"
        )
        XCTAssertTrue(try requireElement("profile-on-connect-picker", timeout: 2).exists)
        XCTAssertTrue(try requireElement("local-profile-replace-section", timeout: 2).exists)
        XCTAssertTrue(app.staticTexts["Onboard Profiles"].waitForExistence(timeout: 1))
        XCTAssertTrue(app.staticTexts["Replace Profile"].waitForExistence(timeout: 1))
        XCTAssertNotNil(onConnectOption(named: "Use Mouse Settings"))
        XCTAssertNotNil(onConnectOption(named: "Restore Last Profile"))
        XCTAssertFalse(app.buttons["Load From Mouse"].waitForExistence(timeout: 0.5))
        XCTAssertFalse(app.buttons["Apply Last Profile"].waitForExistence(timeout: 0.5))
        assertSynapseWarningMatchesSelectedConnectBehavior()
    }

    private func createFreshProfile(named name: String) throws {
        try openNewProfilePopover()
        try replaceText(in: try requireElement("local-profile-new-name-field", timeout: 2), with: name)
        clickElement(try requireElement("local-profile-start-fresh-button", timeout: 2))
        XCTAssertTrue(
            waitForLocalProfile(named: name, enabled: true, timeout: 3),
            "Fresh local profile \(name) did not appear enabled"
        )
    }

    private func onConnectOption(named name: String) -> XCUIElement? {
        firstExistingElement(
            in: [
                app.buttons[name],
                app.radioButtons[name],
                app.staticTexts[name],
                app.descendants(matching: .any)[name]
            ],
            timeout: 1
        )
    }

    private func assertSynapseWarningMatchesSelectedConnectBehavior(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let warning = app.descendants(matching: .any)["single-slot-synapse-warning"]
        switch selectedOnConnectOptionName() {
        case "Use Mouse Settings":
            XCTAssertTrue(
                warning.waitForExistence(timeout: 1),
                "Synapse warning should show when OpenSnek uses mouse settings on connect",
                file: file,
                line: line
            )
        case "Restore Last Profile":
            XCTAssertFalse(
                warning.waitForExistence(timeout: 0.5),
                "Synapse warning should hide when OpenSnek restores the last profile on connect",
                file: file,
                line: line
            )
        default:
            break
        }
    }

    private func selectedOnConnectOptionName() -> String? {
        ["Use Mouse Settings", "Restore Last Profile"].first { name in
            guard let option = onConnectOption(named: name) else {
                return false
            }
            if option.isSelected {
                return true
            }
            let value = option.value as? String
            return value == "1" || value?.localizedCaseInsensitiveContains("selected") == true
        }
    }

    private func selectOnConnectOption(named name: String) throws {
        try openProfilePicker()
        let option = try XCTUnwrap(onConnectOption(named: name), "Missing On Connect option \(name)")
        clickElement(option)
        XCTAssertTrue(
            waitUntil(timeout: 3) { self.onConnectPresentationMatchesSelectedOption(name) },
            "On Connect option \(name) did not update its visible presentation"
        )
    }

    private func onConnectPresentationMatchesSelectedOption(_ name: String) -> Bool {
        let warning = app.descendants(matching: .any)["single-slot-synapse-warning"]
        switch name {
        case "Use Mouse Settings":
            return warning.exists
        case "Restore Last Profile":
            return !warning.exists
        default:
            return false
        }
    }

    private func createProfileFromCurrentMouse(named name: String) throws {
        try openNewProfilePopover()
        try replaceText(in: try requireElement("local-profile-new-name-field", timeout: 2), with: name)
        let menu = try requireElement("local-profile-copy-source-picker", timeout: 2)
        clickElement(menu)
        let option = firstExistingElement(
            in: [
                app.menuItems["Current Mouse"],
                app.buttons["Current Mouse"],
                app.staticTexts["Current Mouse"],
                app.descendants(matching: .any)["Current Mouse"]
            ],
            timeout: 2
        )
        clickElement(try XCTUnwrap(option, "Current Mouse copy source did not appear"))
        XCTAssertTrue(
            waitForLocalProfile(named: name, enabled: true, timeout: actionTimeout),
            "Current Mouse local profile \(name) did not appear enabled"
        )
    }

    private func createSnapshotProfile(named name: String) throws -> TemporaryLocalProfile {
        try openProfilePicker()
        try createFreshProfile(named: name)
        let profile = try recordTemporaryProfile(named: name, isRestoreProfile: false)
        closeProfilePickerIfNeeded()
        return profile
    }

    private func switchToLocalProfile(_ profile: TemporaryLocalProfile) throws {
        try openProfilePicker()
        let button = try profileElement(identifier: profile.replaceIdentifier, fallbackName: profile.name)
        XCTAssertTrue(
            waitForElementReady(button, timeout: actionTimeout),
            "Profile \(profile.name) stayed disabled before replace"
        )
        clickLeftSideOfCell(button)
        XCTAssertTrue(
            waitForLoadingFeedbackOrSelectedProfile(named: profile.name, timeout: 1),
            "Replacing \(profile.name) did not show loading feedback or prompt selection"
        )
        try assertSelectedProfile(named: profile.name)
        closeProfilePickerIfNeeded()
    }

    private func applySwitchSettings(_ settings: ProfileSwitchSettings) throws {
        try setDPIStages(settings.dpiStages)
        try setButtonBinding(
            slot: settings.buttonSlot,
            label: settings.buttonLabel,
            rawKind: settings.buttonKindRaw
        )
    }

    private func setDPIStages(_ values: [Int]) throws {
        XCTAssertFalse(values.isEmpty, "Profile switch settings must include at least one DPI stage")
        let card = try requireElement("dpi-stages-card", timeout: 2)
        scrollElementToVisible(card)
        try setDPIStageCount(values.count)
        for (index, value) in values.enumerated() {
            try setDPIStageValue(stage: index + 1, value: value)
        }
        try assertDPIStages(values)
    }

    private func setDPIStageCount(_ targetCount: Int) throws {
        let clampedTarget = max(1, min(5, targetCount))
        while currentDPIStageCount() < clampedTarget {
            let expectedCount = min(currentDPIStageCount() + 1, clampedTarget)
            let button = try requireElement("dpi-stage-count-increase-button", timeout: 2)
            scrollElementToVisible(button)
            let changedAt = Date()
            clickElement(button)
            XCTAssertTrue(
                waitUntil(timeout: actionTimeout) { self.currentDPIStageCount() == expectedCount },
                "DPI stage count did not respond to increase"
            )
            try waitForDPIStagesApplied(count: expectedCount, since: changedAt)
        }
        while currentDPIStageCount() > clampedTarget {
            let expectedCount = max(currentDPIStageCount() - 1, clampedTarget)
            let button = try requireElement("dpi-stage-count-decrease-button", timeout: 2)
            scrollElementToVisible(button)
            let changedAt = Date()
            clickElement(button)
            XCTAssertTrue(
                waitUntil(timeout: actionTimeout) { self.currentDPIStageCount() == expectedCount },
                "DPI stage count did not respond to decrease"
            )
            try waitForDPIStagesApplied(count: expectedCount, since: changedAt)
        }
        XCTAssertTrue(
            waitUntil(timeout: actionTimeout) { self.currentDPIStageCount() == clampedTarget },
            "DPI stage count did not settle at \(clampedTarget)"
        )
    }

    private func setDPIStageValue(stage: Int, value: Int) throws {
        let field = try requireElement("dpi-stage-\(stage)-value-field", timeout: 2)
        scrollElementToVisible(field)
        clickElement(field)
        field.typeKey("a", modifierFlags: .command)
        let changedAt = Date()
        field.typeText(String(value))
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            waitUntil(timeout: actionTimeout) { self.integerValue(from: field) == value },
            "DPI stage \(stage) field did not update to \(value)"
        )
        try waitForDPIStageApplied(stage: stage, value: value, since: changedAt)
    }

    private func setButtonBinding(slot: Int, label: String, rawKind: String) throws {
        let picker = try findElementWhileScrolling("button-binding-kind-picker-\(slot)", maxScrolls: 12)
        scrollElementToVisible(picker)
        clickElement(picker)
        let option = firstExistingElement(
            in: [
                app.menuItems[label],
                app.buttons[label],
                app.staticTexts[label],
                app.descendants(matching: .any)[label]
            ],
            timeout: 2
        )
        let changedAt = Date()
        clickElement(try XCTUnwrap(option, "Button binding option \(label) did not appear"))
        XCTAssertTrue(
            waitForButtonBinding(slot: slot, label: label, rawKind: rawKind, timeout: actionTimeout),
            "Button slot \(slot) did not update to \(label)"
        )
        try waitForButtonBindingApplied(slot: slot, rawKind: rawKind, since: changedAt)
    }

    private func assertVisibleSettings(_ settings: ProfileSwitchSettings) throws {
        try assertDPIStages(settings.dpiStages)
        XCTAssertTrue(
            waitForButtonBinding(
                slot: settings.buttonSlot,
                label: settings.buttonLabel,
                rawKind: settings.buttonKindRaw,
                timeout: actionTimeout
            ),
            "Button slot \(settings.buttonSlot) did not show \(settings.buttonLabel) after profile switch"
        )
    }

    private func assertDPIStages(_ values: [Int]) throws {
        let card = try requireElement("dpi-stages-card", timeout: 2)
        scrollElementToVisible(card)
        XCTAssertTrue(
            waitUntil(timeout: actionTimeout) { self.currentDPIStageCount() == values.count },
            "DPI stage count did not show \(values.count)"
        )
        for (index, value) in values.enumerated() {
            let field = try requireElement("dpi-stage-\(index + 1)-value-field", timeout: 2)
            XCTAssertTrue(
                waitUntil(timeout: actionTimeout) { self.integerValue(from: field) == value },
                "DPI stage \(index + 1) did not show \(value)"
            )
        }
    }

    private func waitForButtonBinding(
        slot: Int,
        label: String,
        rawKind: String,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) {
            let visibleText = self.buttonBindingPickerText(slot: slot)
            if visibleText.contains(label) || visibleText.contains(rawKind) {
                return true
            }
            return self.latestButtonBindingKind(slot: slot) == rawKind
        }
    }

    private func waitForDPIStagesApplied(count: Int, since changedAt: Date) throws {
        let result = waitForFeatureEvent(since: changedAt, timeout: actionTimeout) { event in
            if event.name == "applyEnd",
               self.dpiValues(from: event.state).count == count ||
                self.dpiValues(from: event.patch).count == count {
                return true
            }
            if event.name == "onboardProfileMutationEnd",
               self.dpiValues(from: event.onboardMutation).count == count {
                return true
            }
            return false
        }
        try assertNoFeatureError(since: changedAt, matching: { self.eventContainsDPI($0) })
        XCTAssertNotNil(result, "DPI stage count apply did not finish at \(count)")
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    private func waitForDPIStageApplied(stage: Int, value: Int, since changedAt: Date) throws {
        let index = stage - 1
        let result = waitForFeatureEvent(since: changedAt, timeout: actionTimeout) { event in
            if event.name == "applyEnd",
               self.dpiValues(from: event.state).indices.contains(index),
               self.dpiValues(from: event.state)[index] == value {
                return true
            }
            if event.name == "applyEnd",
               self.dpiValues(from: event.patch).indices.contains(index),
               self.dpiValues(from: event.patch)[index] == value {
                return true
            }
            if event.name == "onboardProfileMutationEnd",
               self.dpiValues(from: event.onboardMutation).indices.contains(index),
               self.dpiValues(from: event.onboardMutation)[index] == value {
                return true
            }
            return false
        }
        try assertNoFeatureError(since: changedAt, matching: { self.eventContainsDPI($0) })
        XCTAssertNotNil(result, "DPI stage \(stage) apply did not finish at \(value)")
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    private func waitForButtonBindingApplied(slot: Int, rawKind: String, since changedAt: Date) throws {
        let slotKey = String(slot)
        let result = waitForFeatureEvent(since: changedAt, timeout: actionTimeout) { event in
            if event.name == "applyEnd",
               event.patch?.buttonBindingSlot == slot,
               event.patch?.buttonBindingKind == rawKind {
                return true
            }
            if event.name == "onboardProfileMutationEnd",
               event.onboardMutation?.buttonBindingKindsBySlot?[slotKey] == rawKind {
                return true
            }
            return false
        }
        try assertNoFeatureError(since: changedAt) { event in
            event.patch?.buttonBindingSlot == slot ||
                event.onboardMutation?.buttonBindingKindsBySlot?[slotKey] != nil
        }
        XCTAssertNotNil(result, "Button slot \(slot) binding apply did not finish as \(rawKind)")
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    private func waitForFeatureEvent(
        since changedAt: Date,
        timeout: TimeInterval,
        matching predicate: @escaping (UITestEvent) -> Bool
    ) -> UITestEvent? {
        let lowerBound = changedAt.timeIntervalSince1970 - 0.1
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let event = readEvents().first(where: { event in
                event.timestamp >= lowerBound &&
                    expectedScope.matches(event.scope) &&
                    predicate(event)
            }) {
                return event
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return readEvents().first(where: { event in
            event.timestamp >= lowerBound &&
                expectedScope.matches(event.scope) &&
                predicate(event)
        })
    }

    private func assertNoFeatureError(
        since changedAt: Date,
        matching predicate: (UITestEvent) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let lowerBound = changedAt.timeIntervalSince1970 - 0.1
        let error = readEvents().first { event in
            event.timestamp >= lowerBound &&
                expectedScope.matches(event.scope) &&
                (event.name == "applyError" || event.name == "onboardProfileMutationError") &&
                predicate(event)
        }
        if let error {
            XCTFail("Hardware apply failed while changing profile settings: \(error.error ?? "unknown error")", file: file, line: line)
        }
    }

    private func eventContainsDPI(_ event: UITestEvent) -> Bool {
        !dpiValues(from: event.patch).isEmpty ||
            !dpiValues(from: event.state).isEmpty ||
            !dpiValues(from: event.onboardMutation).isEmpty
    }

    private func dpiValues(from patch: UITestPatch?) -> [Int] {
        patch?.dpiStagePairs?.map(\.x) ?? patch?.dpiStages ?? []
    }

    private func dpiValues(from mutation: UITestOnboardProfileMutation?) -> [Int] {
        mutation?.dpiStagePairs?.map(\.x) ?? mutation?.dpiStages ?? []
    }

    private func dpiValues(from state: UITestState?) -> [Int] {
        state?.dpiStagePairs?.map(\.x) ?? state?.dpiStages ?? []
    }

    private func currentDPIStageCount() -> Int {
        (1...5).filter { stage in
            app.descendants(matching: .any)["dpi-stage-\(stage)-value-field"].exists
        }
        .count
    }

    private func buttonBindingPickerText(slot: Int) -> String {
        let picker = app.descendants(matching: .any)["button-binding-kind-picker-\(slot)"]
        return [picker.label, picker.value as? String]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func latestButtonBindingKind(slot: Int) -> String? {
        let key = String(slot)
        return readEvents()
            .reversed()
            .first {
                expectedScope.matches($0.scope) &&
                    $0.onboardMutation?.buttonBindingKindsBySlot?[key] != nil
            }?
            .onboardMutation?
            .buttonBindingKindsBySlot?[key]
    }

    private func openProfilePicker(timeout: TimeInterval = 5) throws {
        if app.descendants(matching: .any)["onboard-profiles-card"].exists {
            return
        }

        let pill = try requireElement("onboard-profile-pill-button", timeout: 3)
        scrollElementToVisible(pill)
        clickElement(pill)
        XCTAssertTrue(
            app.descendants(matching: .any)["onboard-profiles-card"].waitForExistence(timeout: timeout),
            "Profile picker did not open"
        )
    }

    private func closeProfilePickerIfNeeded() {
        let card = app.descendants(matching: .any)["onboard-profiles-card"]
        guard card.exists else { return }
        for _ in 0..<3 where card.exists {
            app.typeKey(.escape, modifierFlags: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
    }

    private func openNewProfilePopover() throws {
        try openProfilePicker()
        let button = try requireElement("local-profile-create-button", timeout: 2)
        clickElement(button)
        XCTAssertTrue(
            app.descendants(matching: .any)["local-profile-new-name-field"].waitForExistence(timeout: 2),
            "New Profile popover did not open"
        )
    }

    private func selectedSingleSlotProfileName() throws -> String {
        let row = try requireElement("onboard-profile-row-1", timeout: 2)
        let label = elementText(row)
        let name = label.split(separator: ",", maxSplits: 1).first.map(String.init) ?? label
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Base Profile" : trimmed
    }

    private func assertSelectedProfile(named name: String) throws {
        XCTAssertTrue(
            waitForSelectedProfile(named: name, timeout: actionTimeout),
            "Selected profile UI did not update to \(name)"
        )
        let row = try requireElement("onboard-profile-row-1", timeout: 2)
        XCTAssertTrue(elementText(row).contains(name), "Onboard slot row did not show \(name)")
        let pill = try requireElement("onboard-profile-pill-button", timeout: 2)
        XCTAssertTrue(elementText(pill).contains(name), "Profile pill did not show \(name)")
    }

    private func recordTemporaryProfile(
        named name: String,
        isRestoreProfile: Bool
    ) throws -> TemporaryLocalProfile {
        let replaceButton = try localProfileButton(named: name)
        let manageButton = try manageButton(named: name)
        let profile = TemporaryLocalProfile(
            name: name,
            replaceIdentifier: replaceButton.identifier,
            manageIdentifier: manageButton.identifier,
            isRestoreProfile: isRestoreProfile
        )
        temporaryProfiles.append(profile)
        return profile
    }

    private func renameTemporaryProfile(_ profile: TemporaryLocalProfile, to newName: String) throws {
        try renameLocalProfile(manageIdentifier: profile.manageIdentifier, currentName: profile.name, to: newName)
        if let index = temporaryProfiles.firstIndex(of: profile) {
            temporaryProfiles[index].name = newName
        }
    }

    private func renameLocalProfile(
        manageIdentifier: String,
        currentName: String,
        to newName: String
    ) throws {
        let manage = try manageButton(identifier: manageIdentifier, fallbackName: currentName)
        XCTAssertTrue(
            waitForElementReady(manage, timeout: actionTimeout),
            "Manage button for \(currentName) stayed disabled"
        )
        clickElement(manage)
        let field = try requireElement(renameFieldIdentifier(fromManageIdentifier: manageIdentifier), timeout: 2)
        try replaceText(in: field, with: newName)
        clickElement(try requireElement(renameButtonIdentifier(fromManageIdentifier: manageIdentifier), timeout: 2))
        XCTAssertTrue(
            waitForProfileIdentifier(
                replaceButtonIdentifier(fromManageIdentifier: manageIdentifier),
                toShowName: newName,
                timeout: 3
            ),
            "Local profile rename to \(newName) did not appear"
        )
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                !self.app.descendants(matching: .any)[renameFieldIdentifier(fromManageIdentifier: manageIdentifier)].exists
            },
            "Rename popover for \(newName) did not close"
        )
    }

    private func deleteTemporaryProfile(matching manageIdentifier: String) throws {
        guard let profile = temporaryProfiles.first(where: { $0.manageIdentifier == manageIdentifier }) else {
            return
        }
        try deleteLocalProfile(manageIdentifier: manageIdentifier, currentName: profile.name)
        temporaryProfiles.removeAll { $0.manageIdentifier == manageIdentifier }
    }

    private func deleteLocalProfile(manageIdentifier: String, currentName: String) throws {
        let manage = try manageButton(identifier: manageIdentifier, fallbackName: currentName)
        XCTAssertTrue(
            waitForElementReady(manage, timeout: actionTimeout),
            "Manage button for \(currentName) stayed disabled"
        )
        clickElement(manage)
        let deleteID = deleteButtonIdentifier(fromManageIdentifier: manageIdentifier)
        clickElement(try requireElement(deleteID, timeout: 2))
        XCTAssertTrue(
            waitUntil(timeout: 3) { !self.app.descendants(matching: .any)[manageIdentifier].exists },
            "Local profile \(currentName) was not deleted"
        )
        XCTAssertTrue(
            waitUntil(timeout: 3) { !self.app.descendants(matching: .any)[deleteID].exists },
            "Delete popover for \(currentName) did not close"
        )
    }

    private func restoreAndDeleteTemporaryProfiles() {
        do {
            try restoreAndDeleteTemporaryProfilesThrowing()
        } catch {
            XCTFail("Failed to clean up local profile UI test state: \(error)")
        }
    }

    private func restoreAndDeleteTemporaryProfilesThrowing() throws {
        try openProfilePicker()
        try restoreOriginalProfileIfNeeded()
        for profile in temporaryProfiles.reversed() {
            try deleteLocalProfile(manageIdentifier: profile.manageIdentifier, currentName: profile.name)
        }
        try deleteAllUITestProfiles()
        temporaryProfiles.removeAll()
        originalProfileName = nil
    }

    private func restoreOriginalProfileIfNeeded() throws {
        guard let originalProfileName,
              originalProfileName != "Base Profile" else {
            return
        }
        guard let restoreButton = findLocalProfileButton(named: originalProfileName, timeout: 3) else { return }
        XCTAssertTrue(
            waitForElementReady(restoreButton, timeout: actionTimeout),
            "Original profile \(originalProfileName) stayed disabled"
        )
        clickLeftSideOfCell(restoreButton)
        XCTAssertTrue(
            waitForSelectedProfile(named: originalProfileName, timeout: actionTimeout),
            "Original profile \(originalProfileName) was not restored"
        )
    }

    private func localProfileButton(named name: String) throws -> XCUIElement {
        let button = app.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 2), "Local profile row \(name) did not exist")
        return button
    }

    private func manageButton(named name: String) throws -> XCUIElement {
        let button = app.buttons["Manage \(name)"]
        XCTAssertTrue(button.waitForExistence(timeout: 2), "Manage button for \(name) did not exist")
        return button
    }

    private func manageButton(identifier: String, fallbackName: String) throws -> XCUIElement {
        if let identified = findLocalProfileButton(identifier: identifier, timeout: 1) {
            return identified
        }
        return try manageButton(named: fallbackName)
    }

    private func profileElement(identifier: String, fallbackName: String) throws -> XCUIElement {
        if let identified = findLocalProfileButton(identifier: identifier, timeout: 2) {
            return identified
        }
        return try localProfileButton(named: fallbackName)
    }

    private func waitForLocalProfile(
        named name: String,
        enabled: Bool,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) {
            let button = self.app.buttons[name]
            return button.exists && button.isEnabled == enabled
        }
    }

    private func localProfileExists(named name: String) -> Bool {
        app.buttons[name].waitForExistence(timeout: 0.5)
    }

    private func deleteAllUITestProfiles() throws {
        var deletedProfileIDs: Set<String> = []
        while let profile = findFirstUITestProfile() {
            guard deletedProfileIDs.insert(profile.manageIdentifier).inserted else {
                XCTFail("Local profile cleanup could not remove \(profile.name)")
                return
            }
            try deleteLocalProfile(manageIdentifier: profile.manageIdentifier, currentName: profile.name)
            temporaryProfiles.removeAll { $0.manageIdentifier == profile.manageIdentifier }
        }
    }

    private func findFirstUITestProfile() -> TemporaryLocalProfile? {
        scrollLocalProfileListToTop()
        for _ in 0..<12 {
            if let button = firstVisibleUITestProfileReplaceButton() {
                let uuid = profileUUID(fromReplaceIdentifier: button.identifier)
                let name = elementText(button)
                guard !uuid.isEmpty, !name.isEmpty else {
                    return nil
                }
                return TemporaryLocalProfile(
                    name: name,
                    replaceIdentifier: button.identifier,
                    manageIdentifier: "local-profile-manage-\(uuid)",
                    isRestoreProfile: false
                )
            }
            scrollLocalProfileListDown()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
    }

    private func firstVisibleUITestProfileReplaceButton() -> XCUIElement? {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", testProfileNamePrefix)
        return app.buttons
            .matching(predicate)
            .allElementsBoundByIndex
            .first { $0.identifier.hasPrefix("local-profile-replace-") && $0.exists }
    }

    private func waitForSelectedProfile(named name: String, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            let row = self.app.descendants(matching: .any)["onboard-profile-row-1"]
            let pill = self.app.descendants(matching: .any)["onboard-profile-pill-button"]
            return row.exists &&
                pill.exists &&
                self.elementText(row).contains(name) &&
                self.elementText(pill).contains(name)
        }
    }

    private func waitForProfileIdentifier(
        _ identifier: String,
        toShowName name: String,
        timeout: TimeInterval
    ) -> Bool {
        waitUntil(timeout: timeout) {
            guard let element = self.findLocalProfileButton(identifier: identifier, timeout: 0.1) else {
                return false
            }
            return self.elementText(element).contains(name)
        }
    }

    private func waitForLoadingFeedbackOrSelectedProfile(named name: String, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            self.app.descendants(matching: .any)["local-profile-loading-overlay"].exists ||
                self.textContaining("Replacing profile").exists ||
                self.waitForSelectedProfile(named: name, timeout: 0.1)
        }
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

    private func requireButton(
        _ identifier: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Missing UI button \(identifier)", file: file, line: line)
        return button
    }

    private func findElementWhileScrolling(
        _ identifier: String,
        maxScrolls: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        if element.waitForExistence(timeout: 0.5) {
            return element
        }

        let scrollView = detailScrollView()
        for _ in 0..<maxScrolls {
            if scrollView.exists {
                scrollView.scroll(byDeltaX: 0, deltaY: -700)
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            if element.exists {
                return element
            }
        }

        XCTAssertTrue(element.exists, "Missing UI element \(identifier)", file: file, line: line)
        return try XCTUnwrap(element.exists ? element : nil, file: file, line: line)
    }

    private func findLocalProfileButton(identifier: String, timeout: TimeInterval) -> XCUIElement? {
        scrollLocalProfileListToTop()
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let button = app.buttons[identifier]
            if button.exists {
                return button
            }
            scrollLocalProfileListDown()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        let button = app.buttons[identifier]
        return button.exists ? button : nil
    }

    private func findLocalProfileButton(named name: String, timeout: TimeInterval) -> XCUIElement? {
        scrollLocalProfileListToTop()
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let button = app.buttons[name]
            if button.exists {
                return button
            }
            scrollLocalProfileListDown()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        let button = app.buttons[name]
        return button.exists ? button : nil
    }

    private func scrollLocalProfileListToTop() {
        let list = app.scrollViews["local-profile-replace-list"]
        guard list.exists else { return }
        for _ in 0..<8 {
            list.scroll(byDeltaX: 0, deltaY: 250)
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        }
    }

    private func scrollLocalProfileListDown() {
        let list = app.scrollViews["local-profile-replace-list"]
        guard list.exists else { return }
        list.scroll(byDeltaX: 0, deltaY: -250)
    }

    private func replaceText(in field: XCUIElement, with text: String) throws {
        clickElement(field)
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
    }

    private func clickLeftSideOfCell(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).click()
    }

    private func textContaining(_ text: String) -> XCUIElement {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
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

    private func waitForElementReady(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        waitUntil(timeout: timeout) {
            element.exists && element.isEnabled
        }
    }

    private func integerValue(from element: XCUIElement) -> Int? {
        for raw in [element.value as? String, element.label] {
            guard let raw else { continue }
            let digits = raw.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let value = Int(digits) {
                return value
            }
        }
        return nil
    }

    private func renameFieldIdentifier(fromManageIdentifier identifier: String) -> String {
        "local-profile-rename-field-\(profileUUID(fromManageIdentifier: identifier))"
    }

    private func replaceButtonIdentifier(fromManageIdentifier identifier: String) -> String {
        "local-profile-replace-\(profileUUID(fromManageIdentifier: identifier))"
    }

    private func renameButtonIdentifier(fromManageIdentifier identifier: String) -> String {
        "local-profile-rename-button-\(profileUUID(fromManageIdentifier: identifier))"
    }

    private func deleteButtonIdentifier(fromManageIdentifier identifier: String) -> String {
        "local-profile-delete-\(profileUUID(fromManageIdentifier: identifier))"
    }

    private func profileUUID(fromManageIdentifier identifier: String) -> String {
        identifier.replacingOccurrences(of: "local-profile-manage-", with: "")
    }

    private func profileUUID(fromReplaceIdentifier identifier: String) -> String {
        identifier.replacingOccurrences(of: "local-profile-replace-", with: "")
    }
}
