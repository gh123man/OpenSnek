import Foundation
import CoreBluetooth
import OpenSnekCore
import OpenSnekProtocols

/// Restarts a completion deadline whenever a BLE response remains active.
/// Callers serialize access on the owning transport queue.
final class BLEVendorResponseIdleTimer: @unchecked Sendable {
    typealias Scheduler = @Sendable (DispatchWorkItem) -> Void

    private let scheduler: Scheduler
    private let onIdle: @Sendable () -> Void
    private var workItem: DispatchWorkItem?

    convenience init(queue: DispatchQueue, idleInterval: TimeInterval, onIdle: @escaping @Sendable () -> Void) { self.init(scheduler: { item in queue.asyncAfter(deadline: .now() + idleInterval, execute: item) }, onIdle: onIdle) }

    init(scheduler: @escaping Scheduler, onIdle: @escaping @Sendable () -> Void) {
        self.scheduler = scheduler
        self.onIdle = onIdle
    }

    func restart() {
        workItem?.cancel()
        let item = DispatchWorkItem(block: onIdle)
        workItem = item
        scheduler(item)
    }

    func cancel() {
        workItem?.cancel()
        workItem = nil
    }
}

/// Coordinates BLE vendor transport client operations.
public final class BLEVendorTransportClient: NSObject, @unchecked Sendable {
    /// Stores connected peripheral summary data.
    public struct ConnectedPeripheralSummary: Sendable {
        public let name: String?
        public let identifier: UUID

        public init(name: String?, identifier: UUID) {
            self.name = name
            self.identifier = identifier
        }
    }

    private static let responseIdleInterval: TimeInterval = 0.12

    private let queue = DispatchQueue(label: "open.snek.bt.vendor")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    private var notifications: [Data] = []
    private var writeQueue: [Data] = []
    private var completion: ((Result<[Data], any Error>) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?
    private var isNotifyReady = false
    private var preferredPeripheralName: String?
    private lazy var responseIdleTimer = BLEVendorResponseIdleTimer(queue: queue, idleInterval: Self.responseIdleInterval) { [weak self] in
        guard let self else { return }
        self.finish(.success(self.notifications))
    }

    public func run(writes: [Data], timeout: TimeInterval = 2.2, preferredPeripheralName: String? = nil) async throws -> [Data] {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Data], any Error>) in
            queue.async {
                guard self.completion == nil else {
                    continuation.resume(throwing: BridgeError.commandFailed("BT vendor busy"))
                    return
                }

                self.notifications = []
                self.writeQueue = writes
                self.responseIdleTimer.cancel()
                self.timeoutWorkItem?.cancel()
                self.timeoutWorkItem = nil
                self.preferredPeripheralName = preferredPeripheralName?.trimmingCharacters(in: .whitespacesAndNewlines)

                self.completion = { output in continuation.resume(with: output) }

                if self.central == nil { self.central = CBCentralManager(delegate: self, queue: self.queue) } else { self.ensureConnectedAndReady() }

                let timeoutItem = DispatchWorkItem { [weak self] in self?.finish(.failure(BridgeError.commandFailed("BT vendor timeout"))) }
                self.timeoutWorkItem = timeoutItem
                self.queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
            }
        }
    }

    public func currentPeripheralSummary() async -> ConnectedPeripheralSummary? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let peripheral = self.peripheral, peripheral.state == .connected else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ConnectedPeripheralSummary(name: peripheral.name, identifier: peripheral.identifier))
            }
        }
    }

    public func connectedPeripheralSummaries() async -> [ConnectedPeripheralSummary]? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let central = self.central else {
                    continuation.resume(returning: nil)
                    return
                }
                guard central.state == .poweredOn else {
                    continuation.resume(returning: nil)
                    return
                }

                let peripherals = central.retrieveConnectedPeripherals(withServices: [CBUUID(nsuuid: BLEVendorProtocol.serviceUUID)])
                continuation.resume(returning: peripherals.map { peripheral in ConnectedPeripheralSummary(name: peripheral.name, identifier: peripheral.identifier) })
            }
        }
    }

    private func sendNextWriteIfReady() {
        guard isNotifyReady, let peripheral, let writeChar, !writeQueue.isEmpty else {
            scheduleFinishIfIdle()
            return
        }

        responseIdleTimer.cancel()
        let next = writeQueue.removeFirst()
        peripheral.writeValue(next, for: writeChar, type: .withResponse)
    }

    private func scheduleFinishIfIdle() {
        guard writeQueue.isEmpty else { return }
        responseIdleTimer.restart()
    }

    private func fail(_ message: String) { finish(.failure(BridgeError.commandFailed("BT vendor: \(message)"))) }

    private func ensureConnectedAndReady() {
        guard let central else { return }
        guard central.state == .poweredOn else { return }

        if isNotifyReady, let peripheral, peripheral.state == .connected, writeChar != nil, notifyChar != nil, peripheralMatchesPreference(peripheral) {
            sendNextWriteIfReady()
            return
        }

        let peripherals = central.retrieveConnectedPeripherals(withServices: [CBUUID(nsuuid: BLEVendorProtocol.serviceUUID)])
        guard let connected = preferredPeripheral(from: peripherals) else {
            queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, self.completion != nil else { return }
                self.ensureConnectedAndReady()
            }
            return
        }

        if peripheral?.identifier != connected.identifier {
            isNotifyReady = false
            writeChar = nil
            notifyChar = nil
        }
        peripheral = connected
        connected.delegate = self
        if connected.state == .connected { connected.discoverServices([CBUUID(nsuuid: BLEVendorProtocol.serviceUUID)]) } else { central.connect(connected) }
    }

    private func preferredPeripheral(from peripherals: [CBPeripheral]) -> CBPeripheral? {
        guard let preferredPeripheralName, !preferredPeripheralName.isEmpty else { return peripherals.first }

        return peripherals.first(where: { peripheralMatchesPreference($0) }) ?? peripherals.first
    }

    private func peripheralMatchesPreference(_ peripheral: CBPeripheral) -> Bool {
        guard let preferredPeripheralName, !preferredPeripheralName.isEmpty else { return true }
        return BluetoothNameMatcher.looselyMatches(peripheral.name, preferredPeripheralName)
    }

    private func finish(_ output: Result<[Data], Error>) {
        guard let completion else { return }
        self.completion = nil
        responseIdleTimer.cancel()
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        completion(output)
    }
}

