import Foundation
import CoreBluetooth

private enum ProbeError: LocalizedError {
    case usage(String)
    case protocolError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .usage(let text): return text
        case .protocolError(let text): return text
        case .timeout: return "Operation timed out"
        }
    }
}

private struct DpiSnapshot: Equatable {
    let active: Int
    let count: Int
    let slots: [Int]
    let marker: UInt8

    var values: [Int] { Array(slots.prefix(count)) }
}

private enum VendorProtocol {
    static let serviceUUID = UUID(uuidString: "52401523-F97C-7F90-0E7F-6C6F4E36DB1C")!
    static let writeUUID = UUID(uuidString: "52401524-F97C-7F90-0E7F-6C6F4E36DB1C")!
    static let notifyUUID = UUID(uuidString: "52401525-F97C-7F90-0E7F-6C6F4E36DB1C")!

    static let dpiGet: [UInt8] = [0x0B, 0x84, 0x01, 0x00]
    static let dpiSet: [UInt8] = [0x0B, 0x04, 0x01, 0x00]

    static func readHeader(req: UInt8, key: [UInt8]) -> Data {
        Data([req, 0x00, 0x00, 0x00] + key)
    }

    static func writeHeader(req: UInt8, payloadLength: UInt8, key: [UInt8]) -> Data {
        Data([req, payloadLength, 0x00, 0x00] + key)
    }

    struct NotifyHeader {
        let req: UInt8
        let length: Int
        let status: UInt8

        init?(data: Data) {
            guard data.count >= 8 else { return nil }
            req = data[0]
            length = Int(data[1])
            status = data[7]
        }
    }

    static func parsePayloadFrames(notifies: [Data], req: UInt8) -> Data? {
        guard let headerIndex = notifies.firstIndex(where: { frame in
            guard let hdr = NotifyHeader(data: frame) else { return false }
            return hdr.req == req && [0x02, 0x03, 0x05].contains(hdr.status)
        }), let header = NotifyHeader(data: notifies[headerIndex]), header.status == 0x02
        else { return nil }

        let continuation: [Data]
        if headerIndex + 1 < notifies.count {
            continuation = Array(notifies[(headerIndex + 1)...]).filter { $0.count == 20 }
        } else {
            continuation = []
        }
        let payload = continuation.reduce(into: Data()) { partialResult, frame in
            partialResult.append(frame)
        }
        if header.length == 0 { return Data() }
        return payload.prefix(header.length)
    }

    static func parseDpiSnapshot(_ payload: Data) -> DpiSnapshot? {
        guard payload.count >= 2 else { return nil }
        let active = Int(payload[0])
        let count = max(1, min(5, Int(payload[1])))

        var slots: [Int] = [800, 1600, 2400, 3200, 6400]
        var marker: UInt8 = 0x03

        if payload.count >= 37 {
            for i in 0..<5 {
                let off = 2 + (i * 7)
                guard off + 6 < payload.count else { break }
                let dpi = Int(payload[off + 1]) | (Int(payload[off + 2]) << 8)
                slots[i] = dpi
                marker = payload[off + 6]
            }
        } else {
            for i in 0..<count {
                let off = 2 + (i * 7)
                guard off + 4 < payload.count else { break }
                let dpi = Int(payload[off + 1]) | (Int(payload[off + 2]) << 8)
                slots[i] = dpi
            }
            if count == 1 {
                slots = Array(repeating: slots[0], count: 5)
            }
            if payload.count > 2 + (count * 7) {
                marker = payload[min(payload.count - 1, 2 + count * 7)]
            }
        }

        return DpiSnapshot(active: max(0, min(count - 1, active)), count: count, slots: slots, marker: marker)
    }

