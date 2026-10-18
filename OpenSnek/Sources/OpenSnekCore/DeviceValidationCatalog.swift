import Foundation

/// Exports shipped profile facts for offline validation tools without opening any hardware.
public struct DeviceValidationCatalog: Codable, Sendable {
    public let schemaVersion: Int
    public let profiles: [Profile]

    public init(profiles: [DeviceProfile] = DeviceProfiles.all) {
        schemaVersion = 1
        self.profiles = profiles.map(Profile.init)
    }

    /// Contains code-owned facts, not a claim that every shipped capability has hardware evidence.
    public struct Profile: Codable, Sendable {
        public let id: String
        public let transport: String
        public let productIDs: [Int]
        public let isLocallyValidated: Bool
        public let capabilities: [String: Bool]

        init(_ profile: DeviceProfile) {
            id = profile.id.rawValue
            transport = profile.transport.rawValue
            productIDs = profile.supportedProducts.sorted()
            isLocallyValidated = profile.isLocallyValidated
            capabilities = Dictionary(uniqueKeysWithValues: Feature.allCases.map { ($0.rawValue, $0.isSupported(by: profile)) })
        }
    }

    /// Names the bounded capability fields a validation manifest may claim.
    private enum Feature: String, CaseIterable {
        case dpiStages = "dpi_stages"
        case independentXY = "independent_xy"
        case pollRate = "poll_rate"
        case powerManagement = "power_management"
        case buttonRemap = "button_remap"
        case lightingBrightness = "lighting_brightness"
        case advancedLighting = "advanced_lighting_effects"
        case onboardProfiles = "onboard_profiles"
        case softwareLighting = "software_lighting"
        case scrollControls = "scroll_controls"

        func isSupported(by profile: DeviceProfile) -> Bool {
            switch self {
            case .dpiStages: return profile.supportsDPIControls
            case .independentXY: return profile.supportsIndependentXYDPI
            case .pollRate: return profile.transport == .usb && profile.supportsPollRateControls
            case .powerManagement: return profile.supportsPowerManagementControls
            case .buttonRemap: return profile.supportsButtonRemapControls
            case .lightingBrightness: return profile.supportsLightingBrightnessControls
            case .advancedLighting: return profile.supportsAdvancedLightingEffects
            case .onboardProfiles: return profile.supportsMappedOnboardProfileCRUD
            case .softwareLighting: return profile.transport == .usb && profile.softwareLightingFrameLayout != nil && !profile.supportedSoftwareLightingPresets.isEmpty
            case .scrollControls: return profile.transport == .usb && profile.supportsScrollModeControls
            }
        }
    }
}
