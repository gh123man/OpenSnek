import XCTest
import OpenSnekCore
@testable import OpenSnek
@testable import OpenSnekHardware

/// Exercises the real connection selector with fake peripherals and durable recovery journals.
@MainActor final class HardwareBluetoothRecoveryTests: XCTestCase {
    private let mouseA = BLEVendorTransportClient.ConnectedPeripheralSummary(name: "BSK V3 PRO", identifier: UUID())
    private let mouseB = BLEVendorTransportClient.ConnectedPeripheralSummary(name: "BSK V3 PRO", identifier: UUID())
    private let baseline = Data([1, 1, 1, 0x40, 6, 0x40, 6] + Array(repeating: UInt8(0), count: 29))

    func testDisconnectDoesNotSendOperationOrRestoreToIdenticalMouse() async throws {
        let url = journalURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let target = try makeTarget()
        let bus = FakeBluetoothBus(peripherals: [mouseA], payloads: [mouseA.identifier: baseline, mouseB.identifier: baseline])
        let client = BridgeClient(startHIDMonitoring: false, requiredBluetoothPeripheralIdentifier: target.peripheralIdentifier)
        let transport = await client.btVendorClient
        do {
            try await HardwareValidationSession.run(
                deviceID: target.peripheralIdentifier.uuidString, journalURL: url, read: { try bus.read(target: target, transport: transport) }, restore: { try bus.write($0, transport: transport) },
                operation: {
                    var changed = self.baseline
                    changed[3] = 0x84
                    changed[4] = 3
                    try bus.write(HardwareBluetoothSnapshot(target: target, payload: changed), transport: transport)
                    bus.peripherals = [self.mouseB]
                    bus.currentIdentifier = self.mouseB.identifier
                    // Even a ready cached connection to B must never receive A's next command.
                    try bus.write(HardwareBluetoothSnapshot(target: target, payload: changed), transport: transport)
                })
            XCTFail("Disconnection must fail the operation and leave recovery pending")
        } catch {
            XCTAssertEqual(bus.writes[mouseA.identifier], 1)
            XCTAssertNil(bus.writes[mouseB.identifier])
            XCTAssertEqual(try HardwareValidationJournal<HardwareBluetoothSnapshot>.load(from: url).phase, .restoreFailed)
        }
        // Simulate a new process: reload identity and baseline, build a new bridge, then recover.
        try await recover(url: url, bus: bus, shouldSucceed: false)
        XCTAssertNil(bus.writes[mouseB.identifier])
        bus.peripherals = [mouseB, mouseA]
        try await recover(url: url, bus: bus, shouldSucceed: true)
        XCTAssertEqual(bus.payloads[mouseA.identifier], baseline)
        XCTAssertNil(bus.writes[mouseB.identifier])
    }

    func testPreparedJournalRecoversAfterRestartAndRequiresVerifiedReadback() async throws {
        let url = journalURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let target = try makeTarget()
        let snapshot = HardwareBluetoothSnapshot(target: target, payload: baseline)
        try HardwareValidationJournal(schemaVersion: 1, deviceID: target.peripheralIdentifier.uuidString, original: snapshot, phase: .prepared).save(to: url, create: true)
        let bus = FakeBluetoothBus(peripherals: [mouseB, mouseA], payloads: [mouseA.identifier: Data(), mouseB.identifier: baseline])
        bus.ignoreWrites = true
        try await recover(url: url, bus: bus, shouldSucceed: false)
        bus.ignoreWrites = false
        try await recover(url: url, bus: bus, shouldSucceed: true)
        XCTAssertNil(bus.writes[mouseB.identifier])
    }

    func testCaptureRejectsAmbiguousModelsAndRecoveryRejectsLegacyJournal() throws {
        let target = try makeTarget()
        XCTAssertThrowsError(try HardwareBluetoothTarget.capture(device: target.device, peripherals: [mouseA, mouseB]))
        let url = journalURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try HardwareValidationJournal(schemaVersion: 1, deviceID: target.device.id, original: baseline, phase: .prepared).save(to: url, create: true)
        XCTAssertThrowsError(try HardwareBluetoothTarget.recover(from: url))
    }

