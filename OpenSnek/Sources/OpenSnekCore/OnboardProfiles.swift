import Foundation

public enum OnboardProfileSupport: String, Codable, Hashable, Sendable {
    case unavailable
    case mappedCore

    public var isSupported: Bool {
        switch self {
        case .unavailable:
            return false
        case .mappedCore:
            return true
        }
    }
}

public enum OnboardProfileLimits {
    public static let minimumPersistentProfileID = 1
    public static let maximumPersistentProfileID = 5
    public static let minimumStoredSlotID = 1
    public static let maximumStoredSlotID = 4
    public static let storedSlotProfileIDOffset = 1
    public static let minimumStoredProfileID = minimumStoredSlotID + storedSlotProfileIDOffset

    public static func clampPersistentProfileID(_ profileID: Int) -> Int {
        max(minimumPersistentProfileID, min(maximumPersistentProfileID, profileID))
    }

    public static func containsPersistentProfileID(_ profileID: UInt8) -> Bool {
        contains(Int(profileID), lowerBound: minimumPersistentProfileID, upperBound: maximumPersistentProfileID)
    }

    public static func containsStoredProfileID(_ profileID: UInt8) -> Bool {
        contains(Int(profileID), lowerBound: minimumStoredProfileID, upperBound: maximumPersistentProfileID)
    }

    public static func containsStoredSlot(_ storedSlot: UInt8) -> Bool {
        contains(Int(storedSlot), lowerBound: minimumStoredSlotID, upperBound: maximumStoredSlotID)
    }

    public static func profileID(forStoredSlot storedSlot: UInt8) -> UInt8 {
        storedSlot &+ UInt8(storedSlotProfileIDOffset)
    }

    public static var storedProfileIDs: [UInt8] {
        (minimumStoredProfileID...maximumPersistentProfileID).map { UInt8($0) }
    }

    public static var persistentProfileIDRangeDescription: String {
        rangeDescription(minimumPersistentProfileID, maximumPersistentProfileID)
    }

    public static var storedProfileIDRangeDescription: String {
        rangeDescription(minimumStoredProfileID, maximumPersistentProfileID)
    }

    public static var storedSlotRangeDescription: String {
        rangeDescription(minimumStoredSlotID, maximumStoredSlotID)
    }

    private static func contains(_ value: Int, lowerBound: Int, upperBound: Int) -> Bool {
        value >= lowerBound && value <= upperBound
    }

    private static func rangeDescription(_ lowerBound: Int, _ upperBound: Int) -> String {
        "\(lowerBound)..\(upperBound)"
    }
}

public struct OnboardProfileMetadata: Codable, Hashable, Sendable {
    public static let synapseCompatibleFallbackOwner = "31933b5452df5708882d4fb55d0b2905f16d829500fe936c56f98d5cd0241a76"

    public let identifier: UUID
    public let name: String
    public let owner: String

    public init(
        identifier: UUID = UUID(),
        name: String,
        owner: String = "31933b5452df5708882d4fb55d0b2905f16d829500fe936c56f98d5cd0241a76"
    ) {
        self.identifier = identifier
        self.name = Self.normalizedName(name)
        self.owner = Self.normalizedOwner(owner)
    }

    public func renamed(_ name: String) -> OnboardProfileMetadata {
        OnboardProfileMetadata(identifier: identifier, name: name, owner: owner)
    }

    public func replacingOwner(_ owner: String) -> OnboardProfileMetadata {
        OnboardProfileMetadata(identifier: identifier, name: name, owner: owner)
    }

    public func withSynapseCompatibleOwner(_ owner: String? = nil) -> OnboardProfileMetadata {
        let resolvedOwner = owner.flatMap(Self.synapseCompatibleOwner(from:))
            ?? Self.synapseCompatibleOwner(from: self.owner)
            ?? Self.synapseCompatibleFallbackOwner
        return replacingOwner(resolvedOwner)
    }

    public var hasSynapseCompatibleOwner: Bool {
        Self.synapseCompatibleOwner(from: owner) != nil
    }