/// Adds scoped helpers for `BLEVendorTransportClient`.
extension BLEVendorTransportClient: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: ensureConnectedAndReady()
        case .unauthorized: fail("Bluetooth access unauthorized; allow OpenSnek in System Settings > Privacy & Security > Bluetooth")
        case .poweredOff: fail("Bluetooth is powered off")
        case .unsupported: fail("Bluetooth is unsupported on this Mac")
        case .resetting, .unknown: break
        @unknown default: fail("Bluetooth state is unsupported")
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { peripheral.discoverServices([CBUUID(nsuuid: BLEVendorProtocol.serviceUUID)]) }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isNotifyReady = false
        fail("Failed to connect: \(error?.localizedDescription ?? "unknown")")
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isNotifyReady = false
        writeChar = nil
        notifyChar = nil
        if self.peripheral?.identifier == peripheral.identifier { self.peripheral = nil }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            fail("Service discovery failed: \(error.localizedDescription)")
            return
        }
        for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            fail("Characteristic discovery failed: \(error.localizedDescription)")
            return
        }

        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == CBUUID(nsuuid: BLEVendorProtocol.writeUUID) { writeChar = characteristic }
            if characteristic.uuid == CBUUID(nsuuid: BLEVendorProtocol.notifyUUID) { notifyChar = characteristic }
        }

        if let notifyChar { peripheral.setNotifyValue(true, for: notifyChar) }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            fail("Enable notify failed: \(error.localizedDescription)")
            return
        }
        if characteristic.isNotifying {
            isNotifyReady = true
            sendNextWriteIfReady()
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            fail("Write failed: \(error.localizedDescription)")
            return
        }
        sendNextWriteIfReady()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            fail("Notify update failed: \(error.localizedDescription)")
            return
        }
        guard let value = characteristic.value else { return }
        notifications.append(value)
        scheduleFinishIfIdle()
    }
}
