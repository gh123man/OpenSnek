import Foundation
import OpenSnekCore

public struct OpenSnekButtonProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var bindings: [Int: ButtonBindingDraft]

    public init(id: UUID = UUID(), name: String, bindings: [Int: ButtonBindingDraft]) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bindings = bindings
    }
}

public struct OpenSnekLocalProfileContent: Codable, Hashable, Sendable {
    public var dpi: OnboardDPIProfileSnapshot?
    public var buttonBindings: [Int: ButtonBindingDraft]
    public var brightnessByLEDID: [Int: Int]
    public var staticColorByLEDID: [Int: RGBPatch]
    public var lightingEffect: LightingEffectPatch?
    public var scrollMode: Int?
    public var scrollAcceleration: Bool?
    public var scrollSmartReel: Bool?

    public init(
        dpi: OnboardDPIProfileSnapshot? = nil,
        buttonBindings: [Int: ButtonBindingDraft] = [:],
        brightnessByLEDID: [Int: Int] = [:],
        staticColorByLEDID: [Int: RGBPatch] = [:],
        lightingEffect: LightingEffectPatch? = nil,
        scrollMode: Int? = nil,
        scrollAcceleration: Bool? = nil,
        scrollSmartReel: Bool? = nil
    ) {
        self.dpi = dpi
        self.buttonBindings = buttonBindings
        self.brightnessByLEDID = brightnessByLEDID.mapValues { max(0, min(255, $0)) }
        self.staticColorByLEDID = staticColorByLEDID
        self.lightingEffect = lightingEffect
        self.scrollMode = scrollMode.map { max(0, min(1, $0)) }
        self.scrollAcceleration = scrollAcceleration
        self.scrollSmartReel = scrollSmartReel
    }

    public var hasApplicableFields: Bool {
        if dpi != nil { return true }
        if !buttonBindings.isEmpty { return true }
        if !brightnessByLEDID.isEmpty { return true }
        if !staticColorByLEDID.isEmpty { return true }
        if lightingEffect != nil { return true }
        if scrollMode != nil { return true }
        if scrollAcceleration != nil { return true }
        if scrollSmartReel != nil { return true }
        return false
    }
}

public struct OpenSnekLocalProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var onboardIdentifier: UUID?
    public var syntheticSourceKey: String?
    public var sourceDeviceProfileID: DeviceProfileID?
    public var sourceTransport: DeviceTransportKind?
    public var content: OpenSnekLocalProfileContent
    public var lastSyncedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        onboardIdentifier: UUID? = nil,
        syntheticSourceKey: String? = nil,
        sourceDeviceProfileID: DeviceProfileID? = nil,
        sourceTransport: DeviceTransportKind? = nil,
        content: OpenSnekLocalProfileContent,
        lastSyncedAt: Date = Date()
    ) {
        self.id = id
        self.name = Self.normalizedName(name)
        self.onboardIdentifier = onboardIdentifier
        self.syntheticSourceKey = Self.normalizedSyntheticSourceKey(syntheticSourceKey)
        self.sourceDeviceProfileID = sourceDeviceProfileID
        self.sourceTransport = sourceTransport
        self.content = content
        self.lastSyncedAt = lastSyncedAt
    }

    public static func normalizedName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Profile" : String(trimmed.prefix(100))
    }

    public static func normalizedSyntheticSourceKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum DeviceConnectBehavior: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case useMouseSettings = "use_mouse_settings"
    case restoreOpenSnekSettings = "restore_open_snek_settings"

    public var id: String { rawValue }
}

public struct PersistedLightingEffectPreference: Hashable, Sendable {
    public let kind: LightingEffectKind
    public let waveDirection: LightingWaveDirection
    public let reactiveSpeed: Int
    public let secondaryColor: RGBColor

    public init(
        kind: LightingEffectKind,
        waveDirection: LightingWaveDirection,
        reactiveSpeed: Int,
        secondaryColor: RGBColor
    ) {
        self.kind = kind
        self.waveDirection = waveDirection
        self.reactiveSpeed = reactiveSpeed
        self.secondaryColor = secondaryColor
    }
}