    public static func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Onboard Profile" : String(trimmed.prefix(100))
    }

    public static func normalizedOwner(_ value: String) -> String {
        synapseCompatibleOwner(from: value) ?? synapseCompatibleFallbackOwner
    }

    public static func isSynapseCompatibleOwner(_ value: String) -> Bool {
        synapseCompatibleOwner(from: value) != nil
    }

    public static func synapseCompatibleOwner(from value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 64 else { return nil }
        let scalars = trimmed.unicodeScalars
        guard scalars.allSatisfy({ scalar in
            (scalar.value >= 48 && scalar.value <= 57) ||
                (scalar.value >= 65 && scalar.value <= 70) ||
                (scalar.value >= 97 && scalar.value <= 102)
        }) else {
            return nil
        }
        return trimmed.lowercased()
    }
}

public struct OnboardProfileSummary: Codable, Identifiable, Hashable, Sendable {
    public let profileID: Int
    public let metadata: OnboardProfileMetadata?
    public let isAssigned: Bool
    public let isActive: Bool
    public let isBaseProfile: Bool

    public init(
        profileID: Int,
        metadata: OnboardProfileMetadata?,
        isAssigned: Bool,
        isActive: Bool,
        isBaseProfile: Bool
    ) {
        self.profileID = max(0, profileID)
        self.metadata = metadata
        self.isAssigned = isAssigned
        self.isActive = isActive
        self.isBaseProfile = isBaseProfile
    }

    public var id: Int { profileID }

    public var displayName: String {
        if let name = metadata?.name, !name.isEmpty {
            return name
        }
        if isBaseProfile {
            return "Base Profile"
        }
        return "Profile \(profileID)"
    }
}

public struct OnboardDPIProfileSnapshot: Codable, Hashable, Sendable {
    public let scalar: DpiPair?
    public let activeStage: Int?
    public let pairs: [DpiPair]
    public let stageIDs: [UInt8]
    public let marker: UInt8?

    public init(
        scalar: DpiPair?,
        activeStage: Int?,
        pairs: [DpiPair],
        stageIDs: [UInt8] = [],
        marker: UInt8? = nil
    ) {
        self.scalar = scalar
        self.activeStage = activeStage
        self.pairs = Array(pairs.prefix(DeviceProfiles.maximumDpiStageCount))
        self.stageIDs = Array(stageIDs.prefix(DeviceProfiles.maximumDpiStageCount))
        self.marker = marker
    }

    public var values: [Int] {
        pairs.map(\.x)
    }

    public var stageCount: Int {
        DeviceProfiles.clampDpiStageCount(pairs.count)
    }
}

public struct OnboardProfileSnapshot: Codable, Hashable, Sendable {
    public let profileID: Int
    public let metadata: OnboardProfileMetadata
    public let dpi: OnboardDPIProfileSnapshot?
    public let buttonBindings: [Int: ButtonBindingDraft]
    public let brightnessByLEDID: [Int: Int]
    public let staticColorByLEDID: [Int: RGBPatch]
    public let scrollMode: Int?
    public let scrollAcceleration: Bool?
    public let scrollSmartReel: Bool?

    public init(
        profileID: Int,
        metadata: OnboardProfileMetadata,
        dpi: OnboardDPIProfileSnapshot? = nil,
        buttonBindings: [Int: ButtonBindingDraft] = [:],
        brightnessByLEDID: [Int: Int] = [:],
        staticColorByLEDID: [Int: RGBPatch] = [:],
        scrollMode: Int? = nil,
        scrollAcceleration: Bool? = nil,
        scrollSmartReel: Bool? = nil
    ) {
        self.profileID = max(0, profileID)
        self.metadata = metadata
        self.dpi = dpi
        self.buttonBindings = buttonBindings
        self.brightnessByLEDID = brightnessByLEDID.mapValues { max(0, min(255, $0)) }
        self.staticColorByLEDID = staticColorByLEDID
        self.scrollMode = scrollMode.map { max(0, min(1, $0)) }
        self.scrollAcceleration = scrollAcceleration
        self.scrollSmartReel = scrollSmartReel
    }

