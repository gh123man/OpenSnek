import Foundation
import XCTest
import OpenSnekCore
import OpenSnekProtocols
@testable import OpenSnekHardware
@testable import OpenSnek

/// Stores async timeout error test data.
struct AsyncTimeoutError: Error {}

func withAsyncTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw AsyncTimeoutError()
        }

        let result = try await group.next()
        group.cancelAll()
        return try XCTUnwrap(result)
    }
}

/// Provides a passive update stub backend test double.
actor PassiveUpdateStubBackend: DeviceBackend {
    nonisolated var usesRemoteServiceTransport: Bool { false }

    private let devices: [MouseDevice]
    private let shouldUseFastPollingValue: Bool
    private var stateByDeviceID: [String: MouseState]
    private var fastReadCounter = 0
    private var readStateCounter = 0
    private let stateUpdateStreamPair = AsyncStream.makeStream(of: BackendStateUpdate.self)

    init(devices: [MouseDevice], stateByDeviceID: [String: MouseState], shouldUseFastPolling: Bool) {
        self.devices = devices
        self.stateByDeviceID = stateByDeviceID
        self.shouldUseFastPollingValue = shouldUseFastPolling
    }

    func listDevices() async throws -> [MouseDevice] { devices }

    func readState(device: MouseDevice) async throws -> MouseState {
        readStateCounter += 1
        guard let state = stateByDeviceID[device.id] else { throw NSError(domain: "USBPassiveDPIEventTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing state for \(device.id)"]) }
        return state
    }

    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot? {
        fastReadCounter += 1
        guard let state = stateByDeviceID[device.id], let active = state.dpi_stages.active_stage, let values = state.dpi_stages.values else { return nil }
        return DpiFastSnapshot(active: active, values: values)
    }

    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool { shouldUseFastPollingValue }

    func hidAccessStatus() async -> HIDAccessStatus { HIDAccessStatus(authorization: .granted, hostLabel: "Test Host (io.opensnek.OpenSnek)", bundleIdentifier: "io.opensnek.OpenSnek", detail: nil) }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> { stateUpdateStreamPair.stream }

    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState { throw NSError(domain: "USBPassiveDPIEventTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "apply not implemented"]) }

    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? { nil }

    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? { nil }

    func emitStateUpdate(deviceID: String, state: MouseState, updatedAt: Date = Date()) {
        stateByDeviceID[deviceID] = state
        stateUpdateStreamPair.continuation.yield(.deviceState(deviceID: deviceID, state: state, updatedAt: updatedAt))
    }

    func fastReadCount() -> Int { fastReadCounter }

    func readStateCount() -> Int { readStateCounter }

    func emitTransportStatusUpdate(deviceID: String, status: DpiUpdateTransportStatus, updatedAt: Date = Date()) { stateUpdateStreamPair.continuation.yield(.dpiTransportStatus(deviceID: deviceID, status: status, updatedAt: updatedAt)) }
}

/// Provides a racing passive update stub backend test double.
actor RacingPassiveUpdateStubBackend: DeviceBackend {
    nonisolated var usesRemoteServiceTransport: Bool { false }

    private let devices: [MouseDevice]
    private var staleStateByDeviceID: [String: MouseState]
    private var fastSnapshotByDeviceID: [String: DpiFastSnapshot]
    private let shouldUseFastPollingValue: Bool
    private let stateUpdateStreamPair = AsyncStream.makeStream(of: BackendStateUpdate.self)
    private var readStateStarted = false
    private var readStateStartedContinuations: [CheckedContinuation<Void, Never>] = []
    private var readStateResumeContinuation: CheckedContinuation<Void, Never>?

    init(devices: [MouseDevice], staleStateByDeviceID: [String: MouseState], fastSnapshotByDeviceID: [String: DpiFastSnapshot] = [:], shouldUseFastPolling: Bool = false, blockReadState: Bool = true) {
        self.devices = devices
        self.staleStateByDeviceID = staleStateByDeviceID
        self.fastSnapshotByDeviceID = fastSnapshotByDeviceID
        self.shouldUseFastPollingValue = shouldUseFastPolling
        self.blockReadState = blockReadState
    }

    private let blockReadState: Bool

    func listDevices() async throws -> [MouseDevice] { devices }

    func readState(device: MouseDevice) async throws -> MouseState {
        readStateStarted = true
        let continuations = readStateStartedContinuations
        readStateStartedContinuations.removeAll()
        for continuation in continuations { continuation.resume() }

        if blockReadState { await withCheckedContinuation { continuation in readStateResumeContinuation = continuation } }

        guard let state = staleStateByDeviceID[device.id] else { throw NSError(domain: "USBPassiveDPIEventTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing stale state for \(device.id)"]) }
        return state
    }

    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot? { fastSnapshotByDeviceID[device.id] }

    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool { shouldUseFastPollingValue }

    func hidAccessStatus() async -> HIDAccessStatus { HIDAccessStatus(authorization: .granted, hostLabel: "Test Host (io.opensnek.OpenSnek)", bundleIdentifier: "io.opensnek.OpenSnek", detail: nil) }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> { stateUpdateStreamPair.stream }

    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState { throw NSError(domain: "USBPassiveDPIEventTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "apply not implemented"]) }

    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? { nil }

    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? { nil }

    func waitForReadStateStart() async {
        if readStateStarted { return }

        await withCheckedContinuation { continuation in readStateStartedContinuations.append(continuation) }
    }

    func resumeReadState() {
        readStateResumeContinuation?.resume()
        readStateResumeContinuation = nil
    }

    func setFastSnapshot(_ snapshot: DpiFastSnapshot, for deviceID: String) { fastSnapshotByDeviceID[deviceID] = snapshot }

    func emitStateUpdate(deviceID: String, state: MouseState, updatedAt: Date) { stateUpdateStreamPair.continuation.yield(.deviceState(deviceID: deviceID, state: state, updatedAt: updatedAt)) }
}

func makePassiveTestDevice(id: String, transport: DeviceTransportKind) -> MouseDevice {
    MouseDevice(
        id: id, vendor_id: transport == .bluetooth ? 0x068E : 0x1532, product_id: transport == .bluetooth ? 0x00BA : 0x00AB, product_name: "Passive Test Mouse", transport: transport, path_b64: "", serial: "PASSIVE-\(id)", firmware: "1.0.0", location_id: abs(id.hashValue),
        profile_id: transport == .bluetooth ? .basiliskV3XHyperspeed : .basiliskV3Pro, supports_advanced_lighting_effects: transport != .bluetooth, onboard_profile_count: transport == .bluetooth ? 1 : 3)
}

func makePassiveTestState(device: MouseDevice, dpiValues: [Int], activeStage: Int, dpiValue: Int) -> MouseState {
    MouseState(
        device: DeviceSummary(id: device.id, product_name: device.product_name, serial: device.serial, transport: device.transport, firmware: device.firmware), connection: device.transport.connectionLabel, battery_percent: 82, charging: false, dpi: DpiPair(x: dpiValue, y: dpiValue),
        dpi_stages: DpiStages(active_stage: activeStage, values: dpiValues), poll_rate: 1000, sleep_timeout: 300, device_mode: DeviceMode(mode: 0x00, param: 0x00), led_value: 64, capabilities: Capabilities(dpi_stages: true, poll_rate: true, power_management: true, button_remap: true, lighting: true)
    )
}
