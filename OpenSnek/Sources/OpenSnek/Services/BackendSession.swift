import AppKit
import Foundation
import OpenSnekCore

enum OpenSnekProcessRole: String, Sendable {
    case app
    case service

    static var current: OpenSnekProcessRole {
        ProcessInfo.processInfo.arguments.contains("--service-mode") ? .service : .app
    }

    var isService: Bool {
        self == .service
    }
}

protocol DeviceBackend: AnyObject, Sendable {
    func listDevices() async throws -> [MouseDevice]
    func readState(device: MouseDevice) async throws -> MouseState
    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot?
    func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState
    func readLightingColor(device: MouseDevice) async throws -> RGBPatch?
    func debugUSBReadButtonBinding(device: MouseDevice, slot: Int, profile: Int) async throws -> [UInt8]?
}

struct DpiFastSnapshot: Codable, Hashable, Sendable {
    let active: Int
    let values: [Int]
}

private struct ApplyRequest: Codable, Sendable {
    let device: MouseDevice
    let patch: DevicePatch
}

private struct ButtonBindingReadRequest: Codable, Sendable {
    let device: MouseDevice
    let slot: Int
    let profile: Int
}

private enum BackendCodec {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

private final class XPCReplyBox: @unchecked Sendable {
    let handler: (Data?, String?) -> Void

    init(_ handler: @escaping (Data?, String?) -> Void) {
        self.handler = handler
    }

    func reply(data: Data?, error: String?) {
        handler(data, error)
    }
}

private func scheduleBackendReply<T: Encodable & Sendable>(
    replyBox: XPCReplyBox,
    operation: @escaping @Sendable () async throws -> T
) {
    DispatchQueue.global(qos: .userInitiated).async {
        Task {
            await BackgroundServiceXPCBridge.replyWithResult(replyBox, operation: operation)
        }
    }
}

final actor LocalBridgeBackend: DeviceBackend {
    static let shared = LocalBridgeBackend()

    private let client = BridgeClient()
    private var cachedDevices: [MouseDevice] = []
    private var cachedDevicesAt: Date?
    private var cachedStateByDeviceID: [String: MouseState] = [:]
    private var cachedStateAtByDeviceID: [String: Date] = [:]
    private var cachedFastByDeviceID: [String: DpiFastSnapshot] = [:]
    private var cachedFastAtByDeviceID: [String: Date] = [:]

    func listDevices() async throws -> [MouseDevice] {
        if let cachedDevicesAt,
           Date().timeIntervalSince(cachedDevicesAt) < 1.0,
           !cachedDevices.isEmpty {
            return cachedDevices
        }
        let devices = try await client.listDevices()
        cachedDevices = devices
        cachedDevicesAt = Date()
        return devices
    }

    func readState(device: MouseDevice) async throws -> MouseState {
        if let cachedAt = cachedStateAtByDeviceID[device.id],
           let cached = cachedStateByDeviceID[device.id],
           Date().timeIntervalSince(cachedAt) < 1.0 {
            return cached
        }
        let state = try await client.readState(device: device)
        cachedStateByDeviceID[device.id] = state
        cachedStateAtByDeviceID[device.id] = Date()
        return state
    }

    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot? {
        if let cachedAt = cachedFastAtByDeviceID[device.id],
           let cached = cachedFastByDeviceID[device.id],
           Date().timeIntervalSince(cachedAt) < 0.2 {
            return cached
        }
        guard let snapshot = try await client.readDpiStagesFast(device: device) else { return nil }
        let fast = DpiFastSnapshot(active: snapshot.active, values: snapshot.values)
        cachedFastByDeviceID[device.id] = fast
        cachedFastAtByDeviceID[device.id] = Date()
        return fast
    }

    func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState {
        let state = try await client.apply(device: device, patch: patch)
        cachedStateByDeviceID[device.id] = state
        cachedStateAtByDeviceID[device.id] = Date()
        if let values = state.dpi_stages.values,
           let active = state.dpi_stages.active_stage {
            let fast = DpiFastSnapshot(active: active, values: values)
            cachedFastByDeviceID[device.id] = fast
            cachedFastAtByDeviceID[device.id] = Date()
        }
        return state
    }

    func readLightingColor(device: MouseDevice) async throws -> RGBPatch? {
        try await client.readLightingColor(device: device)
    }

    func debugUSBReadButtonBinding(device: MouseDevice, slot: Int, profile: Int) async throws -> [UInt8]? {
        try await client.debugUSBReadButtonBinding(device: device, slot: slot, profile: profile)
    }
}

@objc protocol BackgroundServiceXPCProtocol {
    func ping(_ reply: @escaping (Bool) -> Void)
    func listDevices(_ reply: @escaping (Data?, String?) -> Void)
    func readState(_ deviceData: Data, reply: @escaping (Data?, String?) -> Void)
    func readDpiStagesFast(_ deviceData: Data, reply: @escaping (Data?, String?) -> Void)
    func apply(_ requestData: Data, reply: @escaping (Data?, String?) -> Void)
    func readLightingColor(_ deviceData: Data, reply: @escaping (Data?, String?) -> Void)
    func debugUSBReadButtonBinding(_ requestData: Data, reply: @escaping (Data?, String?) -> Void)
}

final class BackgroundServiceXPCBridge: NSObject, BackgroundServiceXPCProtocol {
    private let backend: LocalBridgeBackend

