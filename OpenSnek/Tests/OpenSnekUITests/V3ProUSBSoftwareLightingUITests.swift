import XCTest

final class V3ProUSBSoftwareLightingUITests: OpenSnekHardwareUITestCase {
    override var expectedScope: HardwareDeviceScope {
        .v3ProUSB
    }

    override func restoreHardwareStateIfNeeded() {
        expandLightingCardIfNeeded(timeout: 1)
        let stopButton = app.descendants(matching: .any)["software-lighting-stop-button"]
        if stopButton.exists {
            clickElement(stopButton)
            _ = waitForStatusText(absent: "Running", timeout: 2)
        }
    }

    func testLightingTabsAndAdvancedApplyReplacementStayConnected() throws {
        let appReadyStartedAt = Date()
        let deviceName = try XCTUnwrap(launchAndWaitForScopedDevice(timeout: 10))
        XCTAssertLessThanOrEqual(Date().timeIntervalSince(appReadyStartedAt), 10)
        if let expectedProductName = expectedScope.productName {
            assertElementText(deviceName, equals: expectedProductName, context: "selected device name")
        }
        try keepMouseAwakeForUITest(timeout: 4)
        assertSelectedDeviceNeverDisconnected(context: "after launch")

        let lightingCard = app.descendants(matching: .any)["lighting-card"]
        XCTAssertTrue(lightingCard.waitForExistence(timeout: 2), "Lighting card did not appear")
        scrollElementToVisible(lightingCard)
        XCTAssertTrue(
            app.descendants(matching: .any)["lighting-card-summary-text"].waitForExistence(timeout: 1),
            "Collapsed lighting summary did not appear"
        )
        expandLightingCardIfNeeded()

        let tabPicker = app.descendants(matching: .any)["lighting-card-tab-picker"]
        XCTAssertTrue(tabPicker.waitForExistence(timeout: 1), "Lighting tab picker did not appear")
        selectSegment("Onboard", in: tabPicker, normalizedX: 0.25)
        assertOnboardLightingControlsExist()
        selectSegment("Individual Zones", in: app.descendants(matching: .any)["lighting-zone-mode-picker"], normalizedX: 0.75)
        XCTAssertTrue(
            app.descendants(matching: .any)["lighting-zone-logo-orb-button"].waitForExistence(timeout: 1),
            "Individual zone orb controls did not appear"
        )
        assertSelectedDeviceNeverDisconnected(context: "after onboard tab enumeration")

        selectSegment("Advanced", in: tabPicker, normalizedX: 0.75)
        assertAdvancedLightingControlsExist()
        assertSelectedDeviceNeverDisconnected(context: "after advanced tab enumeration")

        try applySoftwareLightingAndAssertRunning(label: nil)
        try selectSoftwareLightingPreset("Scrolling Rainbow")
        try applySoftwareLightingAndAssertRunning(label: "Scrolling Rainbow")
        try selectSoftwareLightingPreset("Aurora")
        try applySoftwareLightingAndAssertRunning(label: "Aurora")

        assertNoDisconnectedEventsOverInterval(2.0)
        assertSelectedDeviceNeverDisconnected(context: "after repeated advanced Apply")
    }

    private func expandLightingCardIfNeeded(timeout: TimeInterval = 2) {
        let tabPicker = app.descendants(matching: .any)["lighting-card-tab-picker"]
        if tabPicker.exists {
            return
        }

        let lightingCard = app.descendants(matching: .any)["lighting-card"]
        if lightingCard.exists {
            scrollElementToVisible(lightingCard)
        }

        let expandButton = app.descendants(matching: .any)["lighting-card-expand-button"]
        if expandButton.waitForExistence(timeout: timeout) {
            scrollElementToVisible(expandButton)
            clickElement(expandButton)
        }
    }

    private func assertOnboardLightingControlsExist() {
        XCTAssertTrue(
            app.descendants(matching: .any)["lighting-brightness-slider"].waitForExistence(timeout: 1),
            "Onboard brightness slider did not appear"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["lighting-effect-picker"].waitForExistence(timeout: 1),
            "Onboard preset picker did not appear"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["lighting-zone-mode-picker"].waitForExistence(timeout: 1),
            "Onboard zone-mode picker did not appear"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["lighting-all-zones-orb-button"].waitForExistence(timeout: 1),
            "All-zones color orb did not appear"
        )
    }

