import Foundation
import Network
import OpenSnekCore
import OpenSnekHardware

/// Serializes background service request handler state and operations.
private actor BackgroundServiceRequestHandler {
    private let backend: any DeviceBackend

    init(backend: any DeviceBackend) { self.backend = backend }

    func handle(_ request: BackgroundServiceRequestEnvelope) async -> BackgroundServiceResponseEnvelope { do { return try await makeResponse(for: request) } catch { return BackgroundServiceResponseEnvelope(payload: nil, error: error.localizedDescription) } }

    private func makeResponse(for request: BackgroundServiceRequestEnvelope) async throws -> BackgroundServiceResponseEnvelope {
        let payload: Data

        switch request.method {
        case .ping: payload = try BackendCodec.encode(true)
        case .listDevices: payload = try BackendCodec.encode(try await backend.listDevices())
        case .readState:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.readState(device: device))
        case .readDpiStagesFast:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.readDpiStagesFast(device: device))
        case .shouldUseFastDPIPolling:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(await backend.shouldUseFastDPIPolling(device: device))
        case .usbControlAvailability:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.usbControlAvailability(device: device))
        case .dpiUpdateTransportStatus:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(await backend.dpiUpdateTransportStatus(device: device))
        case .hidAccessStatus:
            let forceRefresh = (try? decodePayload(Bool.self, from: request.payload)) ?? true
            if let backend = backend as? any HIDAccessRefreshControllingBackend { payload = try BackendCodec.encode(await backend.hidAccessStatus(forceRefresh: forceRefresh)) } else { payload = try BackendCodec.encode(await backend.hidAccessStatus()) }
        case .apply:
            let applyRequest = try decodePayload(ApplyRequest.self, from: request.payload)
            if let backend = backend as? any ApplyOptionsSupportingBackend {
                payload = try BackendCodec.encode(try await backend.apply(device: applyRequest.device, patch: applyRequest.patch, options: applyRequest.options))
            } else {
                payload = try BackendCodec.encode(try await backend.apply(device: applyRequest.device, patch: applyRequest.patch))
            }
        case .listOnboardProfiles:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.listOnboardProfiles(device: device))
        case .readOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileIDRequest.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.readOnboardProfile(device: onboardRequest.device, profileID: onboardRequest.profileID))
        case .readOnboardProfileCore:
            let onboardRequest = try decodePayload(OnboardProfileIDRequest.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.readOnboardProfileCore(device: onboardRequest.device, profileID: onboardRequest.profileID))
        case .readOnboardProfileButtonBindings:
            let onboardRequest = try decodePayload(OnboardProfileIDRequest.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.readOnboardProfileButtonBindings(device: onboardRequest.device, profileID: onboardRequest.profileID))
        case .createOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileCreateRequest.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.createOnboardProfile(device: onboardRequest.device, mutation: onboardRequest.mutation, targetProfileID: onboardRequest.targetProfileID, replaceAssignedProfile: onboardRequest.replaceAssignedProfile))
        case .renameOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileRenameRequest.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.renameOnboardProfile(device: onboardRequest.device, profileID: onboardRequest.profileID, name: onboardRequest.name))
        case .updateOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileUpdateRequest.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.updateOnboardProfile(device: onboardRequest.device, profileID: onboardRequest.profileID, mutation: onboardRequest.mutation))
        case .projectOnboardProfileDPIToActiveLayer:
            let onboardRequest = try decodePayload(OnboardProfileDPIProjectionRequest.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.projectOnboardProfileDPIToActiveLayer(device: onboardRequest.device, profileID: onboardRequest.profileID, dpi: onboardRequest.dpi))
        case .deleteOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileIDRequest.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.deleteOnboardProfile(device: onboardRequest.device, profileID: onboardRequest.profileID))
        case .activateOnboardProfile:
            let onboardRequest = try decodePayload(OnboardProfileIDRequest.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.activateOnboardProfile(device: onboardRequest.device, profileID: onboardRequest.profileID))
        case .refreshActiveOnboardProfile:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.refreshActiveOnboardProfile(device: device))
        case .readLightingColor:
            let device = try decodePayload(MouseDevice.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.readLightingColor(device: device))
        case .startSoftwareLighting:
            let lightingRequest = try decodePayload(SoftwareLightingStartRequest.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.startSoftwareLighting(device: lightingRequest.device, request: lightingRequest.request))
        case .stopSoftwareLighting:
            if let stopRequest = try? decodePayload(SoftwareLightingStopRequest.self, from: request.payload) {
                payload = try BackendCodec.encode(await backend.stopSoftwareLighting(device: stopRequest.device))
            } else {
                let statusRequest = try decodePayload(SoftwareLightingStatusRequest.self, from: request.payload)
                payload = try BackendCodec.encode(await backend.stopSoftwareLighting(deviceID: statusRequest.deviceID))
            }
        case .stopAllSoftwareLighting: payload = try BackendCodec.encode(await backend.stopAllSoftwareLighting())
        case .softwareLightingStatus:
            let statusRequest = try decodePayload(SoftwareLightingStatusRequest.self, from: request.payload)
            payload = try BackendCodec.encode(await backend.softwareLightingStatus(deviceID: statusRequest.deviceID))
        case .debugUSBReadButtonBinding:
            let bindingRequest = try decodePayload(ButtonBindingReadRequest.self, from: request.payload)
            payload = try BackendCodec.encode(try await backend.debugUSBReadButtonBinding(device: bindingRequest.device, slot: bindingRequest.slot, profile: bindingRequest.profile))
        case .subscribeStateUpdates: payload = try BackendCodec.encode(true)
        }

        return BackgroundServiceResponseEnvelope(payload: payload, error: nil)
    }

    private func decodePayload<T: Decodable>(_ type: T.Type, from payload: Data?) throws -> T {
        guard let payload else { throw BackgroundServiceTransportError.missingPayload }
        return try BackendCodec.decode(type, from: payload)
    }
}

