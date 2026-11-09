import XCTest
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols
@testable import OpenSnek

/// Exercises the receiver's actual app apply path with journaled stored/live restoration.
@MainActor final class HardwareBasiliskV4USBTests: XCTestCase {
    /// Keeps complete wire originals rather than reconstructing defaults.
    private struct Layer: Codable, Equatable, Sendable {
        let stages: [UInt8]
        let scalar: [UInt8]
        let brightness: [UInt8]
        let effect: [UInt8]
        let button: [UInt8]
    }

    /// Records both targets plus the device-wide polling and sleep registers.
    private struct Snapshot: Codable, Equatable, Sendable {
        let layers: [Layer]
        let poll: [UInt8]
        let sleep: [UInt8]
    }

    func testReceiverApplyAndRestore() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPEN_SNEK_HW"] == "1" else { throw XCTSkip("Set OPEN_SNEK_HW=1 for receiver hardware validation") }
        let scope = try HardwareValidationScope(environment: environment)
        let client = BridgeClient()
        let device = try scope.select(from: await client.listDevices(), transport: .usb)
        guard device.product_id == 0x00EA, device.profile_id == .basiliskV4Hyperspeed else { throw HardwareValidationSession.failure("Select the Basilisk V4 HyperSpeed receiver") }
        let read = { try await self.readSnapshot(client, device) }
        let restore = { (snapshot: Snapshot) in try await self.restore(snapshot, client, device) }
        if scope.isRecovery {
            try await HardwareValidationSession.recover(deviceID: device.id, journalURL: scope.journalURL, read: read, restore: restore)
            return
        }
        try await HardwareValidationSession.run(deviceID: device.id, journalURL: scope.journalURL, read: read, restore: restore, operation: { try await self.exercise(client, device) })
    }

    private func exercise(_ client: BridgeClient, _ device: MouseDevice) async throws {
        for values in [[1000], [800, 1600, 3200], [900], [400, 800, 1600, 3200, 6400]] {
            let pairs = values.map { DpiPair(x: $0, y: $0 + 100) }
            let active = values.count - 1
            let state = try await client.apply(device: device, patch: DevicePatch(dpiStages: values, dpiStagePairs: pairs, activeStage: active))
            guard state.dpi_stages.values == values, state.dpi_stages.pairs == pairs, state.dpi_stages.active_stage == active else { throw HardwareValidationSession.failure("App DPI apply mismatch") }
        }
        let active = try await client.apply(device: device, patch: DevicePatch(activeStage: 1))
        guard active.dpi_stages.active_stage == 1 else { throw HardwareValidationSession.failure("Active-only stage apply mismatch") }
        for rate in [500, 125, 1000] {
            let state = try await client.apply(device: device, patch: DevicePatch(pollRate: rate))
            guard state.poll_rate == rate else { throw HardwareValidationSession.failure("App polling apply mismatch") }
        }
        let power = try await client.apply(device: device, patch: DevicePatch(sleepTimeout: 301, ledBrightness: 86))
        guard power.sleep_timeout == 301, power.led_value == 86 else { throw HardwareValidationSession.failure("App power/brightness apply mismatch") }
        for kind in DeviceProfiles.basiliskV4HyperspeedUSB.supportedLightingEffects { _ = try await client.apply(device: device, patch: DevicePatch(lightingEffect: LightingEffectPatch(kind: kind, primary: RGBPatch(r: 32, g: 160, b: 96)))) }
        _ = try await client.apply(device: device, patch: DevicePatch(buttonBinding: ButtonBindingPatch(slot: 4, kind: .rightClick, hidKey: nil)))
        let snapshot = try await readSnapshot(client, device)
        guard snapshot.layers.allSatisfy({ Array($0.button.suffix(7)) == [1, 1, 2, 0, 0, 0, 0] }) else { throw HardwareValidationSession.failure("App button apply mismatch") }
    }

    private func readSnapshot(_ client: BridgeClient, _ device: MouseDevice) async throws -> Snapshot {
        var layers: [Layer] = []
        for target: UInt8 in [1, 0] {
            let stages = try await command((client, device), 4, 0x86, 38, [target])
            let scalar = try await command((client, device), 4, 0x85, 7, [target])
            let brightness = try await command((client, device), 15, 0x84, 3, [target, 10])
            let effect = try await command((client, device), 15, 0x82, 12, [target, 0])
            let button = try await command((client, device), 2, 0x8C, 10, [target, 4, 0])
            layers.append(Layer(stages: stages, scalar: scalar, brightness: brightness, effect: effect, button: button))
        }
        let poll = try await command((client, device), 0, 0x8E, 2, [1])
        let sleep = try await command((client, device), 7, 0x83, 2, [])
        return Snapshot(layers: layers, poll: poll, sleep: sleep)
    }

    private func restore(_ snapshot: Snapshot, _ client: BridgeClient, _ device: MouseDevice) async throws {
        guard snapshot.layers.count == 2, snapshot.poll.count == 2, snapshot.sleep.count == 2, snapshot.layers.allSatisfy({ $0.stages.count == 38 && $0.scalar.count == 7 && $0.brightness.count == 3 && $0.effect.count == 12 && $0.button.count == 10 }) else {
            throw HardwareValidationSession.failure("Invalid V4 receiver journal")
        }
        for (index, layer) in snapshot.layers.enumerated() {
            let target: UInt8 = index == 0 ? 1 : 0
            _ = try await command((client, device), 4, 6, 38, [target] + layer.stages.dropFirst())
            _ = try await command((client, device), 4, 5, 7, [target] + layer.scalar.dropFirst())
            _ = try await command((client, device), 15, 4, 3, [target, 0, layer.brightness[2]])
            _ = try await command((client, device), 15, 2, 12, [target, 0] + layer.effect.dropFirst(2))
            _ = try await command((client, device), 2, 0x0C, 10, [target] + layer.button.dropFirst())
        }
        _ = try await command((client, device), 0, 0x0E, 2, snapshot.poll)
        _ = try await command((client, device), 7, 3, 2, snapshot.sleep)
    }

    private func command(_ target: (BridgeClient, MouseDevice), _ cls: UInt8, _ cmd: UInt8, _ size: UInt8, _ args: [UInt8]) async throws -> [UInt8] {
        let (client, device) = target
        guard BLEProbeSession.runningAppProcessIDs().isEmpty else { throw HardwareValidationSession.failure("Stop app/service before hardware validation") }
        guard let session = await client.sessionFor(device: device), let reply = try session.perform(classID: cls, cmdID: cmd, size: size, args: args, transactionID: 0x1F), reply[0] == 2 else { throw HardwareValidationSession.failure("Receiver register command failed") }
        return Array(reply[8..<(8 + Int(size))])
    }
}