public struct PersistedDeviceSettingsSnapshot: Codable, Hashable, Sendable {
    public var stageCount: Int
    public var stageValues: [Int]
    public var stagePairs: [DpiPair]
    public var activeStage: Int
    public var pollRate: Int?
    public var sleepTimeout: Int?
    public var lowBatteryThresholdRaw: Int?
    public var scrollMode: Int?
    public var scrollAcceleration: Bool?
    public var scrollSmartReel: Bool?
    public var ledBrightness: Int?
    public var primaryLightingColor: RGBColor?
    public var lightingEffect: LightingEffectPatch?
    public var usbLightingZoneID: String
    public var buttonBindings: [Int: ButtonBindingDraft]

    public init(
        stageCount: Int,
        stageValues: [Int],
        stagePairs: [DpiPair],
        activeStage: Int,
        pollRate: Int?,
        sleepTimeout: Int?,
        lowBatteryThresholdRaw: Int?,
        scrollMode: Int?,
        scrollAcceleration: Bool?,
        scrollSmartReel: Bool?,
        ledBrightness: Int?,
        primaryLightingColor: RGBColor?,
        lightingEffect: LightingEffectPatch?,
        usbLightingZoneID: String,
        buttonBindings: [Int: ButtonBindingDraft]
    ) {
        let normalizedPairs = Array(stagePairs.prefix(DeviceProfiles.maximumDpiStageCount))
        let fallbackValues = normalizedPairs.map(\.x)
        let normalizedValues = Array(
            (stageValues.isEmpty ? fallbackValues : stageValues).prefix(DeviceProfiles.maximumDpiStageCount)
        )
        let resolvedCount = DeviceProfiles.clampDpiStageCount(
            max(stageCount, normalizedPairs.count, normalizedValues.count)
        )
        self.stageCount = resolvedCount
        self.stageValues = normalizedValues
        self.stagePairs = normalizedPairs
        self.activeStage = max(1, min(resolvedCount, activeStage))
        self.pollRate = pollRate
        self.sleepTimeout = sleepTimeout
        self.lowBatteryThresholdRaw = lowBatteryThresholdRaw
        self.scrollMode = scrollMode
        self.scrollAcceleration = scrollAcceleration
        self.scrollSmartReel = scrollSmartReel
        self.ledBrightness = ledBrightness
        self.primaryLightingColor = primaryLightingColor
        self.lightingEffect = lightingEffect
        self.usbLightingZoneID = usbLightingZoneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "all"
            : usbLightingZoneID
        self.buttonBindings = buttonBindings
    }
}