    static func buildDpiPayload(active: Int, count: Int, slots: [Int], marker: UInt8) -> Data {
        let clippedCount = max(1, min(5, count))
        var payload = [UInt8](repeating: 0, count: 38)
        payload[0] = UInt8(max(0, min(clippedCount - 1, active)))
        payload[1] = UInt8(clippedCount)
        var off = 2
        for i in 0..<5 {
            let dpi = max(100, min(30_000, slots[i]))
            payload[off] = UInt8(i)
            payload[off + 1] = UInt8(dpi & 0xFF)
            payload[off + 2] = UInt8((dpi >> 8) & 0xFF)
            payload[off + 3] = UInt8(dpi & 0xFF)
            payload[off + 4] = UInt8((dpi >> 8) & 0xFF)
            payload[off + 5] = 0x00
            payload[off + 6] = i == 4 ? marker : 0x00
            off += 7
        }
        payload[37] = 0x00
        return Data(payload)
    }

    static func mergedSlots(current: [Int], requestedCount: Int, requested: [Int]) -> [Int] {
        var slots = Array(current.prefix(5))
        if slots.count < 5 { slots += Array(repeating: 800, count: 5 - slots.count) }
        let count = max(1, min(5, requestedCount))
        if count == 1, let first = requested.first {
            return Array(repeating: first, count: 5)
        }
        for i in 0..<count where i < requested.count {
            slots[i] = requested[i]
        }
        return slots
    }
}

private final class VendorClient: NSObject, @unchecked Sendable {
    private let queue = DispatchQueue(label: "open.snek.probe.bt")
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var isNotifyReady = false

    private var writeQueue: [Data] = []
    private var notifications: [Data] = []
    private var completion: ((Result<[Data], any Error>) -> Void)?
    private var timeoutWorkItem: DispatchWorkItem?
    private var finishWorkItem: DispatchWorkItem?

    func run(writes: [Data], timeout: TimeInterval = 1.0) async throws -> [Data] {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Data], any Error>) in
            queue.async {
                guard self.completion == nil else {
                    continuation.resume(throwing: ProbeError.protocolError("Probe busy"))
                    return
                }

                self.writeQueue = writes
                self.notifications = []
                self.timeoutWorkItem?.cancel()
                self.finishWorkItem?.cancel()
                self.timeoutWorkItem = nil
                self.finishWorkItem = nil

                self.completion = { result in
                    continuation.resume(with: result)
                }

                if self.central == nil {
                    self.central = CBCentralManager(delegate: self, queue: self.queue)
                } else {
                    self.ensureReady()
                }

                let timeoutItem = DispatchWorkItem { [weak self] in
                    self?.finish(.failure(ProbeError.timeout))
                }
                self.timeoutWorkItem = timeoutItem
                self.queue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
            }
        }
    }

    private func ensureReady() {
        guard let central else { return }
        guard central.state == .poweredOn else { return }
        if isNotifyReady, peripheral?.state == .connected, writeChar != nil, notifyChar != nil {
            sendNextWrite()
            return
        }

        let connected = central.retrieveConnectedPeripherals(withServices: [CBUUID(nsuuid: VendorProtocol.serviceUUID)])
        guard let first = connected.first else {
            finish(.failure(ProbeError.protocolError("No connected peripheral with Razer vendor service")))
            return
        }
        peripheral = first
        first.delegate = self
        if first.state == .connected {
            first.discoverServices([CBUUID(nsuuid: VendorProtocol.serviceUUID)])
        } else {
            central.connect(first)
        }
    }

    private func sendNextWrite() {
        guard isNotifyReady, let peripheral, let writeChar, !writeQueue.isEmpty else {
            scheduleFinish()
            return
        }
        finishWorkItem?.cancel()
        let next = writeQueue.removeFirst()
        peripheral.writeValue(next, for: writeChar, type: .withResponse)
    }

    private func scheduleFinish() {
        guard writeQueue.isEmpty else { return }
        finishWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(.success(self.notifications))
        }
        finishWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.22, execute: item)
    }

    private func finish(_ result: Result<[Data], any Error>) {
        guard let completion else { return }
        self.completion = nil
        timeoutWorkItem?.cancel()
        finishWorkItem?.cancel()
        timeoutWorkItem = nil
        finishWorkItem = nil
        completion(result)
    }
}

