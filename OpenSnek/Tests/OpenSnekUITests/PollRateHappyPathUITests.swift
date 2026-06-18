import XCTest

final class PollRateHappyPathUITests: OpenSnekHardwareUITestCase {
    private var pollRateToRestore: Int?

    override func restoreHardwareStateIfNeeded() {
        guard let restore = pollRateToRestore else {
            return
        }
        _ = clickPollRateOption(restore, picker: app.descendants(matching: .any)["poll-rate-picker"])
        _ = waitForEvent(
            named: "applyEnd",
            timeout: 2,
            matching: { $0.patch?.pollRate == restore && expectedScope.matches($0.scope) }
        )
    }

    func testChangingPollRateAppliesExpectedUSBCommandAndState() throws {
        let appReadyStartedAt = Date()
        let deviceName = try XCTUnwrap(launchAndWaitForScopedDevice(timeout: 5))
        XCTAssertLessThanOrEqual(Date().timeIntervalSince(appReadyStartedAt), 5)
        if let expectedProductName = expectedScope.productName {
            assertElementText(deviceName, equals: expectedProductName, context: "selected device name")
        }
        try keepMouseAwakeForUITest()

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
}
