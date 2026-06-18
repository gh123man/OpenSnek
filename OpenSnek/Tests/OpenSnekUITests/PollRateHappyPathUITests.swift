import AppKit
import XCTest

final class PollRateHappyPathUITests: XCTestCase {
    private static let targetBundleIdentifier = "io.opensnek.OpenSnek"

    private let expectedScope = HardwareDeviceScope.fromEnvironment()

    private var app: XCUIApplication!
    private var eventsURL: URL!
    private var didRecordIssue = false
    private var pollRateToRestore: Int?
    private var appliedPollRate: Int?

    override func setUpWithError() throws {
        continueAfterFailure = false

        terminateRunningOpenSnek()

        let runID = UUID().uuidString
        eventsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-snek-uitest-\(runID)")
            .appendingPathExtension("ndjson")
        try? FileManager.default.removeItem(at: eventsURL)

        app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-events-path",
            eventsURL.path,
            "--ui-test-run-id",
            runID,
            "--ui-test-force-local-backend",
        ]
        app.launchEnvironment = [
            "OPEN_SNEK_UITEST_EVENTS_PATH": eventsURL.path,
            "OPEN_SNEK_UITEST_RUN_ID": runID,
            "OPEN_SNEK_UITEST_FORCE_LOCAL_BACKEND": "1",
        ]
    }

    override func tearDownWithError() throws {
        if let app, app.state != .notRunning {
            restorePollRateIfNeeded()
        }
        if didRecordIssue {
            attachEventLog()
        }
        if let app, app.state != .notRunning {
            app.terminate()
        }
        app = nil
        eventsURL = nil
        didRecordIssue = false
        pollRateToRestore = nil
        appliedPollRate = nil
    }

    private func terminateRunningOpenSnek() {
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.targetBundleIdentifier)
        for runningApp in runningApps where !runningApp.isTerminated {
            if !runningApp.terminate() {
                _ = runningApp.forceTerminate()
            }
        }

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let remainingApps = NSRunningApplication.runningApplications(withBundleIdentifier: Self.targetBundleIdentifier)
                .filter { !$0.isTerminated }
            if remainingApps.isEmpty {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        for runningApp in NSRunningApplication.runningApplications(withBundleIdentifier: Self.targetBundleIdentifier)
            where !runningApp.isTerminated {
            _ = runningApp.forceTerminate()
        }
    }

    private func ensureMainWindowIsOpen(
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if app.windows.firstMatch.waitForExistence(timeout: 1) {
            return
        }

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 2),
            "OpenSnek launched without a main window, and File > New Window did not create one.",
            file: file,
            line: line
        )
    }

    override func record(_ issue: XCTIssue) {
        didRecordIssue = true
        super.record(issue)
    }

    func testChangingPollRateAppliesExpectedUSBCommandAndState() throws {
        app.launch()
        ensureMainWindowIsOpen()

        let appReadyStartedAt = Date()
        let deviceName = try XCTUnwrap(waitForScopedRealDevice(timeout: 5))
        XCTAssertLessThanOrEqual(Date().timeIntervalSince(appReadyStartedAt), 5)
        if let expectedProductName = expectedScope.productName {
            assertElementText(deviceName, equals: expectedProductName, context: "selected device name")
        }

        let statusBadge = app.descendants(matching: .any)["device-status-badge"]
        XCTAssertTrue(statusBadge.waitForExistence(timeout: 1), "Device status badge did not appear")
        assertElementText(statusBadge, equals: "Connected", context: "device status")

        let pollRateCard = app.descendants(matching: .any)["poll-rate-card"]
        XCTAssertTrue(pollRateCard.waitForExistence(timeout: 1), "Polling-rate card did not appear")
        scrollElementToVisible(pollRateCard)

        let pollRatePicker = app.descendants(matching: .any)["poll-rate-picker"]
        XCTAssertTrue(pollRatePicker.waitForExistence(timeout: 1), "Polling-rate picker did not appear")
        scrollElementToVisible(pollRatePicker)

        let hydratedState = try XCTUnwrap(
            latestExpectedDeviceState(),
            "Expected a real readState event for \(expectedScope.description)"
        )
        let initialPollRate = try XCTUnwrap(hydratedState.pollRate, "Expected real device state to include poll_rate")
        pollRateToRestore = initialPollRate

        let targetPollRate = targetPollRate(after: initialPollRate)
        let expectedArgs = try expectedUSBPollRateArgs(for: targetPollRate)
        let clickStartedAt = try XCTUnwrap(
            clickPollRateOption(targetPollRate, picker: pollRatePicker),
            "Could not click \(targetPollRate) Hz"
        )

        let applyEnd = try XCTUnwrap(
            waitForEvent(
                named: "applyEnd",
                timeout: 2,
                matching: { event in
                    event.patch?.pollRate == targetPollRate &&
                        expectedScope.matches(event.scope)
                }
            ),
            "Poll-rate apply to \(targetPollRate) Hz did not complete within 2s"
        )
        appliedPollRate = targetPollRate
        XCTAssertLessThanOrEqual(applyEnd.timestamp - clickStartedAt.timeIntervalSince1970, 2)

        let events = readEvents()
        assertDiscoveredExpectedScopedDevice(events)
        XCTAssertTrue(events.contains { $0.name == "listDevices" }, "App did not record real device discovery")
        XCTAssertTrue(events.contains { $0.name == "readState" && expectedScope.matches($0.scope) }, "App did not record real state hydration")

        let applyStart = try XCTUnwrap(
            events.first {
                    $0.name == "applyStart" &&
                    $0.patch?.pollRate == targetPollRate &&
                    expectedScope.matches($0.scope) &&
                    $0.timestamp >= clickStartedAt.timeIntervalSince1970 - 0.1
            },
            "App did not record applyStart for \(targetPollRate) Hz"
        )
        XCTAssertEqual(applyStart.patch?.pollRate, targetPollRate)
        assertExpectedScope(applyStart.scope, context: "applyStart")

        let command = try XCTUnwrap(
            events.first {
                $0.name == "usbCommand" &&
                    $0.timestamp >= applyStart.timestamp &&
                    $0.command?.name == "usbSetPollRate" &&
                    $0.command?.args == expectedArgs &&
                    expectedScope.matches($0.scope)
            }?.command,
            "App did not record the expected real USB poll-rate command for \(targetPollRate) Hz"
        )
        XCTAssertEqual(command.protocolName, expectedScope.protocolName)
        XCTAssertEqual(command.classID, 0x00)
        XCTAssertEqual(command.cmdID, 0x05)
        XCTAssertEqual(command.size, 0x01)
        XCTAssertEqual(command.args, expectedArgs)

        assertExpectedScope(applyEnd.scope, context: "applyEnd")
        XCTAssertEqual(applyEnd.state?.pollRate, targetPollRate)
        let elapsed = try XCTUnwrap(applyEnd.elapsed, "App did not record apply elapsed time")
        XCTAssertLessThanOrEqual(elapsed, 2)
        XCTAssertFalse(events.contains { $0.name == "overlapDetected" }, "App detected overlapping apply calls")
        XCTAssertLessThanOrEqual(events.compactMap(\.maxConcurrentApplyCount).max() ?? 1, 1)
    }

    private func waitForScopedRealDevice(
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement? {
        if let deviceName = identifiedText("selected-device-name", timeout: timeout) {
            assertDiscoveredExpectedScopedDevice(readEvents(), file: file, line: line)
            return deviceName
        }

        failMissingScopedDevice(timeout: timeout, file: file, line: line)
        return nil
    }

    private func failMissingScopedDevice(timeout: TimeInterval, file: StaticString, line: UInt) {
        let events = readEvents()
        if let denied = events.last(where: { $0.hidAccessStatus?.authorization == "denied" })?.hidAccessStatus {
            XCTFail(
                "OpenSnek.app does not have Input Monitoring permission. Grant System Settings > Privacy & Security > Input Monitoring for \(denied.hostLabel), then relaunch the UI test. Detail: \(denied.detail ?? "none").",
                file: file,
                line: line
            )
            return
        }

        if let listError = events.last(where: { $0.name == "listDevicesError" }) {
            XCTFail(
                "Expected connected \(expectedScope.description), but real device discovery failed: \(listError.error ?? "unknown error").",
                file: file,
                line: line
            )
            return
        }

        let discoveredDevices = events.flatMap { $0.devices ?? [] }
        let latestListedDevices = events.last { $0.name == "listDevices" }?.devices

        if let latestListedDevices, latestListedDevices.isEmpty {
            XCTFail(
                "Expected connected \(expectedScope.description), but OpenSnek discovered no devices within \(timeout)s. Confirm the device is connected over USB and Input Monitoring is granted to OpenSnek.app.",
                file: file,
                line: line
            )
            return
        }

        if !discoveredDevices.isEmpty, !discoveredDevices.contains(where: expectedScope.matches) {
            XCTFail(
                "Expected connected \(expectedScope.description), but OpenSnek discovered \(describeDevices(discoveredDevices)).",
                file: file,
                line: line
            )
            return
        }

        if discoveredDevices.contains(where: expectedScope.matches) {
            XCTFail(
                "Expected \(expectedScope.description) was discovered by the real backend, but the device UI did not become visible within \(timeout)s.",
                file: file,
                line: line
            )
            return
        }

        if events.isEmpty {
            XCTFail(
                "Expected connected \(expectedScope.description), but no UI test events were recorded. Check OPEN_SNEK_UITEST_EVENTS_PATH and \(eventsURL.path).",
                file: file,
                line: line
            )
            return
        }

        XCTFail(
            "Expected connected \(expectedScope.description), but the device UI did not become visible within \(timeout)s. Recorded events: \(events.map(\.name).joined(separator: ", ")).",
            file: file,
            line: line
        )
    }

    private func assertDiscoveredExpectedScopedDevice(
        _ events: [UITestEvent],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scopes = events.compactMap(\.scope).filter(expectedScope.matches)
        if let scope = scopes.first {
            assertExpectedScope(scope, context: "real backend scope", file: file, line: line)
        }

        let discoveredDevices = events.flatMap { $0.devices ?? [] }
        guard !discoveredDevices.isEmpty else {
            XCTFail("Real backend did not record discovered devices for \(expectedScope.description)", file: file, line: line)
            return
        }

        XCTAssertTrue(
            discoveredDevices.contains(where: expectedScope.matches),
            "Expected connected \(expectedScope.description), but OpenSnek discovered \(describeDevices(discoveredDevices)).",
            file: file,
            line: line
        )
    }

    private func assertExpectedScope(
        _ scope: UITestScope?,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let scope else {
            XCTFail("App did not record scoped device/protocol metadata for \(context)", file: file, line: line)
            return
        }
        XCTAssertEqual(scope.protocolName, expectedScope.protocolName, "\(context) protocol", file: file, line: line)
        XCTAssertEqual(scope.transport, expectedScope.transport, "\(context) transport", file: file, line: line)
        XCTAssertEqual(scope.vendorID, expectedScope.vendorID, "\(context) vendor ID", file: file, line: line)
        XCTAssertEqual(scope.productID, expectedScope.productID, "\(context) product ID", file: file, line: line)
        if let productName = expectedScope.productName {
            XCTAssertEqual(scope.productName, productName, "\(context) product name", file: file, line: line)
        }
        XCTAssertEqual(scope.profileID, expectedScope.profileID, "\(context) profile ID", file: file, line: line)
    }

    private func latestExpectedDeviceState() -> UITestState? {
        readEvents()
            .last { $0.name == "readState" && expectedScope.matches($0.scope) }?
            .state
    }

    private func targetPollRate(after current: Int) -> Int {
        current == 500 ? 1000 : 500
    }

    private func expectedUSBPollRateArgs(for pollRate: Int) throws -> [Int] {
        switch pollRate {
        case 1000:
            return [0x01]
        case 500:
            return [0x02]
        case 125:
            return [0x08]
        default:
            throw XCTSkip("Unsupported poll-rate target \(pollRate)")
        }
    }

    private func restorePollRateIfNeeded() {
        guard !didRecordIssue,
              let restore = pollRateToRestore,
              let appliedPollRate,
              restore != appliedPollRate else {
            return
        }
        _ = clickPollRateOption(restore, picker: app.descendants(matching: .any)["poll-rate-picker"])
        _ = waitForEvent(
            named: "applyEnd",
            timeout: 2,
            matching: { $0.patch?.pollRate == restore && expectedScope.matches($0.scope) }
        )
    }

    private func describeDevices(_ devices: [UITestDevice]) -> String {
        devices.map { device in
            "\(device.productName) (\(device.protocolName), transport \(device.transport), product 0x\(String(device.productID, radix: 16, uppercase: true)), profile \(device.profileID ?? "none"), id \(device.id))"
        }
        .joined(separator: "; ")
    }

    private func identifiedText(_ identifier: String, timeout: TimeInterval) -> XCUIElement? {
        firstExistingElement(
            in: [
                app.staticTexts[identifier],
                app.textFields[identifier],
                app.descendants(matching: .any)[identifier],
            ],
            timeout: timeout
        )
    }

    private func assertElementText(
        _ element: XCUIElement,
        equals expectedText: String,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if element.label == expectedText {
            return
        }
        if let value = element.value as? String, value == expectedText {
            return
        }
        if app.staticTexts[expectedText].waitForExistence(timeout: 0.5) {
            return
        }

        XCTFail(
            "\(context) exposed \(describeElementText(element)) instead of \(expectedText)",
            file: file,
            line: line
        )
    }

    private func describeElementText(_ element: XCUIElement) -> String {
        let value = (element.value as? String) ?? "nil"
        return "label \"\(element.label)\", value \"\(value)\""
    }

    private func clickPollRateOption(_ rate: Int, picker: XCUIElement) -> Date? {
        let identifier = "poll-rate-option-\(rate)"
        let label = "\(rate) Hz"
        let candidates = [
            app.buttons[identifier],
            app.radioButtons[identifier],
            app.buttons[label],
            app.radioButtons[label],
        ]

        if let option = firstExistingElement(in: candidates, timeout: 1) {
            scrollElementToVisible(option)
            let clickedAt = Date()
            if option.isHittable {
                option.click()
            } else {
                option.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }
            return clickedAt
        }

        if picker.exists {
            let xOffset: CGFloat
            switch rate {
            case 125:
                xOffset = 1.0 / 6.0
            case 500:
                xOffset = 0.5
            case 1000:
                xOffset = 5.0 / 6.0
            default:
                return nil
            }
            let clickedAt = Date()
            picker.coordinate(withNormalizedOffset: CGVector(dx: xOffset, dy: 0.5)).click()
            return clickedAt
        }

        return nil
    }

    private func scrollElementToVisible(_ element: XCUIElement, maxScrolls: Int = 8) {
        guard element.exists else { return }
        let scrollView = detailScrollView()
        for _ in 0..<maxScrolls where !element.isHittable {
            if scrollView.exists {
                scrollView.scroll(byDeltaX: 0, deltaY: -700)
            } else {
                app.swipeUp()
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private func detailScrollView() -> XCUIElement {
        let identified = app.scrollViews["device-detail-scroll-view"]
        return identified.exists ? identified : app.scrollViews.firstMatch
    }

    private func firstExistingElement(in candidates: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let element = candidates.first(where: { $0.exists }) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return candidates.first(where: { $0.exists })
    }

    private func waitForEvent(
        named name: String,
        timeout: TimeInterval,
        matching predicate: (UITestEvent) -> Bool
    ) -> UITestEvent? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let event = readEvents().first(where: { $0.name == name && predicate($0) }) {
                return event
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return readEvents().first(where: { $0.name == name && predicate($0) })
    }

    private func readEvents() -> [UITestEvent] {
        guard let eventsURL,
              let data = try? Data(contentsOf: eventsURL),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return text
            .split(separator: "\n")
            .compactMap { line in
                try? JSONDecoder().decode(UITestEvent.self, from: Data(line.utf8))
            }
    }

    private func attachEventLog() {
        guard let eventsURL else { return }
        if FileManager.default.fileExists(atPath: eventsURL.path) {
            let attachment = XCTAttachment(contentsOfFile: eventsURL)
            attachment.name = "OpenSnek UI hardware events"
            attachment.lifetime = .keepAlways
            add(attachment)
            return
        }

        let attachment = XCTAttachment(string: "No UI hardware event log found at \(eventsURL.path)")
        attachment.name = "Missing OpenSnek UI hardware events"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct HardwareDeviceScope {
    let protocolName: String
    let transport: String
    let vendorID: Int
    let productID: Int
    let productName: String?
    let profileID: String

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> HardwareDeviceScope {
        HardwareDeviceScope(
            protocolName: environment["OPEN_SNEK_UITEST_EXPECTED_PROTOCOL"] ?? "usb-hid",
            transport: environment["OPEN_SNEK_UITEST_EXPECTED_TRANSPORT"] ?? "usb",
            vendorID: intValue(environment["OPEN_SNEK_UITEST_EXPECTED_VENDOR_ID"]) ?? 0x1532,
            productID: intValue(environment["OPEN_SNEK_UITEST_EXPECTED_PRODUCT_ID"]) ?? 0x00AB,
            productName: environment["OPEN_SNEK_UITEST_EXPECTED_PRODUCT_NAME"] ?? "Razer Basilisk V3 Pro",
            profileID: environment["OPEN_SNEK_UITEST_EXPECTED_PROFILE_ID"] ?? "basilisk_v3_pro"
        )
    }

    var description: String {
        let productName = productName.map { "\($0) " } ?? ""
        return "\(productName)(\(protocolName), transport \(transport), product 0x\(String(productID, radix: 16, uppercase: true)), profile \(profileID))"
    }

    func matches(_ scope: UITestScope?) -> Bool {
        guard let scope else { return false }
        return scope.protocolName == protocolName &&
            scope.transport == transport &&
            scope.vendorID == vendorID &&
            scope.productID == productID &&
            (productName == nil || scope.productName == productName) &&
            scope.profileID == profileID
    }

    func matches(_ device: UITestDevice) -> Bool {
        device.protocolName == protocolName &&
            device.transport == transport &&
            device.vendorID == vendorID &&
            device.productID == productID &&
            (productName == nil || device.productName == productName) &&
            device.profileID == profileID
    }

    private static func intValue(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("0x") {
            return Int(trimmed.dropFirst(2), radix: 16)
        }
        return Int(trimmed)
    }
}

private struct UITestEvent: Decodable {
    let timestamp: TimeInterval
    let runID: String
    let name: String
    let source: String?
    let deviceID: String?
    let scope: UITestScope?
    let devices: [UITestDevice]?
    let patch: UITestPatch?
    let command: UITestUSBCommand?
    let state: UITestState?
    let activeApplyCount: Int?
    let maxConcurrentApplyCount: Int?
    let elapsed: TimeInterval?
    let readbackPolicy: String?
    let hidAccessStatus: UITestHIDAccessStatus?
    let error: String?
}

private struct UITestScope: Decodable {
    let protocolName: String
    let transport: String
    let vendorID: Int
    let productID: Int
    let productName: String
    let profileID: String
}

private struct UITestDevice: Decodable {
    let id: String
    let protocolName: String
    let transport: String
    let vendorID: Int
    let productID: Int
    let productName: String
    let profileID: String?
    let serial: String?
}

private struct UITestPatch: Decodable {
    let pollRate: Int?
    let sleepTimeout: Int?
    let activeStage: Int?
    let dpiStages: [Int]?
    let ledBrightness: Int?
}

private struct UITestUSBCommand: Decodable {
    let name: String
    let protocolName: String
    let classID: Int
    let cmdID: Int
    let size: Int
    let args: [Int]
}

private struct UITestState: Decodable {
    let connection: String
    let pollRate: Int?
    let dpi: Int?
}

private struct UITestHIDAccessStatus: Decodable {
    let authorization: String
    let hostLabel: String
    let bundleIdentifier: String?
    let detail: String?
}