extension VendorClient: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        ensureReady()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([CBUUID(nsuuid: VendorProtocol.serviceUUID)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        isNotifyReady = false
        finish(.failure(error ?? ProbeError.protocolError("Failed to connect peripheral")))
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        isNotifyReady = false
        writeChar = nil
        notifyChar = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            finish(.failure(error))
            return
        }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error {
            finish(.failure(error))
            return
        }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == CBUUID(nsuuid: VendorProtocol.writeUUID) {
                writeChar = characteristic
            }
            if characteristic.uuid == CBUUID(nsuuid: VendorProtocol.notifyUUID) {
                notifyChar = characteristic
            }
        }
        if let notifyChar {
            peripheral.setNotifyValue(true, for: notifyChar)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            finish(.failure(error))
            return
        }
        if characteristic.isNotifying {
            isNotifyReady = true
            sendNextWrite()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            finish(.failure(error))
            return
        }
        sendNextWrite()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            finish(.failure(error))
            return
        }
        guard let value = characteristic.value else { return }
        notifications.append(value)
    }
}

private actor ProbeBridge {
    private let vendor = VendorClient()
    private var reqID: UInt8 = 0x30

    private func nextReq() -> UInt8 {
        defer { reqID = reqID &+ 1 }
        return reqID
    }

    func readDpi() async throws -> DpiSnapshot {
        for attempt in 0..<3 {
            let req = nextReq()
            let header = VendorProtocol.readHeader(req: req, key: VendorProtocol.dpiGet)
            let notifies = try await vendor.run(writes: [header], timeout: 1.2)
            if let payload = VendorProtocol.parsePayloadFrames(notifies: notifies, req: req),
               let snapshot = VendorProtocol.parseDpiSnapshot(payload) {
                return snapshot
            }
            if attempt < 2 {
                try await Task.sleep(nanoseconds: 60_000_000)
            }
        }
        throw ProbeError.protocolError("Failed to parse DPI payload")
    }

    func setDpi(active: Int, values: [Int], verifyRetries: Int, verifyDelayMs: Int) async throws -> DpiSnapshot {
        let current = try await readDpi()
        let count = max(1, min(5, values.count))
        let mergedSlots = VendorProtocol.mergedSlots(current: current.slots, requestedCount: count, requested: values)
        let expected = DpiSnapshot(
            active: max(0, min(count - 1, active)),
            count: count,
            slots: mergedSlots,
            marker: current.marker
        )
        let payload = VendorProtocol.buildDpiPayload(
            active: expected.active,
            count: expected.count,
            slots: expected.slots,
            marker: expected.marker
        )

        let req = nextReq()
        let header = VendorProtocol.writeHeader(req: req, payloadLength: 0x26, key: VendorProtocol.dpiSet)
        let notifies = try await vendor.run(
            writes: [header, payload.prefix(20), payload.suffix(from: 20)],
            timeout: 1.0
        )
        guard let ack = notifies.compactMap({ VendorProtocol.NotifyHeader(data: $0) }).first(where: { $0.req == req }),
              ack.status == 0x02
        else {
            throw ProbeError.protocolError("DPI set did not return success ACK")
        }

        let retries = max(1, verifyRetries)
        for attempt in 0..<retries {
            let readback = try await readDpi()
            if readback.active == expected.active && readback.values == expected.values {
                return readback
            }
            if attempt < retries - 1 {
                try await Task.sleep(nanoseconds: UInt64(max(0, verifyDelayMs)) * 1_000_000)
            }
        }
        throw ProbeError.protocolError("Readback mismatch after DPI set")
    }
}

