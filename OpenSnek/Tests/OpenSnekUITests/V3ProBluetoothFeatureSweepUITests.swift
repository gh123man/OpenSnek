import XCTest

/// Exercises V3 pro Bluetooth feature sweep UI behavior.
final class V3ProBluetoothFeatureSweepUITests: OpenSnekHardwareUITestCase {
    private lazy var sweep = FeatureSweep(testCase: self, configuration: .v3ProBluetooth)
    private var pendingClutchRestoreDPI: Int?

    override var expectedScope: HardwareDeviceScope { .v3ProBluetooth }

    override func restoreHardwareStateIfNeeded() {
        sweep.restoreHardwareStateIfNeeded()
        if let pendingClutchRestoreDPI {
            _ = try? setSensitivityClutchDPI(pendingClutchRestoreDPI, timeout: 5)
            self.pendingClutchRestoreDPI = nil
        }
    }

    func testV3ProBluetoothFeatureSweepDoesNotCrossInterfere() throws { try sweep.run() }

    func testV3ProBluetoothSensitivityClutchDPIAppliesFromUI() throws {
        _ = try XCTUnwrap(launchAndWaitForScopedDevice(timeout: 15), "Expected connected \(expectedScope.description)")
        try keepMouseAwakeForUITest(timeout: 5)

        let card = try findElementWhileScrolling("button-mapping-card", maxScrolls: 12)
        scrollElementToVisible(card)
        let row = try findElementWhileScrolling("button-binding-row-15", maxScrolls: 12)
        scrollElementToVisible(row)
        ensureSensitivityClutchDPIControls()

        let field = try requireElement("button-binding-clutch-dpi-field-15", timeout: 2)
        let originalDPI = integerValue(from: field) ?? 400
        pendingClutchRestoreDPI = originalDPI

        let targetDPI = originalDPI == 800 ? 400 : 800
        let event = try setSensitivityClutchDPI(targetDPI, timeout: 5)
        XCTAssertEqual(event.onboardMutation?.buttonBindingSlots, [15])
        XCTAssertEqual(event.onboardMutation?.buttonBindingKindsBySlot?["15"], "dpi_clutch")
        XCTAssertEqual(event.onboardMutation?.buttonBindingClutchDPIBySlot?["15"], targetDPI)
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, 5)
        try assertSensitivityClutchDPIFieldStays(targetDPI, duration: 2)

        if targetDPI != originalDPI {
            _ = try setSensitivityClutchDPI(originalDPI, timeout: 5)
            try assertSensitivityClutchDPIFieldStays(originalDPI, duration: 1)
        }
        pendingClutchRestoreDPI = nil
    }

    private func ensureSensitivityClutchDPIControls() {
        let field = app.descendants(matching: .any)["button-binding-clutch-dpi-field-15"]
        if field.waitForExistence(timeout: 0.5) { return }

        let picker = app.descendants(matching: .any)["button-binding-kind-picker-15"]
        XCTAssertTrue(picker.waitForExistence(timeout: 2), "Sensitivity clutch binding picker did not appear")
        scrollElementToVisible(picker)
        clickElement(picker)

        let option = firstExistingElement(in: [app.menuItems["DPI Clutch"], app.buttons["DPI Clutch"], app.staticTexts["DPI Clutch"], app.descendants(matching: .any)["DPI Clutch"]], timeout: 2)
        XCTAssertNotNil(option, "DPI Clutch binding option did not appear")
        if let option { clickElement(option) }

        XCTAssertTrue(field.waitForExistence(timeout: 2), "Clutch DPI field did not appear after selecting DPI Clutch")
    }

    @discardableResult private func setSensitivityClutchDPI(_ dpi: Int, timeout: TimeInterval) throws -> UITestEvent {
        let field = try requireElement("button-binding-clutch-dpi-field-15", timeout: 2)
        scrollElementToVisible(field)
        clickElement(field)
        field.typeKey("a", modifierFlags: .command)
        let changedAt = Date()
        field.typeText(String(dpi))
        field.typeKey(.return, modifierFlags: [])

        return try XCTUnwrap(
            waitForEvent(named: "onboardProfileMutationEnd", timeout: timeout) { event in
                event.timestamp >= changedAt.timeIntervalSince1970 - 0.1 && expectedScope.matches(event.scope) && event.onboardMutation?.buttonBindingSlots?.contains(15) == true && event.onboardMutation?.buttonBindingKindsBySlot?["15"] == "dpi_clutch"
                    && event.onboardMutation?.buttonBindingClutchDPIBySlot?["15"] == dpi
            }, "Sensitivity clutch mutation did not complete within \(timeout)s")
    }

    private func assertSensitivityClutchDPIFieldStays(_ dpi: Int, duration: TimeInterval, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(duration)
        var observedValues: [Int] = []
        repeat {
            let field = try requireElement("button-binding-clutch-dpi-field-15", timeout: 1, file: file, line: line)
            scrollElementToVisible(field)
            let observed = integerValue(from: field)
            if let observed { observedValues.append(observed) }
            XCTAssertEqual(observed, Optional(dpi), "Sensitivity clutch field changed while waiting for post-write stability; observed \(observedValues)", file: file, line: line)
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
    }

    private func requireElement(_ identifier: String, timeout: TimeInterval, file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing UI element \(identifier)", file: file, line: line)
        return try XCTUnwrap(element.exists ? element : nil, file: file, line: line)
    }

    private func findElementWhileScrolling(_ identifier: String, maxScrolls: Int, file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        if element.waitForExistence(timeout: 0.5) { return element }

        let scrollView = detailScrollView()
        for _ in 0..<maxScrolls {
            if scrollView.exists {
                scrollView.scroll(byDeltaX: 0, deltaY: -700)
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            if element.exists { return element }
        }

        XCTAssertTrue(element.exists, "Missing UI element \(identifier)", file: file, line: line)
        return try XCTUnwrap(element.exists ? element : nil, file: file, line: line)
    }

    private func integerValue(from element: XCUIElement) -> Int? {
        for raw in [element.value as? String, element.label] {
            guard let raw else { continue }
            let digits = raw.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let value = Int(digits) { return value }
        }
        return nil
    }
}
