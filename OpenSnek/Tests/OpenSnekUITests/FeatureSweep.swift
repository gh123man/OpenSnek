import XCTest

final class FeatureSweep {
    enum Feature: Hashable {
        case onboardProfiles
        case dpiStageSelection
        case dpiValue
        case lightingBrightness
        case pollRate
        case sleepTimeout
        case lowBatteryThreshold
        case scrollControls
        case buttonMapping
    }

    struct Configuration {
        let appReadyDeadline: TimeInterval
        let actionDeadline: TimeInterval
        let expectedSelectedDeviceName: String?
        let expectedCards: [String]
        let absentCards: [String]
        let features: [Feature]
        let assertUSBPollRateCommand: Bool
        let buttonTurboCandidateSlots: [Int]
    }

    private enum ChangedFeature: Hashable {
        case dpiStage
        case dpiValue
        case brightness
        case pollRate
        case sleepTimeout
        case lowBatteryThreshold
        case scrollMode
        case scrollAcceleration
        case scrollSmartReel
        case buttonTurbo
    }

    private struct OriginalState {
        let dpiStageIndex: Int
        let dpi: Int?
        let ledValue: Int?
        let pollRate: Int?
        let sleepTimeout: Int?
        let lowBatteryThresholdRaw: Int?
        let scrollMode: Int?
        let scrollAcceleration: Bool?
        let scrollSmartReel: Bool?
    }

    private unowned let testCase: OpenSnekHardwareUITestCase
    private let configuration: Configuration
    private var originalState: OriginalState?
    private var originalDPIFromUI: Int?
    private var changedFeatures: Set<ChangedFeature> = []
    private var toggledButtonTurboSlot: Int?

    init(testCase: OpenSnekHardwareUITestCase, configuration: Configuration) {
        self.testCase = testCase
        self.configuration = configuration
    }

    func run() throws {
        let appReadyStartedAt = Date()
        let deviceName = try XCTUnwrap(
            testCase.launchAndWaitForScopedDevice(timeout: configuration.appReadyDeadline),
            "Expected connected \(testCase.expectedScope.description)"
        )
        XCTAssertLessThanOrEqual(Date().timeIntervalSince(appReadyStartedAt), configuration.appReadyDeadline)
        if let expectedSelectedDeviceName = configuration.expectedSelectedDeviceName {
            testCase.assertElementText(deviceName, equals: expectedSelectedDeviceName, context: "selected device name")
        }

        let originalDeviceState = try XCTUnwrap(
            testCase.latestExpectedDeviceState(),
            "Expected hydrated state for \(testCase.expectedScope.description)"
        )
        originalState = OriginalState(
            dpiStageIndex: originalDeviceState.activeStage ?? 0,
            dpi: originalDeviceState.dpi,
            ledValue: originalDeviceState.ledValue,
            pollRate: originalDeviceState.pollRate,
            sleepTimeout: originalDeviceState.sleepTimeout,
            lowBatteryThresholdRaw: originalDeviceState.lowBatteryThresholdRaw,
            scrollMode: originalDeviceState.scrollMode,
            scrollAcceleration: originalDeviceState.scrollAcceleration,
            scrollSmartReel: originalDeviceState.scrollSmartReel
        )

        try testCase.keepMouseAwakeForUITest(timeout: configuration.actionDeadline)
        let state = try XCTUnwrap(
            testCase.latestExpectedScopedState(),
            "Expected scoped state after UI-test setup for \(testCase.expectedScope.description)"
        )

        try assertFeatureSurface()
        for feature in configuration.features {
            let featureState = testCase.latestExpectedScopedState() ?? state
            switch feature {
            case .onboardProfiles:
                try exerciseOnboardProfileSurface()
            case .dpiStageSelection:
                try exerciseDPIStageSelection(from: featureState)
            case .dpiValue:
                try exerciseDPIValue(from: featureState)
            case .lightingBrightness:
                try exerciseLightingBrightness(from: featureState)
            case .pollRate:
                try exercisePollRate(from: featureState)
            case .sleepTimeout:
                try exercisePowerManagement(from: featureState)
            case .lowBatteryThreshold:
                try exerciseLowBatteryThreshold(from: featureState)
            case .scrollControls:
                try exerciseScrollControls(from: featureState)
            case .buttonMapping:
                try exerciseButtonMappingSurface()
            }
        }

        assertNoInterferenceFailures()
    }

