import XCTest
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols
@testable import OpenSnek

/// Validates every V4 Bluetooth remap and native default against both observed read targets.
@MainActor final class HardwareBasiliskV4BluetoothButtonTests: XCTestCase {
    /// Raw interleaved reads retain both current and baseline lanes for exact recovery checks.
    private struct Button: Codable, Equatable, Sendable {
        let slot: UInt8
        let live: Data
        let stored: Data
    }

    /// Recovery requires a pinned physical peripheral as well as the original button payloads.
    private struct Snapshot: Codable, Equatable, Sendable {
        let target: HardwareBluetoothTarget
        let buttons: [Button]
    }

    /// Keeps every app/probe exchange on the same UUID under one app-isolation lease.
    private struct Session {
        let target: HardwareBluetoothTarget
        let client: BridgeClient
        let isolation: BLEProbeSession
    }

    func testAllButtonsAndNativeDefaults() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["OPEN_SNEK_HW"] == "1" else { throw XCTSkip("Set OPEN_SNEK_HW=1 for Bluetooth button validation") }
        let scope = try HardwareValidationScope(environment: environment)
        let isolation = try BLEProbeSession()
        let target = try await selectTarget(scope)
        guard target.device.profile_id == .basiliskV4Hyperspeed else { throw HardwareValidationSession.failure("Select the Basilisk V4 HyperSpeed") }
        let session = Session(target: target, client: BridgeClient(startHIDMonitoring: false, requiredBluetoothPeripheralIdentifier: target.peripheralIdentifier), isolation: isolation)
        let read = { try await self.readSnapshot(session) }
        let restore = { (snapshot: Snapshot) in try await self.restore(snapshot, session: session) }
        if scope.isRecovery {
            try await HardwareValidationSession.recover(deviceID: target.peripheralIdentifier.uuidString, journalURL: scope.journalURL, read: read, restore: restore)
            return
        }
        let original = try await read()
        try await HardwareValidationSession.run(deviceID: target.peripheralIdentifier.uuidString, journalURL: scope.journalURL, read: read, restore: restore, operation: { try await self.exercise(original, session: session) })
    }

    private func selectTarget(_ scope: HardwareValidationScope) async throws -> HardwareBluetoothTarget {
        if scope.isRecovery {
            let journal = try HardwareValidationJournal<Snapshot>.load(from: scope.journalURL)
            try validate(journal.original)
            guard journal.deviceID == journal.original.target.peripheralIdentifier.uuidString else { throw HardwareValidationSession.failure("Journal peripheral mismatch") }
            return journal.original.target
        }
        let discovery = BridgeClient(startHIDMonitoring: false)
        let device = try scope.select(from: await discovery.listDevices(), transport: .bluetooth)
        guard await discovery.prepareBluetoothControlConnection(preferredPeripheralName: device.product_name) else { throw HardwareValidationSession.failure("Cannot connect to selected mouse") }
        return try await HardwareBluetoothTarget.capture(device: device, peripherals: discovery.btVendorClient.connectedPeripheralSummaries() ?? [])
    }

    private func validate(_ snapshot: Snapshot) throws {
        let expected = DeviceProfiles.basiliskV4HyperspeedBluetooth.buttonLayout.writableSlots.map(UInt8.init).sorted()
        guard snapshot.target.device.transport == .bluetooth, snapshot.target.device.profile_id == .basiliskV4Hyperspeed, snapshot.buttons.map(\.slot).sorted() == expected, snapshot.buttons.allSatisfy({ $0.live.count == 16 && $0.stored == $0.live && $0.live.first == $0.slot }) else {
            throw HardwareValidationSession.failure("Complete matching V4 button targets required; no writes sent")
        }
    }

    private func readButton(_ slot: UInt8, session: Session) async throws -> Button {
        let live = try await exchange(.buttonBindGet(target: 0, slot: slot), session: session)
        let stored = try await exchange(.buttonBindGet(target: 1, slot: slot), session: session)
        return Button(slot: slot, live: live, stored: stored)
    }

    private func readSnapshot(_ session: Session) async throws -> Snapshot {
        var buttons: [Button] = []
        for slot in DeviceProfiles.basiliskV4HyperspeedBluetooth.buttonLayout.writableSlots { buttons.append(try await readButton(UInt8(slot), session: session)) }
        let snapshot = Snapshot(target: session.target, buttons: buttons)
        try validate(snapshot)
        return snapshot
    }

    private func exercise(_ original: Snapshot, session: Session) async throws {
        for button in original.buttons {
            try session.isolation.checkAppIsStopped()
            print("TEST button \(button.slot) changed mapping")
            let originalBlock = try block(button.stored, slot: button.slot)
            let kind: ButtonBindingKind = originalBlock == [1, 1, 2, 0, 0, 0, 0] ? .middleClick : .rightClick
            let expected: [UInt8] = [1, 1, kind == .middleClick ? 3 : 2, 0, 0, 0, 0]
            _ = try await session.client.apply(device: session.target.device, patch: DevicePatch(buttonBinding: ButtonBindingPatch(slot: Int(button.slot), kind: kind, hidKey: nil)))
            try await verify(button.slot, expected: expected, session: session)
            print("TEST button \(button.slot) native Default")
            _ = try await session.client.apply(device: session.target.device, patch: DevicePatch(buttonBinding: ButtonBindingPatch(slot: Int(button.slot), kind: .default, hidKey: nil)))
            guard let native = ButtonBindingSupport.defaultUSBFunctionBlock(for: Int(button.slot), profileID: .basiliskV4Hyperspeed) else { throw HardwareValidationSession.failure("Missing native Default") }
            try await verify(button.slot, expected: native, session: session)
            try await restoreButton(button, session: session)
            print("PASS button \(button.slot) changed, Default and exact original restore")
        }
    }

    private func verify(_ slot: UInt8, expected: [UInt8], session: Session) async throws {
        let read = try await readButton(slot, session: session)
        guard try block(read.live, slot: slot) == expected, try block(read.stored, slot: slot) == expected else { throw HardwareValidationSession.failure("Button apply readback mismatch") }
    }

    private func block(_ payload: Data, slot: UInt8) throws -> [UInt8] {
        guard payload.count == 16, let block = BLEVendorProtocol.extractBluetoothFunctionBlock(payload: payload, target: 1, slot: slot, profileID: .basiliskV4Hyperspeed) else { throw HardwareValidationSession.failure("Malformed button read") }
        return block
    }

    private func restoreButton(_ button: Button, session: Session) async throws {
        let payload = Data([1, button.slot, 0] + (try block(button.stored, slot: button.slot)))
        _ = try await exchange(.buttonBind(slot: button.slot), payload: payload, session: session)
        guard try await readButton(button.slot, session: session) == button else { throw HardwareValidationSession.failure("Button restore mismatch; retain journal") }
    }

    private func restore(_ snapshot: Snapshot, session: Session) async throws {
        try validate(snapshot)
        guard snapshot.target == session.target else { throw HardwareValidationSession.failure("Recovery target changed") }
        for button in snapshot.buttons { try await restoreButton(button, session: session) }
    }

    private func exchange(_ key: BLEVendorProtocol.Key, payload: Data? = nil, session: Session) async throws -> Data {
        try session.isolation.checkAppIsStopped()
        let req = await session.client.nextBTReq()
        let frames = payload.map { BLEVendorProtocol.buildWriteFrames(req: req, key: key, payload: $0) } ?? [BLEVendorProtocol.buildReadHeader(req: req, key: key)]
        let result = try await session.client.btExchange(frames, timeout: 1.2, device: session.target.device)
        guard await session.client.btAckSuccess(notifies: result, req: req) else { throw HardwareValidationSession.failure("Button command rejected req=\(req) key=\(key.bytes) frames=\(result.map { $0.map { String(format: "%02x", $0) }.joined() })") }
        if payload != nil { return Data() }
        guard let read = BLEVendorProtocol.parsePayloadFrames(notifies: result, req: req) else { throw HardwareValidationSession.failure("No button payload") }
        return read
    }
}
