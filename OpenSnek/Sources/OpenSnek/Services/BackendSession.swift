import Foundation
import Network
import OpenSnekCore
import OpenSnekHardware

/// Defines OpenSnek process role values.
enum OpenSnekProcessRole: String, Sendable {
    case app
    case service

    static var current: OpenSnekProcessRole { ProcessInfo.processInfo.arguments.contains("--service-mode") ? .service : .app }

    var isService: Bool { self == .service }
}

/// Defines the device backend contract.
protocol DeviceBackend: AnyObject, Sendable {
    var usesRemoteServiceTransport: Bool { get }
    func listDevices() async throws -> [MouseDevice]
    func readState(device: MouseDevice) async throws -> MouseState
    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot?
    func shouldUseFastDPIPolling(device: MouseDevice) async -> Bool
    func usbControlAvailability(device: MouseDevice) async throws -> USBControlAvailability
    func dpiUpdateTransportStatus(device: MouseDevice) async -> DpiUpdateTransportStatus
    func hidAccessStatus() async -> HIDAccessStatus
    func stateUpdates() async -> AsyncStream<BackendStateUpdate>
    func updateRemoteClientPresence(sourceProcessID: Int32, selectedDeviceID: String?) async
    func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState
    func listOnboardProfiles(device: MouseDevice) async throws -> OnboardProfileInventory
    func readOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot
    func readOnboardProfileCore(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot
    func readOnboardProfileButtonBindings(device: MouseDevice, profileID: Int) async throws -> [Int: ButtonBindingDraft]
    func createOnboardProfile(device: MouseDevice, mutation: OnboardProfileMutation, targetProfileID: Int?, replaceAssignedProfile: Bool) async throws -> OnboardProfileSnapshot
    func renameOnboardProfile(device: MouseDevice, profileID: Int, name: String) async throws -> OnboardProfileSnapshot
    func updateOnboardProfile(device: MouseDevice, profileID: Int, mutation: OnboardProfileMutation) async throws -> OnboardProfileSnapshot
    func projectOnboardProfileDPIToActiveLayer(device: MouseDevice, profileID: Int, dpi: OnboardDPIProfileSnapshot) async throws -> Bool
    func deleteOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileInventory
    func activateOnboardProfile(device: MouseDevice, profileID: Int) async throws -> MouseState
    func refreshActiveOnboardProfile(device: MouseDevice) async throws -> MouseState
    func readLightingColor(device: MouseDevice) async throws -> RGBPatch?
    func startSoftwareLighting(device: MouseDevice, request: SoftwareLightingEffectRequest) async throws -> SoftwareLightingEngineStatus
    func stopSoftwareLighting(deviceID: String) async -> SoftwareLightingEngineStatus?
    func stopSoftwareLighting(device: MouseDevice) async -> SoftwareLightingEngineStatus?
    func stopAllSoftwareLighting() async -> [SoftwareLightingEngineStatus]
    func softwareLightingStatus(deviceID: String) async -> SoftwareLightingEngineStatus?
    func debugUSBReadButtonBinding(device: MouseDevice, slot: Int, profile: Int) async throws -> [UInt8]?
}

/// Defines the HID access refresh controlling backend contract.
protocol HIDAccessRefreshControllingBackend: DeviceBackend { func hidAccessStatus(forceRefresh: Bool) async -> HIDAccessStatus }

/// Adds scoped helpers for `ApplyOptionsSupportingBackend`.
extension ApplyOptionsSupportingBackend { func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState { try await apply(device: device, patch: patch, options: ApplyOptions()) } }

/// Serializes bootstrap pending backend state and operations.
final actor BootstrapPendingBackend: DeviceBackend {
    nonisolated static let shared = BootstrapPendingBackend()

    nonisolated var usesRemoteServiceTransport: Bool { false }

    func listDevices() async throws -> [MouseDevice] { [] }

    func readState(device _: MouseDevice) async throws -> MouseState { throw BridgeError.commandFailed("Backend is still starting") }

    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? { nil }

    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool { true }

    func usbControlAvailability(device _: MouseDevice) async throws -> USBControlAvailability { .unknown }

    func dpiUpdateTransportStatus(device _: MouseDevice) async -> DpiUpdateTransportStatus { .unknown }

    func hidAccessStatus() async -> HIDAccessStatus { .unknown(detail: "Backend is still starting.") }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> { AsyncStream { _ in } }

    func updateRemoteClientPresence(sourceProcessID _: Int32, selectedDeviceID _: String?) async {}

    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState { throw BridgeError.commandFailed("Backend is still starting") }

    func listOnboardProfiles(device _: MouseDevice) async throws -> OnboardProfileInventory { throw BridgeError.commandFailed("Backend is still starting") }

    func readOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileSnapshot { throw BridgeError.commandFailed("Backend is still starting") }

    func readOnboardProfileCore(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileSnapshot { throw BridgeError.commandFailed("Backend is still starting") }

    func readOnboardProfileButtonBindings(device _: MouseDevice, profileID _: Int) async throws -> [Int: ButtonBindingDraft] { throw BridgeError.commandFailed("Backend is still starting") }

    func createOnboardProfile(device _: MouseDevice, mutation _: OnboardProfileMutation, targetProfileID _: Int?, replaceAssignedProfile _: Bool) async throws -> OnboardProfileSnapshot { throw BridgeError.commandFailed("Backend is still starting") }

    func renameOnboardProfile(device _: MouseDevice, profileID _: Int, name _: String) async throws -> OnboardProfileSnapshot { throw BridgeError.commandFailed("Backend is still starting") }

    func updateOnboardProfile(device _: MouseDevice, profileID _: Int, mutation _: OnboardProfileMutation) async throws -> OnboardProfileSnapshot { throw BridgeError.commandFailed("Backend is still starting") }

    func projectOnboardProfileDPIToActiveLayer(device _: MouseDevice, profileID _: Int, dpi _: OnboardDPIProfileSnapshot) async throws -> Bool { throw BridgeError.commandFailed("Backend is still starting") }

    func deleteOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileInventory { throw BridgeError.commandFailed("Backend is still starting") }

    func activateOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> MouseState { throw BridgeError.commandFailed("Backend is still starting") }

    func refreshActiveOnboardProfile(device _: MouseDevice) async throws -> MouseState { throw BridgeError.commandFailed("Backend is still starting") }

    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? { nil }

    func startSoftwareLighting(device _: MouseDevice, request _: SoftwareLightingEffectRequest) async throws -> SoftwareLightingEngineStatus { throw BridgeError.commandFailed("Backend is still starting") }

    func stopSoftwareLighting(deviceID _: String) async -> SoftwareLightingEngineStatus? { nil }

    func softwareLightingStatus(deviceID _: String) async -> SoftwareLightingEngineStatus? { nil }

    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? { nil }
}

/// Adds scoped helpers for `DeviceBackend`.
extension DeviceBackend {
    func usbControlAvailability(device _: MouseDevice) async throws -> USBControlAvailability { .unknown }

    func dpiUpdateTransportStatus(device: MouseDevice) async -> DpiUpdateTransportStatus {
        let usesFastPolling = await shouldUseFastDPIPolling(device: device)
        return usesFastPolling ? .pollingFallback : .realTimeHID
    }

    func updateRemoteClientPresence(sourceProcessID _: Int32, selectedDeviceID _: String?) async {}

    func listOnboardProfiles(device _: MouseDevice) async throws -> OnboardProfileInventory { throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.") }

    func readOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileSnapshot { throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.") }

    func readOnboardProfileCore(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileSnapshot { throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.") }

    func readOnboardProfileButtonBindings(device _: MouseDevice, profileID _: Int) async throws -> [Int: ButtonBindingDraft] { throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.") }

    func createOnboardProfile(device _: MouseDevice, mutation _: OnboardProfileMutation, targetProfileID _: Int?, replaceAssignedProfile _: Bool) async throws -> OnboardProfileSnapshot { throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.") }

    func renameOnboardProfile(device _: MouseDevice, profileID _: Int, name _: String) async throws -> OnboardProfileSnapshot { throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.") }

    func updateOnboardProfile(device _: MouseDevice, profileID _: Int, mutation _: OnboardProfileMutation) async throws -> OnboardProfileSnapshot { throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.") }

    func projectOnboardProfileDPIToActiveLayer(device _: MouseDevice, profileID _: Int, dpi _: OnboardDPIProfileSnapshot) async throws -> Bool { false }

    func deleteOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> OnboardProfileInventory { throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.") }

    func activateOnboardProfile(device _: MouseDevice, profileID _: Int) async throws -> MouseState { throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.") }

    func refreshActiveOnboardProfile(device _: MouseDevice) async throws -> MouseState { throw BridgeError.commandFailed("Onboard profile CRUD is not supported by this backend.") }

    func startSoftwareLighting(device _: MouseDevice, request _: SoftwareLightingEffectRequest) async throws -> SoftwareLightingEngineStatus { throw BridgeError.commandFailed("Software lighting is not supported by this backend.") }

    func stopSoftwareLighting(deviceID _: String) async -> SoftwareLightingEngineStatus? { nil }

    func stopSoftwareLighting(device: MouseDevice) async -> SoftwareLightingEngineStatus? { await stopSoftwareLighting(deviceID: device.id) }

    func stopAllSoftwareLighting() async -> [SoftwareLightingEngineStatus] { [] }

    func softwareLightingStatus(deviceID _: String) async -> SoftwareLightingEngineStatus? { nil }
}

/// Captures DPI fast state.
struct DpiFastSnapshot: Codable, Hashable, Sendable {
    let active: Int
    let values: [Int]
}

/// Defines HID access authorization values.
enum HIDAccessAuthorization: String, Codable, Sendable {
    case unknown
    case granted
    case denied
    case unavailable
}

/// Stores HID access status data.
struct HIDAccessStatus: Codable, Equatable, Sendable {
    let authorization: HIDAccessAuthorization
    let hostLabel: String
    let bundleIdentifier: String?
    let detail: String?

    static func unknown(detail: String? = nil) -> HIDAccessStatus { HIDAccessStatus(authorization: .unknown, hostLabel: PermissionSupport.currentHostLabel(), bundleIdentifier: Bundle.main.bundleIdentifier, detail: detail) }

    static func unavailable(detail: String? = nil) -> HIDAccessStatus { HIDAccessStatus(authorization: .unavailable, hostLabel: PermissionSupport.currentHostLabel(), bundleIdentifier: Bundle.main.bundleIdentifier, detail: detail) }

    var isDenied: Bool { authorization == .denied }

    var diagnosticsLabel: String {
        switch authorization {
        case .unknown: return "Checking"
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .unavailable: return "Unavailable"
        }
    }
}

/// Captures shared service state.
struct SharedServiceSnapshot: Codable, Sendable {
    let devices: [MouseDevice]
    let stateByDeviceID: [String: MouseState]
    let lastUpdatedByDeviceID: [String: Date]
    let observedAtByDeviceID: [String: Date]
    let softwareLightingStatusByDeviceID: [String: SoftwareLightingEngineStatus]
    let usbControlAvailabilityByDeviceID: [String: USBControlAvailability]

    init(
        devices: [MouseDevice], stateByDeviceID: [String: MouseState], lastUpdatedByDeviceID: [String: Date], observedAtByDeviceID: [String: Date] = [:], softwareLightingStatusByDeviceID: [String: SoftwareLightingEngineStatus] = [:],
        usbControlAvailabilityByDeviceID: [String: USBControlAvailability] = [:]
    ) {
        self.devices = devices
        self.stateByDeviceID = stateByDeviceID
        self.lastUpdatedByDeviceID = lastUpdatedByDeviceID
        self.observedAtByDeviceID = observedAtByDeviceID
        self.softwareLightingStatusByDeviceID = softwareLightingStatusByDeviceID
        self.usbControlAvailabilityByDeviceID = usbControlAvailabilityByDeviceID
    }

    /// Defines coding keys for serialized data.
    private enum CodingKeys: String, CodingKey {
        case devices
        case stateByDeviceID
        case lastUpdatedByDeviceID
        case observedAtByDeviceID
        case softwareLightingStatusByDeviceID
        case usbControlAvailabilityByDeviceID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        devices = try container.decode([MouseDevice].self, forKey: .devices)
        stateByDeviceID = try container.decode([String: MouseState].self, forKey: .stateByDeviceID)
        lastUpdatedByDeviceID = try container.decode([String: Date].self, forKey: .lastUpdatedByDeviceID)
        observedAtByDeviceID = try container.decodeIfPresent([String: Date].self, forKey: .observedAtByDeviceID) ?? [:]
        softwareLightingStatusByDeviceID = try container.decodeIfPresent([String: SoftwareLightingEngineStatus].self, forKey: .softwareLightingStatusByDeviceID) ?? [:]
        usbControlAvailabilityByDeviceID = try container.decodeIfPresent([String: USBControlAvailability].self, forKey: .usbControlAvailabilityByDeviceID) ?? [:]
    }
}

/// Stores cross process client presence data.
struct CrossProcessClientPresence: Codable, Sendable {
    let sourceProcessID: Int32
    let selectedDeviceID: String?
}

/// Defines backend state update values.
enum BackendStateUpdate: Codable, Sendable {
    case deviceList([MouseDevice], updatedAt: Date)
    case deviceState(deviceID: String, state: MouseState, updatedAt: Date)
    case dpiTransportStatus(deviceID: String, status: DpiUpdateTransportStatus, updatedAt: Date)
    case softwareLightingStatus(deviceID: String, status: SoftwareLightingEngineStatus?, updatedAt: Date)
    case usbControlAvailability(deviceID: String, availability: USBControlAvailability, updatedAt: Date)
    case snapshot(SharedServiceSnapshot)
    case openSettingsRequested
}

func mergedStateFromPassiveDpiEvent(previous: MouseState?, event: PassiveDPIEvent) -> MouseState? {
    guard let previous, let stageValues = previous.dpi_stages.values, !stageValues.isEmpty else { return nil }

    let resolvedStageValues: [Int]
    let resolvedStagePairs: [DpiPair]?
    let resolvedActiveStage: Int?
    if stageValues.count == 1, stageValues[0] == previous.dpi?.x, stageValues[0] != event.dpiX {
        // A HID-only bootstrap path only knows the most recently observed DPI.
        // Keep that single-slot fallback state fresh until a full read seeds the
        // actual stage list.
        resolvedStageValues = [event.dpiX]
        resolvedStagePairs = [DpiPair(x: event.dpiX, y: event.dpiY)]
        resolvedActiveStage = 0
    } else {
        resolvedStageValues = stageValues
        let basePairs = BridgeClient.resolveDpiStagePairs(values: stageValues, pairs: nil, fallbackPairs: previous.dpi_stages.pairs)
        let matchingIndices = stageValues.enumerated().compactMap { index, value in value == event.dpiX ? index : nil }
        if matchingIndices.count == 1, var basePairs {
            let matchedStage = matchingIndices[0]
            resolvedActiveStage = matchedStage
            if matchedStage >= 0, matchedStage < basePairs.count { basePairs[matchedStage] = DpiPair(x: event.dpiX, y: event.dpiY) }
            resolvedStagePairs = basePairs
        } else {
            resolvedActiveStage = previous.dpi_stages.active_stage
            resolvedStagePairs = basePairs
        }
    }

    return MouseState(
        device: previous.device, connection: previous.connection, battery_percent: previous.battery_percent, charging: previous.charging, dpi: DpiPair(x: event.dpiX, y: event.dpiY), dpi_stages: DpiStages(active_stage: resolvedActiveStage, values: resolvedStageValues, pairs: resolvedStagePairs),
        poll_rate: previous.poll_rate, sleep_timeout: previous.sleep_timeout, device_mode: previous.device_mode, low_battery_threshold_raw: previous.low_battery_threshold_raw, scroll_mode: previous.scroll_mode, scroll_acceleration: previous.scroll_acceleration,
        scroll_smart_reel: previous.scroll_smart_reel, active_onboard_profile: previous.active_onboard_profile, onboard_profile_count: previous.onboard_profile_count, led_value: previous.led_value, capabilities: previous.capabilities)
}
