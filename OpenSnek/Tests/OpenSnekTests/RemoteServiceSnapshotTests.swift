import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

func waitUntil(
    timeout: TimeInterval = 2.0,
    pollInterval: UInt64 = 20_000_000,
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: pollInterval)
    }
    XCTFail("Timed out waiting for condition")
}

func clearSnapshotPreferences(for device: MouseDevice) {
    let defaults = UserDefaults.standard
    let key = DevicePersistenceKeys.key(for: device)
    let legacyKey = DevicePersistenceKeys.legacyKey(for: device)
    let prefixes = [
        "lightingColor.\(key)",
        "lightingColor.\(legacyKey)",
        "lightingZone.\(key)",
        "lightingZone.\(legacyKey)",
        "lightingEffect.\(key)",
        "lightingEffect.\(legacyKey)",
        "softwareLightingApplyOnConnect.\(key)",
        "softwareLightingRequest.\(key)",
        "connectBehavior.\(key)",
        "connectBehavior.\(legacyKey)",
        "settingsSnapshot.\(key)",
        "settingsSnapshot.\(legacyKey)",
        "selectedLocalProfile.\(key)",
        "selectedLocalProfile.\(legacyKey)",
        "buttonBindings.\(key)",
        "buttonBindings.\(legacyKey)",
        "buttonBindings.\(key).profile1",
        "buttonBindings.\(key).profile2",
        "buttonBindings.\(legacyKey).profile1",
        "buttonBindings.\(legacyKey).profile2"
    ]
    for storedKey in defaults.dictionaryRepresentation().keys
    where prefixes.contains(where: { storedKey.hasPrefix($0) }) {
        defaults.removeObject(forKey: storedKey)
    }
}

/// Stores snapshot device identity test data.
struct SnapshotDeviceIdentity {
    let transport: DeviceTransportKind
    let serial: String
    let locationID: Int
}

func makeSnapshotDevice(
    id: String,
    productName: String,
    identity: SnapshotDeviceIdentity,
    profile: DeviceProfileID
) -> MouseDevice {
    MouseDevice(
        id: id,
        vendor_id: 0x1532,
        product_id: identity.transport == .bluetooth ? 0x00BA : 0x00AB,
        product_name: productName,
        transport: identity.transport,
        path_b64: "",
        serial: identity.serial,
        firmware: "1.0.0",
        location_id: identity.locationID,
        profile_id: profile,
        supports_advanced_lighting_effects: true,
        onboard_profile_count: 1
    )
}

func makeSnapshotState(
    device: MouseDevice,
    connection: String,
    batteryPercent: Int,
    dpiValues: [Int],
    activeStage: Int
) -> MouseState {
    let dpiValue = dpiValues.indices.contains(activeStage) ? dpiValues[activeStage] : (dpiValues.first ?? 0)
    return MouseState(
        device: DeviceSummary(
            id: device.id,
            product_name: device.product_name,
            serial: device.serial,
            transport: device.transport,
            firmware: device.firmware
        ),
        connection: connection,
        battery_percent: batteryPercent,
        charging: false,
        dpi: DpiPair(x: dpiValue, y: dpiValue),
        dpi_stages: DpiStages(active_stage: activeStage, values: dpiValues),
        poll_rate: 1000,
        device_mode: DeviceMode(mode: 0x00, param: 0x00),
        led_value: 64,
        capabilities: Capabilities(
            dpi_stages: true,
            poll_rate: true,
            power_management: true,
            button_remap: true,
            lighting: true
        )
    )
}