public final class DevicePreferenceStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let openSnekButtonProfilesKey = "openSnekButtonProfiles"
    private let openSnekLocalProfilesKey = "openSnekLocalProfiles"
    private let openSnekLocalProfilesMigrationKey = "openSnekLocalProfilesMigratedFromButtonProfiles"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadOpenSnekButtonProfiles() -> [OpenSnekButtonProfile] {
        guard
            let data = defaults.data(forKey: openSnekButtonProfilesKey),
            let decoded = try? JSONDecoder().decode([OpenSnekButtonProfile].self, from: data)
        else {
            return []
        }
        return decoded
    }

    public func loadOpenSnekLocalProfiles() -> [OpenSnekLocalProfile] {
        var profiles = decodedOpenSnekLocalProfiles()
        if !defaults.bool(forKey: openSnekLocalProfilesMigrationKey) {
            profiles.append(contentsOf: migratedButtonProfiles(existingLocalProfiles: profiles))
            persistOpenSnekLocalProfiles(normalizedLocalProfiles(profiles))
            defaults.set(true, forKey: openSnekLocalProfilesMigrationKey)
        }
        return sortedLocalProfiles(normalizedLocalProfiles(profiles))
    }

    @discardableResult
    public func createOpenSnekLocalProfile(
        name: String,
        content: OpenSnekLocalProfileContent = OpenSnekLocalProfileContent(),
        copying sourceID: UUID? = nil
    ) -> OpenSnekLocalProfile {
        let sourceContent = sourceID.flatMap { id in
            loadOpenSnekLocalProfiles().first(where: { $0.id == id })?.content
        }
        let profile = OpenSnekLocalProfile(
            name: name,
            content: sourceContent ?? content
        )
        var profiles = loadOpenSnekLocalProfiles()
        profiles.append(profile)
        persistOpenSnekLocalProfiles(normalizedLocalProfiles(profiles))
        return profile
    }

    @discardableResult
    public func updateOpenSnekLocalProfile(
        id: UUID,
        name: String? = nil,
        content: OpenSnekLocalProfileContent? = nil,
        onboardIdentifier: UUID? = nil,
        syntheticSourceKey: String? = nil,
        sourceDeviceProfileID: DeviceProfileID? = nil,
        sourceTransport: DeviceTransportKind? = nil
    ) -> OpenSnekLocalProfile? {
        var profiles = loadOpenSnekLocalProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        if let name {
            profiles[index].name = OpenSnekLocalProfile.normalizedName(name)
        }
        if let content {
            profiles[index].content = content
        }
        if onboardIdentifier != nil {
            profiles[index].onboardIdentifier = onboardIdentifier
        }
        if syntheticSourceKey != nil {
            profiles[index].syntheticSourceKey = OpenSnekLocalProfile.normalizedSyntheticSourceKey(syntheticSourceKey)
        }
        if sourceDeviceProfileID != nil {
            profiles[index].sourceDeviceProfileID = sourceDeviceProfileID
        }
        if sourceTransport != nil {
            profiles[index].sourceTransport = sourceTransport
        }
        profiles[index].lastSyncedAt = Date()
        persistOpenSnekLocalProfiles(normalizedLocalProfiles(profiles))
        return profiles[index]
    }

    public func deleteOpenSnekLocalProfile(id: UUID) {
        let filtered = loadOpenSnekLocalProfiles().filter { $0.id != id }
        persistOpenSnekLocalProfiles(filtered)
    }

    @discardableResult
    public func upsertOpenSnekLocalProfile(
        name: String,
        content: OpenSnekLocalProfileContent,
        onboardIdentifier: UUID? = nil,
        syntheticSourceKey: String? = nil,
        device: MouseDevice? = nil
    ) -> OpenSnekLocalProfile {
        var profiles = loadOpenSnekLocalProfiles()
        let normalizedSyntheticSourceKey = OpenSnekLocalProfile.normalizedSyntheticSourceKey(syntheticSourceKey)
        let index = profiles.firstIndex { profile in
            if let onboardIdentifier, profile.onboardIdentifier == onboardIdentifier {
                return true
            }
            if let normalizedSyntheticSourceKey, profile.syntheticSourceKey == normalizedSyntheticSourceKey {
                return true
            }
            return false
        }
        let updated: OpenSnekLocalProfile
        if let index {
            profiles[index].name = OpenSnekLocalProfile.normalizedName(name)
            profiles[index].onboardIdentifier = onboardIdentifier ?? profiles[index].onboardIdentifier
            profiles[index].syntheticSourceKey = normalizedSyntheticSourceKey ?? profiles[index].syntheticSourceKey
            profiles[index].sourceDeviceProfileID = device?.profile_id ?? profiles[index].sourceDeviceProfileID
            profiles[index].sourceTransport = device?.transport ?? profiles[index].sourceTransport
            profiles[index].content = content
            profiles[index].lastSyncedAt = Date()
            updated = profiles[index]
        } else {
            updated = OpenSnekLocalProfile(
                name: name,
                onboardIdentifier: onboardIdentifier,
                syntheticSourceKey: normalizedSyntheticSourceKey,
                sourceDeviceProfileID: device?.profile_id,
                sourceTransport: device?.transport,
                content: content
            )
            profiles.append(updated)
        }
        persistOpenSnekLocalProfiles(normalizedLocalProfiles(profiles))
        return updated
    }

    @discardableResult
    public func upsertOpenSnekLocalProfile(
        from snapshot: OnboardProfileSnapshot,
        device: MouseDevice,
        syntheticSourceKey: String? = nil
    ) -> OpenSnekLocalProfile {
        upsertOpenSnekLocalProfile(
            name: snapshot.metadata.name,
            content: OpenSnekLocalProfileContent(
                dpi: snapshot.dpi,
                buttonBindings: snapshot.buttonBindings,
                brightnessByLEDID: snapshot.brightnessByLEDID,
                staticColorByLEDID: snapshot.staticColorByLEDID,
                scrollMode: snapshot.scrollMode,
                scrollAcceleration: snapshot.scrollAcceleration,
                scrollSmartReel: snapshot.scrollSmartReel
            ),
            onboardIdentifier: syntheticSourceKey == nil ? snapshot.metadata.identifier : nil,
            syntheticSourceKey: syntheticSourceKey,
            device: device
        )
    }

    public static func localProfileSyntheticSourceKey(device: MouseDevice, slot: Int) -> String {
        if device.profile_id == .basiliskV3XHyperspeed {
            return "device-slot.profile.\(DeviceProfileID.basiliskV3XHyperspeed.rawValue).\(device.transport.rawValue).slot\(max(1, slot))"
        }
        return "device-slot.\(DevicePersistenceKeys.key(for: device)).slot\(max(1, slot))"
    }

    @discardableResult
    public func saveOpenSnekButtonProfile(name: String, bindings: [Int: ButtonBindingDraft]) -> OpenSnekButtonProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = OpenSnekButtonProfile(
            name: trimmed.isEmpty ? "Untitled Profile" : trimmed,
            bindings: bindings
        )
        var profiles = loadOpenSnekButtonProfiles()
        profiles.append(profile)
        persistOpenSnekButtonProfiles(profiles)
        return profile
    }

    @discardableResult
    public func updateOpenSnekButtonProfile(
        id: UUID,
        name: String? = nil,
        bindings: [Int: ButtonBindingDraft]? = nil
    ) -> OpenSnekButtonProfile? {
        var profiles = loadOpenSnekButtonProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            profiles[index].name = trimmed.isEmpty ? profiles[index].name : trimmed
        }
        if let bindings {
            profiles[index].bindings = bindings
        }
        persistOpenSnekButtonProfiles(profiles)
        return profiles[index]
    }

    public func deleteOpenSnekButtonProfile(id: UUID) {
        let filtered = loadOpenSnekButtonProfiles().filter { $0.id != id }
        persistOpenSnekButtonProfiles(filtered)
    }

    public func persistConnectBehavior(_ behavior: DeviceConnectBehavior, device: MouseDevice) {
        defaults.set(behavior.rawValue, forKey: connectBehaviorKey(device: device))
    }

    public func loadConnectBehavior(device: MouseDevice) -> DeviceConnectBehavior? {
        let rawValue = defaults.string(forKey: connectBehaviorKey(device: device))
            ?? defaults.string(forKey: connectBehaviorLegacyKey(device: device))
        guard let rawValue else { return nil }
        return DeviceConnectBehavior(rawValue: rawValue)
    }

    public func persistDeviceSettingsSnapshot(_ snapshot: PersistedDeviceSettingsSnapshot, device: MouseDevice) {
        guard settingStorageEnabled else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: settingsSnapshotKey(device: device))
    }

    public func loadPersistedDeviceSettingsSnapshot(device: MouseDevice) -> PersistedDeviceSettingsSnapshot? {
        let data = defaults.data(forKey: settingsSnapshotKey(device: device))
            ?? defaults.data(forKey: settingsSnapshotLegacyKey(device: device))
        guard
            let data,
            let decoded = try? JSONDecoder().decode(PersistedDeviceSettingsSnapshot.self, from: data)
        else {
            return nil
        }
        return decoded
    }

    public func persistLightingColor(_ color: RGBColor, device: MouseDevice, zoneID: String? = nil) {
        guard settingStorageEnabled else { return }
        let key = lightingColorKey(device: device, zoneID: zoneID)
        defaults.set([color.r, color.g, color.b], forKey: key)
    }

    public func loadPersistedLightingColor(device: MouseDevice, zoneID: String? = nil) -> RGBColor? {
        let values = lightingColorKeys(device: device, zoneID: zoneID)
            .lazy
            .compactMap { self.defaults.array(forKey: $0) as? [Int] }
            .first
        guard let values, values.count == 3 else { return nil }
        return RGBColor(
            r: max(0, min(255, values[0])),
            g: max(0, min(255, values[1])),
            b: max(0, min(255, values[2]))
        )
    }

    public func persistLightingZoneID(_ zoneID: String, device: MouseDevice) {
        guard settingStorageEnabled else { return }
        let key = "lightingZone.\(DevicePersistenceKeys.key(for: device))"
        defaults.set(zoneID, forKey: key)
    }

    public func loadPersistedLightingZoneID(device: MouseDevice) -> String? {
        let key = "lightingZone.\(DevicePersistenceKeys.key(for: device))"
        let legacyKey = "lightingZone.\(DevicePersistenceKeys.legacyKey(for: device))"
        let zoneID = defaults.string(forKey: key) ?? defaults.string(forKey: legacyKey)
        guard let trimmed = zoneID?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    public func persistLightingEffect(_ effect: LightingEffectPatch, device: MouseDevice) {
        guard settingStorageEnabled else { return }
        let key = "lightingEffect.\(DevicePersistenceKeys.key(for: device))"
        let persisted = PersistedLightingEffect(
            kindRaw: effect.kind.rawValue,
            waveDirectionRaw: effect.waveDirection.rawValue,
            reactiveSpeed: max(1, min(4, effect.reactiveSpeed)),
            secondaryRGB: [effect.secondary.r, effect.secondary.g, effect.secondary.b]
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        defaults.set(data, forKey: key)
    }

    public func loadPersistedLightingEffect(device: MouseDevice) -> PersistedLightingEffectPreference? {
        let key = "lightingEffect.\(DevicePersistenceKeys.key(for: device))"
        let legacyKey = "lightingEffect.\(DevicePersistenceKeys.legacyKey(for: device))"
        let data = defaults.data(forKey: key) ?? defaults.data(forKey: legacyKey)
        guard
            let data,
            let decoded = try? JSONDecoder().decode(PersistedLightingEffect.self, from: data),
            let kind = LightingEffectKind(rawValue: decoded.kindRaw)
        else {
            return nil
        }

        let direction = LightingWaveDirection(rawValue: decoded.waveDirectionRaw) ?? .left
        let speed = max(1, min(4, decoded.reactiveSpeed))
        let fallback = [0, 170, 255]
        let values = (0..<3).map { idx -> Int in
            if idx < decoded.secondaryRGB.count {
                return decoded.secondaryRGB[idx]
            }
            return fallback[idx]
        }
        let color = RGBColor(
            r: max(0, min(255, values[0])),
            g: max(0, min(255, values[1])),
            b: max(0, min(255, values[2]))
        )
        return PersistedLightingEffectPreference(
            kind: kind,
            waveDirection: direction,
            reactiveSpeed: speed,
            secondaryColor: color
        )
    }

    public func persistSoftwareLightingApplyOnConnect(_ enabled: Bool, device: MouseDevice) {
        guard settingStorageEnabled else { return }
        defaults.set(enabled, forKey: softwareLightingApplyOnConnectKey(device: device))
    }

    public func loadSoftwareLightingApplyOnConnect(device: MouseDevice) -> Bool {
        defaults.bool(forKey: softwareLightingApplyOnConnectKey(device: device))
    }

    public func persistSoftwareLightingRequest(_ request: SoftwareLightingEffectRequest, device: MouseDevice) {
        guard settingStorageEnabled else { return }
        guard let data = try? JSONEncoder().encode(request) else { return }
        defaults.set(data, forKey: softwareLightingRequestKey(device: device))
    }

    public func loadPersistedSoftwareLightingRequest(device: MouseDevice) -> SoftwareLightingEffectRequest? {
        guard
            let data = defaults.data(forKey: softwareLightingRequestKey(device: device)),
            let decoded = try? JSONDecoder().decode(SoftwareLightingEffectRequest.self, from: data)
        else {
            return nil
        }
        return decoded
    }

    public func persistButtonBinding(_ binding: ButtonBindingPatch, device: MouseDevice, profile: Int? = nil) {
        guard settingStorageEnabled else { return }
        var persisted = loadPersistedButtonBindings(device: device, profile: profile)
        persisted[binding.slot] = ButtonBindingSupport.normalizedDefaultRepresentation(
            for: binding.slot,
            draft: ButtonBindingDraft(
                kind: binding.kind,
                hidKey: binding.kind == .keyboardSimple ? max(4, min(231, binding.hidKey ?? 4)) : 4,
                hidModifiers: binding.kind == .keyboardSimple ? max(0, min(255, binding.hidModifiers ?? 0)) : 0,
                turboEnabled: binding.kind.supportsTurbo ? binding.turboEnabled : false,
                turboRate: ButtonBindingSupport.clampTurboRate(
                    binding.turboRate ?? ButtonBindingSupport.defaultTurboRate
                ),
                clutchDPI: binding.kind == .dpiClutch ? DeviceProfiles.clampDPI(binding.clutchDPI ?? ButtonBindingSupport.defaultBasiliskDPIClutchDPI, device: device) : nil
            ),
            profileID: device.profile_id
        )
        savePersistedButtonBindings(device: device, bindings: persisted, profile: profile)
    }

    public func savePersistedButtonBindings(device: MouseDevice, bindings: [Int: ButtonBindingDraft], profile: Int? = nil) {
        guard settingStorageEnabled else { return }
        let key = buttonBindingsKey(device: device, profile: profile)
        let encoded = bindings.reduce(into: [String: PersistedButtonBinding]()) { partialResult, pair in
            partialResult[String(pair.key)] = PersistedButtonBinding(
                kindRaw: pair.value.kind.rawValue,
                hidKey: pair.value.hidKey,
                hidModifiers: pair.value.hidModifiers,
                turboEnabled: pair.value.turboEnabled,
                turboRate: pair.value.turboRate,
                clutchDPI: pair.value.clutchDPI
            )
        }
        guard let data = try? JSONEncoder().encode(encoded) else { return }
        defaults.set(data, forKey: key)
        defaults.synchronize()
    }

    private var settingStorageEnabled: Bool {
        DeveloperRuntimeOptions.settingStorageEnabled(defaults: defaults)
    }

    public func loadPersistedButtonBindings(device: MouseDevice, profile: Int? = nil) -> [Int: ButtonBindingDraft] {
        let key = buttonBindingsKey(device: device, profile: profile)
        let legacyKey = buttonBindingsLegacyKey(device: device, profile: profile)
        let data = defaults.data(forKey: key) ?? legacyKey.flatMap { defaults.data(forKey: $0) }
        guard
            let data,
            let decoded = try? JSONDecoder().decode([String: PersistedButtonBinding].self, from: data)
        else {
            return [:]
        }

        let allowedSlots = Set((device.button_layout?.visibleSlots ?? ButtonSlotDescriptor.defaults).map(\.slot))
        return decoded.reduce(into: [Int: ButtonBindingDraft]()) { partialResult, pair in
            guard
                let slot = Int(pair.key),
                let kind = ButtonBindingKind(rawValue: pair.value.kindRaw),
                allowedSlots.contains(slot)
            else {
                return
            }
            partialResult[slot] = ButtonBindingSupport.normalizedDefaultRepresentation(
                for: slot,
                draft: ButtonBindingDraft(
                    kind: kind,
                    hidKey: max(4, min(231, pair.value.hidKey)),
                    hidModifiers: kind == .keyboardSimple ? max(0, min(255, pair.value.hidModifiers ?? 0)) : 0,
                    turboEnabled: kind.supportsTurbo ? pair.value.turboEnabled : false,
                    turboRate: ButtonBindingSupport.clampTurboRate(pair.value.turboRate),
                    clutchDPI: kind == .dpiClutch ? DeviceProfiles.clampDPI(pair.value.clutchDPI ?? ButtonBindingSupport.defaultBasiliskDPIClutchDPI, device: device) : nil
                ),
                profileID: device.profile_id
            )
        }
    }

    private func buttonBindingsKey(device: MouseDevice, profile: Int?) -> String {
        let base = "buttonBindings.\(DevicePersistenceKeys.key(for: device))"
        guard let profile else { return base }
        return "\(base).profile\(max(1, profile))"
    }

    private func buttonBindingsLegacyKey(device: MouseDevice, profile: Int?) -> String? {
        let legacyBase = "buttonBindings.\(DevicePersistenceKeys.legacyKey(for: device))"
        let currentBase = "buttonBindings.\(DevicePersistenceKeys.key(for: device))"
        if let profile, profile > 1 {
            return nil
        }
        return defaults.data(forKey: currentBase) == nil ? legacyBase : currentBase
    }

    private func connectBehaviorKey(device: MouseDevice) -> String {
        "connectBehavior.\(DevicePersistenceKeys.key(for: device))"
    }

    private func connectBehaviorLegacyKey(device: MouseDevice) -> String {
        "connectBehavior.\(DevicePersistenceKeys.legacyKey(for: device))"
    }

    private func settingsSnapshotKey(device: MouseDevice) -> String {
        "settingsSnapshot.\(DevicePersistenceKeys.key(for: device))"
    }

    private func settingsSnapshotLegacyKey(device: MouseDevice) -> String {
        "settingsSnapshot.\(DevicePersistenceKeys.legacyKey(for: device))"
    }

    private func lightingColorKeys(device: MouseDevice, zoneID: String?) -> [String] {
        let normalizedZoneID = normalizedLightingZoneID(zoneID)
        var keys: [String] = []
        if let normalizedZoneID {
            keys.append(lightingColorKey(device: device, zoneID: normalizedZoneID))
            keys.append(lightingColorKey(device: device, zoneID: normalizedZoneID, useLegacyKey: true))
        }
        keys.append(lightingColorKey(device: device, zoneID: nil))
        keys.append(lightingColorKey(device: device, zoneID: nil, useLegacyKey: true))
        return keys
    }

    private func lightingColorKey(device: MouseDevice, zoneID: String?, useLegacyKey: Bool = false) -> String {
        let deviceKey = useLegacyKey ? DevicePersistenceKeys.legacyKey(for: device) : DevicePersistenceKeys.key(for: device)
        guard let normalizedZoneID = normalizedLightingZoneID(zoneID) else {
            return "lightingColor.\(deviceKey)"
        }
        return "lightingColor.\(deviceKey).zone.\(normalizedZoneID)"
    }

    private func softwareLightingApplyOnConnectKey(device: MouseDevice) -> String {
        "softwareLightingApplyOnConnect.\(DevicePersistenceKeys.key(for: device))"
    }

    private func softwareLightingRequestKey(device: MouseDevice) -> String {
        "softwareLightingRequest.\(DevicePersistenceKeys.key(for: device))"
    }

    private func normalizedLightingZoneID(_ zoneID: String?) -> String? {
        guard let zoneID else { return nil }
        let trimmed = zoneID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed != "all" else { return nil }
        return trimmed
    }

    private func persistOpenSnekButtonProfiles(_ profiles: [OpenSnekButtonProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: openSnekButtonProfilesKey)
    }

    private func decodedOpenSnekLocalProfiles() -> [OpenSnekLocalProfile] {
        guard
            let data = defaults.data(forKey: openSnekLocalProfilesKey),
            let decoded = try? JSONDecoder().decode([OpenSnekLocalProfile].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private func migratedButtonProfiles(existingLocalProfiles: [OpenSnekLocalProfile]) -> [OpenSnekLocalProfile] {
        let existingIDs = Set(existingLocalProfiles.map(\.id))
        return loadOpenSnekButtonProfiles()
            .filter { !existingIDs.contains($0.id) }
            .map { profile in
                OpenSnekLocalProfile(
                    id: profile.id,
                    name: profile.name,
                    content: OpenSnekLocalProfileContent(buttonBindings: profile.bindings)
                )
            }
    }

    private func normalizedLocalProfiles(_ profiles: [OpenSnekLocalProfile]) -> [OpenSnekLocalProfile] {
        var byID: [UUID: OpenSnekLocalProfile] = [:]
        var orderedIDs: [UUID] = []
        for profile in profiles {
            let duplicateID = duplicateSyntheticBackupID(for: profile, in: byID)
            let profileID = duplicateID ?? profile.id
            if byID[profileID] == nil {
                orderedIDs.append(profileID)
            }
            if let existing = byID[profileID],
               existing.lastSyncedAt > profile.lastSyncedAt {
                continue
            }
            byID[profileID] = profile.id == profileID ? profile : localProfile(profile, replacingID: profileID)
        }
        return orderedIDs.compactMap { byID[$0] }
    }

    private func duplicateSyntheticBackupID(
        for profile: OpenSnekLocalProfile,
        in profilesByID: [UUID: OpenSnekLocalProfile]
    ) -> UUID? {
        guard profile.syntheticSourceKey != nil else { return nil }
        guard profile.sourceDeviceProfileID == .basiliskV3XHyperspeed else { return nil }
        return profilesByID.first { element in
            let existing = element.value
            return existing.syntheticSourceKey != nil &&
                existing.sourceDeviceProfileID == profile.sourceDeviceProfileID &&
                existing.sourceTransport == profile.sourceTransport
        }?.key
    }

    private func localProfile(_ profile: OpenSnekLocalProfile, replacingID id: UUID) -> OpenSnekLocalProfile {
        OpenSnekLocalProfile(
            id: id,
            name: profile.name,
            onboardIdentifier: profile.onboardIdentifier,
            syntheticSourceKey: profile.syntheticSourceKey,
            sourceDeviceProfileID: profile.sourceDeviceProfileID,
            sourceTransport: profile.sourceTransport,
            content: profile.content,
            lastSyncedAt: profile.lastSyncedAt
        )
    }

    private func sortedLocalProfiles(_ profiles: [OpenSnekLocalProfile]) -> [OpenSnekLocalProfile] {
        profiles.sorted {
            let nameOrder = $0.name.localizedCaseInsensitiveCompare($1.name)
            if nameOrder == .orderedSame {
                return $0.id.uuidString < $1.id.uuidString
            }
            return nameOrder == .orderedAscending
        }
    }

    private func persistOpenSnekLocalProfiles(_ profiles: [OpenSnekLocalProfile]) {
        guard let data = try? JSONEncoder().encode(sortedLocalProfiles(profiles)) else { return }
        defaults.set(data, forKey: openSnekLocalProfilesKey)
    }
}

private struct PersistedButtonBinding: Codable {
    let kindRaw: String
    let hidKey: Int
    let hidModifiers: Int?
    let turboEnabled: Bool
    let turboRate: Int
    let clutchDPI: Int?
}

private struct PersistedLightingEffect: Codable {
    let kindRaw: String
    let waveDirectionRaw: Int
    let reactiveSpeed: Int
    let secondaryRGB: [Int]
}
