import XCTest
import OpenSnekCore
@testable import OpenSnek

final class HardwareDpiReliabilityTests: XCTestCase {
    private struct Step {
        let values: [Int]
        let active: Int // 0-indexed
    }

    private struct StableDpiExpectation {
        let values: [Int]
        let active: Int
        let consecutiveMatches: Int
    }

    private func requireHardwareRunEnabled() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["OPEN_SNEK_HW"] == "1" else {
            throw XCTSkip("Set OPEN_SNEK_HW=1 to run hardware reliability tests.")
        }
    }

    func testBluetoothDpiStageApplyIsStableAcrossSequence() async throws {
        try requireHardwareRunEnabled()

        let client = BridgeClient()
        let devices = try await client.listDevices()
        guard let bt = devices.first(where: { $0.transport == .bluetooth }) else {
            throw XCTSkip("No Bluetooth device found for reliability test.")
        }

        // Sequence intentionally mixes single-stage and multi-stage active changes.
        let steps: [Step] = [
            Step(values: [1000], active: 0),
            Step(values: [800, 1600, 3200], active: 0),
            Step(values: [800, 1600, 3200], active: 2),
            Step(values: [1200, 2400], active: 1),
            Step(values: [900], active: 0)
        ]

        for (idx, step) in steps.enumerated() {
            let patch = DevicePatch(dpiStages: step.values, activeStage: step.active)
            _ = try await client.apply(device: bt, patch: patch)

            let stable = try await waitForStableDpiState(
                client: client,
                device: bt,
                expectation: StableDpiExpectation(
                    values: step.values,
                    active: step.active,
                    consecutiveMatches: 3
                ),
                timeout: 4.0
            )

            XCTAssertTrue(
                stable,
                "Step \(idx + 1) failed to converge values=\(step.values) active=\(step.active + 1)"
            )
        }
    }

    private func waitForStableDpiState(
        client: BridgeClient,
        device: MouseDevice,
        expectation: StableDpiExpectation,
        timeout: TimeInterval
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var matches = 0

        while Date() < deadline {
            let state = try await client.readState(device: device)
            let values = state.dpi_stages.values ?? []
            let active = state.dpi_stages.active_stage ?? -1
            let compared = Array(values.prefix(expectation.values.count))

            if active == expectation.active && compared == expectation.values {
                matches += 1
                if matches >= expectation.consecutiveMatches {
                    return true
                }
            } else {
                matches = 0
            }

            try await Task.sleep(nanoseconds: 160_000_000)
        }

        return false
    }
}
