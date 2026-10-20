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
        let target = try await selectTarget(scope: scope)
        let device = target.device
        // All nested apply/readState exchanges share this immutable transport pin.
        let client = BridgeClient(startHIDMonitoring: false, requiredBluetoothPeripheralIdentifier: target.peripheralIdentifier)
        let read = { try await HardwareBluetoothSnapshot(target: target, payload: self.readSnapshot(client: client, device: device, isolation: isolation)) }
        let restore = { (snapshot: HardwareBluetoothSnapshot) in
            guard snapshot.target == target else { throw HardwareValidationSession.failure("Recovery target changed; no writes sent") }
            try await self.restore(snapshot.payload, client: client, device: device, isolation: isolation)
        }
        print("[hardware-validation] peripheral=\(target.peripheralIdentifier) journal=\(scope.journalURL.path) recovery=\(scope.isRecovery)")
        if scope.isRecovery {
            try await HardwareValidationSession.recover(deviceID: target.peripheralIdentifier.uuidString, journalURL: scope.journalURL, read: read, restore: restore)
            return
        }
        try await HardwareValidationSession.run(deviceID: target.peripheralIdentifier.uuidString, journalURL: scope.journalURL, read: read, restore: restore, operation: { try await self.exerciseSequence(client: client, device: device, isolation: isolation) })
    }

    private func selectTarget(scope: HardwareValidationScope) async throws -> HardwareBluetoothTarget {
        if scope.isRecovery { return try HardwareBluetoothTarget.recover(from: scope.journalURL) }
        let discovery = BridgeClient(startHIDMonitoring: false)
        let device = try scope.select(from: await discovery.listDevices(), transport: .bluetooth)
        guard await discovery.prepareBluetoothControlConnection(preferredPeripheralName: device.product_name) else { throw HardwareValidationSession.failure("Cannot prepare the explicitly selected Bluetooth device") }
        return try await HardwareBluetoothTarget.capture(device: device, peripherals: discovery.btVendorClient.connectedPeripheralSummaries() ?? [])
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