    init(backend: LocalBridgeBackend) {
        self.backend = backend
    }

    func ping(_ reply: @escaping (Bool) -> Void) {
        reply(true)
    }

    func listDevices(_ reply: @escaping (Data?, String?) -> Void) {
        let backend = self.backend
        let replyBox = XPCReplyBox(reply)
        scheduleBackendReply(replyBox: replyBox) {
            try await backend.listDevices()
        }
    }

    func readState(_ deviceData: Data, reply: @escaping (Data?, String?) -> Void) {
        let backend = self.backend
        let replyBox = XPCReplyBox(reply)
        scheduleBackendReply(replyBox: replyBox) {
            let device = try BackendCodec.decode(MouseDevice.self, from: deviceData)
            return try await backend.readState(device: device)
        }
    }

    func readDpiStagesFast(_ deviceData: Data, reply: @escaping (Data?, String?) -> Void) {
        let backend = self.backend
        let replyBox = XPCReplyBox(reply)
        scheduleBackendReply(replyBox: replyBox) {
            let device = try BackendCodec.decode(MouseDevice.self, from: deviceData)
            return try await backend.readDpiStagesFast(device: device)
        }
    }

    func apply(_ requestData: Data, reply: @escaping (Data?, String?) -> Void) {
        let backend = self.backend
        let replyBox = XPCReplyBox(reply)
        scheduleBackendReply(replyBox: replyBox) {
            let request = try BackendCodec.decode(ApplyRequest.self, from: requestData)
            return try await backend.apply(device: request.device, patch: request.patch)
        }
    }

    func readLightingColor(_ deviceData: Data, reply: @escaping (Data?, String?) -> Void) {
        let backend = self.backend
        let replyBox = XPCReplyBox(reply)
        scheduleBackendReply(replyBox: replyBox) {
            let device = try BackendCodec.decode(MouseDevice.self, from: deviceData)
            return try await backend.readLightingColor(device: device)
        }
    }

    func debugUSBReadButtonBinding(_ requestData: Data, reply: @escaping (Data?, String?) -> Void) {
        let backend = self.backend
        let replyBox = XPCReplyBox(reply)
        scheduleBackendReply(replyBox: replyBox) {
            let request = try BackendCodec.decode(ButtonBindingReadRequest.self, from: requestData)
            return try await backend.debugUSBReadButtonBinding(
                device: request.device,
                slot: request.slot,
                profile: request.profile
            )
        }
    }

