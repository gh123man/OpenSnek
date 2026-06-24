import Foundation
import OpenSnekCore

/// Defines apply readback policy values.
enum ApplyReadbackPolicy: String, Codable, Sendable {
    case immediateStateReadback
    case skipStateReadback
}

/// Stores apply options.
struct ApplyOptions: Codable, Sendable {
    let readbackPolicy: ApplyReadbackPolicy

    init(readbackPolicy: ApplyReadbackPolicy = .immediateStateReadback) {
        self.readbackPolicy = readbackPolicy
    }
}

/// Defines the apply options supporting backend contract.
protocol ApplyOptionsSupportingBackend: DeviceBackend {
    func apply(device: MouseDevice, patch: DevicePatch, options: ApplyOptions) async throws -> MouseState
}

/// Carries apply request data.
struct ApplyRequest: Codable, Sendable {
    let device: MouseDevice
    let patch: DevicePatch
    let options: ApplyOptions
}

/// Carries button binding read request data.
struct ButtonBindingReadRequest: Codable, Sendable {
    let device: MouseDevice
    let slot: Int
    let profile: Int
}

/// Carries software lighting start request data.
struct SoftwareLightingStartRequest: Codable, Sendable {
    let device: MouseDevice
    let request: SoftwareLightingEffectRequest
}

/// Carries software lighting status request data.
struct SoftwareLightingStatusRequest: Codable, Sendable {
    let deviceID: String
}

/// Carries software lighting stop request data.
struct SoftwareLightingStopRequest: Codable, Sendable {
    let device: MouseDevice
}

/// Carries onboard profile ID request data.
struct OnboardProfileIDRequest: Codable, Sendable {
    let device: MouseDevice
    let profileID: Int
}

/// Carries onboard profile create request data.
struct OnboardProfileCreateRequest: Codable, Sendable {
    let device: MouseDevice
    let mutation: OnboardProfileMutation
    let targetProfileID: Int?
    let replaceAssignedProfile: Bool
}

/// Carries onboard profile rename request data.
struct OnboardProfileRenameRequest: Codable, Sendable {
    let device: MouseDevice
    let profileID: Int
    let name: String
}

/// Carries onboard profile update request data.
struct OnboardProfileUpdateRequest: Codable, Sendable {
    let device: MouseDevice
    let profileID: Int
    let mutation: OnboardProfileMutation
}

/// Carries stream subscription request data.
struct StreamSubscriptionRequest: Codable, Sendable {
    let sourceProcessID: Int32
    let selectedDeviceID: String?
}

/// Defines background service stream client event values.
enum BackgroundServiceStreamClientEvent: String, Codable, Sendable {
    case clientPresence
}

/// Wraps background service stream client payload data.
struct BackgroundServiceStreamClientEnvelope: Codable, Sendable {
    let event: BackgroundServiceStreamClientEvent
    let payload: Data?
}

/// Defines background service stream server event values.
enum BackgroundServiceStreamServerEvent: String, Codable, Sendable {
    case stateUpdate
    case openSettingsRequested
}

/// Wraps background service stream server payload data.
struct BackgroundServiceStreamServerEnvelope: Codable, Sendable {
    let event: BackgroundServiceStreamServerEvent
    let payload: Data?
}

/// Defines backend codec values.
enum BackendCodec {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

/// Defines background service method values.
enum BackgroundServiceMethod: String, Codable, Sendable {
    case ping
    case listDevices
    case readState
    case readDpiStagesFast
    case usbControlAvailability
    case shouldUseFastDPIPolling
    case dpiUpdateTransportStatus
    case hidAccessStatus
    case apply
    case listOnboardProfiles
    case readOnboardProfile
    case readOnboardProfileCore
    case readOnboardProfileButtonBindings
    case createOnboardProfile
    case renameOnboardProfile
    case updateOnboardProfile
    case deleteOnboardProfile
    case activateOnboardProfile
    case refreshActiveOnboardProfile
    case readLightingColor
    case startSoftwareLighting
    case stopSoftwareLighting
    case stopAllSoftwareLighting
    case softwareLightingStatus
    case debugUSBReadButtonBinding
    case subscribeStateUpdates
}

/// Wraps background service request payload data.
struct BackgroundServiceRequestEnvelope: Codable, Sendable {
    let method: BackgroundServiceMethod
    let payload: Data?
}

/// Wraps background service response payload data.
struct BackgroundServiceResponseEnvelope: Codable, Sendable {
    let payload: Data?
    let error: String?
}