/// Stores snapshot software lighting remote backend test data.
actor SnapshotSoftwareLightingRemoteBackend: DeviceBackend {
    nonisolated var usesRemoteServiceTransport: Bool { true }

    private var softwareLightingStartsByDeviceID: [String: Int] = [:]
    private var softwareLightingStatusByDeviceID: [String: SoftwareLightingEngineStatus] = [:]

    func listDevices() async throws -> [MouseDevice] { [] }
    func readState(device _: MouseDevice) async throws -> MouseState { throw SnapshotBackendError.unimplemented }
    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? { nil }
    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool { false }
    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .granted,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }
    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState {
        throw SnapshotBackendError.unimplemented
    }
    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? { nil }
    func startSoftwareLighting(
        device: MouseDevice,
        request: SoftwareLightingEffectRequest
    ) async throws -> SoftwareLightingEngineStatus {
        softwareLightingStartsByDeviceID[device.id, default: 0] += 1
        let status = SoftwareLightingEngineStatus(deviceID: device.id, state: .running, request: request)
        softwareLightingStatusByDeviceID[device.id] = status
        return status
    }
    func stopSoftwareLighting(deviceID: String) async -> SoftwareLightingEngineStatus? {
        let status = SoftwareLightingEngineStatus(
            deviceID: deviceID,
            state: .stopped,
            request: softwareLightingStatusByDeviceID[deviceID]?.request
        )
        softwareLightingStatusByDeviceID[deviceID] = status
        return status
    }
    func softwareLightingStatus(deviceID: String) async -> SoftwareLightingEngineStatus? {
        softwareLightingStatusByDeviceID[deviceID]
    }
    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? { nil }

    func softwareLightingStartCount(for deviceID: String) -> Int {
        softwareLightingStartsByDeviceID[deviceID, default: 0]
    }

    func softwareLightingRequest(for deviceID: String) -> SoftwareLightingEffectRequest? {
        softwareLightingStatusByDeviceID[deviceID]?.request
    }
}

/// Stores snapshot test remote backend test data.
final class SnapshotTestRemoteBackend: DeviceBackend {
    var usesRemoteServiceTransport: Bool { true }

    private let shouldUseFastDPIPollingValue: Bool
    private let diagnosticCounter = SnapshotDiagnosticCounter()

    init(shouldUseFastDPIPolling: Bool = false) {
        self.shouldUseFastDPIPollingValue = shouldUseFastDPIPolling
    }

    func listDevices() async throws -> [MouseDevice] { [] }
    func readState(device _: MouseDevice) async throws -> MouseState { throw SnapshotBackendError.unimplemented }
    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? { nil }
    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool { shouldUseFastDPIPollingValue }
    func dpiUpdateTransportStatus(device _: MouseDevice) async -> DpiUpdateTransportStatus {
        await diagnosticCounter.increment()
        return shouldUseFastDPIPollingValue ? .pollingFallback : .realTimeHID
    }
    func dpiUpdateTransportStatusRequestCount() async -> Int {
        await diagnosticCounter.count()
    }
    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .granted,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }
    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState { throw SnapshotBackendError.unimplemented }
    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? { nil }
    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? { nil }
}

/// Stores snapshot diagnostic counter test data.
actor SnapshotDiagnosticCounter {
    private var value = 0

    func increment() {
        value += 1
    }

    func count() -> Int {
        value
    }
}

/// Stores snapshot unavailable remote backend test data.
final class SnapshotUnavailableRemoteBackend: DeviceBackend {
    var usesRemoteServiceTransport: Bool { true }

    func listDevices() async throws -> [MouseDevice] { [] }
    func readState(device _: MouseDevice) async throws -> MouseState {
        throw NSError(domain: "RemoteServiceSnapshotTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Device not available"
        ])
    }
    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? { nil }
    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool { false }
    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .granted,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }
    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState {
        throw SnapshotBackendError.unimplemented
    }
    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? { nil }
    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? { nil }
}

