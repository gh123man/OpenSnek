import XCTest

final class V3ProUSBMasterFeatureUITests: OpenSnekHardwareUITestCase {
    private enum Feature: Hashable {
        case dpiStage
        case brightness
        case pollRate
        case sleepTimeout
        case lowBatteryThreshold
        case scrollMode
        case scrollAcceleration
        case scrollSmartReel
    }

    private struct OriginalState {
        let dpiStageIndex: Int
        let dpiStageValue: Int
        let ledValue: Int?
        let pollRate: Int?
        let sleepTimeout: Int?
        let lowBatteryThresholdRaw: Int?
        let scrollMode: Int?
        let scrollAcceleration: Bool?
        let scrollSmartReel: Bool?
    }

    private let actionDeadline: TimeInterval = 3
    private let appReadyDeadline: TimeInterval = 10
    private var originalState: OriginalState?
    private var changedFeatures: Set<Feature> = []

    override var expectedScope: HardwareDeviceScope {
        .v3ProUSB
    }

    override func restoreHardwareStateIfNeeded() {
        guard let originalState else { return }

        if changedFeatures.contains(.scrollSmartReel), let value = originalState.scrollSmartReel {
            restoreScrollSmartReel(value)
        }
        if changedFeatures.contains(.scrollAcceleration), let value = originalState.scrollAcceleration {
            restoreScrollAcceleration(value)
        }
        if changedFeatures.contains(.scrollMode), let value = originalState.scrollMode {
            restoreScrollMode(value)
        }
        if changedFeatures.contains(.lowBatteryThreshold), let value = originalState.lowBatteryThresholdRaw {
            restoreLowBatteryThreshold(value)
        }
        if changedFeatures.contains(.sleepTimeout), let value = originalState.sleepTimeout {
            restoreSleepTimeout(value)
        }
        if changedFeatures.contains(.pollRate), let value = originalState.pollRate {
            restorePollRate(value)
        }
        if changedFeatures.contains(.brightness), let value = originalState.ledValue {
            restoreBrightness(value)
        }
        if changedFeatures.contains(.dpiStage) {
            restoreDPIStage(index: originalState.dpiStageIndex, value: originalState.dpiStageValue)
        }
    }

    func testV3ProUSBMasterFeatureSweepDoesNotCrossInterfere() throws {
        let appReadyStartedAt = Date()
        let deviceName = try XCTUnwrap(launchAndWaitForScopedDevice(timeout: appReadyDeadline))
        XCTAssertLessThanOrEqual(Date().timeIntervalSince(appReadyStartedAt), appReadyDeadline)
        assertElementText(deviceName, equals: "Razer Basilisk V3 Pro", context: "selected device name")

        let state = try XCTUnwrap(latestExpectedDeviceState(), "Expected hydrated state for \(expectedScope.description)")
        let originalDPIStageIndex = try editableDPIStageIndex(from: state)
        let originalDPIStageValue = try scalarDPIValue(at: originalDPIStageIndex, in: state)
        originalState = OriginalState(
            dpiStageIndex: originalDPIStageIndex,
            dpiStageValue: originalDPIStageValue,
            ledValue: state.ledValue,
            pollRate: state.pollRate,
            sleepTimeout: state.sleepTimeout,
            lowBatteryThresholdRaw: state.lowBatteryThresholdRaw,
            scrollMode: state.scrollMode,
            scrollAcceleration: state.scrollAcceleration,
            scrollSmartReel: state.scrollSmartReel
        )

        try assertV3ProUSBFeatureSurface()
        try exerciseOnboardProfileSurface()
        try exerciseDPIStageValue(from: state)
        try exerciseLightingBrightness(from: state)
        try exercisePollRate(from: state)
        try exercisePowerManagement(from: state)
        try exerciseLowBatteryThreshold(from: state)
        try exerciseScrollControls(from: state)
        try exerciseButtonMappingSurface()

        assertNoInterferenceFailures()
    }

    private func assertV3ProUSBFeatureSurface() throws {
        for identifier in [
            "dpi-stages-card",
            "onboard-profiles-card",
            "lighting-card",
            "power-management-card",
            "poll-rate-card",
            "low-battery-threshold-card",
            "scroll-controls-card",
            "button-mapping-card",
        ] {
            let element = app.descendants(matching: .any)[identifier]
            XCTAssertTrue(element.waitForExistence(timeout: 2), "Missing feature card \(identifier)")
        }
    }