/// Serializes background service subscriber session state and operations.
private actor BackgroundServiceSubscriberSession {
    nonisolated let id = UUID()

    private let connection: NWConnection
    private let sourceProcessID: Int32
    private let initialSelectedDeviceID: String?
    private let onPresenceUpdate: @Sendable (CrossProcessClientPresence) async -> Void
    private let onDisconnect: @Sendable (Int32) async -> Void
    private var didHandleDisconnect = false

    init(connection: NWConnection, subscription: StreamSubscriptionRequest, onPresenceUpdate: @escaping @Sendable (CrossProcessClientPresence) async -> Void, onDisconnect: @escaping @Sendable (Int32) async -> Void) {
        self.connection = connection
        sourceProcessID = subscription.sourceProcessID
        initialSelectedDeviceID = subscription.selectedDeviceID
        self.onPresenceUpdate = onPresenceUpdate
        self.onDisconnect = onDisconnect
    }

    func run() async {
        await onPresenceUpdate(CrossProcessClientPresence(sourceProcessID: sourceProcessID, selectedDeviceID: initialSelectedDeviceID))

        do {
            while !Task.isCancelled {
                let frame = try await BackgroundServiceTransport.receiveFrame(from: connection)
                let envelope = try BackendCodec.decode(BackgroundServiceStreamClientEnvelope.self, from: frame)
                switch envelope.event {
                case .clientPresence:
                    guard let payload = envelope.payload else { throw BackgroundServiceTransportError.missingPayload }
                    let presence = try BackendCodec.decode(CrossProcessClientPresence.self, from: payload)
                    await onPresenceUpdate(presence)
                }
            }
        } catch { if !Task.isCancelled, !isConnectionClosed(error) { AppLog.warning("Service", "subscriber session failed: \(error.localizedDescription)") } }

        await disconnect()
    }

    func sendStateUpdate(_ update: BackendStateUpdate) async throws { try await send(BackgroundServiceStreamServerEnvelope(event: .stateUpdate, payload: try BackendCodec.encode(update))) }

    func sendOpenSettingsRequested() async throws { try await send(BackgroundServiceStreamServerEnvelope(event: .openSettingsRequested, payload: nil)) }

    func stop() async {
        connection.cancel()
        await disconnect()
    }

    private func disconnect() async {
        guard !didHandleDisconnect else { return }
        didHandleDisconnect = true
        await onDisconnect(sourceProcessID)
    }

    private func send(_ envelope: BackgroundServiceStreamServerEnvelope) async throws { try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(envelope), over: connection) }

    private func isConnectionClosed(_ error: Error) -> Bool {
        if let transportError = error as? BackgroundServiceTransportError { if case .connectionClosed = transportError { return true } }
        return false
    }
}

/// Serializes background service subscriber registry state and operations.
private actor BackgroundServiceSubscriberRegistry {
    private var sessions: [UUID: BackgroundServiceSubscriberSession] = [:]

    func add(_ session: BackgroundServiceSubscriberSession) { sessions[session.id] = session }

    func remove(id: UUID) { sessions.removeValue(forKey: id) }

    func closeAll() async {
        let currentSessions = Array(sessions.values)
        sessions.removeAll()
        for session in currentSessions { await session.stop() }
    }

    func broadcast(_ update: BackendStateUpdate) async {
        for (id, session) in sessions {
            do { try await session.sendStateUpdate(update) } catch {
                sessions.removeValue(forKey: id)
                await session.stop()
            }
        }
    }

    func requestOpenSettings() async -> Bool {
        var delivered = false
        for (id, session) in sessions {
            do {
                try await session.sendOpenSettingsRequested()
                delivered = true
            } catch {
                sessions.removeValue(forKey: id)
                await session.stop()
            }
        }
        return delivered
    }
}

