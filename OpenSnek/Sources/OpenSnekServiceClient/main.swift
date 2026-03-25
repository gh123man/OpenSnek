import Foundation
import Network
import OpenSnekAppSupport
import OpenSnekCore

@main
enum OpenSnekServiceClient {
    static func main() async {
        let cli = ServiceClientCLI(arguments: Array(CommandLine.arguments.dropFirst()))
        let exitCode = await cli.run()
        Foundation.exit(exitCode)
    }
}

private struct ServiceEndpoint {
    let processIdentifier: Int32
    let port: NWEndpoint.Port
}

private actor ServiceDebugClient {
    private let host: NWEndpoint.Host = .ipv4(.loopback)
    private let port: NWEndpoint.Port
    private var latestPresence: CrossProcessClientPresence
    private var remoteSubscription: ServiceDebugSubscription?

    init(port: NWEndpoint.Port, sourceProcessID: Int32) {
        self.port = port
        latestPresence = CrossProcessClientPresence(
            sourceProcessID: sourceProcessID,
            selectedDeviceID: nil
        )
    }

    func ping() async -> Bool {
        (try? await request(method: .ping, payload: nil, responseType: Bool.self)) ?? false
    }

    func listDevices() async throws -> [MouseDevice] {
        try await request(method: .listDevices, payload: nil, responseType: [MouseDevice].self)
    }

    func readState(device: MouseDevice) async throws -> MouseState {
        try await request(
            method: .readState,
            payload: try BackendCodec.encode(device),
            responseType: MouseState.self
        )
    }

    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot? {
        try await request(
            method: .readDpiStagesFast,
            payload: try BackendCodec.encode(device),
            responseType: DpiFastSnapshot?.self
        )
    }

    func dpiUpdateTransportStatus(device: MouseDevice) async throws -> DpiUpdateTransportStatus {
        try await request(
            method: .dpiUpdateTransportStatus,
            payload: try BackendCodec.encode(device),
            responseType: DpiUpdateTransportStatus.self
        )
    }

    func hidAccessStatus() async throws -> HIDAccessStatus {
        try await request(
            method: .hidAccessStatus,
            payload: try BackendCodec.encode(true),
            responseType: HIDAccessStatus.self
        )
    }

    func updatePresence(selectedDeviceID: String?) async {
        let presence = CrossProcessClientPresence(
            sourceProcessID: latestPresence.sourceProcessID,
            selectedDeviceID: selectedDeviceID
        )
        latestPresence = presence
        guard let remoteSubscription else { return }
        await remoteSubscription.updatePresence(presence)
    }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        if let remoteSubscription {
            await remoteSubscription.stop()
        }
        let remoteSubscription = ServiceDebugSubscription(
            host: host,
            port: port,
            initialPresence: latestPresence
        )
        self.remoteSubscription = remoteSubscription
        return await remoteSubscription.makeStream()
    }

    private func request<T: Decodable & Sendable>(
        method: BackgroundServiceMethod,
        payload: Data?,
        responseType: T.Type
    ) async throws -> T {
        let connection = NWConnection(host: host, port: port, using: BackgroundServiceTransport.clientParameters())
        defer { connection.cancel() }

        try await BackgroundServiceTransport.awaitReady(connection: connection)

        let request = BackgroundServiceRequestEnvelope(method: method, payload: payload)
        try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(request), over: connection)

        let responseData = try await BackgroundServiceTransport.receiveFrame(from: connection)
        let response = try BackendCodec.decode(BackgroundServiceResponseEnvelope.self, from: responseData)
        if let error = response.error {
            throw NSError(domain: "OpenSnek.ServiceClient", code: 1, userInfo: [
                NSLocalizedDescriptionKey: error
            ])
        }
        guard let payload = response.payload else {
            throw NSError(domain: "OpenSnek.ServiceClient", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Background service returned no payload"
            ])
        }
        return try BackendCodec.decode(responseType, from: payload)
    }
}