@main
struct OpenSnekProbe {
    static func main() async {
        do {
            try await run()
            Foundation.exit(EXIT_SUCCESS)
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            throw ProbeError.usage(usageText)
        }
        let bridge = ProbeBridge()

        switch command {
        case "dpi-read":
            let snapshot = try await bridge.readDpi()
            print("active=\(snapshot.active + 1) count=\(snapshot.count) values=\(snapshot.values)")
        case "dpi-set":
            let parsed = try parseSetArgs(Array(args.dropFirst()))
            let snapshot = try await bridge.setDpi(
                active: parsed.active,
                values: parsed.values,
                verifyRetries: parsed.verifyRetries,
                verifyDelayMs: parsed.verifyDelayMs
            )
            print("applied active=\(snapshot.active + 1) values=\(snapshot.values)")
        case "dpi-cycle":
            let parsed = try parseCycleArgs(Array(args.dropFirst()))
            for i in 0..<parsed.loops {
                let values = parsed.sequence[i % parsed.sequence.count]
                let snapshot = try await bridge.setDpi(
                    active: parsed.active,
                    values: values,
                    verifyRetries: parsed.verifyRetries,
                    verifyDelayMs: parsed.verifyDelayMs
                )
                print("loop \(i + 1): active=\(snapshot.active + 1) values=\(snapshot.values)")
                if parsed.sleepMs > 0 {
                    try await Task.sleep(nanoseconds: UInt64(parsed.sleepMs) * 1_000_000)
                }
            }
        default:
            throw ProbeError.usage(usageText)
        }
    }

    private static var usageText: String {
        """
        Usage:
          OpenSnekProbe dpi-read
          OpenSnekProbe dpi-set --values 1600,6400 [--active 1] [--verify-retries 6] [--verify-delay-ms 120]
          OpenSnekProbe dpi-cycle --sequence 800,6400;1600,6400 --loops 10 [--active 1] [--sleep-ms 120]
        """
    }

    private static func parseSetArgs(_ args: [String]) throws -> (values: [Int], active: Int, verifyRetries: Int, verifyDelayMs: Int) {
        let flags = parseFlags(args)
        guard let valuesRaw = flags["--values"] else {
            throw ProbeError.usage("Missing --values\n\(usageText)")
        }
        let values = try parseValues(valuesRaw)
        let active = max(0, (Int(flags["--active"] ?? "1") ?? 1) - 1)
        let verifyRetries = Int(flags["--verify-retries"] ?? "6") ?? 6
        let verifyDelayMs = Int(flags["--verify-delay-ms"] ?? "120") ?? 120
        return (values, active, verifyRetries, verifyDelayMs)
    }

    private static func parseCycleArgs(_ args: [String]) throws -> (sequence: [[Int]], loops: Int, active: Int, sleepMs: Int, verifyRetries: Int, verifyDelayMs: Int) {
        let flags = parseFlags(args)
        guard let raw = flags["--sequence"] else {
            throw ProbeError.usage("Missing --sequence\n\(usageText)")
        }
        let sequence = try raw.split(separator: ";").map { try parseValues(String($0)) }
        guard !sequence.isEmpty else { throw ProbeError.usage("Empty --sequence") }
        let loops = max(1, Int(flags["--loops"] ?? "10") ?? 10)
        let active = max(0, (Int(flags["--active"] ?? "1") ?? 1) - 1)
        let sleepMs = max(0, Int(flags["--sleep-ms"] ?? "120") ?? 120)
        let verifyRetries = Int(flags["--verify-retries"] ?? "6") ?? 6
        let verifyDelayMs = Int(flags["--verify-delay-ms"] ?? "120") ?? 120
        return (sequence, loops, active, sleepMs, verifyRetries, verifyDelayMs)
    }

    private static func parseFlags(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0
        while i < args.count {
            let key = args[i]
            if key.hasPrefix("--"), i + 1 < args.count {
                result[key] = args[i + 1]
                i += 2
            } else {
                i += 1
            }
        }
        return result
    }

    private static func parseValues(_ raw: String) throws -> [Int] {
        let values = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let clipped = values.prefix(5).map { max(100, min(30_000, $0)) }
        guard !clipped.isEmpty else {
            throw ProbeError.usage("Invalid DPI values: \(raw)")
        }
        return clipped
    }
}
