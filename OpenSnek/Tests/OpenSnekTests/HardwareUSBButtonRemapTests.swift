import XCTest
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

/// Exercises explicitly scoped USB remaps with complete journaled recovery of both targets.
@MainActor final class HardwareUSBButtonRemapTests: XCTestCase {
    private static let backButtonSlot = 4
    /// Preserves original live/persistent blocks without assuming factory defaults or equal targets.
    private struct Snapshot: Codable, Equatable, Sendable {
        let slot: Int
        let persistent: [UInt8]
        let live: [UInt8]
    }

    func testUSBButtonRemapRightClickRoundTrip() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPEN_SNEK_HW"] == "1" else { throw XCTSkip("Set OPEN_SNEK_HW=1 to run USB hardware remap tests.") }
        let scope = try HardwareValidationScope(environment: environment)
        let client = BridgeClient()
        let device = try scope.select(from: await client.listDevices(), transport: .usb)
        print("[hardware-validation] journal=\(scope.journalURL.path) recovery=\(scope.isRecovery)")
        if scope.isRecovery {
            try await HardwareValidationSession.recover(deviceID: device.id, journalURL: scope.journalURL, read: { try await self.readSnapshot(client: client, device: device) }, restore: { try await self.restore($0, client: client, device: device) })
            return
        }
        try await HardwareValidationSession.run(
            deviceID: device.id, journalURL: scope.journalURL, read: { try await self.readSnapshot(client: client, device: device) }, restore: { try await self.restore($0, client: client, device: device) },
            operation: {
                try self.requireAppStopped()
                _ = try await client.apply(device: device, patch: DevicePatch(buttonBinding: ButtonBindingPatch(slot: Self.backButtonSlot, kind: .rightClick, hidKey: nil)))
                let state = try await self.readSnapshot(client: client, device: device)
                let expected: [UInt8] = [0x01, 0x01, 0x02, 0, 0, 0, 0]
                guard state.persistent == expected, state.live == expected else { throw HardwareValidationSession.failure("USB remap did not match right-click on both targets") }
            })
    }

    private func requireAppStopped() throws { guard BLEProbeSession.runningAppProcessIDs().isEmpty else { throw HardwareValidationSession.failure("Stop the app/service before USB hardware validation") } }

    private func readSnapshot(client: BridgeClient, device: MouseDevice) async throws -> Snapshot {
        try requireAppStopped()
        guard let persistent = try await client.debugUSBReadButtonBinding(device: device, slot: Self.backButtonSlot, profile: 1), let live = try await client.debugUSBReadButtonBinding(device: device, slot: Self.backButtonSlot, profile: 0), persistent.count == 7, live.count == 7 else {
            throw HardwareValidationSession.failure("Both complete original USB button targets are required before testing")
        }
        return Snapshot(slot: Self.backButtonSlot, persistent: persistent, live: live)
    }

    private func restore(_ snapshot: Snapshot, client: BridgeClient, device: MouseDevice) async throws {
        try requireAppStopped()
        guard snapshot.slot == Self.backButtonSlot, snapshot.persistent.count == 7, snapshot.live.count == 7 else { throw HardwareValidationSession.failure("Invalid USB button journal") }
        var failures: [String] = []
        // A persistent write may project into live, so always restore live last, even if the first restore fails.
        let persistentThenLive = [1, 0]
        for target in persistentThenLive {
            let block = target == 1 ? snapshot.persistent : snapshot.live
            do { guard try await client.debugUSBSetButtonBindingRaw(device: device, slot: snapshot.slot, profile: target, functionBlock: block) else { throw HardwareValidationSession.failure("USB restore target \(target) rejected") } } catch { failures.append(error.localizedDescription) }
        }
        guard failures.isEmpty else { throw HardwareValidationSession.failure("Retain journal for recovery: \(failures.joined(separator: "; "))") }
    }
}