private actor ServiceDebugSubscription {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private var latestPresence: CrossProcessClientPresence
    private var connection: NWConnection?
    private var isReady = false
    private var readinessWaiters: [CheckedContinuation<Void, Never>] = []

    init(host: NWEndpoint.Host, port: NWEndpoint.Port, initialPresence: CrossProcessClientPresence) {
        self.host = host
        self.port = port
        latestPresence = initialPresence
    }

    func makeStream() async -> AsyncStream<BackendStateUpdate> {
        let stream = AsyncStream { continuation in
            let task = Task {
                await self.run(continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task {
                    await self.stop()
                }
            }
        }
        await waitUntilReady()
        return stream
    }

    func updatePresence(_ presence: CrossProcessClientPresence) async {
        latestPresence = presence
        guard let connection else { return }
        do {
            try await sendClientPresence(presence, over: connection)
        } catch {
            connection.cancel()
            if self.connection === connection {
                self.connection = nil
            }
        }
    }

    func stop() {
        connection?.cancel()
        connection = nil
        resumeReadinessWaiters()
    }

    private func run(continuation: AsyncStream<BackendStateUpdate>.Continuation) async {
        let connection = NWConnection(host: host, port: port, using: BackgroundServiceTransport.clientParameters())
        self.connection = connection

        defer {
            connection.cancel()
            if self.connection === connection {
                self.connection = nil
            }
            continuation.finish()
        }

        do {
            try await BackgroundServiceTransport.awaitReady(connection: connection)

            let subscribeRequest = BackgroundServiceRequestEnvelope(
                method: .subscribeStateUpdates,
                payload: try BackendCodec.encode(
                    StreamSubscriptionRequest(
                        sourceProcessID: latestPresence.sourceProcessID,
                        selectedDeviceID: latestPresence.selectedDeviceID
                    )
                )
            )
            try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(subscribeRequest), over: connection)

            let responseData = try await BackgroundServiceTransport.receiveFrame(from: connection)
            let response = try BackendCodec.decode(BackgroundServiceResponseEnvelope.self, from: responseData)
            if let error = response.error {
                throw NSError(domain: "OpenSnek.ServiceClient", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: error
                ])
            }
            isReady = true
            resumeReadinessWaiters()

            while !Task.isCancelled {
                let frame = try await BackgroundServiceTransport.receiveFrame(from: connection)
                let envelope = try BackendCodec.decode(BackgroundServiceStreamServerEnvelope.self, from: frame)
                switch envelope.event {
                case .stateUpdate:
                    guard let payload = envelope.payload else {
                        throw BackgroundServiceTransportError.missingPayload
                    }
                    continuation.yield(try BackendCodec.decode(BackendStateUpdate.self, from: payload))
                case .openSettingsRequested:
                    continuation.yield(.openSettingsRequested)
                }
            }
        } catch {
            resumeReadinessWaiters()
            if !Task.isCancelled {
                fputs("[service-client] subscription ended: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    private func sendClientPresence(_ presence: CrossProcessClientPresence, over connection: NWConnection) async throws {
        let envelope = BackgroundServiceStreamClientEnvelope(
            event: .clientPresence,
            payload: try BackendCodec.encode(presence)
        )
        try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(envelope), over: connection)
    }

    private func waitUntilReady() async {
        guard !isReady else { return }
        await withCheckedContinuation { continuation in
            readinessWaiters.append(continuation)
        }
    }

    private func resumeReadinessWaiters() {
        let waiters = readinessWaiters
        readinessWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

private actor WatchState {
    private(set) var devices: [MouseDevice] = []
    private(set) var statesByDeviceID: [String: MouseState] = [:]

    func apply(_ update: BackendStateUpdate) {
        switch update {
        case .deviceList(let devices, _):
            self.devices = devices
        case .deviceState(let deviceID, let state, _):
            statesByDeviceID[deviceID] = state
        case .dpiTransportStatus:
            break
        case .snapshot(let snapshot):
            devices = snapshot.devices
            statesByDeviceID = snapshot.stateByDeviceID
        case .openSettingsRequested:
            break
        }
    }

    func replaceDevices(_ devices: [MouseDevice]) {
        self.devices = devices
    }

    func device(matching token: String) -> MouseDevice? {
        if let index = Int(token), devices.indices.contains(index) {
            return devices[index]
        }
        return devices.first(where: { $0.id == token })
    }

    func deviceTable() -> String {
        guard !devices.isEmpty else { return "no devices" }
        return devices.enumerated().map { index, device in
            let dpi: String
            if let value = statesByDeviceID[device.id]?.dpi?.x {
                dpi = String(value)
            } else {
                dpi = "-"
            }
            return "[\(index)] \(device.product_name) id=\(device.id) transport=\(device.transport.rawValue) dpi=\(dpi)"
        }.joined(separator: "\n")
    }
}

private struct ServiceClientCLI {
    let arguments: [String]

    func run() async -> Int32 {
        do {
            let parsed = try ParsedArguments(arguments: arguments)
            let command = parsed.command ?? "watch"
            switch command {
            case "help", "--help", "-h":
                print(Self.usage)
            case "status":
                try await runStatus(parsed: parsed)
            case "watch":
                try await runWatch(parsed: parsed)
            default:
                throw CLIError("Unknown command '\(command)'")
            }
            return 0
        } catch {
            fputs("error: \(error.localizedDescription)\n", stderr)
            fputs("\(Self.usage)\n", stderr)
            return 1
        }
    }

    private func runStatus(parsed: ParsedArguments) async throws {
        let endpoint = try resolveEndpoint(parsed: parsed)
        let client = ServiceDebugClient(port: endpoint.port, sourceProcessID: Int32(ProcessInfo.processInfo.processIdentifier))
        guard await client.ping() else {
            throw CLIError("Background service ping failed on port \(endpoint.port.rawValue)")
        }
        print("service pid=\(endpoint.processIdentifier) port=\(endpoint.port.rawValue)")
        let hid = try await client.hidAccessStatus()
        print("hid-access=\(hid.diagnosticsLabel) host=\"\(hid.hostLabel)\"")
        let devices = try await client.listDevices()
        if devices.isEmpty {
            print("devices: none")
        } else {
            for (index, device) in devices.enumerated() {
                print("[\(index)] \(device.product_name) id=\(device.id) transport=\(device.transport.rawValue)")
            }
        }
    }

    private func runWatch(parsed: ParsedArguments) async throws {
        let endpoint = try resolveEndpoint(parsed: parsed)
        let sourceProcessID = Int32(ProcessInfo.processInfo.processIdentifier)
        let client = ServiceDebugClient(port: endpoint.port, sourceProcessID: sourceProcessID)
        guard await client.ping() else {
            throw CLIError("Background service ping failed on port \(endpoint.port.rawValue)")
        }

        let watchState = WatchState()
        let devices = try await client.listDevices()
        await watchState.replaceDevices(devices)

        print("service pid=\(endpoint.processIdentifier) port=\(endpoint.port.rawValue)")
        print("watching state updates")
        print("commands: help | list | presence <index|device-id|none> | read-state <index|device-id> | fast <index|device-id> | transport <index|device-id> | quit")
        if !devices.isEmpty {
            print(await watchState.deviceTable())
        }

        let updates = await client.stateUpdates()
        let updateTask = Task {
            for await update in updates {
                await watchState.apply(update)
                print(Self.describe(update))
            }
        }

        defer {
            updateTask.cancel()
        }

        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let command = parts.first else { continue }

            switch command {
            case "help":
                print("commands: help | list | presence <index|device-id|none> | read-state <index|device-id> | fast <index|device-id> | transport <index|device-id> | quit")
            case "list":
                let listed = try await client.listDevices()
                await watchState.replaceDevices(listed)
                print(await watchState.deviceTable())
            case "presence":
                guard parts.count == 2 else {
                    print("usage: presence <index|device-id|none>")
                    continue
                }
                if parts[1] == "none" {
                    await client.updatePresence(selectedDeviceID: nil)
                    print("presence selectedDeviceID=nil")
                    continue
                }
                guard let device = await watchState.device(matching: parts[1]) else {
                    print("unknown device '\(parts[1])'")
                    continue
                }
                await client.updatePresence(selectedDeviceID: device.id)
                print("presence selectedDeviceID=\(device.id)")
            case "read-state":
                guard parts.count == 2 else {
                    print("usage: read-state <index|device-id>")
                    continue
                }
                guard let device = await watchState.device(matching: parts[1]) else {
                    print("unknown device '\(parts[1])'")
                    continue
                }
                let startedAt = Date()
                print("read-state start device=\(device.id)")
                let state = try await client.readState(device: device)
                let elapsed = Date().timeIntervalSince(startedAt)
                print("read-state ok device=\(device.id) elapsed=\(String(format: "%.3f", elapsed))s dpi=\(state.dpi?.x ?? -1) battery=\(state.battery_percent ?? -1)")
            case "fast":
                guard parts.count == 2 else {
                    print("usage: fast <index|device-id>")
                    continue
                }
                guard let device = await watchState.device(matching: parts[1]) else {
                    print("unknown device '\(parts[1])'")
                    continue
                }
                let startedAt = Date()
                print("fast-read start device=\(device.id)")
                let snapshot = try await client.readDpiStagesFast(device: device)
                let elapsed = Date().timeIntervalSince(startedAt)
                print("fast-read ok device=\(device.id) elapsed=\(String(format: "%.3f", elapsed))s snapshot=\(String(describing: snapshot))")
            case "transport":
                guard parts.count == 2 else {
                    print("usage: transport <index|device-id>")
                    continue
                }
                guard let device = await watchState.device(matching: parts[1]) else {
                    print("unknown device '\(parts[1])'")
                    continue
                }
                let startedAt = Date()
                print("transport-status start device=\(device.id)")
                let status = try await client.dpiUpdateTransportStatus(device: device)
                let elapsed = Date().timeIntervalSince(startedAt)
                print("transport-status ok device=\(device.id) elapsed=\(String(format: "%.3f", elapsed))s status=\(status.rawValue)")
            case "quit", "exit":
                return
            default:
                print("unknown command '\(command)'")
            }
        }
    }

    private func resolveEndpoint(parsed: ParsedArguments) throws -> ServiceEndpoint {
        if let portValue = parsed.port {
            guard let port = NWEndpoint.Port(rawValue: UInt16(portValue)) else {
                throw CLIError("Invalid --port value \(portValue)")
            }
            return ServiceEndpoint(processIdentifier: Int32(parsed.processIdentifier ?? 0), port: port)
        }
        let defaults = UserDefaults.standard
        let pidValue = defaults.integer(forKey: BackgroundServiceDefaultsKeys.pid)
        let portValue = defaults.integer(forKey: BackgroundServiceDefaultsKeys.port)
        guard pidValue > 0 else {
            throw CLIError("No running background service PID in defaults")
        }
        guard let port = NWEndpoint.Port(rawValue: UInt16(portValue)), portValue > 0 else {
            throw CLIError("No running background service port in defaults")
        }
        return ServiceEndpoint(processIdentifier: Int32(pidValue), port: port)
    }

    private static func describe(_ update: BackendStateUpdate) -> String {
        let prefix = "[\(timestampString(Date()))]"
        switch update {
        case .deviceList(let devices, let updatedAt):
            let ids = devices.map(\.id).joined(separator: ",")
            return "\(prefix) deviceList updatedAt=\(timestampString(updatedAt)) ids=[\(ids)]"
        case .deviceState(let deviceID, let state, let updatedAt):
            return "\(prefix) deviceState device=\(deviceID) updatedAt=\(timestampString(updatedAt)) dpi=\(state.dpi?.x ?? -1) battery=\(state.battery_percent ?? -1)"
        case .dpiTransportStatus(let deviceID, let status, let updatedAt):
            return "\(prefix) dpiTransportStatus device=\(deviceID) updatedAt=\(timestampString(updatedAt)) status=\(status.rawValue)"
        case .snapshot(let snapshot):
            let ids = snapshot.devices.map(\.id).joined(separator: ",")
            return "\(prefix) snapshot ids=[\(ids)] states=\(snapshot.stateByDeviceID.keys.sorted())"
        case .openSettingsRequested:
            return "\(prefix) openSettingsRequested"
        }
    }

    private static func timestampString(_ date: Date) -> String {
        String(format: "%.3f", date.timeIntervalSince1970)
    }

    private static let usage = """
    usage:
      swift run --package-path OpenSnek OpenSnekServiceClient status
      swift run --package-path OpenSnek OpenSnekServiceClient watch
      swift run --package-path OpenSnek OpenSnekServiceClient status --port 50897
      swift run --package-path OpenSnek OpenSnekServiceClient watch --port 50897 --pid 45217
    """
}

private struct CLIError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private struct ParsedArguments {
    let command: String?
    let port: Int?
    let processIdentifier: Int?

    init(arguments: [String]) throws {
        var remaining: [String] = []
        var port: Int?
        var processIdentifier: Int?

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--port":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]) else {
                    throw CLIError("Expected integer after --port")
                }
                port = value
            case "--pid":
                index += 1
                guard index < arguments.count, let value = Int(arguments[index]) else {
                    throw CLIError("Expected integer after --pid")
                }
                processIdentifier = value
            default:
                remaining.append(argument)
            }
            index += 1
        }

        command = remaining.first
        self.port = port
        self.processIdentifier = processIdentifier
    }
}
