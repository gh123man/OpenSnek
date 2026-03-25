import Foundation
import Network
import OpenSnekCore

public enum BackgroundServiceDefaultsKeys {
    public static let endpoint = "backgroundServiceEndpoint"
    public static let port = "backgroundServicePort"
    public static let pid = "backgroundServicePID"
}

public struct DpiFastSnapshot: Codable, Hashable, Sendable {
    public let active: Int
    public let values: [Int]

    public init(active: Int, values: [Int]) {
        self.active = active
        self.values = values
    }
}

public enum DpiUpdateTransportStatus: String, Codable, Equatable, Sendable {
    case unknown
    case listening
    case streamActive
    case pollingFallback
    case realTimeHID
    case unsupported

    public var diagnosticsLabel: String {
        switch self {
        case .unknown:
            return "Checking"
        case .listening:
            return "Listening for first HID event"
        case .streamActive:
            return "HID stream active"
        case .pollingFallback:
            return "Polling fallback active"
        case .realTimeHID:
            return "Real-time HID active"
        case .unsupported:
            return "Unsupported"
        }
    }
}

public enum HIDAccessAuthorization: String, Codable, Sendable {
    case unknown
    case granted
    case denied
    case unavailable
}

public struct HIDAccessStatus: Codable, Equatable, Sendable {
    public let authorization: HIDAccessAuthorization
    public let hostLabel: String
    public let bundleIdentifier: String?
    public let detail: String?

    public init(
        authorization: HIDAccessAuthorization,
        hostLabel: String,
        bundleIdentifier: String?,
        detail: String?
    ) {
        self.authorization = authorization
        self.hostLabel = hostLabel
        self.bundleIdentifier = bundleIdentifier
        self.detail = detail
    }

    public static func unknown(detail: String? = nil) -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .unknown,
            hostLabel: currentHostLabel(),
            bundleIdentifier: Bundle.main.bundleIdentifier,
            detail: detail
        )
    }

    public static func unavailable(detail: String? = nil) -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .unavailable,
            hostLabel: currentHostLabel(),
            bundleIdentifier: Bundle.main.bundleIdentifier,
            detail: detail
        )
    }

    public var isDenied: Bool {
        authorization == .denied
    }

    public var diagnosticsLabel: String {
        switch authorization {
        case .unknown:
            return "Checking"
        case .granted:
            return "Granted"
        case .denied:
            return "Denied"
        case .unavailable:
            return "Unavailable"
        }
    }

    private static func currentHostLabel(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> String {
        let processName = ProcessInfo.processInfo.processName
        let trimmed = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedBundleIdentifier = trimmed.isEmpty ? "io.opensnek.OpenSnek" : trimmed
        return "\(processName) (\(resolvedBundleIdentifier))"
    }
}

public struct SharedServiceSnapshot: Codable, Sendable {
    public let devices: [MouseDevice]
    public let stateByDeviceID: [String: MouseState]
    public let lastUpdatedByDeviceID: [String: Date]

    public init(
        devices: [MouseDevice],
        stateByDeviceID: [String: MouseState],
        lastUpdatedByDeviceID: [String: Date]
    ) {
        self.devices = devices
        self.stateByDeviceID = stateByDeviceID
        self.lastUpdatedByDeviceID = lastUpdatedByDeviceID
    }
}

public struct CrossProcessClientPresence: Codable, Sendable {
    public let sourceProcessID: Int32
    public let selectedDeviceID: String?

    public init(sourceProcessID: Int32, selectedDeviceID: String?) {
        self.sourceProcessID = sourceProcessID
        self.selectedDeviceID = selectedDeviceID
    }
}

public enum BackendStateUpdate: Codable, Sendable {
    case deviceList([MouseDevice], updatedAt: Date)
    case deviceState(deviceID: String, state: MouseState, updatedAt: Date)
    case dpiTransportStatus(deviceID: String, status: DpiUpdateTransportStatus, updatedAt: Date)
    case snapshot(SharedServiceSnapshot)
    case openSettingsRequested
}

public struct ApplyRequest: Codable, Sendable {
    public let device: MouseDevice
    public let patch: DevicePatch

    public init(device: MouseDevice, patch: DevicePatch) {
        self.device = device
        self.patch = patch
    }
}

public struct ButtonBindingReadRequest: Codable, Sendable {
    public let device: MouseDevice
    public let slot: Int
    public let profile: Int

    public init(device: MouseDevice, slot: Int, profile: Int) {
        self.device = device
        self.slot = slot
        self.profile = profile
    }
}

public struct StreamSubscriptionRequest: Codable, Sendable {
    public let sourceProcessID: Int32
    public let selectedDeviceID: String?