    func testStrictRoutingReusesAndReconnectsOnlyThePinnedUUID() {
        let transport = BLEVendorTransportClient(requiredPeripheralIdentifier: mouseA.identifier)
        for preferredName in [mouseA.name, nil, "Another model"] {
            XCTAssertEqual(transport.selectConnection(from: [mouseB, mouseA], preferredName: preferredName, currentIdentifier: mouseB.identifier, isReady: true), .connect(mouseA.identifier))
            XCTAssertEqual(transport.selectConnection(from: [mouseA, mouseB], preferredName: preferredName, currentIdentifier: mouseA.identifier, isReady: true), .reuse)
            XCTAssertEqual(transport.selectConnection(from: [mouseB], preferredName: preferredName, currentIdentifier: mouseA.identifier, isReady: true), .unavailable)
            XCTAssertEqual(transport.selectConnection(from: [], preferredName: preferredName, currentIdentifier: nil, isReady: false), .unavailable)
            XCTAssertEqual(transport.selectConnection(from: [mouseA], preferredName: preferredName, currentIdentifier: mouseA.identifier, isReady: false), .connect(mouseA.identifier))
        }
    }

    private func recover(url: URL, bus: FakeBluetoothBus, shouldSucceed: Bool) async throws {
        // No discovered device ID is required in the new process: it may have a different hash.
        let scope = try HardwareValidationScope(environment: ["OPEN_SNEK_HW_RECOVER_JOURNAL": url.path])
        let target = try HardwareBluetoothTarget.recover(from: scope.journalURL)
        let client = BridgeClient(startHIDMonitoring: false, requiredBluetoothPeripheralIdentifier: target.peripheralIdentifier)
        let transport = await client.btVendorClient
        do {
            try await HardwareValidationSession.recover(deviceID: target.peripheralIdentifier.uuidString, journalURL: url, read: { try bus.read(target: target, transport: transport) }, restore: { try bus.write($0, transport: transport) })
            XCTAssertTrue(shouldSucceed)
        } catch { XCTAssertFalse(shouldSucceed, "Unexpected recovery failure: \(error)") }
        XCTAssertEqual(try HardwareValidationJournal<HardwareBluetoothSnapshot>.load(from: url).phase, shouldSucceed ? .restored : .restoreFailed)
    }

    private func makeTarget() throws -> HardwareBluetoothTarget {
        let device = MouseDevice(id: "process-local-generated-id", vendor_id: 0x068E, product_id: 0x00AC, product_name: "BSK V3 PRO", transport: .bluetooth, path_b64: "", serial: nil, firmware: nil)
        return try HardwareBluetoothTarget.capture(device: device, peripherals: [mouseA])
    }

    private func journalURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("bluetooth-recovery-\(UUID().uuidString).json") }
}

/// Routes every simulated read/write through the same pinned selector used by CoreBluetooth.
@MainActor private final class FakeBluetoothBus {
    var peripherals: [BLEVendorTransportClient.ConnectedPeripheralSummary]
    var currentIdentifier: UUID?
    var payloads: [UUID: Data]
    var writes: [UUID: Int] = [:]
    var ignoreWrites = false

    init(peripherals: [BLEVendorTransportClient.ConnectedPeripheralSummary], payloads: [UUID: Data]) {
        self.peripherals = peripherals
        self.payloads = payloads
    }

    func read(target: HardwareBluetoothTarget, transport: BLEVendorTransportClient) throws -> HardwareBluetoothSnapshot {
        let identifier = try route(target: target, transport: transport)
        return HardwareBluetoothSnapshot(target: target, payload: try XCTUnwrap(payloads[identifier]))
    }

    func write(_ snapshot: HardwareBluetoothSnapshot, transport: BLEVendorTransportClient) throws {
        let identifier = try route(target: snapshot.target, transport: transport)
        writes[identifier, default: 0] += 1
        if !ignoreWrites { payloads[identifier] = snapshot.payload }
    }

    private func route(target: HardwareBluetoothTarget, transport: BLEVendorTransportClient) throws -> UUID {
        switch transport.selectConnection(from: peripherals, preferredName: target.device.product_name, currentIdentifier: currentIdentifier, isReady: currentIdentifier != nil) {
        case .connect(let identifier): currentIdentifier = identifier
        case .reuse: break
        case .unavailable, .wait: throw HardwareValidationSession.failure("Selected peripheral unavailable")
        }
        return try XCTUnwrap(currentIdentifier)
    }
}