/// Stores snapshot readback remote backend test data.
actor SnapshotReadbackRemoteBackend: DeviceBackend {
    nonisolated var usesRemoteServiceTransport: Bool { true }

    private let stateByDeviceID: [String: MouseState]
    private var readCountsByDeviceID: [String: Int] = [:]

    init(stateByDeviceID: [String: MouseState]) {
        self.stateByDeviceID = stateByDeviceID
    }

    func listDevices() async throws -> [MouseDevice] { [] }

    func readState(device: MouseDevice) async throws -> MouseState {
        readCountsByDeviceID[device.id, default: 0] += 1
        guard let state = stateByDeviceID[device.id] else {
            throw SnapshotBackendError.unimplemented
        }
        return state
    }

    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? { nil }
    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool { false }
    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .granted,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }
    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState { throw SnapshotBackendError.unimplemented }
    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? { nil }
    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? { nil }

    func readCount(for deviceID: String) -> Int {
        readCountsByDeviceID[deviceID] ?? 0
    }
}

/// Provides a snapshot recording remote backend test double.
actor SnapshotRecordingRemoteBackend: DeviceBackend {
    nonisolated var usesRemoteServiceTransport: Bool { true }

    private let device: MouseDevice
    private let state: MouseState
    private var applies: [DevicePatch] = []

    init(device: MouseDevice, state: MouseState) {
        self.device = device
        self.state = state
    }

    func listDevices() async throws -> [MouseDevice] { [device] }
    func readState(device _: MouseDevice) async throws -> MouseState { state }
    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? { nil }
    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool { false }
    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .granted,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }
    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    func apply(device _: MouseDevice, patch: DevicePatch) async throws -> MouseState {
        applies.append(patch)
        return state
    }
    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? { nil }
    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? { nil }

    func applyCount() -> Int {
        applies.count
    }
}

/// Stores remote bootstrap service backend test data.
actor RemoteBootstrapServiceBackend: DeviceBackend {
    nonisolated var usesRemoteServiceTransport: Bool { false }

    nonisolated static let device = MouseDevice(
        id: "remote-bootstrap-device",
        vendor_id: 0x068E,
        product_id: 0x00AC,
        product_name: "Bootstrap Mouse",
        transport: .bluetooth,
        path_b64: "",
        serial: "BOOTSTRAP",
        firmware: "1.0.0",
        location_id: 1,
        profile_id: .basiliskV3Pro,
        supports_advanced_lighting_effects: true,
        onboard_profile_count: 1
    )

    private let stateUpdatesStream: AsyncStream<BackendStateUpdate>
    private let stateUpdatesContinuation: AsyncStream<BackendStateUpdate>.Continuation

    private let state = MouseState(
        device: DeviceSummary(
            id: "remote-bootstrap-device",
            product_name: "Bootstrap Mouse",
            serial: "BOOTSTRAP",
            transport: .bluetooth,
            firmware: "1.0.0"
        ),
        connection: "bluetooth",
        battery_percent: 83,
        charging: false,
        dpi: DpiPair(x: 1600, y: 1600),
        dpi_stages: DpiStages(active_stage: 1, values: [800, 1600, 2400]),
        poll_rate: nil,
        sleep_timeout: 300,
        device_mode: nil,
        led_value: 64,
        capabilities: Capabilities(
            dpi_stages: true,
            poll_rate: false,
            power_management: true,
            button_remap: true,
            lighting: true
        )
    )

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: BackendStateUpdate.self)
        stateUpdatesStream = stream
        stateUpdatesContinuation = continuation
    }

    func listDevices() async throws -> [MouseDevice] { [Self.device] }
    func readState(device _: MouseDevice) async throws -> MouseState { state }
    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? {
        DpiFastSnapshot(active: 1, values: [800, 1600, 2400])
    }
    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool { false }
    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .granted,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }
    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        stateUpdatesStream
    }
    func emit(_ update: BackendStateUpdate) {
        stateUpdatesContinuation.yield(update)
    }
    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState { state }
    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? { RGBPatch(r: 12, g: 34, b: 56) }
    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? { nil }
}

/// Defines snapshot backend error test values.
enum SnapshotBackendError: Error {
    case unimplemented
}