    public init(sourceProcessID: Int32, selectedDeviceID: String?) {
        self.sourceProcessID = sourceProcessID
        self.selectedDeviceID = selectedDeviceID
    }
}

public enum BackgroundServiceStreamClientEvent: String, Codable, Sendable {
    case clientPresence
}

public struct BackgroundServiceStreamClientEnvelope: Codable, Sendable {
    public let event: BackgroundServiceStreamClientEvent
    public let payload: Data?

    public init(event: BackgroundServiceStreamClientEvent, payload: Data?) {
        self.event = event
        self.payload = payload
    }
}

public enum BackgroundServiceStreamServerEvent: String, Codable, Sendable {
    case stateUpdate
    case openSettingsRequested
}

public struct BackgroundServiceStreamServerEnvelope: Codable, Sendable {
    public let event: BackgroundServiceStreamServerEvent
    public let payload: Data?

    public init(event: BackgroundServiceStreamServerEvent, payload: Data?) {
        self.event = event
        self.payload = payload
    }
}

public enum BackendCodec {
    public static let encoder = JSONEncoder()
    public static let decoder = JSONDecoder()

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

public enum BackgroundServiceMethod: String, Codable, Sendable {
    case ping
    case listDevices
    case readState
    case readDpiStagesFast
    case shouldUseFastDPIPolling
    case dpiUpdateTransportStatus
    case hidAccessStatus
    case apply
    case readLightingColor
    case debugUSBReadButtonBinding
    case subscribeStateUpdates
}

public struct BackgroundServiceRequestEnvelope: Codable, Sendable {
    public let method: BackgroundServiceMethod
    public let payload: Data?

    public init(method: BackgroundServiceMethod, payload: Data?) {
        self.method = method
        self.payload = payload
    }
}

public struct BackgroundServiceResponseEnvelope: Codable, Sendable {
    public let payload: Data?
    public let error: String?

    public init(payload: Data?, error: String?) {
        self.payload = payload
        self.error = error
    }
}

public enum BackgroundServiceTransportError: LocalizedError {
    case connectionClosed
    case invalidLength
    case missingPayload
    case listenerUnavailable

    public var errorDescription: String? {
        switch self {
        case .connectionClosed:
            return "Background service connection closed unexpectedly"
        case .invalidLength:
            return "Background service returned an invalid message"
        case .missingPayload:
            return "Background service request was missing its payload"
        case .listenerUnavailable:
            return "Background service listener did not publish a port"
        }
    }
}

public final class BackgroundServiceResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    public init() {}

    public func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return false }
        hasResumed = true
        return true
    }
}

public enum BackgroundServiceTransport {
    public static func listenerParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        return parameters
    }

    public static func clientParameters() -> NWParameters {
        .tcp
    }

    public static func awaitReady(listener: NWListener) async throws -> NWEndpoint.Port {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "io.opensnek.service.listener")
            let gate = BackgroundServiceResumeGate()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    guard let port = listener.port else {
                        continuation.resume(throwing: BackgroundServiceTransportError.listenerUnavailable)
                        return
                    }
                    continuation.resume(returning: port)
                case .failed(let error):
                    guard gate.claim() else { return }
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard gate.claim() else { return }
                    continuation.resume(throwing: BackgroundServiceTransportError.connectionClosed)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    public static func awaitReady(connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "io.opensnek.service.client")
            let gate = BackgroundServiceResumeGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    continuation.resume()
                case .failed(let error):
                    guard gate.claim() else { return }
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard gate.claim() else { return }
                    continuation.resume(throwing: BackgroundServiceTransportError.connectionClosed)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    public static func sendFrame(_ payload: Data, over connection: NWConnection) async throws {
        var framed = Data()
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { header in
            framed.append(contentsOf: header)
        }
        framed.append(payload)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    public static func receiveFrame(from connection: NWConnection) async throws -> Data {
        let header = try await receiveExactly(4, from: connection)
        let length = header.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }

        if length == 0 {
            return Data()
        }

        return try await receiveExactly(Int(length), from: connection)
    }

    private static func receiveExactly(_ count: Int, from connection: NWConnection) async throws -> Data {
        guard count >= 0 else {
            throw BackgroundServiceTransportError.invalidLength
        }

        var buffer = Data()
        while buffer.count < count {
            let chunk = try await receiveChunk(maximumLength: count - buffer.count, from: connection)
            buffer.append(chunk)
        }
        return buffer
    }

    private static func receiveChunk(maximumLength: Int, from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }
                if isComplete {
                    continuation.resume(throwing: BackgroundServiceTransportError.connectionClosed)
                } else {
                    continuation.resume(throwing: BackgroundServiceTransportError.invalidLength)
                }
            }
        }
    }
}