    fileprivate static func replyWithResult<T: Encodable & Sendable>(
        _ replyBox: XPCReplyBox,
        operation: @escaping () async throws -> T
    ) async {
        do {
            let value = try await operation()
            replyBox.reply(data: try BackendCodec.encode(value), error: nil)
        } catch {
            replyBox.reply(data: nil, error: error.localizedDescription)
        }
    }
}

final actor XPCDeviceBackend: DeviceBackend {
    private let connection: NSXPCConnection

    init(endpoint: NSXPCListenerEndpoint) {
        let connection = NSXPCConnection(listenerEndpoint: endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: BackgroundServiceXPCProtocol.self)
        connection.resume()
        self.connection = connection
    }

    func ping() async -> Bool {
        await withCheckedContinuation { continuation in
            guard let proxy = connection.remoteObjectProxy as? BackgroundServiceXPCProtocol else {
                continuation.resume(returning: false)
                return
            }
            proxy.ping { ok in
                continuation.resume(returning: ok)
            }
        }
    }

    func listDevices() async throws -> [MouseDevice] {
        try await request { proxy, reply in
            proxy.listDevices(reply)
        }
    }

    func readState(device: MouseDevice) async throws -> MouseState {
        let data = try BackendCodec.encode(device)
        return try await request { proxy, reply in
            proxy.readState(data, reply: reply)
        }
    }

    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot? {
        let data = try BackendCodec.encode(device)
        return try await request { proxy, reply in
            proxy.readDpiStagesFast(data, reply: reply)
        }
    }

    func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState {
        let data = try BackendCodec.encode(ApplyRequest(device: device, patch: patch))
        return try await request { proxy, reply in
            proxy.apply(data, reply: reply)
        }
    }

    func readLightingColor(device: MouseDevice) async throws -> RGBPatch? {
        let data = try BackendCodec.encode(device)
        return try await request { proxy, reply in
            proxy.readLightingColor(data, reply: reply)
        }
    }

    func debugUSBReadButtonBinding(device: MouseDevice, slot: Int, profile: Int) async throws -> [UInt8]? {
        let requestData = try BackendCodec.encode(
            ButtonBindingReadRequest(device: device, slot: slot, profile: profile)
        )
        return try await request { proxy, reply in
            proxy.debugUSBReadButtonBinding(requestData, reply: reply)
        }
    }

    private func request<T: Decodable & Sendable>(
        _ invoke: @escaping (BackgroundServiceXPCProtocol, @escaping (Data?, String?) -> Void) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let errorProxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: error)
            }

            guard let proxy = errorProxy as? BackgroundServiceXPCProtocol else {
                continuation.resume(throwing: NSError(domain: "OpenSnek.XPC", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create XPC proxy"
                ]))
                return
            }

            invoke(proxy) { data, errorMessage in
                if let errorMessage {
                    continuation.resume(throwing: NSError(domain: "OpenSnek.XPC", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: errorMessage
                    ]))
                    return
                }
                guard let data else {
                    continuation.resume(throwing: NSError(domain: "OpenSnek.XPC", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "Service returned no payload"
                    ]))
                    return
                }
                do {
                    continuation.resume(returning: try BackendCodec.decode(T.self, from: data))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

final class BackgroundServiceHost: NSObject, NSXPCListenerDelegate {
    private let listener = NSXPCListener.anonymous()
    private let bridge: BackgroundServiceXPCBridge
    private let defaults = UserDefaults.standard
    private let pid = ProcessInfo.processInfo.processIdentifier

    init(backend: LocalBridgeBackend) {
        bridge = BackgroundServiceXPCBridge(backend: backend)
        super.init()
        listener.delegate = self
    }

    func start() throws {
        let endpointData = try NSKeyedArchiver.archivedData(
            withRootObject: listener.endpoint,
            requiringSecureCoding: true
        )
        defaults.set(endpointData, forKey: BackgroundServiceCoordinator.endpointDefaultsKey)
        defaults.set(pid, forKey: BackgroundServiceCoordinator.pidDefaultsKey)
        defaults.synchronize()
        listener.resume()
    }

    func stop() {
        if defaults.integer(forKey: BackgroundServiceCoordinator.pidDefaultsKey) == pid {
            defaults.removeObject(forKey: BackgroundServiceCoordinator.endpointDefaultsKey)
            defaults.removeObject(forKey: BackgroundServiceCoordinator.pidDefaultsKey)
            defaults.synchronize()
        }
        listener.invalidate()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: BackgroundServiceXPCProtocol.self)
        newConnection.exportedObject = bridge
        newConnection.resume()
        return true
    }
}