/// Coordinates background service host behavior.
final class BackgroundServiceHost: @unchecked Sendable {
    private let defaults: UserDefaults
    private let pid = ProcessInfo.processInfo.processIdentifier
    private let listener: NWListener
    private let backend: any DeviceBackend
    private let handler: BackgroundServiceRequestHandler
    private let subscribers = BackgroundServiceSubscriberRegistry()
    private let remoteClientPresenceHandler: @Sendable (CrossProcessClientPresence) async -> Void
    private let remoteClientDisconnectHandler: @Sendable (Int32) async -> Void
    private let queue = DispatchQueue(label: "io.opensnek.service.host")
    private var backendStateUpdatesTask: Task<Void, Never>?

    init(backend: any DeviceBackend, defaults: UserDefaults = .standard, remoteClientPresenceHandler: @escaping @Sendable (CrossProcessClientPresence) async -> Void = { _ in }, remoteClientDisconnectHandler: @escaping @Sendable (Int32) async -> Void = { _ in }) throws {
        self.defaults = defaults
        self.listener = try NWListener(using: BackgroundServiceTransport.listenerParameters())
        self.backend = backend
        self.handler = BackgroundServiceRequestHandler(backend: backend)
        self.remoteClientPresenceHandler = remoteClientPresenceHandler
        self.remoteClientDisconnectHandler = remoteClientDisconnectHandler
    }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }

        let port = try await BackgroundServiceTransport.awaitReady(listener: listener)
        defaults.removeObject(forKey: BackgroundServiceCoordinator.endpointDefaultsKey)
        defaults.set(Int(port.rawValue), forKey: BackgroundServiceCoordinator.portDefaultsKey)
        defaults.set(pid, forKey: BackgroundServiceCoordinator.pidDefaultsKey)
        defaults.synchronize()
        startBroadcastingBackendStateUpdates()
        AppLog.info("Service", "background service published pid=\(pid) port=\(port.rawValue)")
    }

    func stop() {
        backendStateUpdatesTask?.cancel()
        backendStateUpdatesTask = nil
        Task { await subscribers.closeAll() }
        if defaults.integer(forKey: BackgroundServiceCoordinator.pidDefaultsKey) == pid {
            defaults.removeObject(forKey: BackgroundServiceCoordinator.endpointDefaultsKey)
            defaults.removeObject(forKey: BackgroundServiceCoordinator.portDefaultsKey)
            defaults.removeObject(forKey: BackgroundServiceCoordinator.pidDefaultsKey)
            defaults.synchronize()
        }
        listener.cancel()
    }

    func requestOpenSettingsForConnectedClients() async -> Bool { await subscribers.requestOpenSettings() }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.handle(connection)
            case .failed(let error):
                AppLog.warning("Service", "background service connection failed: \(error.localizedDescription)")
                connection.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func handle(_ connection: NWConnection) {
        let handler = self.handler
        let subscribers = self.subscribers
        let remoteClientPresenceHandler = self.remoteClientPresenceHandler
        let remoteClientDisconnectHandler = self.remoteClientDisconnectHandler
        Task {
            do {
                let requestData = try await BackgroundServiceTransport.receiveFrame(from: connection)
                let request = try BackendCodec.decode(BackgroundServiceRequestEnvelope.self, from: requestData)

                if request.method == .subscribeStateUpdates {
                    guard let payload = request.payload else { throw BackgroundServiceTransportError.missingPayload }
                    let subscription = try BackendCodec.decode(StreamSubscriptionRequest.self, from: payload)
                    let session = BackgroundServiceSubscriberSession(connection: connection, subscription: subscription, onPresenceUpdate: remoteClientPresenceHandler, onDisconnect: remoteClientDisconnectHandler)
                    await subscribers.add(session)
                    let response = BackgroundServiceResponseEnvelope(payload: try BackendCodec.encode(true), error: nil)
                    try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(response), over: connection)
                    await session.run()
                    await subscribers.remove(id: session.id)
                    return
                }

                let response = await handler.handle(request)
                try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(response), over: connection)
            } catch { AppLog.warning("Service", "background service request failed: \(error.localizedDescription)") }
            connection.cancel()
        }
    }

    private func startBroadcastingBackendStateUpdates() {
        backendStateUpdatesTask?.cancel()
        backendStateUpdatesTask = Task { [backend, subscribers] in
            let stream = await backend.stateUpdates()
            for await update in stream { await subscribers.broadcast(update) }
        }
    }
}