    private func assertAdvancedLightingControlsExist() {
        let expectedIdentifiers = [
            "software-lighting-apply-on-connect-checkbox",
            "software-lighting-preset-picker",
            "software-lighting-speed-slider",
            "software-lighting-brightness-slider",
            "software-lighting-palette-list",
            "software-lighting-palette-reset-button",
            "software-lighting-palette-add-button",
            "software-lighting-palette-0-orb-button",
            "software-lighting-apply-button"
        ]
        for identifier in expectedIdentifiers {
            let element = app.descendants(matching: .any)[identifier]
            scrollElementToVisible(element)
            XCTAssertTrue(element.waitForExistence(timeout: 1), "\(identifier) did not appear")
        }
    }

    private func applySoftwareLightingAndAssertRunning(label: String?) throws {
        let applyButton = app.descendants(matching: .any)["software-lighting-apply-button"]
        XCTAssertTrue(applyButton.waitForExistence(timeout: 1), "Software lighting Apply button did not appear")
        scrollElementToVisible(applyButton)
        let clickedAt = Date()
        clickElement(applyButton)

        let frameEvent = waitForEvent(named: "usbCommand", timeout: 5) { event in
            event.timestamp >= clickedAt.timeIntervalSince1970 - 0.1 &&
                event.command?.name == "usbLightingCustomFrame" &&
                expectedScope.matches(event.scope)
        }
        XCTAssertNotNil(frameEvent, "Software lighting Apply did not produce a Custom Frame USB command")

        if let label {
            XCTAssertTrue(
                waitForStatusText(containing: "Running \(label)", timeout: 3),
                "Software lighting status did not update to Running \(label)"
            )
        } else {
            XCTAssertTrue(
                waitForStatusText(containing: "Running", timeout: 3),
                "Software lighting status did not report a running effect"
            )
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["software-lighting-stop-button"].waitForExistence(timeout: 1),
            "Software lighting Stop button did not appear after Apply"
        )
        assertSelectedDeviceNeverDisconnected(context: "after software lighting Apply")
    }

    private func selectSoftwareLightingPreset(_ label: String) throws {
        let picker = app.descendants(matching: .any)["software-lighting-preset-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 1), "Software lighting preset picker did not appear")
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
        let selectedOption = try XCTUnwrap(option, "Could not find software lighting preset option \(label)")
        clickElement(selectedOption)
    }

    private func selectSegment(_ label: String, in picker: XCUIElement, normalizedX: CGFloat) {
        XCTAssertTrue(picker.waitForExistence(timeout: 1), "Segmented picker for \(label) did not appear")
        if let option = firstExistingElement(
            in: [
                picker.descendants(matching: .button)[label],
                app.buttons[label],
                app.radioButtons[label],
                app.descendants(matching: .any)[label]
            ],
            timeout: 0.5
        ) {
            clickElement(option)
            return
        }
        picker.coordinate(withNormalizedOffset: CGVector(dx: normalizedX, dy: 0.5)).click()
    }

    private func assertSelectedDeviceNeverDisconnected(context: String) {
        let statusBadge = app.descendants(matching: .any)["device-status-badge"]
        XCTAssertTrue(statusBadge.waitForExistence(timeout: 1), "Device status badge did not appear \(context)")
        XCTAssertNotEqual(elementText(statusBadge), "Disconnected", "Device was marked disconnected \(context)")
    }

    private func assertNoDisconnectedEventsOverInterval(_ interval: TimeInterval) {
        let deadline = Date().addingTimeInterval(interval)
        repeat {
            assertSelectedDeviceNeverDisconnected(context: "during software lighting stability watch")
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
    }

    private func waitForStatusText(containing expected: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let statusText = app.descendants(matching: .any)["software-lighting-status-text"]
        repeat {
            if statusText.exists, elementText(statusText).contains(expected) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return statusText.exists && elementText(statusText).contains(expected)
    }

    private func waitForStatusText(absent text: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let statusText = app.descendants(matching: .any)["software-lighting-status-text"]
        repeat {
            if !statusText.exists || !elementText(statusText).contains(text) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return !statusText.exists || !elementText(statusText).contains(text)
    }
}
