import Foundation
import Network
import OpenSnekCore
import OpenSnekHardware

/// Serializes IPC device backend state and operations.
final actor IPCDeviceBackend: HIDAccessRefreshControllingBackend, ApplyOptionsSupportingBackend {
    private let host: NWEndpoint.Host = .ipv4(.loopback)
    private let port: NWEndpoint.Port
    private var latestRemoteClientPresence: CrossProcessClientPresence
    private var remoteSubscription: BackgroundServiceClientSubscription?

    init(port: NWEndpoint.Port) {
        self.port = port
        latestRemoteClientPresence = CrossProcessClientPresence(sourceProcessID: Int32(ProcessInfo.processInfo.processIdentifier), selectedDeviceID: nil)
    }

    nonisolated var usesRemoteServiceTransport: Bool { true }

    func ping() async -> Bool { (try? await request(method: .ping, payload: nil, responseType: Bool.self)) ?? false }

    func listDevices() async throws -> [MouseDevice] { try await request(method: .listDevices, payload: nil, responseType: [MouseDevice].self) }

    func readState(device: MouseDevice) async throws -> MouseState { try await request(method: .readState, payload: try BackendCodec.encode(device), responseType: MouseState.self) }

    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot? { try await request(method: .readDpiStagesFast, payload: try BackendCodec.encode(device), responseType: DpiFastSnapshot?.self) }

    func shouldUseFastDPIPolling(device: MouseDevice) async -> Bool { (try? await request(method: .shouldUseFastDPIPolling, payload: try BackendCodec.encode(device), responseType: Bool.self)) ?? false }

    func usbControlAvailability(device: MouseDevice) async throws -> USBControlAvailability { try await request(method: .usbControlAvailability, payload: try BackendCodec.encode(device), responseType: USBControlAvailability.self) }

    func dpiUpdateTransportStatus(device: MouseDevice) async -> DpiUpdateTransportStatus { (try? await request(method: .dpiUpdateTransportStatus, payload: try BackendCodec.encode(device), responseType: DpiUpdateTransportStatus.self)) ?? .unknown }

    func hidAccessStatus() async -> HIDAccessStatus { await hidAccessStatus(forceRefresh: true) }

    func hidAccessStatus(forceRefresh: Bool) async -> HIDAccessStatus {
        (try? await request(method: .hidAccessStatus, payload: try BackendCodec.encode(forceRefresh), responseType: HIDAccessStatus.self)) ?? HIDAccessStatus.unavailable(detail: "Failed to query HID access status from background service.")
    }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        if let remoteSubscription { await remoteSubscription.stop() }
        let remoteSubscription = BackgroundServiceClientSubscription(host: host, port: port, initialPresence: latestRemoteClientPresence)
        self.remoteSubscription = remoteSubscription
        return await remoteSubscription.makeStream()
    }

    func updateRemoteClientPresence(sourceProcessID: Int32, selectedDeviceID: String?) async {
        let presence = CrossProcessClientPresence(sourceProcessID: sourceProcessID, selectedDeviceID: selectedDeviceID)
        latestRemoteClientPresence = presence
        guard let remoteSubscription else { return }
        await remoteSubscription.updatePresence(presence)
    }

    func apply(device: MouseDevice, patch: DevicePatch, options: ApplyOptions) async throws -> MouseState { try await request(method: .apply, payload: try BackendCodec.encode(ApplyRequest(device: device, patch: patch, options: options)), responseType: MouseState.self) }

    func listOnboardProfiles(device: MouseDevice) async throws -> OnboardProfileInventory { try await request(method: .listOnboardProfiles, payload: try BackendCodec.encode(device), responseType: OnboardProfileInventory.self) }

    func readOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot { try await request(method: .readOnboardProfile, payload: try BackendCodec.encode(OnboardProfileIDRequest(device: device, profileID: profileID)), responseType: OnboardProfileSnapshot.self) }

    func readOnboardProfileCore(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot {
        try await request(method: .readOnboardProfileCore, payload: try BackendCodec.encode(OnboardProfileIDRequest(device: device, profileID: profileID)), responseType: OnboardProfileSnapshot.self)
    }

    func readOnboardProfileButtonBindings(device: MouseDevice, profileID: Int) async throws -> [Int: ButtonBindingDraft] {
        try await request(method: .readOnboardProfileButtonBindings, payload: try BackendCodec.encode(OnboardProfileIDRequest(device: device, profileID: profileID)), responseType: [Int: ButtonBindingDraft].self)
    }

    func createOnboardProfile(device: MouseDevice, mutation: OnboardProfileMutation, targetProfileID: Int?, replaceAssignedProfile: Bool) async throws -> OnboardProfileSnapshot {
        try await request(method: .createOnboardProfile, payload: try BackendCodec.encode(OnboardProfileCreateRequest(device: device, mutation: mutation, targetProfileID: targetProfileID, replaceAssignedProfile: replaceAssignedProfile)), responseType: OnboardProfileSnapshot.self)
    }

    func renameOnboardProfile(device: MouseDevice, profileID: Int, name: String) async throws -> OnboardProfileSnapshot {
        try await request(method: .renameOnboardProfile, payload: try BackendCodec.encode(OnboardProfileRenameRequest(device: device, profileID: profileID, name: name)), responseType: OnboardProfileSnapshot.self)
    }

    func updateOnboardProfile(device: MouseDevice, profileID: Int, mutation: OnboardProfileMutation) async throws -> OnboardProfileSnapshot {
        try await request(method: .updateOnboardProfile, payload: try BackendCodec.encode(OnboardProfileUpdateRequest(device: device, profileID: profileID, mutation: mutation)), responseType: OnboardProfileSnapshot.self)
    }

    func projectOnboardProfileDPIToActiveLayer(device: MouseDevice, profileID: Int, dpi: OnboardDPIProfileSnapshot) async throws -> Bool {
        try await request(method: .projectOnboardProfileDPIToActiveLayer, payload: try BackendCodec.encode(OnboardProfileDPIProjectionRequest(device: device, profileID: profileID, dpi: dpi)), responseType: Bool.self)
    }

    func deleteOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileInventory { try await request(method: .deleteOnboardProfile, payload: try BackendCodec.encode(OnboardProfileIDRequest(device: device, profileID: profileID)), responseType: OnboardProfileInventory.self) }

    func activateOnboardProfile(device: MouseDevice, profileID: Int) async throws -> MouseState { try await request(method: .activateOnboardProfile, payload: try BackendCodec.encode(OnboardProfileIDRequest(device: device, profileID: profileID)), responseType: MouseState.self) }

    func refreshActiveOnboardProfile(device: MouseDevice) async throws -> MouseState { try await request(method: .refreshActiveOnboardProfile, payload: try BackendCodec.encode(device), responseType: MouseState.self) }

    func readLightingColor(device: MouseDevice) async throws -> RGBPatch? { try await request(method: .readLightingColor, payload: try BackendCodec.encode(device), responseType: RGBPatch?.self) }

    func startSoftwareLighting(device: MouseDevice, request lightingRequest: SoftwareLightingEffectRequest) async throws -> SoftwareLightingEngineStatus {
        try await request(method: .startSoftwareLighting, payload: try BackendCodec.encode(SoftwareLightingStartRequest(device: device, request: lightingRequest)), responseType: SoftwareLightingEngineStatus.self)
    }

    func stopSoftwareLighting(deviceID: String) async -> SoftwareLightingEngineStatus? { try? await request(method: .stopSoftwareLighting, payload: try BackendCodec.encode(SoftwareLightingStatusRequest(deviceID: deviceID)), responseType: SoftwareLightingEngineStatus?.self) }

    func stopSoftwareLighting(device: MouseDevice) async -> SoftwareLightingEngineStatus? { try? await request(method: .stopSoftwareLighting, payload: try BackendCodec.encode(SoftwareLightingStopRequest(device: device)), responseType: SoftwareLightingEngineStatus?.self) }

    func stopAllSoftwareLighting() async -> [SoftwareLightingEngineStatus] { (try? await request(method: .stopAllSoftwareLighting, payload: nil, responseType: [SoftwareLightingEngineStatus].self)) ?? [] }

    func softwareLightingStatus(deviceID: String) async -> SoftwareLightingEngineStatus? { try? await request(method: .softwareLightingStatus, payload: try BackendCodec.encode(SoftwareLightingStatusRequest(deviceID: deviceID)), responseType: SoftwareLightingEngineStatus?.self) }

    func debugUSBReadButtonBinding(device: MouseDevice, slot: Int, profile: Int) async throws -> [UInt8]? { try await request(method: .debugUSBReadButtonBinding, payload: try BackendCodec.encode(ButtonBindingReadRequest(device: device, slot: slot, profile: profile)), responseType: [UInt8]?.self) }

    private func request<T: Decodable & Sendable>(method: BackgroundServiceMethod, payload: Data?, responseType: T.Type) async throws -> T {
        let connection = NWConnection(host: host, port: port, using: BackgroundServiceTransport.clientParameters())
        defer { connection.cancel() }

        try await BackgroundServiceTransport.awaitReady(connection: connection)

        let request = BackgroundServiceRequestEnvelope(method: method, payload: payload)
        try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(request), over: connection)

        let responseData = try await BackgroundServiceTransport.receiveFrame(from: connection)
        let response = try BackendCodec.decode(BackgroundServiceResponseEnvelope.self, from: responseData)
        if let error = response.error { throw NSError(domain: "OpenSnek.Service", code: 2, userInfo: [NSLocalizedDescriptionKey: error]) }
        guard let payload = response.payload else { throw NSError(domain: "OpenSnek.Service", code: 3, userInfo: [NSLocalizedDescriptionKey: "Background service returned no payload"]) }
        return try BackendCodec.decode(responseType, from: payload)
    }
}