    public var summary: OnboardProfileSummary {
        OnboardProfileSummary(
            profileID: profileID,
            metadata: metadata,
            isAssigned: profileID > 0,
            isActive: profileID == 0,
            isBaseProfile: profileID <= 1
        )
    }
}

public struct OnboardProfileMutation: Codable, Hashable, Sendable {
    public var metadata: OnboardProfileMetadata?
    public var dpi: OnboardDPIProfileSnapshot?
    public var buttonBindings: [Int: ButtonBindingDraft]?
    public var brightnessByLEDID: [Int: Int]?
    public var staticColorByLEDID: [Int: RGBPatch]?
    public var scrollMode: Int?
    public var scrollAcceleration: Bool?
    public var scrollSmartReel: Bool?

    public init(
        metadata: OnboardProfileMetadata? = nil,
        dpi: OnboardDPIProfileSnapshot? = nil,
        buttonBindings: [Int: ButtonBindingDraft]? = nil,
        brightnessByLEDID: [Int: Int]? = nil,
        staticColorByLEDID: [Int: RGBPatch]? = nil,
        scrollMode: Int? = nil,
        scrollAcceleration: Bool? = nil,
        scrollSmartReel: Bool? = nil
    ) {
        self.metadata = metadata
        self.dpi = dpi
        self.buttonBindings = buttonBindings
        self.brightnessByLEDID = brightnessByLEDID?.mapValues { max(0, min(255, $0)) }
        self.staticColorByLEDID = staticColorByLEDID
        self.scrollMode = scrollMode.map { max(0, min(1, $0)) }
        self.scrollAcceleration = scrollAcceleration
        self.scrollSmartReel = scrollSmartReel
    }

    public var isEmpty: Bool {
        if metadata != nil { return false }
        if dpi != nil { return false }
        if buttonBindings != nil { return false }
        if brightnessByLEDID != nil { return false }
        if staticColorByLEDID != nil { return false }
        if scrollMode != nil { return false }
        if scrollAcceleration != nil { return false }
        if scrollSmartReel != nil { return false }
        return true
    }

    public func merged(with newer: OnboardProfileMutation) -> OnboardProfileMutation {
        OnboardProfileMutation(
            metadata: newer.metadata ?? metadata,
            dpi: newer.dpi ?? dpi,
            buttonBindings: newer.buttonBindings ?? buttonBindings,
            brightnessByLEDID: newer.brightnessByLEDID ?? brightnessByLEDID,
            staticColorByLEDID: newer.staticColorByLEDID ?? staticColorByLEDID,
            scrollMode: newer.scrollMode ?? scrollMode,
            scrollAcceleration: newer.scrollAcceleration ?? scrollAcceleration,
            scrollSmartReel: newer.scrollSmartReel ?? scrollSmartReel
        )
    }
}

public struct OnboardProfileInventory: Codable, Hashable, Sendable {
    public let activeProfileID: Int
    public let maxProfileID: Int
    public let assignedProfileIDs: [Int]
    public let profiles: [OnboardProfileSummary]

    public init(
        activeProfileID: Int,
        maxProfileID: Int,
        assignedProfileIDs: [Int],
        profiles: [OnboardProfileSummary]
    ) {
        self.activeProfileID = max(0, activeProfileID)
        let normalizedMaxProfileID = max(1, maxProfileID)
        self.maxProfileID = normalizedMaxProfileID
        let normalizedAssigned = Set(assignedProfileIDs.map { max(1, min(normalizedMaxProfileID, $0)) })
        self.assignedProfileIDs = normalizedAssigned.sorted()
        self.profiles = profiles.sorted { lhs, rhs in
            lhs.profileID < rhs.profileID
        }
    }

    public var assignableProfileIDs: [Int] {
        guard maxProfileID >= 2 else { return [] }
        return Array(2...maxProfileID).filter { !assignedProfileIDs.contains($0) }
    }

    public func summary(for profileID: Int) -> OnboardProfileSummary? {
        profiles.first(where: { $0.profileID == profileID })
    }
}