    private func exerciseOnConnectControls() throws {
        let detailsButton = try requireElement("on-connect-details-button", timeout: 2)
        scrollElementToVisible(detailsButton)
        clickElement(detailsButton)
        clickElement(detailsButton)

        let picker = try requireElement("on-connect-picker", timeout: 1)
        XCTAssertTrue(picker.exists, "On-connect picker was not present")
    }

    private func exerciseOnboardProfileSurface() throws {
        let card = try requireElement("onboard-profiles-card", timeout: 2)
        scrollElementToVisible(card)

        let baseProfile = try requireElement("onboard-profile-row-1", timeout: 5)
        scrollElementToVisible(baseProfile)
        clickElement(baseProfile)

        let nameField = try requireElement("onboard-profile-name-field", timeout: 2)
        XCTAssertTrue(nameField.exists, "Onboard profile name field did not appear")
        XCTAssertTrue(
            app.descendants(matching: .any)["onboard-profile-rename-button"].waitForExistence(timeout: 1),
            "Onboard profile rename action did not appear"
        )
    }

    private func exerciseDPIStageValue(from state: UITestState) throws {
        let stageIndex = try editableDPIStageIndex(from: state)
        let initial = try scalarDPIValue(at: stageIndex, in: state)
        let target = initial >= 700 ? initial - 100 : initial + 100
        let field = try requireElement("dpi-stage-\(stageIndex + 1)-value-field", timeout: 2)
        scrollElementToVisible(field)
        let changedAt = Date()
        replaceText(in: field, with: String(target))
        changedFeatures.insert(.dpiStage)

        let event = try XCTUnwrap(
            waitForOnboardMutation(
                since: changedAt,
                timeout: actionDeadline,
                matching: { mutation in
                    guard let pairs = mutation.dpiStagePairs,
                          pairs.indices.contains(stageIndex) else {
                        return false
                    }
                    return pairs[stageIndex] == UITestDpiPair(x: target, y: target)
                }
            ),
            "DPI stage mutation did not complete within \(actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, actionDeadline)
        assertExpectedScope(event.scope, context: "DPI stage mutation")
    }

    private func exerciseLightingBrightness(from state: UITestState) throws {
        let initialBrightness = try XCTUnwrap(state.ledValue, "V3 Pro USB state did not include LED brightness")
        let targetBrightness = initialBrightness > 128 ? 96 : 192
        let slider = try requireElement("lighting-brightness-slider", timeout: 2)
        scrollElementToVisible(slider)
        let changedAt = Date()
        slider.adjust(toNormalizedSliderPosition: CGFloat(targetBrightness) / 255.0)
        changedFeatures.insert(.brightness)

        let event = try XCTUnwrap(
            waitForOnboardMutation(
                since: changedAt,
                timeout: actionDeadline,
                matching: { mutation in
                    mutation.brightnessByLEDID?.values.contains { abs($0 - targetBrightness) <= 12 } == true
                }
            ),
            "Lighting brightness mutation did not complete within \(actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, actionDeadline)
        assertExpectedScope(event.scope, context: "lighting brightness mutation")
    }

    private func exercisePollRate(from state: UITestState) throws {
        let initialPollRate = try XCTUnwrap(state.pollRate, "V3 Pro USB state did not include poll rate")
        let target = targetPollRate(after: initialPollRate)
        let expectedArgs = try expectedUSBPollRateArgs(for: target)
        let picker = try requireElement("poll-rate-picker", timeout: 2)
        scrollElementToVisible(picker)
        let clickedAt = try XCTUnwrap(clickPollRateOption(target, picker: picker), "Could not click \(target) Hz")
        changedFeatures.insert(.pollRate)

        let event = try XCTUnwrap(
            waitForApplyEnd(
                since: clickedAt,
                timeout: actionDeadline,
                matching: { $0.patch?.pollRate == target && $0.state?.pollRate == target }
            ),
            "Poll-rate apply did not complete within \(actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, actionDeadline)

        let command = try XCTUnwrap(
            readEvents().first {
                $0.name == "usbCommand" &&
                    $0.timestamp >= clickedAt.timeIntervalSince1970 - 0.1 &&
                    $0.command?.name == "usbSetPollRate" &&
                    $0.command?.args == expectedArgs &&
                    expectedScope.matches($0.scope)
            }?.command,
            "Poll-rate action did not emit the expected USB command"
        )
        XCTAssertEqual(command.classID, 0x00)
        XCTAssertEqual(command.cmdID, 0x05)
        XCTAssertEqual(command.size, 0x01)
        XCTAssertEqual(command.args, expectedArgs)
    }

    private func exercisePowerManagement(from state: UITestState) throws {
        let initial = try XCTUnwrap(state.sleepTimeout, "V3 Pro USB state did not include sleep timeout")
        let target = initial >= 840 ? initial - 60 : initial + 60
        let slider = try requireElement("sleep-timeout-slider", timeout: 2)
        scrollElementToVisible(slider)
        let changedAt = Date()
        slider.adjust(toNormalizedSliderPosition: normalizedSleepTimeout(target))
        changedFeatures.insert(.sleepTimeout)

        let event = try XCTUnwrap(
            waitForApplyEnd(
                since: changedAt,
                timeout: actionDeadline,
                matching: { event in
                    guard let patched = event.patch?.sleepTimeout,
                          let applied = event.state?.sleepTimeout else {
                        return false
                    }
                    return patched == applied && patched != initial
                }
            ),
            "Sleep-timeout apply did not complete within \(actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, actionDeadline)
    }

    private func exerciseLowBatteryThreshold(from state: UITestState) throws {
        let initial = try XCTUnwrap(state.lowBatteryThresholdRaw, "V3 Pro USB state did not include low-battery threshold")
        let target = initial >= 0x3E ? initial - 1 : initial + 1
        let slider = try requireElement("low-battery-threshold-slider", timeout: 2)
        scrollElementToVisible(slider)
        let changedAt = Date()
        slider.adjust(toNormalizedSliderPosition: normalizedLowBatteryThreshold(target))
        changedFeatures.insert(.lowBatteryThreshold)

        let event = try XCTUnwrap(
            waitForApplyEnd(
                since: changedAt,
                timeout: actionDeadline,
                matching: { event in
                    guard let patched = event.patch?.lowBatteryThresholdRaw,
                          let applied = event.state?.lowBatteryThresholdRaw else {
                        return false
                    }
                    return patched == applied && patched != initial
                }
            ),
            "Low-battery threshold apply did not complete within \(actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, actionDeadline)
    }

    private func exerciseScrollControls(from state: UITestState) throws {
        if let scrollMode = state.scrollMode {
            let target = scrollMode == 0 ? 1 : 0
            let picker = try requireElement("scroll-mode-picker", timeout: 2)
            scrollElementToVisible(picker)
            let clickedAt = Date()
            picker.coordinate(withNormalizedOffset: CGVector(dx: target == 0 ? 0.25 : 0.75, dy: 0.5)).click()
            changedFeatures.insert(.scrollMode)
            let event = try XCTUnwrap(
                waitForOnboardMutation(
                    since: clickedAt,
                    timeout: actionDeadline,
                    matching: { $0.scrollMode == target }
                ),
                "Scroll mode mutation did not complete within \(actionDeadline)s"
            )
            XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, actionDeadline)
        }

        if let acceleration = state.scrollAcceleration {
            let toggle = try requireElement("scroll-acceleration-toggle", timeout: 2)
            scrollElementToVisible(toggle)
            let clickedAt = Date()
            clickElement(toggle)
            changedFeatures.insert(.scrollAcceleration)
            let event = try XCTUnwrap(
                waitForOnboardMutation(
                    since: clickedAt,
                    timeout: actionDeadline,
                    matching: { $0.scrollAcceleration == !acceleration }
                ),
                "Scroll acceleration mutation did not complete within \(actionDeadline)s"
            )
            XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, actionDeadline)
        }

        if let smartReel = state.scrollSmartReel {
            let toggle = try requireElement("scroll-smart-reel-toggle", timeout: 2)
            scrollElementToVisible(toggle)
            let clickedAt = Date()
            clickElement(toggle)
            changedFeatures.insert(.scrollSmartReel)
            let event = try XCTUnwrap(
                waitForOnboardMutation(
                    since: clickedAt,
                    timeout: actionDeadline,
                    matching: { $0.scrollSmartReel == !smartReel }
                ),
                "Scroll smart-reel mutation did not complete within \(actionDeadline)s"
            )
            XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, actionDeadline)
        }
    }

    private func exerciseButtonMappingSurface() throws {
        let card = try requireElement("button-mapping-card", timeout: 2)
        scrollElementToVisible(card)

        let row = try XCTUnwrap(
            firstExistingElement(
                in: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map {
                    app.descendants(matching: .any)["button-binding-row-\($0)"]
                },
                timeout: 2
            ),
            "No button mapping rows appeared"
        )
        XCTAssertTrue(row.exists, "Button mapping row was not present")
    }

    private func assertNoInterferenceFailures() {
        let events = readEvents()
        XCTAssertFalse(events.contains { $0.name == "overlapDetected" }, "App detected overlapping feature writes")
        XCTAssertLessThanOrEqual(events.compactMap(\.maxConcurrentApplyCount).max() ?? 1, 1)

        let slowEvents = events.filter {
            ($0.name == "applyEnd" || $0.name == "onboardProfileMutationEnd") &&
                (($0.elapsed ?? 0) > actionDeadline)
        }
        XCTAssertTrue(
            slowEvents.isEmpty,
            "Feature writes exceeded \(actionDeadline)s: \(slowEvents.map { "\($0.name)=\($0.elapsed ?? -1)" }.joined(separator: ", "))"
        )
        XCTAssertTrue(events.contains { $0.name == "applyEnd" && $0.patch?.pollRate != nil })
        XCTAssertTrue(events.contains { $0.name == "onboardProfileMutationEnd" && $0.onboardMutation?.dpiStagePairs != nil })
        XCTAssertTrue(events.contains { $0.name == "onboardProfileMutationEnd" && $0.onboardMutation?.brightnessByLEDID != nil })
    }

    private func waitForApplyEnd(
        since startedAt: Date,
        timeout: TimeInterval,
        matching predicate: @escaping (UITestEvent) -> Bool
    ) -> UITestEvent? {
        waitForEvent(named: "applyEnd", timeout: timeout) {
            $0.timestamp >= startedAt.timeIntervalSince1970 - 0.1 &&
                expectedScope.matches($0.scope) &&
                predicate($0)
        }
    }

    private func waitForOnboardMutation(
        since startedAt: Date,
        timeout: TimeInterval,
        matching predicate: @escaping (UITestOnboardProfileMutation) -> Bool
    ) -> UITestEvent? {
        waitForEvent(named: "onboardProfileMutationEnd", timeout: timeout) { event in
            guard event.timestamp >= startedAt.timeIntervalSince1970 - 0.1,
                  expectedScope.matches(event.scope),
                  let mutation = event.onboardMutation else {
                return false
            }
            return predicate(mutation)
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

    private func restoreDPIStage(index: Int, value: Int) {
        guard let field = firstExistingElement(
            in: [app.descendants(matching: .any)["dpi-stage-\(index + 1)-value-field"]],
            timeout: 0.5
        ) else { return }
        scrollElementToVisible(field)
        let changedAt = Date()
        replaceText(in: field, with: String(value))
        _ = waitForOnboardMutation(since: changedAt, timeout: actionDeadline) { mutation in
            guard let pairs = mutation.dpiStagePairs,
                  pairs.indices.contains(index) else {
                return false
            }
            return pairs[index] == UITestDpiPair(x: value, y: value)
        }
    }

    private func restoreBrightness(_ brightness: Int) {
        guard let slider = firstExistingElement(in: [app.descendants(matching: .any)["lighting-brightness-slider"]], timeout: 0.5) else { return }
        scrollElementToVisible(slider)
        let changedAt = Date()
        slider.adjust(toNormalizedSliderPosition: CGFloat(brightness) / 255.0)
        _ = waitForOnboardMutation(since: changedAt, timeout: actionDeadline) { mutation in
            mutation.brightnessByLEDID?.values.contains { abs($0 - brightness) <= 12 } == true
        }
    }

    private func restorePollRate(_ pollRate: Int) {
        guard let picker = firstExistingElement(in: [app.descendants(matching: .any)["poll-rate-picker"]], timeout: 0.5) else { return }
        scrollElementToVisible(picker)
        guard let clickedAt = clickPollRateOption(pollRate, picker: picker) else { return }
        _ = waitForApplyEnd(since: clickedAt, timeout: actionDeadline) { $0.patch?.pollRate == pollRate }
    }

    private func restoreSleepTimeout(_ timeout: Int) {
        guard let slider = firstExistingElement(in: [app.descendants(matching: .any)["sleep-timeout-slider"]], timeout: 0.5) else { return }
        scrollElementToVisible(slider)
        let changedAt = Date()
        slider.adjust(toNormalizedSliderPosition: normalizedSleepTimeout(timeout))
        _ = waitForApplyEnd(since: changedAt, timeout: actionDeadline) { $0.patch?.sleepTimeout == timeout }
    }

    private func restoreLowBatteryThreshold(_ raw: Int) {
        guard let slider = firstExistingElement(in: [app.descendants(matching: .any)["low-battery-threshold-slider"]], timeout: 0.5) else { return }
        scrollElementToVisible(slider)
        let changedAt = Date()
        slider.adjust(toNormalizedSliderPosition: normalizedLowBatteryThreshold(raw))
        _ = waitForApplyEnd(since: changedAt, timeout: actionDeadline) { $0.patch?.lowBatteryThresholdRaw == raw }
    }

    private func restoreScrollMode(_ mode: Int) {
        guard let picker = firstExistingElement(in: [app.descendants(matching: .any)["scroll-mode-picker"]], timeout: 0.5) else { return }
        scrollElementToVisible(picker)
        let clickedAt = Date()
        picker.coordinate(withNormalizedOffset: CGVector(dx: mode == 0 ? 0.25 : 0.75, dy: 0.5)).click()
        _ = waitForOnboardMutation(since: clickedAt, timeout: actionDeadline) { $0.scrollMode == mode }
    }

    private func restoreScrollAcceleration(_ enabled: Bool) {
        restoreToggle("scroll-acceleration-toggle") { $0.scrollAcceleration == enabled }
    }

    private func restoreScrollSmartReel(_ enabled: Bool) {
        restoreToggle("scroll-smart-reel-toggle") { $0.scrollSmartReel == enabled }
    }

    private func restoreToggle(
        _ identifier: String,
        matching predicate: @escaping (UITestOnboardProfileMutation) -> Bool
    ) {
        guard let toggle = firstExistingElement(in: [app.descendants(matching: .any)[identifier]], timeout: 0.5) else { return }
        scrollElementToVisible(toggle)
        let clickedAt = Date()
        clickElement(toggle)
        _ = waitForOnboardMutation(since: clickedAt, timeout: actionDeadline, matching: predicate)
    }

    private func normalizedSleepTimeout(_ value: Int) -> CGFloat {
        CGFloat(max(60, min(900, value)) - 60) / CGFloat(900 - 60)
    }

    private func normalizedLowBatteryThreshold(_ value: Int) -> CGFloat {
        CGFloat(max(0x0C, min(0x3F, value)) - 0x0C) / CGFloat(0x3F - 0x0C)
    }

    private func editableDPIStageIndex(from state: UITestState) throws -> Int {
        let stages = state.dpiStages ?? state.dpiStagePairs?.map(\.x) ?? []
        XCTAssertGreaterThanOrEqual(stages.count, 2, "V3 Pro USB should expose multiple DPI stages")
        let activeStage = state.activeStage ?? 0
        return activeStage == 0 ? 1 : 0
    }

    private func scalarDPIValue(at index: Int, in state: UITestState) throws -> Int {
        if let pair = state.dpiStagePairs?[safe: index] {
            XCTAssertEqual(pair.x, pair.y, "Master test currently edits scalar DPI stages")
            return pair.x
        }
        let values = try XCTUnwrap(state.dpiStages, "V3 Pro USB state did not include DPI stages")
        return try XCTUnwrap(values[safe: index], "V3 Pro USB state did not include DPI stage \(index + 1)")
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        clickElement(field)
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
        field.typeKey(.return, modifierFlags: [])
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
