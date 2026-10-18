import XCTest
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols
@testable import OpenSnek

/// Exercises explicitly scoped Bluetooth DPI mutations with exact baseline restoration.
@MainActor final class HardwareDpiReliabilityTests: XCTestCase {
    /// Stores a requested DPI-stage transition.
    private struct Step {
        let values: [Int]
        let active: Int
    }

    func testBluetoothDpiStageApplyIsStableAcrossSequence() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPEN_SNEK_HW"] == "1" else { throw XCTSkip("Set OPEN_SNEK_HW=1 to run hardware reliability tests.") }
        let scope = try HardwareValidationScope(environment: environment)
        let isolation = try BLEProbeSession()
        let client = BridgeClient()
        let device = try scope.select(from: await client.listDevices(), transport: .bluetooth)
        guard await client.prepareBluetoothControlConnection(preferredPeripheralName: device.product_name) else { throw HardwareValidationSession.failure("Cannot prepare the explicitly selected Bluetooth device") }
        let peripherals = await client.btVendorClient.connectedPeripheralSummaries() ?? []
        let matchingNames = peripherals.filter { BluetoothNameMatcher.looselyMatches($0.name, device.product_name) }
        guard matchingNames.count == 1 else { throw HardwareValidationSession.failure("Disconnect other matching Bluetooth models before hardware validation; name-based routing is ambiguous") }
        print("[hardware-validation] journal=\(scope.journalURL.path) recovery=\(scope.isRecovery)")
        if scope.isRecovery {
            try await HardwareValidationSession.recover(deviceID: device.id, journalURL: scope.journalURL, read: { try await self.readSnapshot(client: client, device: device, isolation: isolation) }, restore: { try await self.restore($0, client: client, device: device, isolation: isolation) })
            return
        }
        try await HardwareValidationSession.run(
            deviceID: device.id, journalURL: scope.journalURL, read: { try await self.readSnapshot(client: client, device: device, isolation: isolation) }, restore: { try await self.restore($0, client: client, device: device, isolation: isolation) },
            operation: { try await self.exerciseSequence(client: client, device: device, isolation: isolation) })
    }

    private func exerciseSequence(client: BridgeClient, device: MouseDevice, isolation: BLEProbeSession) async throws {
        let steps = [Step(values: [1000], active: 0), Step(values: [800, 1600, 3200], active: 0), Step(values: [800, 1600, 3200], active: 2), Step(values: [1200, 2400], active: 1), Step(values: [900], active: 0)]
        for (index, step) in steps.enumerated() {
            try isolation.checkAppIsStopped()
            _ = try await client.apply(device: device, patch: DevicePatch(dpiStages: step.values, activeStage: step.active))
            let stable = try await waitForStableState(client: client, device: device, step: step)
            guard stable else { throw HardwareValidationSession.failure("DPI step \(index + 1) did not stabilize") }
        }
    }

    private func readSnapshot(client: BridgeClient, device: MouseDevice, isolation: BLEProbeSession) async throws -> Data {
        try isolation.checkAppIsStopped()
        let request = await client.nextBTReq()
        let frames = try await client.btExchange([BLEVendorProtocol.buildReadHeader(req: request, key: .dpiStagesGet)], timeout: 1.2, device: device)
        guard let payload = BLEVendorProtocol.parsePayloadFrames(notifies: frames, req: request) else { throw HardwareValidationSession.failure("No DPI baseline payload; no mutation is safe") }
        return try HardwareDPIBaseline.validate(payload, range: DeviceProfiles.dpiRange(for: device))
    }

    private func restore(_ snapshot: Data, client: BridgeClient, device: MouseDevice, isolation: BLEProbeSession) async throws {
        try isolation.checkAppIsStopped()
        let validated = try HardwareDPIBaseline.validate(snapshot, range: DeviceProfiles.dpiRange(for: device))
        let payload = validated + Data(repeating: 0, count: 38 - validated.count)
        let request = await client.nextBTReq()
        let header = BLEVendorProtocol.buildWriteHeader(req: request, payloadLength: UInt8(payload.count), key: .dpiStagesSet)
        let frames = try await client.btExchange([header, payload.prefix(20), payload.suffix(from: 20)], timeout: 1.2, device: device)
        guard await client.btAckSuccess(notifies: frames, req: request) else { throw HardwareValidationSession.failure("DPI restore rejected; retain the journal for recovery") }
    }

    private func waitForStableState(client: BridgeClient, device: MouseDevice, step: Step) async throws -> Bool {
        let deadline = Date().addingTimeInterval(4)
        var matches = 0
        while Date() < deadline {
            let state = try await client.readState(device: device)
            if state.dpi_stages.active_stage == step.active, state.dpi_stages.values == step.values { matches += 1 } else { matches = 0 }
            if matches >= 3 { return true }
            try await Task.sleep(nanoseconds: 160_000_000)
        }
        return false
    }
}