    func restoreHardwareStateIfNeeded() {
        guard let originalState else { return }

        if changedFeatures.contains(.scrollSmartReel), let value = originalState.scrollSmartReel {
            restoreScrollSmartReel(value)
        }
        if changedFeatures.contains(.buttonTurbo), let slot = toggledButtonTurboSlot {
            restoreButtonTurbo(slot: slot)
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
        if changedFeatures.contains(.dpiValue), let value = originalState.dpi ?? originalDPIFromUI {
            restoreDPIValue(value)
        }
        if changedFeatures.contains(.dpiStage) {
            restoreDPIStageSelection(index: originalState.dpiStageIndex)
        }
    }

    private func assertFeatureSurface() throws {
        for identifier in configuration.expectedCards {
            let element = testCase.app.descendants(matching: .any)[identifier]
            XCTAssertTrue(element.waitForExistence(timeout: 2), "Missing feature card \(identifier)")
        }

        for identifier in configuration.absentCards {
            let element = testCase.app.descendants(matching: .any)[identifier]
            XCTAssertFalse(element.waitForExistence(timeout: 0.5), "Unexpected unsupported feature card \(identifier)")
        }
    }

    private func exerciseOnboardProfileSurface() throws {
        let pill = try requireElement("onboard-profile-pill-button", timeout: 2)
        testCase.clickElement(pill)

        let card = try requireElement("onboard-profiles-card", timeout: 5)
        XCTAssertTrue(card.exists, "Onboard profile manager popover did not appear")
        let baseProfile = try requireElement("onboard-profile-row-1", timeout: 5)
        testCase.clickElement(baseProfile)

        let nameField = try requireElement("onboard-profile-name-field", timeout: 2)
        XCTAssertTrue(nameField.exists, "Onboard profile name field did not appear")
        XCTAssertTrue(
            testCase.app.descendants(matching: .any)["onboard-profile-rename-button"].waitForExistence(timeout: 1),
            "Onboard profile rename action did not appear"
        )
    }

    private func exerciseDPIStageSelection(from state: UITestState) throws {
        let stages = state.dpiStages ?? state.dpiStagePairs?.map(\.x) ?? []
        XCTAssertGreaterThanOrEqual(stages.count, 2, "\(testCase.expectedScope.description) should expose multiple DPI stages")
        let current = state.activeStage ?? 0
        let target = current == 0 ? 1 : 0
        let button = try requireElement("dpi-stage-\(target + 1)-select-button", timeout: 2)
        testCase.scrollElementToVisible(button)
        let clickedAt = Date()
        testCase.clickElement(button)
        changedFeatures.insert(.dpiStage)

        let event = try XCTUnwrap(
            waitForDPIStageEnd(since: clickedAt, timeout: configuration.actionDeadline, target: target),
            "DPI stage selection did not complete within \(configuration.actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, configuration.actionDeadline)
        testCase.assertExpectedScope(event.scope, context: "DPI stage selection")
    }

    private func exerciseDPIValue(from state: UITestState) throws {
        let field = try requireElement("dpi-stage-1-value-field", timeout: 2)
        testCase.scrollElementToVisible(field)
        let initialDPI = try XCTUnwrap(
            state.dpi ?? integerValue(from: field),
            "\(testCase.expectedScope.description) UI did not expose a restorable DPI value"
        )
        if originalState?.dpi == nil {
            originalDPIFromUI = initialDPI
        }
        let target = targetDPI(after: initialDPI)
        let changedAt = try setSingleDPIValue(target)
        changedFeatures.insert(.dpiValue)

        let event = try XCTUnwrap(
            waitForDPIValueEnd(
                since: changedAt,
                timeout: configuration.actionDeadline,
                target: target,
                monitoringFieldIdentifier: "dpi-stage-1-value-field"
            ),
            "DPI value mutation did not complete within \(configuration.actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, configuration.actionDeadline)
        testCase.assertExpectedScope(event.scope, context: "DPI value mutation")
    }

    private func exerciseLightingBrightness(from state: UITestState) throws {
        guard let initialBrightness = state.ledValue else {
            let slider = try requireElement("lighting-brightness-slider", timeout: 2)
            testCase.scrollElementToVisible(slider)
            return
        }
        let targetBrightness = initialBrightness > 128 ? 96 : 192
        let slider = try requireElement("lighting-brightness-slider", timeout: 2)
        testCase.scrollElementToVisible(slider)
        let changedAt = Date()
        slider.adjust(toNormalizedSliderPosition: CGFloat(targetBrightness) / 255.0)
        changedFeatures.insert(.brightness)

        let event = try XCTUnwrap(
            waitForLightingBrightnessEnd(
                since: changedAt,
                timeout: configuration.actionDeadline,
                targetBrightness: targetBrightness
            ),
            "Lighting brightness mutation did not complete within \(configuration.actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, configuration.actionDeadline)
        testCase.assertExpectedScope(event.scope, context: "lighting brightness mutation")
    }

    private func exercisePollRate(from state: UITestState) throws {
        let initialPollRate = try XCTUnwrap(
            state.pollRate,
            "\(testCase.expectedScope.description) state did not include poll rate"
        )
        let target = testCase.targetPollRate(after: initialPollRate)
        let expectedArgs = try testCase.expectedUSBPollRateArgs(for: target)
        let picker = try requireElement("poll-rate-picker", timeout: 2)
        testCase.scrollElementToVisible(picker)
        let clickedAt = try XCTUnwrap(testCase.clickPollRateOption(target, picker: picker), "Could not click \(target) Hz")
        changedFeatures.insert(.pollRate)

        let event = try XCTUnwrap(
            waitForApplyEnd(
                since: clickedAt,
                timeout: configuration.actionDeadline,
                matching: { $0.patch?.pollRate == target && $0.state?.pollRate == target }
            ),
            "Poll-rate apply did not complete within \(configuration.actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, configuration.actionDeadline)

        guard configuration.assertUSBPollRateCommand else { return }
        let command = try XCTUnwrap(
            testCase.readEvents().first {
                $0.name == "usbCommand" &&
                    $0.timestamp >= clickedAt.timeIntervalSince1970 - 0.1 &&
                    $0.command?.name == "usbSetPollRate" &&
                    $0.command?.args == expectedArgs &&
                    testCase.expectedScope.matches($0.scope)
            }?.command,
            "Poll-rate action did not emit the expected USB command"
        )
        XCTAssertEqual(command.classID, 0x00)
        XCTAssertEqual(command.cmdID, 0x05)
        XCTAssertEqual(command.size, 0x01)
        XCTAssertEqual(command.args, expectedArgs)
    }

    private func exercisePowerManagement(from state: UITestState) throws {
        let initial = try XCTUnwrap(
            state.sleepTimeout,
            "\(testCase.expectedScope.description) state did not include sleep timeout"
        )
        let target = initial >= 840 ? initial - 60 : initial + 60
        let slider = try requireElement("sleep-timeout-slider", timeout: 2)
        testCase.scrollElementToVisible(slider)
        let changedAt = Date()
        slider.adjust(toNormalizedSliderPosition: testCase.normalizedUITestSleepTimeout(target))
        changedFeatures.insert(.sleepTimeout)

        let event = try XCTUnwrap(
            waitForApplyEnd(
                since: changedAt,
                timeout: configuration.actionDeadline,
                matching: { event in
                    guard let patched = event.patch?.sleepTimeout,
                          let applied = event.state?.sleepTimeout else {
                        return false
                    }
                    return patched == applied && patched != initial
                }
            ),
            "Sleep-timeout apply did not complete within \(configuration.actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, configuration.actionDeadline)
    }

    private func exerciseLowBatteryThreshold(from state: UITestState) throws {
        let initial = try XCTUnwrap(
            state.lowBatteryThresholdRaw,
            "\(testCase.expectedScope.description) state did not include low-battery threshold"
        )
        let target = initial >= 0x3E ? initial - 1 : initial + 1
        let slider = try requireElement("low-battery-threshold-slider", timeout: 2)
        testCase.scrollElementToVisible(slider)
        let changedAt = Date()
        slider.adjust(toNormalizedSliderPosition: normalizedLowBatteryThreshold(target))
        changedFeatures.insert(.lowBatteryThreshold)

        let event = try XCTUnwrap(
            waitForApplyEnd(
                since: changedAt,
                timeout: configuration.actionDeadline,
                matching: { event in
                    guard let patched = event.patch?.lowBatteryThresholdRaw,
                          let applied = event.state?.lowBatteryThresholdRaw else {
                        return false
                    }
                    return patched == applied && patched != initial
                }
            ),
            "Low-battery threshold apply did not complete within \(configuration.actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, configuration.actionDeadline)
    }

    private func exerciseScrollControls(from state: UITestState) throws {
        if let scrollMode = state.scrollMode {
            let target = scrollMode == 0 ? 1 : 0
            let picker = try requireElement("scroll-mode-picker", timeout: 2)
            testCase.scrollElementToVisible(picker)
            let clickedAt = Date()
            picker.coordinate(withNormalizedOffset: CGVector(dx: target == 0 ? 0.25 : 0.75, dy: 0.5)).click()
            changedFeatures.insert(.scrollMode)
            let event = try XCTUnwrap(
                waitForOnboardMutation(
                    since: clickedAt,
                    timeout: configuration.actionDeadline,
                    matching: { $0.scrollMode == target }
                ),
                "Scroll mode mutation did not complete within \(configuration.actionDeadline)s"
            )
            XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, configuration.actionDeadline)
        }

        if let acceleration = state.scrollAcceleration {
            let toggle = try requireElement("scroll-acceleration-toggle", timeout: 2)
            testCase.scrollElementToVisible(toggle)
            let clickedAt = Date()
            testCase.clickElement(toggle)
            changedFeatures.insert(.scrollAcceleration)
            let event = try XCTUnwrap(
                waitForOnboardMutation(
                    since: clickedAt,
                    timeout: configuration.actionDeadline,
                    matching: { $0.scrollAcceleration == !acceleration }
                ),
                "Scroll acceleration mutation did not complete within \(configuration.actionDeadline)s"
            )
            XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, configuration.actionDeadline)
        }

        if let smartReel = state.scrollSmartReel {
            let toggle = try requireElement("scroll-smart-reel-toggle", timeout: 2)
            testCase.scrollElementToVisible(toggle)
            let clickedAt = Date()
            testCase.clickElement(toggle)
            changedFeatures.insert(.scrollSmartReel)
            let event = try XCTUnwrap(
                waitForOnboardMutation(
                    since: clickedAt,
                    timeout: configuration.actionDeadline,
                    matching: { $0.scrollSmartReel == !smartReel }
                ),
                "Scroll smart-reel mutation did not complete within \(configuration.actionDeadline)s"
            )
            XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, configuration.actionDeadline)
        }
    }

    private func exerciseButtonMappingSurface() throws {
        let card = try requireElement("button-mapping-card", timeout: 2)
        testCase.scrollElementToVisible(card)

        let row = try XCTUnwrap(firstButtonBindingRow(), "No button mapping rows appeared")
        XCTAssertTrue(row.exists, "Button mapping row was not present")

        guard let (slot, toggle) = firstButtonTurboToggle() else {
            return
        }
        testCase.scrollElementToVisible(toggle)
        let changedAt = Date()
        testCase.clickElement(toggle)
        toggledButtonTurboSlot = slot
        changedFeatures.insert(.buttonTurbo)

        let event = try XCTUnwrap(
            waitForOnboardMutation(
                since: changedAt,
                timeout: configuration.actionDeadline,
                matching: { $0.buttonBindingSlots?.contains(slot) == true }
            ),
            "Button turbo mutation did not complete within \(configuration.actionDeadline)s"
        )
        XCTAssertLessThanOrEqual(event.elapsed ?? .greatestFiniteMagnitude, configuration.actionDeadline)
    }

    private func assertNoInterferenceFailures() {
        let events = testCase.readEvents()
        XCTAssertFalse(events.contains { $0.name == "overlapDetected" }, "App detected overlapping feature writes")
        XCTAssertLessThanOrEqual(events.compactMap(\.maxConcurrentApplyCount).max() ?? 1, 1)

        let slowEvents = events.filter {
            ($0.name == "applyEnd" || $0.name == "onboardProfileMutationEnd") &&
                (($0.elapsed ?? 0) > configuration.actionDeadline)
        }
        XCTAssertTrue(
            slowEvents.isEmpty,
            "Feature writes exceeded \(configuration.actionDeadline)s: \(slowEvents.map { "\($0.name)=\($0.elapsed ?? -1)" }.joined(separator: ", "))"
        )
        if changedFeatures.contains(.pollRate) {
            XCTAssertTrue(events.contains { $0.name == "applyEnd" && $0.patch?.pollRate != nil })
        }
        if changedFeatures.contains(.dpiStage) {
            XCTAssertTrue(events.contains { eventContainsDPIStageChange($0) })
        }
        if changedFeatures.contains(.dpiValue) {
            XCTAssertTrue(events.contains { eventContainsDPIValueChange($0) })
        }
        if changedFeatures.contains(.brightness) {
            XCTAssertTrue(events.contains { eventContainsBrightnessChange($0) })
        }
        if changedFeatures.contains(.buttonTurbo) {
            XCTAssertTrue(events.contains { $0.name == "onboardProfileMutationEnd" && $0.onboardMutation?.buttonBindingSlots != nil })
        }
    }

    private func waitForApplyEnd(
        since startedAt: Date,
        timeout: TimeInterval,
        matching predicate: @escaping (UITestEvent) -> Bool
    ) -> UITestEvent? {
        testCase.waitForEvent(named: "applyEnd", timeout: timeout) {
            $0.timestamp >= startedAt.timeIntervalSince1970 - 0.1 &&
                testCase.expectedScope.matches($0.scope) &&
                predicate($0)
        }
    }

    private func waitForOnboardMutation(
        since startedAt: Date,
        timeout: TimeInterval,
        matching predicate: @escaping (UITestOnboardProfileMutation) -> Bool
    ) -> UITestEvent? {
        testCase.waitForEvent(named: "onboardProfileMutationEnd", timeout: timeout) { event in
            guard event.timestamp >= startedAt.timeIntervalSince1970 - 0.1,
                  testCase.expectedScope.matches(event.scope),
                  let mutation = event.onboardMutation else {
                return false
            }
            return predicate(mutation)
        }
    }

    private func waitForDPIStageEnd(since startedAt: Date, timeout: TimeInterval, target: Int) -> UITestEvent? {
        waitForFeatureEvent(since: startedAt, timeout: timeout) { [testCase] event in
            testCase.expectedScope.matches(event.scope) &&
                (
                    event.name == "onboardProfileMutationEnd" && event.onboardMutation?.dpiActiveStage == target ||
                    event.name == "applyEnd" && event.patch?.activeStage == target && event.state?.activeStage == target
                )
        }
    }

    private func waitForDPIValueEnd(
        since startedAt: Date,
        timeout: TimeInterval,
        target: Int,
        monitoringFieldIdentifier: String? = nil
    ) -> UITestEvent? {
        let deadline = Date().addingTimeInterval(timeout)
        var sawTargetInUI = false
        var observedValues: [Int] = []

        repeat {
            if let monitoringFieldIdentifier,
               let visibleValue = visibleDPIFieldValue(identifier: monitoringFieldIdentifier) {
                if observedValues.last != visibleValue {
                    observedValues.append(visibleValue)
                }
                if visibleValue == target {
                    sawTargetInUI = true
                } else if sawTargetInUI {
                    XCTFail(
                        "DPI field rolled back after showing \(target); observed visible values \(observedValues)"
                    )
                    return nil
                }
            }

            if let event = testCase.readEvents().first(where: { event in
                guard event.timestamp >= startedAt.timeIntervalSince1970 - 0.1,
                      testCase.expectedScope.matches(event.scope) else { return false }
                if event.name == "onboardProfileMutationEnd",
                   self.onboardMutationContainsDPI(event.onboardMutation, target: target) {
                    return true
                }
                if event.name == "applyEnd",
                   self.patchContainsDPI(event.patch, target: target) ||
                    self.stateContainsDPI(event.state, target: target) {
                    return true
                }
                return false
            }) {
                if let monitoringFieldIdentifier,
                   !assertDPIFieldStable(
                    identifier: monitoringFieldIdentifier,
                    target: target,
                    observedValues: &observedValues,
                    duration: 1.0
                   ) {
                    return nil
                }
                return event
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        guard let event = testCase.readEvents().first(where: { event in
            guard event.timestamp >= startedAt.timeIntervalSince1970 - 0.1,
                  testCase.expectedScope.matches(event.scope) else { return false }
            if event.name == "onboardProfileMutationEnd",
               self.onboardMutationContainsDPI(event.onboardMutation, target: target) {
                return true
            }
            if event.name == "applyEnd",
               self.patchContainsDPI(event.patch, target: target) ||
                self.stateContainsDPI(event.state, target: target) {
                return true
            }
            return false
        }) else {
            return nil
        }
        if let monitoringFieldIdentifier,
           !assertDPIFieldStable(
            identifier: monitoringFieldIdentifier,
            target: target,
            observedValues: &observedValues,
            duration: 1.0
           ) {
            return nil
        }
        return event
    }

    private func visibleDPIFieldValue(identifier: String) -> Int? {
        let element = testCase.app.descendants(matching: .any)[identifier]
        guard element.exists else { return nil }
        return integerValue(from: element)
    }

    private func assertDPIFieldStable(
        identifier: String,
        target: Int,
        observedValues: inout [Int],
        duration: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(duration)
        var sawTarget = observedValues.contains(target)
        repeat {
            if let visibleValue = visibleDPIFieldValue(identifier: identifier) {
                if observedValues.last != visibleValue {
                    observedValues.append(visibleValue)
                }
                if visibleValue == target {
                    sawTarget = true
                } else if sawTarget {
                    XCTFail(
                        "DPI field rolled back after showing \(target); observed visible values \(observedValues)"
                    )
                    return false
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline

        if !sawTarget {
            XCTFail(
                "DPI field never showed \(target) after the backend mutation completed; observed visible values \(observedValues)"
            )
            return false
        }
        return true
    }

    private func waitForLightingBrightnessEnd(
        since startedAt: Date,
        timeout: TimeInterval,
        targetBrightness: Int
    ) -> UITestEvent? {
        waitForFeatureEvent(since: startedAt, timeout: timeout) { [testCase] event in
            guard testCase.expectedScope.matches(event.scope) else { return false }
            if event.name == "onboardProfileMutationEnd",
               event.onboardMutation?.brightnessByLEDID?.values.contains(where: { abs($0 - targetBrightness) <= 12 }) == true {
                return true
            }
            if event.name == "applyEnd",
               event.patch?.ledBrightness != nil,
               let applied = event.state?.ledValue,
               abs(applied - targetBrightness) <= 12 {
                return true
            }
            return false
        }
    }

    private func waitForFeatureEvent(
        since startedAt: Date,
        timeout: TimeInterval,
        matching predicate: @escaping (UITestEvent) -> Bool
    ) -> UITestEvent? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let event = testCase.readEvents().first(where: {
                $0.timestamp >= startedAt.timeIntervalSince1970 - 0.1 && predicate($0)
            }) {
                return event
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return testCase.readEvents().first(where: {
            $0.timestamp >= startedAt.timeIntervalSince1970 - 0.1 && predicate($0)
        })
    }

    private func eventContainsDPIStageChange(_ event: UITestEvent) -> Bool {
        event.name == "onboardProfileMutationEnd" && event.onboardMutation?.dpiActiveStage != nil ||
            event.name == "applyEnd" && event.patch?.activeStage != nil
    }

    private func eventContainsDPIValueChange(_ event: UITestEvent) -> Bool {
        event.name == "onboardProfileMutationEnd" && onboardMutationContainsAnyDPI(event.onboardMutation) ||
            event.name == "applyEnd" && (patchContainsAnyDPI(event.patch) || event.state?.dpi != nil)
    }

    private func eventContainsBrightnessChange(_ event: UITestEvent) -> Bool {
        event.name == "onboardProfileMutationEnd" && event.onboardMutation?.brightnessByLEDID != nil ||
            event.name == "applyEnd" && event.patch?.ledBrightness != nil
    }

    private func requireElement(
        _ identifier: String,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> XCUIElement {
        let element = testCase.app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing UI element \(identifier)", file: file, line: line)
        return element
    }

    private func restoreDPIStageSelection(index: Int) {
        guard let button = testCase.firstExistingElement(
            in: [testCase.app.descendants(matching: .any)["dpi-stage-\(index + 1)-select-button"]],
            timeout: 0.5
        ) else { return }
        testCase.scrollElementToVisible(button)
        let clickedAt = Date()
        testCase.clickElement(button)
        _ = waitForDPIStageEnd(since: clickedAt, timeout: configuration.actionDeadline, target: index)
    }

    private func restoreDPIValue(_ dpi: Int) {
        guard let changedAt = try? setSingleDPIValue(dpi) else { return }
        _ = waitForDPIValueEnd(since: changedAt, timeout: configuration.actionDeadline, target: dpi)
    }

    private func restoreBrightness(_ brightness: Int) {
        guard let slider = testCase.firstExistingElement(
            in: [testCase.app.descendants(matching: .any)["lighting-brightness-slider"]],
            timeout: 0.5
        ) else { return }
        testCase.scrollElementToVisible(slider)
        let changedAt = Date()
        slider.adjust(toNormalizedSliderPosition: CGFloat(brightness) / 255.0)
        _ = waitForLightingBrightnessEnd(
            since: changedAt,
            timeout: configuration.actionDeadline,
            targetBrightness: brightness
        )
    }

    private func restorePollRate(_ pollRate: Int) {
        guard let picker = testCase.firstExistingElement(
            in: [testCase.app.descendants(matching: .any)["poll-rate-picker"]],
            timeout: 0.5
        ) else { return }
        testCase.scrollElementToVisible(picker)
        guard let clickedAt = testCase.clickPollRateOption(pollRate, picker: picker) else { return }
        _ = waitForApplyEnd(since: clickedAt, timeout: configuration.actionDeadline) { $0.patch?.pollRate == pollRate }
    }

    private func restoreSleepTimeout(_ timeout: Int) {
        _ = testCase.setSleepTimeoutFromUITestUI(timeout, timeout: configuration.actionDeadline)
    }

    private func restoreLowBatteryThreshold(_ raw: Int) {
        guard let slider = testCase.firstExistingElement(
            in: [testCase.app.descendants(matching: .any)["low-battery-threshold-slider"]],
            timeout: 0.5
        ) else { return }
        testCase.scrollElementToVisible(slider)
        let changedAt = Date()
        slider.adjust(toNormalizedSliderPosition: normalizedLowBatteryThreshold(raw))
        _ = waitForApplyEnd(since: changedAt, timeout: configuration.actionDeadline) {
            $0.patch?.lowBatteryThresholdRaw == raw
        }
    }

    private func restoreScrollMode(_ mode: Int) {
        guard let picker = testCase.firstExistingElement(
            in: [testCase.app.descendants(matching: .any)["scroll-mode-picker"]],
            timeout: 0.5
        ) else { return }
        testCase.scrollElementToVisible(picker)
        let clickedAt = Date()
        picker.coordinate(withNormalizedOffset: CGVector(dx: mode == 0 ? 0.25 : 0.75, dy: 0.5)).click()
        _ = waitForOnboardMutation(since: clickedAt, timeout: configuration.actionDeadline) { $0.scrollMode == mode }
    }

    private func restoreScrollAcceleration(_ enabled: Bool) {
        restoreToggle("scroll-acceleration-toggle") { $0.scrollAcceleration == enabled }
    }

    private func restoreScrollSmartReel(_ enabled: Bool) {
        restoreToggle("scroll-smart-reel-toggle") { $0.scrollSmartReel == enabled }
    }

    private func restoreButtonTurbo(slot: Int) {
        restoreToggle("button-binding-turbo-toggle-\(slot)") { $0.buttonBindingSlots?.contains(slot) == true }
    }

    private func restoreToggle(
        _ identifier: String,
        matching predicate: @escaping (UITestOnboardProfileMutation) -> Bool
    ) {
        guard let toggle = testCase.firstExistingElement(
            in: [testCase.app.descendants(matching: .any)[identifier]],
            timeout: 0.5
        ) else { return }
        testCase.scrollElementToVisible(toggle)
        let clickedAt = Date()
        testCase.clickElement(toggle)
        _ = waitForOnboardMutation(since: clickedAt, timeout: configuration.actionDeadline, matching: predicate)
    }

    private func normalizedLowBatteryThreshold(_ value: Int) -> CGFloat {
        CGFloat(max(0x0C, min(0x3F, value)) - 0x0C) / CGFloat(0x3F - 0x0C)
    }

    private func targetDPI(after current: Int) -> Int {
        current == 800 ? 1200 : 800
    }

    private func setSingleDPIValue(_ dpi: Int) throws -> Date {
        let field = try requireElement("dpi-stage-1-value-field", timeout: 2)
        testCase.scrollElementToVisible(field)
        testCase.clickElement(field)
        field.typeKey("a", modifierFlags: .command)
        let changedAt = Date()
        field.typeText(String(dpi))
        field.typeKey(.return, modifierFlags: [])
        return changedAt
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

    private func onboardMutationContainsDPI(_ mutation: UITestOnboardProfileMutation?, target: Int) -> Bool {
        mutation?.dpiStages?.contains(target) == true ||
            mutation?.dpiStagePairs?.contains { $0.x == target || $0.y == target } == true
    }

    private func onboardMutationContainsAnyDPI(_ mutation: UITestOnboardProfileMutation?) -> Bool {
        mutation?.dpiStages?.isEmpty == false || mutation?.dpiStagePairs?.isEmpty == false
    }

    private func patchContainsDPI(_ patch: UITestPatch?, target: Int) -> Bool {
        patch?.dpiStages?.contains(target) == true ||
            patch?.dpiStagePairs?.contains { $0.x == target || $0.y == target } == true
    }

    private func patchContainsAnyDPI(_ patch: UITestPatch?) -> Bool {
        patch?.dpiStages?.isEmpty == false || patch?.dpiStagePairs?.isEmpty == false
    }

    private func stateContainsDPI(_ state: UITestState?, target: Int) -> Bool {
        state?.dpi == target ||
            state?.dpiStages?.contains(target) == true ||
            state?.dpiStagePairs?.contains { $0.x == target || $0.y == target } == true
    }

    private func firstButtonBindingRow() -> XCUIElement? {
        testCase.firstExistingElement(
            in: (1...128).map { testCase.app.descendants(matching: .any)["button-binding-row-\($0)"] },
            timeout: 2
        )
    }

    private func firstButtonTurboToggle() -> (slot: Int, toggle: XCUIElement)? {
        guard !configuration.buttonTurboCandidateSlots.isEmpty else {
            return nil
        }
        let scrollView = testCase.detailScrollView()
        for attempt in 0..<8 {
            for slot in configuration.buttonTurboCandidateSlots {
                let toggle = testCase.app.descendants(matching: .any)["button-binding-turbo-toggle-\(slot)"]
                if toggle.exists {
                    return (slot, toggle)
                }
            }
            guard attempt < 7, scrollView.exists else { break }
            scrollView.scroll(byDeltaX: 0, deltaY: -450)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return nil
    }
}

extension FeatureSweep.Configuration {
    static let v3XUSB = FeatureSweep.Configuration(
        appReadyDeadline: 10,
        actionDeadline: 3,
        expectedSelectedDeviceName: "Razer Basilisk V3 X HyperSpeed",
        expectedCards: [
            "dpi-stages-card",
            "lighting-card",
            "power-management-card",
            "poll-rate-card",
            "low-battery-threshold-card",
            "button-mapping-card"
        ],
        absentCards: [
            "onboard-profile-pill-button",
            "scroll-controls-card"
        ],
        features: [
            .dpiStageSelection,
            .dpiValue,
            .lightingBrightness,
            .pollRate,
            .sleepTimeout,
            .lowBatteryThreshold,
            .buttonMapping
        ],
        assertUSBPollRateCommand: true,
        buttonTurboCandidateSlots: [1, 2, 3, 4, 5, 9, 10, 96]
    )

    static let v3XBluetooth = FeatureSweep.Configuration(
        appReadyDeadline: 15,
        actionDeadline: 5,
        expectedSelectedDeviceName: nil,
        expectedCards: [
            "dpi-stages-card",
            "lighting-card",
            "power-management-card",
            "button-mapping-card"
        ],
        absentCards: [
            "onboard-profile-pill-button",
            "poll-rate-card",
            "low-battery-threshold-card",
            "scroll-controls-card"
        ],
        features: [
            .dpiValue,
            .lightingBrightness,
            .sleepTimeout,
            .buttonMapping
        ],
        assertUSBPollRateCommand: false,
        buttonTurboCandidateSlots: [1, 2, 3, 4, 5, 9, 10, 96]
    )

    static let v3ProUSB = FeatureSweep.Configuration(
        appReadyDeadline: 10,
        actionDeadline: 3,
        expectedSelectedDeviceName: "Razer Basilisk V3 Pro",
        expectedCards: [
            "dpi-stages-card",
            "onboard-profile-pill-button",
            "lighting-card",
            "power-management-card",
            "poll-rate-card",
            "low-battery-threshold-card",
            "scroll-controls-card",
            "button-mapping-card"
        ],
        absentCards: [],
        features: [
            .onboardProfiles,
            .dpiStageSelection,
            .lightingBrightness,
            .pollRate,
            .sleepTimeout,
            .lowBatteryThreshold,
            .scrollControls,
            .buttonMapping
        ],
        assertUSBPollRateCommand: true,
        buttonTurboCandidateSlots: [1, 2, 3, 4, 5, 9, 10, 15, 52, 53, 106]
    )

    static let v3ProBluetooth = FeatureSweep.Configuration(
        appReadyDeadline: 15,
        actionDeadline: 5,
        expectedSelectedDeviceName: nil,
        expectedCards: [
            "dpi-stages-card",
            "onboard-profile-pill-button",
            "lighting-card",
            "button-mapping-card"
        ],
        absentCards: [
            "poll-rate-card",
            "low-battery-threshold-card",
            "scroll-controls-card"
        ],
        features: [
            .onboardProfiles,
            .dpiValue,
            .lightingBrightness,
            .buttonMapping
        ],
        assertUSBPollRateCommand: false,
        buttonTurboCandidateSlots: []
    )
}