/// Serializes background service client subscription state and operations.
private actor BackgroundServiceClientSubscription {
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
            let task = Task { await self.run(continuation: continuation) }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                Task { await self.stop() }
            }
        }
        await waitUntilReady()
        return stream
    }

    func updatePresence(_ presence: CrossProcessClientPresence) async {
        latestPresence = presence
        guard let connection else { return }
        do { try await sendClientPresence(presence, over: connection) } catch {
            connection.cancel()
            if self.connection === connection { self.connection = nil }
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
            if self.connection === connection { self.connection = nil }
            continuation.finish()
        }

        do {
            try await BackgroundServiceTransport.awaitReady(connection: connection)

            let subscribeRequest = BackgroundServiceRequestEnvelope(method: .subscribeStateUpdates, payload: try BackendCodec.encode(StreamSubscriptionRequest(sourceProcessID: latestPresence.sourceProcessID, selectedDeviceID: latestPresence.selectedDeviceID)))
            try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(subscribeRequest), over: connection)

            let responseData = try await BackgroundServiceTransport.receiveFrame(from: connection)
            let response = try BackendCodec.decode(BackgroundServiceResponseEnvelope.self, from: responseData)
            if let error = response.error { throw NSError(domain: "OpenSnek.Service", code: 2, userInfo: [NSLocalizedDescriptionKey: error]) }
            isReady = true
            resumeReadinessWaiters()

            while !Task.isCancelled {
                let frame = try await BackgroundServiceTransport.receiveFrame(from: connection)
                let envelope = try BackendCodec.decode(BackgroundServiceStreamServerEnvelope.self, from: frame)
                switch envelope.event {
                case .stateUpdate:
                    guard let payload = envelope.payload else { throw BackgroundServiceTransportError.missingPayload }
                    continuation.yield(try BackendCodec.decode(BackendStateUpdate.self, from: payload))
                case .openSettingsRequested: continuation.yield(.openSettingsRequested)
                }
            }
        } catch {
            resumeReadinessWaiters()
            if !Task.isCancelled, !isConnectionClosed(error) { AppLog.warning("Service", "background service subscription failed: \(error.localizedDescription)") }
        }
    }

    private func sendClientPresence(_ presence: CrossProcessClientPresence, over connection: NWConnection) async throws {
        let envelope = BackgroundServiceStreamClientEnvelope(event: .clientPresence, payload: try BackendCodec.encode(presence))
        try await BackgroundServiceTransport.sendFrame(try BackendCodec.encode(envelope), over: connection)
    }

    private func isConnectionClosed(_ error: Error) -> Bool {
        if let transportError = error as? BackgroundServiceTransportError { if case .connectionClosed = transportError { return true } }
        return false
    }

    private func waitUntilReady() async {
        guard !isReady else { return }
        await withCheckedContinuation { continuation in readinessWaiters.append(continuation) }
    }

    private func resumeReadinessWaiters() {
        let waiters = readinessWaiters
        readinessWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
}
