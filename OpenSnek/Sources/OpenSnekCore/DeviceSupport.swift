import Foundation

/// Stores button slot descriptor data.
public struct ButtonSlotDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let slot: Int
    public let friendlyName: String
    public let defaultKind: ButtonBindingKind
    /// Optional section label for devices whose slots split across swappable hardware (e.g. Naga Pro side panels). Rows with the same group are shown together under one header; `nil` renders ungrouped, matching prior behavior.
    public let group: String?

    public init(slot: Int, friendlyName: String, defaultKind: ButtonBindingKind, group: String? = nil) {
        self.slot = slot
        self.friendlyName = friendlyName
        self.defaultKind = defaultKind
        self.group = group
    }

    public var id: Int { slot }

    public static let defaults: [ButtonSlotDescriptor] = [
        ButtonSlotDescriptor(slot: 1, friendlyName: "Left Click", defaultKind: .leftClick), ButtonSlotDescriptor(slot: 2, friendlyName: "Right Click", defaultKind: .rightClick), ButtonSlotDescriptor(slot: 3, friendlyName: "Middle Click", defaultKind: .middleClick),
        ButtonSlotDescriptor(slot: 4, friendlyName: "Back Button", defaultKind: .mouseBack), ButtonSlotDescriptor(slot: 5, friendlyName: "Forward Button", defaultKind: .mouseForward), ButtonSlotDescriptor(slot: 9, friendlyName: "Scroll Up", defaultKind: .scrollUp),
        ButtonSlotDescriptor(slot: 10, friendlyName: "Scroll Down", defaultKind: .scrollDown), ButtonSlotDescriptor(slot: 96, friendlyName: "DPI Cycle", defaultKind: .default)
    ]
}

/// Defines button slot access values.
public enum ButtonSlotAccess: String, Codable, Hashable, Sendable {
    case editable
    case protocolReadOnly
    case softwareReadOnly

    public var defaultNotice: String? {
        switch self {
        case .editable: return nil
        case .protocolReadOnly: return "OpenSnek can see this button, but it cannot change it yet."
        case .softwareReadOnly: return "OpenSnek can detect this button, but this mouse does not expose remapping for it yet."
        }
    }
}

/// Stores documented button slot data.
public struct DocumentedButtonSlot: Identifiable, Hashable, Codable, Sendable {
    public let descriptor: ButtonSlotDescriptor
    public let access: ButtonSlotAccess
    public let note: String?

    public init(descriptor: ButtonSlotDescriptor, access: ButtonSlotAccess, note: String? = nil) {
        self.descriptor = descriptor
        self.access = access
        self.note = note
    }

    public var id: Int { descriptor.slot }
    public var slot: Int { descriptor.slot }
}

/// Stores button slot layout data.
public struct ButtonSlotLayout: Codable, Hashable, Sendable {
    public let visibleSlots: [ButtonSlotDescriptor]
    public let writableSlots: [Int]
    public let documentedSlots: [DocumentedButtonSlot]

    public init(visibleSlots: [ButtonSlotDescriptor], writableSlots: [Int], documentedSlots: [DocumentedButtonSlot] = []) {
        self.visibleSlots = visibleSlots
        self.writableSlots = writableSlots.sorted()

        let writable = Set(self.writableSlots)
        var documentedBySlot = Dictionary(
            uniqueKeysWithValues: visibleSlots.map { descriptor in
                let access: ButtonSlotAccess = writable.contains(descriptor.slot) ? .editable : .protocolReadOnly
                return (descriptor.slot, DocumentedButtonSlot(descriptor: descriptor, access: access))
            })
        for slot in documentedSlots { documentedBySlot[slot.slot] = slot }
        self.documentedSlots = documentedBySlot.values.sorted { $0.slot < $1.slot }
    }

    public func isEditable(_ slot: Int) -> Bool { writableSlots.contains(slot) }

    public func access(for slot: Int) -> ButtonSlotAccess { documentedSlots.first(where: { $0.slot == slot })?.access ?? (isEditable(slot) ? .editable : .protocolReadOnly) }

    public func documentedSlot(for slot: Int) -> DocumentedButtonSlot? { documentedSlots.first(where: { $0.slot == slot }) }

    public func notice(for slot: Int) -> String? { documentedSlot(for: slot)?.note ?? access(for: slot).defaultNotice }

    public var softwareReadOnlySlots: [DocumentedButtonSlot] { documentedSlots.filter { $0.access == .softwareReadOnly } }
}

/// Stores USB lighting zone descriptor data.
public struct USBLightingZoneDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let label: String
    public let ledIDs: [UInt8]

    public init(id: String, label: String, ledIDs: [UInt8]) {
        self.id = id
        self.label = label
        self.ledIDs = ledIDs
    }
}

/// Stores USB lighting target descriptor data.
public struct USBLightingTargetDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let zoneID: String
    public let zoneLabel: String
    public let ledID: UInt8

    public init(zoneID: String, zoneLabel: String, ledID: UInt8) {
        self.zoneID = zoneID
        self.zoneLabel = zoneLabel
        self.ledID = ledID
    }

    public var id: String { "\(zoneID):\(String(format: "%02X", ledID))" }
}

/// Stores passive DPI input descriptor data.
public struct PassiveDPIInputDescriptor: Hashable, Codable, Sendable {
    public let usagePage: Int
    public let usage: Int
    public let reportID: UInt8
    public let subtype: UInt8
    public let heartbeatSubtype: UInt8?
    public let profileSwitchPrefixes: [[UInt8]]
    public let profileSwitchPreludePrefixes: [[UInt8]]
    public let minInputReportSize: Int
    public let maxFeatureReportSize: Int?
    public let maximumDPI: Int

    public init(usagePage: Int, usage: Int, reportID: UInt8, subtype: UInt8, heartbeatSubtype: UInt8? = nil, profileSwitchPrefixes: [[UInt8]] = [], profileSwitchPreludePrefixes: [[UInt8]] = [], minInputReportSize: Int, maxFeatureReportSize: Int? = nil, maximumDPI: Int = 30_000) {
        self.usagePage = usagePage
        self.usage = usage
        self.reportID = reportID
        self.subtype = subtype
        self.heartbeatSubtype = heartbeatSubtype
        self.profileSwitchPrefixes = profileSwitchPrefixes
        self.profileSwitchPreludePrefixes = profileSwitchPreludePrefixes
        self.minInputReportSize = max(1, minInputReportSize)
        self.maxFeatureReportSize = maxFeatureReportSize
        self.maximumDPI = max(100, maximumDPI)
    }

    /// Defines coding keys for serialized data.
    private enum CodingKeys: String, CodingKey {
        case usagePage
        case usage
        case reportID
        case subtype
        case heartbeatSubtype
        case profileSwitchPrefixes
        case profileSwitchPreludePrefixes
        case minInputReportSize
        case maxFeatureReportSize
        case maximumDPI
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            usagePage: try container.decode(Int.self, forKey: .usagePage), usage: try container.decode(Int.self, forKey: .usage), reportID: try container.decode(UInt8.self, forKey: .reportID), subtype: try container.decode(UInt8.self, forKey: .subtype),
            heartbeatSubtype: try container.decodeIfPresent(UInt8.self, forKey: .heartbeatSubtype), profileSwitchPrefixes: try container.decodeIfPresent([[UInt8]].self, forKey: .profileSwitchPrefixes) ?? [],
            profileSwitchPreludePrefixes: try container.decodeIfPresent([[UInt8]].self, forKey: .profileSwitchPreludePrefixes) ?? [], minInputReportSize: try container.decodeIfPresent(Int.self, forKey: .minInputReportSize) ?? 6,
            maxFeatureReportSize: try container.decodeIfPresent(Int.self, forKey: .maxFeatureReportSize), maximumDPI: try container.decodeIfPresent(Int.self, forKey: .maximumDPI) ?? 30_000)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(usagePage, forKey: .usagePage)
        try container.encode(usage, forKey: .usage)
        try container.encode(reportID, forKey: .reportID)
        try container.encode(subtype, forKey: .subtype)
        try container.encodeIfPresent(heartbeatSubtype, forKey: .heartbeatSubtype)
        try container.encode(profileSwitchPrefixes, forKey: .profileSwitchPrefixes)
        try container.encode(profileSwitchPreludePrefixes, forKey: .profileSwitchPreludePrefixes)
        try container.encode(minInputReportSize, forKey: .minInputReportSize)
        try container.encodeIfPresent(maxFeatureReportSize, forKey: .maxFeatureReportSize)
        try container.encode(maximumDPI, forKey: .maximumDPI)
    }
}

/// Stores button binding draft data.
public struct ButtonBindingDraft: Hashable, Codable, Sendable {
    public var kind: ButtonBindingKind
    public var hidKey: Int
    public var hidModifiers: Int
    public var turboEnabled: Bool
    public var turboRate: Int
    public var clutchDPI: Int?

    public init(kind: ButtonBindingKind, hidKey: Int, hidModifiers: Int = 0, turboEnabled: Bool, turboRate: Int, clutchDPI: Int? = nil) {
        self.kind = kind
        self.hidKey = hidKey
        self.hidModifiers = max(0, min(255, hidModifiers))
        self.turboEnabled = turboEnabled
        self.turboRate = turboRate
        self.clutchDPI = clutchDPI.map { max(100, min(30_000, $0)) }
    }

    /// Defines coding keys for serialized data.
    private enum CodingKeys: String, CodingKey {
        case kind
        case hidKey
        case hidModifiers
        case turboEnabled
        case turboRate
        case clutchDPI
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(ButtonBindingKind.self, forKey: .kind)
        self.hidKey = try container.decode(Int.self, forKey: .hidKey)
        self.hidModifiers = max(0, min(255, try container.decodeIfPresent(Int.self, forKey: .hidModifiers) ?? 0))
        self.turboEnabled = try container.decode(Bool.self, forKey: .turboEnabled)
        self.turboRate = try container.decode(Int.self, forKey: .turboRate)
        self.clutchDPI = try container.decodeIfPresent(Int.self, forKey: .clutchDPI).map { max(100, min(30_000, $0)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(hidKey, forKey: .hidKey)
        if hidModifiers != 0 { try container.encode(hidModifiers, forKey: .hidModifiers) }
        try container.encode(turboEnabled, forKey: .turboEnabled)
        try container.encode(turboRate, forKey: .turboRate)
        try container.encodeIfPresent(clutchDPI, forKey: .clutchDPI)
    }
}

/// Stores device profile data.
public struct DeviceProfile: Hashable, Sendable {
    public let id: DeviceProfileID
    public let productName: String
    public let transport: DeviceTransportKind
    public let supportedProducts: Set<Int>
    public let usbTransactionID: UInt8?
    public let buttonLayout: ButtonSlotLayout
    public let supportsAdvancedLightingEffects: Bool
    public let supportedLightingEffects: [LightingEffectKind]
    public let usbLightingLEDIDs: [UInt8]
    public let usbLightingZones: [USBLightingZoneDescriptor]
    public let softwareLightingFrameLayout: SoftwareLightingFrameLayout?
    public let supportedSoftwareLightingPresets: [SoftwareLightingPresetID]
    public let passiveDPIInput: PassiveDPIInputDescriptor?
    public let supportsIndependentXYDPI: Bool
    public let supportsScrollModeControls: Bool
    public let supportsLightingBrightnessControls: Bool
    public let supportsLightingStateReads: Bool
    public let usesProjectedDPIStageWriteReadback: Bool
    public let onboardProfileSupport: OnboardProfileSupport
    public let onboardProfileCount: Int
    public let formFactor: DeviceFormFactor
    public let supportsDPIControls: Bool
    public let supportsPollRateControls: Bool
    public let supportsPowerManagementControls: Bool
    public let supportsButtonRemapControls: Bool
    /// Brightness write targets, also used for reads unless the profile overrides them.
    public let usbBrightnessLEDIDs: [UInt8]?
    /// Separate read targets for devices whose whole-device write address cannot be read.
    public let usbBrightnessReadLEDIDs: [UInt8]?
    public let isLocallyValidated: Bool

    public init(
        id: DeviceProfileID, productName: String, transport: DeviceTransportKind, supportedProducts: Set<Int>, usbTransactionID: UInt8? = nil, buttonLayout: ButtonSlotLayout, supportsAdvancedLightingEffects: Bool, supportedLightingEffects: [LightingEffectKind] = LightingEffectKind.allCases,
        usbLightingLEDIDs: [UInt8] = [], usbLightingZones: [USBLightingZoneDescriptor] = [], softwareLightingFrameLayout: SoftwareLightingFrameLayout? = nil, supportedSoftwareLightingPresets: [SoftwareLightingPresetID] = [], passiveDPIInput: PassiveDPIInputDescriptor? = nil,
        supportsIndependentXYDPI: Bool = false, supportsScrollModeControls: Bool = false, supportsLightingBrightnessControls: Bool = false, supportsLightingStateReads: Bool = true, usesProjectedDPIStageWriteReadback: Bool = false, onboardProfileSupport: OnboardProfileSupport = .unavailable,
        onboardProfileCount: Int = 1, formFactor: DeviceFormFactor = .mouse, supportsDPIControls: Bool = true, supportsPollRateControls: Bool = true, supportsPowerManagementControls: Bool = true, supportsButtonRemapControls: Bool = true, usbBrightnessLEDIDs: [UInt8]? = nil,
        usbBrightnessReadLEDIDs: [UInt8]? = nil, isLocallyValidated: Bool = true
    ) {
        self.id = id
        self.productName = productName
        self.transport = transport
        self.supportedProducts = supportedProducts
        self.usbTransactionID = usbTransactionID
        self.buttonLayout = buttonLayout
        self.supportsAdvancedLightingEffects = supportsAdvancedLightingEffects
        self.supportedLightingEffects = supportedLightingEffects
        self.usbLightingLEDIDs = usbLightingLEDIDs
        self.usbLightingZones = usbLightingZones
        self.softwareLightingFrameLayout = softwareLightingFrameLayout
        self.supportedSoftwareLightingPresets = supportedSoftwareLightingPresets
        self.passiveDPIInput = passiveDPIInput
        self.supportsIndependentXYDPI = supportsIndependentXYDPI
        self.supportsScrollModeControls = supportsScrollModeControls
        self.supportsLightingBrightnessControls = supportsLightingBrightnessControls
        self.supportsLightingStateReads = supportsLightingStateReads
        self.usesProjectedDPIStageWriteReadback = usesProjectedDPIStageWriteReadback
        self.onboardProfileSupport = onboardProfileSupport
        self.onboardProfileCount = max(1, onboardProfileCount)
        self.formFactor = formFactor
        self.supportsDPIControls = supportsDPIControls
        self.supportsPollRateControls = supportsPollRateControls
        self.supportsPowerManagementControls = supportsPowerManagementControls
        self.supportsButtonRemapControls = supportsButtonRemapControls
        self.usbBrightnessLEDIDs = usbBrightnessLEDIDs
        self.usbBrightnessReadLEDIDs = usbBrightnessReadLEDIDs
        self.isLocallyValidated = isLocallyValidated
    }

    public func matches(vendorID: Int, productID: Int, transport: DeviceTransportKind) -> Bool {
        guard transport == self.transport else { return false }
        let supportedVendor = vendorID == 0x1532 || vendorID == 0x068E
        return supportedVendor && supportedProducts.contains(productID)
    }

    public var allUSBLightingLEDIDs: [UInt8] {
        let ids = usbLightingLEDIDs.isEmpty ? usbLightingZones.flatMap(\.ledIDs) : usbLightingLEDIDs
        return ids.isEmpty ? [0x01] : ids
    }

    public var allUSBBrightnessLEDIDs: [UInt8] {
        guard let usbBrightnessLEDIDs, !usbBrightnessLEDIDs.isEmpty else { return allUSBLightingLEDIDs }
        return usbBrightnessLEDIDs
    }

    public var allUSBBrightnessReadLEDIDs: [UInt8] {
        guard let usbBrightnessReadLEDIDs, !usbBrightnessReadLEDIDs.isEmpty else { return allUSBBrightnessLEDIDs }
        return usbBrightnessReadLEDIDs
    }

    public func lightingZone(id zoneID: String) -> USBLightingZoneDescriptor? { usbLightingZones.first(where: { $0.id == zoneID }) }

    public func lightingTargets(for zoneID: String? = nil) -> [USBLightingTargetDescriptor]? {
        let normalizedZoneID = zoneID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalizedZoneID == nil || normalizedZoneID == "" || normalizedZoneID == "all" {
            if !usbLightingZones.isEmpty { return usbLightingZones.flatMap { zone in zone.ledIDs.map { ledID in USBLightingTargetDescriptor(zoneID: zone.id, zoneLabel: zone.label, ledID: ledID) } } }
            return allUSBLightingLEDIDs.map { ledID in USBLightingTargetDescriptor(zoneID: String(format: "led_%02x", ledID), zoneLabel: String(format: "LED 0x%02X", ledID), ledID: ledID) }
        }

        guard let zone = lightingZone(id: normalizedZoneID ?? "") else { return nil }
        return zone.ledIDs.map { ledID in USBLightingTargetDescriptor(zoneID: zone.id, zoneLabel: zone.label, ledID: ledID) }
    }

    public func lightingLEDIDs(for zoneID: String? = nil) -> [UInt8]? { lightingTargets(for: zoneID)?.map(\.ledID) }

    public var supportsMappedOnboardProfileCRUD: Bool { onboardProfileSupport == .mappedCore }
}

/// Adds scoped helpers for `MouseDevice`.
public extension MouseDevice {
    private var resolvedProfile: DeviceProfile? { DeviceProfiles.resolve(vendorID: vendor_id, productID: product_id, transport: transport) }

    var supportsSoftwareLightingEffects: Bool {
        guard transport == .usb, let profile = resolvedProfile else { return false }
        return profile.softwareLightingFrameLayout != nil && !profile.supportedSoftwareLightingPresets.isEmpty
    }

    var supportedSoftwareLightingPresets: [SoftwareLightingPresetID] {
        guard supportsSoftwareLightingEffects else { return [] }
        return resolvedProfile?.supportedSoftwareLightingPresets ?? []
    }

    // Defaults to true for unprofiled devices so existing mouse behavior is
    // unchanged; only profiles that explicitly disable DPI opt out.
    var supportsDPIControls: Bool { resolvedProfile?.supportsDPIControls ?? true }

    var supportsScrollModeControls: Bool {
        guard transport == .usb else { return false }
        return resolvedProfile?.supportsScrollModeControls ?? false
    }

    var supportsLightingBrightnessControls: Bool {
        guard showsLightingControls else { return false }
        return resolvedProfile?.supportsLightingBrightnessControls ?? false
    }

    var usesProjectedDPIStageWriteReadback: Bool { return resolvedProfile?.usesProjectedDPIStageWriteReadback ?? false }

    func supportsSoftwareLightingPreset(_ preset: SoftwareLightingPresetID) -> Bool { supportedSoftwareLightingPresets.contains(preset) }

    var softwareLightingFrameLayout: SoftwareLightingFrameLayout? {
        guard supportsSoftwareLightingEffects else { return nil }
        return resolvedProfile?.softwareLightingFrameLayout
    }
}

/// Defines device profiles values.
public enum DeviceProfiles {
    public static let minimumDPI = 100
    public static let defaultMaximumDPI = 30_000
    public static let minimumDpiStageCount = 1
    public static let maximumDpiStageCount = 5
    public static let sliderLowAnchorDPI = 2_000
    public static let sliderMidAnchorDPI = 10_000
    public static let sliderHighAnchorDPI = 20_000
    public static let sliderLowAnchorPosition = 0.5
    public static let sliderMidAnchorPosition = 0.75
    public static let sliderHighAnchorPosition = 0.9
    public static let sliderFineStepDPI = 100
    public static let sliderMidStepDPI = 250
    public static let sliderHighStepDPI = 500
    public static let sliderExtremeStepDPI = 1_000

    public static let basiliskV3XUSBLightingEffects: [LightingEffectKind] = [.off, .staticColor, .spectrum, .wave, .reactive, .pulseRandom, .pulseSingle, .pulseDual]

    public static let basiliskV335KUSBLightingEffects: [LightingEffectKind] = [.off, .staticColor, .spectrum, .wave]

    public static let basiliskV3XButtonSlots: [ButtonSlotDescriptor] = [
        ButtonSlotDescriptor(slot: 1, friendlyName: "Left Click", defaultKind: .leftClick), ButtonSlotDescriptor(slot: 2, friendlyName: "Right Click", defaultKind: .rightClick), ButtonSlotDescriptor(slot: 3, friendlyName: "Middle Click", defaultKind: .middleClick),
        ButtonSlotDescriptor(slot: 4, friendlyName: "Back Button", defaultKind: .mouseBack), ButtonSlotDescriptor(slot: 5, friendlyName: "Forward Button", defaultKind: .mouseForward), ButtonSlotDescriptor(slot: 9, friendlyName: "Scroll Up", defaultKind: .scrollUp),
        ButtonSlotDescriptor(slot: 10, friendlyName: "Scroll Down", defaultKind: .scrollDown), ButtonSlotDescriptor(slot: 96, friendlyName: "DPI Cycle", defaultKind: .default)
    ]

    public static let basiliskV3XUSBLightingZones: [USBLightingZoneDescriptor] = [USBLightingZoneDescriptor(id: "scroll_wheel", label: "Scroll Wheel", ledIDs: [0x01])]

    public static let basiliskV3XDocumentedReadOnlySlots: [DocumentedButtonSlot] = [
        DocumentedButtonSlot(descriptor: ButtonSlotDescriptor(slot: 6, friendlyName: "Hypershift / Sniper", defaultKind: .default), access: .softwareReadOnly, note: "This button uses a separate device path, so OpenSnek cannot reassign it yet.")
    ]

    public static let basiliskV3FamilyButtonSlots: [ButtonSlotDescriptor] = [
        ButtonSlotDescriptor(slot: 1, friendlyName: "Left Click", defaultKind: .leftClick), ButtonSlotDescriptor(slot: 2, friendlyName: "Right Click", defaultKind: .rightClick), ButtonSlotDescriptor(slot: 3, friendlyName: "Middle Click", defaultKind: .middleClick),
        ButtonSlotDescriptor(slot: 4, friendlyName: "Back Button", defaultKind: .mouseBack), ButtonSlotDescriptor(slot: 5, friendlyName: "Forward Button", defaultKind: .mouseForward), ButtonSlotDescriptor(slot: 9, friendlyName: "Scroll Up", defaultKind: .scrollUp),
        ButtonSlotDescriptor(slot: 10, friendlyName: "Scroll Down", defaultKind: .scrollDown), ButtonSlotDescriptor(slot: 15, friendlyName: "Sensitivity Clutch", defaultKind: .default), ButtonSlotDescriptor(slot: 52, friendlyName: "Wheel Tilt Left", defaultKind: .scrollLeft),
        ButtonSlotDescriptor(slot: 53, friendlyName: "Wheel Tilt Right", defaultKind: .scrollRight), ButtonSlotDescriptor(slot: 96, friendlyName: "DPI Button", defaultKind: .default)
    ]

    public static let basiliskV3ProBluetoothButtonSlots = basiliskV3FamilyButtonSlots
    public static let basiliskV335KUSBButtonSlots = basiliskV3FamilyButtonSlots
    public static let basiliskV3ProUSBButtonSlots = basiliskV3FamilyButtonSlots
    private static let basiliskV3USBFamilyTransactionID: UInt8 = 0x1F
    private static let basiliskV3USBFamilyLightingLEDIDs: [UInt8] = [0x01, 0x04, 0x0A]
    private static let basiliskV3USBFamilyProfileSwitchPrefixes: [[UInt8]] = [[0x05, 0x39]]

    public static let basiliskV3ProBluetoothDocumentedReadOnlySlots: [DocumentedButtonSlot] = [
        DocumentedButtonSlot(descriptor: ButtonSlotDescriptor(slot: 106, friendlyName: "Profile Button", defaultKind: .default), access: .softwareReadOnly, note: "The V3 Pro Bluetooth path still needs capture-backed profile-button defaults before OpenSnek can expose this control.")
    ]

    public static let basiliskV3USBFamilyDocumentedReadOnlySlots: [DocumentedButtonSlot] = [
        DocumentedButtonSlot(descriptor: ButtonSlotDescriptor(slot: 14, friendlyName: "Scroll Mode Toggle", defaultKind: .default), access: .protocolReadOnly, note: "OpenSnek can see this button, but the mouse does not let apps remap it yet."),
        DocumentedButtonSlot(descriptor: ButtonSlotDescriptor(slot: 106, friendlyName: "Profile Button", defaultKind: .default), access: .protocolReadOnly, note: "OpenSnek can see this button, but profile-button remap ACK/readback is not stable enough to expose yet.")
    ]

    public static let basiliskV335KUSBDocumentedReadOnlySlots = basiliskV3USBFamilyDocumentedReadOnlySlots
    public static let basiliskV3USBDocumentedReadOnlySlots = basiliskV3USBFamilyDocumentedReadOnlySlots

    public static let basiliskV335KUSBLightingZones: [USBLightingZoneDescriptor] = [
        USBLightingZoneDescriptor(id: "scroll_wheel", label: "Scroll Wheel", ledIDs: [0x01]), USBLightingZoneDescriptor(id: "logo", label: "Logo", ledIDs: [0x04]), USBLightingZoneDescriptor(id: "underglow", label: "Underglow", ledIDs: [0x0A])
    ]

    public static let basiliskV3ProUSBDocumentedReadOnlySlots = basiliskV3USBFamilyDocumentedReadOnlySlots

    public static let basiliskV3XUSB = DeviceProfile(
        id: .basiliskV3XHyperspeed, productName: "Basilisk V3 X HyperSpeed", transport: .usb, supportedProducts: [0x00B9], usbTransactionID: 0x1F,
        buttonLayout: ButtonSlotLayout(visibleSlots: basiliskV3XButtonSlots, writableSlots: basiliskV3XButtonSlots.map(\.slot), documentedSlots: basiliskV3XDocumentedReadOnlySlots), supportsAdvancedLightingEffects: true, supportedLightingEffects: basiliskV3XUSBLightingEffects,
        usbLightingLEDIDs: [0x01], usbLightingZones: basiliskV3XUSBLightingZones, passiveDPIInput: PassiveDPIInputDescriptor(usagePage: 0x01, usage: 0x06, reportID: 0x05, subtype: 0x02, minInputReportSize: 5, maximumDPI: 18_000), usesProjectedDPIStageWriteReadback: true, onboardProfileCount: 1)

    public static let basiliskV335KUSB = basiliskV3USBFamilyProfile(id: .basiliskV335K, productName: "Basilisk V3 35K", supportedProducts: [0x00CB], maximumDPI: 35_000)

    public static let basiliskV3USB = basiliskV3USBFamilyProfile(id: .basiliskV3, productName: "Basilisk V3", supportedProducts: [0x0099], maximumDPI: 26_000, isLocallyValidated: false)

    public static let basiliskV3ProUSB = basiliskV3USBFamilyProfile(id: .basiliskV3Pro, productName: "Basilisk V3 Pro", supportedProducts: [0x00AA, 0x00AB], maximumDPI: 30_000, supportedSoftwareLightingPresets: SoftwareLightingPresetID.basiliskV3ProPresets)

    private static func basiliskV3USBFamilyProfile(id: DeviceProfileID, productName: String, supportedProducts: Set<Int>, maximumDPI: Int, supportedSoftwareLightingPresets: [SoftwareLightingPresetID] = SoftwareLightingPresetID.animatedPresets, isLocallyValidated: Bool = true) -> DeviceProfile {
        DeviceProfile(
            id: id, productName: productName, transport: .usb, supportedProducts: supportedProducts, usbTransactionID: basiliskV3USBFamilyTransactionID,
            buttonLayout: ButtonSlotLayout(visibleSlots: basiliskV3FamilyButtonSlots, writableSlots: basiliskV3FamilyButtonSlots.map(\.slot), documentedSlots: basiliskV3USBFamilyDocumentedReadOnlySlots), supportsAdvancedLightingEffects: true,
            supportedLightingEffects: basiliskV335KUSBLightingEffects, usbLightingLEDIDs: basiliskV3USBFamilyLightingLEDIDs, usbLightingZones: basiliskV335KUSBLightingZones, softwareLightingFrameLayout: .basiliskV3ProUSB, supportedSoftwareLightingPresets: supportedSoftwareLightingPresets,
            passiveDPIInput: PassiveDPIInputDescriptor(usagePage: 0x01, usage: 0x06, reportID: 0x05, subtype: 0x02, profileSwitchPrefixes: basiliskV3USBFamilyProfileSwitchPrefixes, minInputReportSize: 5, maximumDPI: maximumDPI), supportsIndependentXYDPI: true, supportsScrollModeControls: true,
            supportsLightingBrightnessControls: true, onboardProfileSupport: .mappedCore, onboardProfileCount: 5, isLocallyValidated: isLocallyValidated)
    }

    public static let basiliskV3XBluetooth = DeviceProfile(
        id: .basiliskV3XHyperspeed, productName: "Basilisk V3 X HyperSpeed", transport: .bluetooth, supportedProducts: [0x00BA],
        buttonLayout: ButtonSlotLayout(visibleSlots: basiliskV3XButtonSlots, writableSlots: basiliskV3XButtonSlots.map(\.slot), documentedSlots: basiliskV3XDocumentedReadOnlySlots), supportsAdvancedLightingEffects: false, supportedLightingEffects: [.staticColor], usbLightingLEDIDs: [0x01],
        usbLightingZones: basiliskV3XUSBLightingZones, passiveDPIInput: PassiveDPIInputDescriptor(usagePage: 0x01, usage: 0x02, reportID: 0x05, subtype: 0x02, heartbeatSubtype: 0x10, minInputReportSize: 7, maxFeatureReportSize: 1, maximumDPI: 18_000), supportsLightingBrightnessControls: true,
        onboardProfileCount: 1)

    public static let basiliskV3ProBluetooth = DeviceProfile(
        id: .basiliskV3Pro, productName: "Basilisk V3 Pro", transport: .bluetooth, supportedProducts: [0x00AC],
        buttonLayout: ButtonSlotLayout(visibleSlots: basiliskV3FamilyButtonSlots, writableSlots: basiliskV3FamilyButtonSlots.map(\.slot), documentedSlots: basiliskV3ProBluetoothDocumentedReadOnlySlots), supportsAdvancedLightingEffects: false, supportedLightingEffects: [.staticColor],
        usbLightingLEDIDs: [0x01, 0x04, 0x0A], usbLightingZones: basiliskV335KUSBLightingZones,
        passiveDPIInput: PassiveDPIInputDescriptor(
            usagePage: 0x01, usage: 0x02, reportID: 0x05, subtype: 0x02, heartbeatSubtype: 0x10, profileSwitchPrefixes: [[0x05, 0x05, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]], profileSwitchPreludePrefixes: [[0x04, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]], minInputReportSize: 7,
            maxFeatureReportSize: 1, maximumDPI: 30_000), supportsIndependentXYDPI: true, supportsLightingBrightnessControls: true, onboardProfileSupport: .mappedCore, onboardProfileCount: 5)

    public static let orochiV2BluetoothButtonSlots: [ButtonSlotDescriptor] = [
        ButtonSlotDescriptor(slot: 1, friendlyName: "Left Click", defaultKind: .leftClick), ButtonSlotDescriptor(slot: 2, friendlyName: "Right Click", defaultKind: .rightClick), ButtonSlotDescriptor(slot: 3, friendlyName: "Middle Click", defaultKind: .middleClick),
        ButtonSlotDescriptor(slot: 4, friendlyName: "Back Button", defaultKind: .mouseBack), ButtonSlotDescriptor(slot: 5, friendlyName: "Forward Button", defaultKind: .mouseForward), ButtonSlotDescriptor(slot: 9, friendlyName: "Scroll Up", defaultKind: .scrollUp),
        ButtonSlotDescriptor(slot: 10, friendlyName: "Scroll Down", defaultKind: .scrollDown), ButtonSlotDescriptor(slot: 96, friendlyName: "DPI Cycle", defaultKind: .default)
    ]

    public static let orochiV2Bluetooth = DeviceProfile(
        id: .orochiV2, productName: "Orochi V2", transport: .bluetooth, supportedProducts: [0x0095], buttonLayout: ButtonSlotLayout(visibleSlots: orochiV2BluetoothButtonSlots, writableSlots: [1, 2, 3, 4, 5, 9, 10, 96]), supportsAdvancedLightingEffects: false, supportedLightingEffects: [],
        usbLightingLEDIDs: [], usbLightingZones: [], passiveDPIInput: PassiveDPIInputDescriptor(usagePage: 0x01, usage: 0x02, reportID: 0x05, subtype: 0x02, heartbeatSubtype: 0x10, minInputReportSize: 7, maxFeatureReportSize: 1, maximumDPI: 18_000), onboardProfileCount: 1)

    // Naga Pro's three swappable side panels (2-button, 6-button, 12-button) share one static firmware slot table; only one panel's buttons are physically wired at a time.
    public static let nagaProUSBButtonSlots: [ButtonSlotDescriptor] = [
        ButtonSlotDescriptor(slot: 1, friendlyName: "Left Click", defaultKind: .leftClick, group: "Mouse"), ButtonSlotDescriptor(slot: 2, friendlyName: "Right Click", defaultKind: .rightClick, group: "Mouse"),
        ButtonSlotDescriptor(slot: 3, friendlyName: "Middle Click", defaultKind: .middleClick, group: "Mouse"), ButtonSlotDescriptor(slot: 9, friendlyName: "Scroll Up", defaultKind: .scrollUp, group: "Mouse"),
        ButtonSlotDescriptor(slot: 10, friendlyName: "Scroll Down", defaultKind: .scrollDown, group: "Mouse"), ButtonSlotDescriptor(slot: 11, friendlyName: "DPI Down", defaultKind: .default, group: "Mouse"),
        ButtonSlotDescriptor(slot: 12, friendlyName: "DPI Up", defaultKind: .default, group: "Mouse"), ButtonSlotDescriptor(slot: 52, friendlyName: "Wheel Tilt Left", defaultKind: .scrollLeft, group: "Mouse"),
        ButtonSlotDescriptor(slot: 53, friendlyName: "Wheel Tilt Right", defaultKind: .scrollRight, group: "Mouse"),
        // These slots have no dedicated buttons on the mouse body itself - they only respond when the 2-button panel is installed, and are reversed from panel label order (label 1 = slot 5, label 2 = slot 4).
        ButtonSlotDescriptor(slot: 5, friendlyName: "Panel Button 1", defaultKind: .mouseForward, group: "2-Button Panel"), ButtonSlotDescriptor(slot: 4, friendlyName: "Panel Button 2", defaultKind: .mouseBack, group: "2-Button Panel"),
        // Physical press validation on the 6-button panel (2.4 GHz receiver, firmware 0x00112100) confirmed labels 1-6 map straight to slots 80-85 and every slot accepts remaps. The panel's printed numbering wraps around its physical layout, so position-based reading can look reversed.
        ButtonSlotDescriptor(slot: 80, friendlyName: "Side Button 1", defaultKind: .keyboardSimple, group: "6-Button Panel"), ButtonSlotDescriptor(slot: 81, friendlyName: "Side Button 2", defaultKind: .keyboardSimple, group: "6-Button Panel"),
        ButtonSlotDescriptor(slot: 82, friendlyName: "Side Button 3", defaultKind: .keyboardSimple, group: "6-Button Panel"), ButtonSlotDescriptor(slot: 83, friendlyName: "Side Button 4", defaultKind: .keyboardSimple, group: "6-Button Panel"),
        ButtonSlotDescriptor(slot: 84, friendlyName: "Side Button 5", defaultKind: .keyboardSimple, group: "6-Button Panel"), ButtonSlotDescriptor(slot: 85, friendlyName: "Side Button 6", defaultKind: .keyboardSimple, group: "6-Button Panel"),
        // Physical press validation also confirmed 12-button panel labels 1-12 map straight to slots 64-75 and emit keyboard 1..9, 0, -, =.
        ButtonSlotDescriptor(slot: 64, friendlyName: "Side Button 1", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 65, friendlyName: "Side Button 2", defaultKind: .keyboardSimple, group: "12-Button Panel"),
        ButtonSlotDescriptor(slot: 66, friendlyName: "Side Button 3", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 67, friendlyName: "Side Button 4", defaultKind: .keyboardSimple, group: "12-Button Panel"),
        ButtonSlotDescriptor(slot: 68, friendlyName: "Side Button 5", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 69, friendlyName: "Side Button 6", defaultKind: .keyboardSimple, group: "12-Button Panel"),
        ButtonSlotDescriptor(slot: 70, friendlyName: "Side Button 7", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 71, friendlyName: "Side Button 8", defaultKind: .keyboardSimple, group: "12-Button Panel"),
        ButtonSlotDescriptor(slot: 72, friendlyName: "Side Button 9", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 73, friendlyName: "Side Button 10", defaultKind: .keyboardSimple, group: "12-Button Panel"),
        ButtonSlotDescriptor(slot: 74, friendlyName: "Side Button 11", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 75, friendlyName: "Side Button 12", defaultKind: .keyboardSimple, group: "12-Button Panel")
    ]

    public static let nagaProUSBWritableSlots: [Int] = [1, 2, 3, 4, 5, 9, 10, 52, 53, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 80, 81, 82, 83, 84, 85]

    public static let nagaProUSBDocumentedReadOnlySlots: [DocumentedButtonSlot] = [
        DocumentedButtonSlot(descriptor: ButtonSlotDescriptor(slot: 14, friendlyName: "Scroll Mode Toggle", defaultKind: .default), access: .protocolReadOnly, note: "OpenSnek can see this button, but the mouse does not let apps remap it yet.")
    ]

    public static let nagaProUSBLightingZones: [USBLightingZoneDescriptor] = [USBLightingZoneDescriptor(id: "scroll_wheel", label: "Scroll Wheel", ledIDs: [0x01]), USBLightingZoneDescriptor(id: "logo", label: "Logo", ledIDs: [0x04])]

    public static let nagaProUSB = DeviceProfile(
        id: .nagaPro, productName: "Naga Pro", transport: .usb, supportedProducts: [0x008F, 0x0090], usbTransactionID: 0x1F, buttonLayout: ButtonSlotLayout(visibleSlots: nagaProUSBButtonSlots, writableSlots: nagaProUSBWritableSlots, documentedSlots: nagaProUSBDocumentedReadOnlySlots),
        supportsAdvancedLightingEffects: false, supportedLightingEffects: [], usbLightingLEDIDs: [0x01, 0x04], usbLightingZones: nagaProUSBLightingZones, supportsLightingBrightnessControls: true, onboardProfileSupport: .mappedCore, onboardProfileCount: 5, isLocallyValidated: false)

    // Confirmed by capture: Naga Pro's Bluetooth GATT vendor service uses the identical function-block byte encoding as its USB path, unlike the Basilisk family, which remaps to vendor ID 0x068E over Bluetooth.
    public static let nagaProBluetooth = DeviceProfile(
        id: .nagaPro, productName: "Naga Pro", transport: .bluetooth, supportedProducts: [0x0092], buttonLayout: ButtonSlotLayout(visibleSlots: nagaProUSBButtonSlots, writableSlots: nagaProUSBWritableSlots, documentedSlots: nagaProUSBDocumentedReadOnlySlots), supportsAdvancedLightingEffects: false,
        supportedLightingEffects: [], usbLightingLEDIDs: [0x01, 0x04], usbLightingZones: nagaProUSBLightingZones, supportsLightingBrightnessControls: true, onboardProfileSupport: .mappedCore, onboardProfileCount: 5, isLocallyValidated: false)

    // MARK: - Razer Naga V2 Pro (wired 0x00A7, 2.4 GHz receiver 0x00A8)

    // Contributor-validated USB profile for the Naga V2 Pro wired cable and 2.4 GHz receiver.
    // The body and side panel slot table matches the Naga Pro family, with two differences: the
    // 6-button panel slots 80-85 all carry decoded keyboard defaults, and wheel tilt keeps the
    // Basilisk-family button IDs 0x68 / 0x69. Physical press validation confirmed that the
    // 12-button panel labels 1-12 map straight to slots 64-75 (keyboard 1..9, 0, -, =) and the
    // 6-button panel labels 1-6 to slots 80-85 (keyboard 1..6). Slot 14 is the remappable bottom
    // button and its factory block cycles onboard profiles. Lighting covers the palm logo
    // (LED 0x04) and the 12-button side panel (LED 0x05). Brightness writes use LED 0x00,
    // but reads must use the logo LED 0x04: reading LED 0x00 is rejected even while awake.
    // The 6- and 2-button plates have no lighting. The scroll-mode command is rejected
    // (status 0x05), so scroll-mode controls stay hidden. See
    // captures/usb/2026-10-07-naga-v2-pro-buttons/ and captures/ble/2026-10-07-naga-v2-pro-buttons/.
    public static let nagaV2ProUSBButtonSlots: [ButtonSlotDescriptor] = [
        ButtonSlotDescriptor(slot: 1, friendlyName: "Left Click", defaultKind: .leftClick, group: "Mouse"), ButtonSlotDescriptor(slot: 2, friendlyName: "Right Click", defaultKind: .rightClick, group: "Mouse"),
        ButtonSlotDescriptor(slot: 3, friendlyName: "Middle Click", defaultKind: .middleClick, group: "Mouse"), ButtonSlotDescriptor(slot: 9, friendlyName: "Scroll Up", defaultKind: .scrollUp, group: "Mouse"),
        ButtonSlotDescriptor(slot: 10, friendlyName: "Scroll Down", defaultKind: .scrollDown, group: "Mouse"), ButtonSlotDescriptor(slot: 52, friendlyName: "Wheel Tilt Left", defaultKind: .scrollLeft, group: "Mouse"),
        ButtonSlotDescriptor(slot: 53, friendlyName: "Wheel Tilt Right", defaultKind: .scrollRight, group: "Mouse"),
        // Bottom button: remappable in Synapse and over the vendor protocol. Its factory block
        // `07 01 04` cycles onboard profiles; Synapse rewrites the class-0x06 `06 01 06` form when
        // the button is remapped to DPI-stage cycling. Physical press validation staged a keyboard
        // remap on this slot and the bottom button typed it.
        ButtonSlotDescriptor(slot: 14, friendlyName: "Bottom Button", defaultKind: .default, group: "Mouse"),
        // These slots have no dedicated buttons on the mouse body itself - they only respond when the 2-button panel is installed, and are reversed from panel label order (label 1 = slot 5, label 2 = slot 4).
        ButtonSlotDescriptor(slot: 5, friendlyName: "Panel Button 1", defaultKind: .mouseForward, group: "2-Button Panel"), ButtonSlotDescriptor(slot: 4, friendlyName: "Panel Button 2", defaultKind: .mouseBack, group: "2-Button Panel"),
        // Physical press validation on the receiver and Bluetooth confirmed that the 12-button
        // panel labels 1-12 map straight to slots 64-75 (keyboard 1..9, 0, -, =) and the 6-button
        // panel labels 1-6 map straight to slots 80-85 (keyboard 1..6). The printed numbering wraps
        // around the physical layout, so position-based reading can look reversed.
        ButtonSlotDescriptor(slot: 64, friendlyName: "Side Button 1", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 65, friendlyName: "Side Button 2", defaultKind: .keyboardSimple, group: "12-Button Panel"),
        ButtonSlotDescriptor(slot: 66, friendlyName: "Side Button 3", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 67, friendlyName: "Side Button 4", defaultKind: .keyboardSimple, group: "12-Button Panel"),
        ButtonSlotDescriptor(slot: 68, friendlyName: "Side Button 5", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 69, friendlyName: "Side Button 6", defaultKind: .keyboardSimple, group: "12-Button Panel"),
        ButtonSlotDescriptor(slot: 70, friendlyName: "Side Button 7", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 71, friendlyName: "Side Button 8", defaultKind: .keyboardSimple, group: "12-Button Panel"),
        ButtonSlotDescriptor(slot: 72, friendlyName: "Side Button 9", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 73, friendlyName: "Side Button 10", defaultKind: .keyboardSimple, group: "12-Button Panel"),
        ButtonSlotDescriptor(slot: 74, friendlyName: "Side Button 11", defaultKind: .keyboardSimple, group: "12-Button Panel"), ButtonSlotDescriptor(slot: 75, friendlyName: "Side Button 12", defaultKind: .keyboardSimple, group: "12-Button Panel"),
        ButtonSlotDescriptor(slot: 80, friendlyName: "Side Button 1", defaultKind: .keyboardSimple, group: "6-Button Panel"), ButtonSlotDescriptor(slot: 81, friendlyName: "Side Button 2", defaultKind: .keyboardSimple, group: "6-Button Panel"),
        ButtonSlotDescriptor(slot: 82, friendlyName: "Side Button 3", defaultKind: .keyboardSimple, group: "6-Button Panel"), ButtonSlotDescriptor(slot: 83, friendlyName: "Side Button 4", defaultKind: .keyboardSimple, group: "6-Button Panel"),
        ButtonSlotDescriptor(slot: 84, friendlyName: "Side Button 5", defaultKind: .keyboardSimple, group: "6-Button Panel"), ButtonSlotDescriptor(slot: 85, friendlyName: "Side Button 6", defaultKind: .keyboardSimple, group: "6-Button Panel")
    ]

    public static let nagaV2ProUSBWritableSlots: [Int] = [1, 2, 3, 4, 5, 9, 10, 14, 52, 53, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 80, 81, 82, 83, 84, 85]

    public static let nagaV2ProUSBDocumentedReadOnlySlots: [DocumentedButtonSlot] = [
        DocumentedButtonSlot(
            descriptor: ButtonSlotDescriptor(slot: 96, friendlyName: "DPI Stage Down", defaultKind: .default), access: .protocolReadOnly,
            note: "Rear top button. The native class-0x06 block implements DPI-stage cycling and the slot accepts writes, but OpenSnek preserves the factory binding until a dedicated DPI-stage binding kind ships."),
        DocumentedButtonSlot(
            descriptor: ButtonSlotDescriptor(slot: 109, friendlyName: "DPI Stage Up", defaultKind: .default), access: .protocolReadOnly,
            note: "Forward top button. The native class-0x12 block implements DPI-stage cycling and the slot accepts writes, but OpenSnek preserves the factory binding until a dedicated DPI-stage binding kind ships.")
    ]

    public static let nagaV2ProUSBLightingEffects: [LightingEffectKind] = [.off, .staticColor, .spectrum, .wave, .reactive, .pulseRandom, .pulseSingle, .pulseDual]

    public static let nagaV2ProUSBLightingZones: [USBLightingZoneDescriptor] = [USBLightingZoneDescriptor(id: "logo", label: "Logo", ledIDs: [0x04]), USBLightingZoneDescriptor(id: "side_panel", label: "Side Panel", ledIDs: [0x05])]

    public static let nagaV2ProUSB = DeviceProfile(
        id: .nagaV2Pro, productName: "Naga V2 Pro", transport: .usb, supportedProducts: [0x00A7, 0x00A8], usbTransactionID: 0x1F, buttonLayout: ButtonSlotLayout(visibleSlots: nagaV2ProUSBButtonSlots, writableSlots: nagaV2ProUSBWritableSlots, documentedSlots: nagaV2ProUSBDocumentedReadOnlySlots),
        supportsAdvancedLightingEffects: true, supportedLightingEffects: nagaV2ProUSBLightingEffects, usbLightingLEDIDs: [0x04, 0x05], usbLightingZones: nagaV2ProUSBLightingZones, softwareLightingFrameLayout: .nagaV2ProUSB, supportedSoftwareLightingPresets: SoftwareLightingPresetID.animatedPresets,
        supportsLightingBrightnessControls: true, onboardProfileSupport: .mappedCore, onboardProfileCount: 5, usbBrightnessLEDIDs: [0x00], usbBrightnessReadLEDIDs: [0x04], isLocallyValidated: false)

    // Contributor-validated Bluetooth profile for the Naga V2 Pro (vendor 0x068E, product 0x00A9).
    // The vendor GATT service exposes the same button, DPI, battery, and lighting surface as the
    // 2.4 GHz receiver. Button reads return the current and previous function blocks interleaved;
    // wheel tilt keeps the Basilisk-family IDs 0x68/0x69. Static lighting covers the logo (0x04)
    // and the 12-button side panel (0x05). Battery comes from the vendor keys 05 81 / 05 80, not
    // the standard HID battery characteristic, which reports a stale 100%. Onboard profile CRUD
    // stays on the USB profile: Bluetooth profile create/delete writes are not validated yet, and
    // leaving mapped CRUD off also keeps battery/lighting generic polling enabled. See
    // captures/ble/2026-10-07-naga-v2-pro-buttons/.
    public static let nagaV2ProBluetooth = DeviceProfile(
        id: .nagaV2Pro, productName: "Naga V2 Pro", transport: .bluetooth, supportedProducts: [0x00A9], buttonLayout: ButtonSlotLayout(visibleSlots: nagaV2ProUSBButtonSlots, writableSlots: nagaV2ProUSBWritableSlots, documentedSlots: nagaV2ProUSBDocumentedReadOnlySlots),
        supportsAdvancedLightingEffects: false, supportedLightingEffects: [.staticColor], usbLightingLEDIDs: [0x04, 0x05], usbLightingZones: nagaV2ProUSBLightingZones, supportsLightingBrightnessControls: true, isLocallyValidated: false)

    // MARK: - Razer Basilisk (2017, 0x0064)

    // OpenRazer-backed USB profile (razermouse_driver.c): extended-matrix lighting on
    // logo (0x04) + scroll wheel (0x01), 16,000 DPI ceiling, no wave effect.
    // Contributor hardware validation confirmed DPI (scalar + independent X/Y + a live
    // 5-stage table), poll-rate reads, and all listed lighting effects with transaction
    // 0x1F (OpenRazer uses 0x3F; hardware answers both). Button remap and onboard
    // profiles are not mapped yet, so those controls stay hidden.
    public static let basiliskUSBLightingEffects: [LightingEffectKind] = [.off, .staticColor, .spectrum, .reactive, .pulseRandom, .pulseSingle, .pulseDual]

    public static let basiliskUSBLightingZones: [USBLightingZoneDescriptor] = [USBLightingZoneDescriptor(id: "scroll_wheel", label: "Scroll Wheel", ledIDs: [0x01]), USBLightingZoneDescriptor(id: "logo", label: "Logo", ledIDs: [0x04])]

    public static let basiliskUSB = DeviceProfile(
        id: .basilisk, productName: "Basilisk", transport: .usb, supportedProducts: [0x0064], usbTransactionID: 0x1F, buttonLayout: ButtonSlotLayout(visibleSlots: ButtonSlotDescriptor.defaults, writableSlots: []), supportsAdvancedLightingEffects: true,
        supportedLightingEffects: basiliskUSBLightingEffects, usbLightingLEDIDs: [0x01, 0x04], usbLightingZones: basiliskUSBLightingZones, supportsIndependentXYDPI: true, supportsLightingBrightnessControls: true, supportsPowerManagementControls: false, supportsButtonRemapControls: false,
        isLocallyValidated: false)

    // MARK: - Razer Lancehead Tournament Edition (wired, 0x0060)

    // OpenRazer-backed USB profile: extended-matrix lighting on logo (0x04), scroll
    // wheel (0x01), and the left (0x11) / right (0x10) side strips, 16,000 DPI ceiling,
    // wave supported. Contributor hardware validation confirmed DPI (scalar +
    // independent X/Y + a live 5-stage table read without OpenRazer's 0xFF stage
    // transaction quirk), poll-rate reads, and all listed lighting effects with
    // transaction 0x1F. Button remap is not mapped yet.
    public static let lanceheadTEUSBLightingEffects: [LightingEffectKind] = [.off, .staticColor, .spectrum, .wave, .reactive, .pulseRandom, .pulseSingle, .pulseDual]

    public static let lanceheadTEUSBLightingZones: [USBLightingZoneDescriptor] = [
        USBLightingZoneDescriptor(id: "scroll_wheel", label: "Scroll Wheel", ledIDs: [0x01]), USBLightingZoneDescriptor(id: "logo", label: "Logo", ledIDs: [0x04]), USBLightingZoneDescriptor(id: "left_side", label: "Left Side", ledIDs: [0x11]),
        USBLightingZoneDescriptor(id: "right_side", label: "Right Side", ledIDs: [0x10])
    ]

    public static let lanceheadTEUSB = DeviceProfile(
        id: .lanceheadTournamentEdition, productName: "Lancehead Tournament Edition", transport: .usb, supportedProducts: [0x0060], usbTransactionID: 0x1F, buttonLayout: ButtonSlotLayout(visibleSlots: ButtonSlotDescriptor.defaults, writableSlots: []), supportsAdvancedLightingEffects: true,
        supportedLightingEffects: lanceheadTEUSBLightingEffects, usbLightingLEDIDs: [0x01, 0x04, 0x11, 0x10], usbLightingZones: lanceheadTEUSBLightingZones, supportsIndependentXYDPI: true, supportsLightingBrightnessControls: true, supportsPowerManagementControls: false,
        supportsButtonRemapControls: false, isLocallyValidated: false)

    // MARK: - Razer Huntsman Mini (keyboard, 0x0257)

    // OpenRazer-backed USB profile (razerkbd_driver.c): extended-matrix lighting on the
    // backlight LED (0x05). Contributor hardware validation confirmed brightness and
    // all listed effects with transaction 0x1F, and that the keyboard rejects poll-rate
    // reads (status 0x05). No DPI hardware and no mapped key remap, so only lighting is
    // exposed.
    public static let huntsmanMiniUSBLightingEffects: [LightingEffectKind] = [.off, .staticColor, .spectrum, .wave, .reactive, .pulseRandom, .pulseSingle, .pulseDual]

    public static let huntsmanMiniUSBLightingZones: [USBLightingZoneDescriptor] = [USBLightingZoneDescriptor(id: "backlight", label: "Backlight", ledIDs: [0x05])]

    public static let huntsmanMiniUSB = DeviceProfile(
        id: .huntsmanMini, productName: "Huntsman Mini", transport: .usb, supportedProducts: [0x0257], usbTransactionID: 0x1F, buttonLayout: ButtonSlotLayout(visibleSlots: [], writableSlots: []), supportsAdvancedLightingEffects: true, supportedLightingEffects: huntsmanMiniUSBLightingEffects,
        usbLightingLEDIDs: [0x05], usbLightingZones: huntsmanMiniUSBLightingZones, supportsLightingBrightnessControls: true, formFactor: .keyboard, supportsDPIControls: false, supportsPollRateControls: false, supportsPowerManagementControls: false, supportsButtonRemapControls: false,
        isLocallyValidated: false)

    // MARK: - Razer Tartarus Pro (keypad, 0x0244)

    // OpenRazer-backed USB profile: extended-matrix lighting on the backlight LED
    // (0x05) with transaction 0x1F. Brightness keeps OpenRazer's ZERO_LED addressing
    // (LED 0x00); contributor hardware validation showed 0x00 and 0x05 alias the same
    // brightness register, and confirmed all listed effects (including breathing with
    // 0x1F, without OpenRazer's 0x3F breath quirk). OpenRazer deliberately never
    // switches this device into driver mode; OpenSnek likewise only reads device mode.
    // Analog actuation and key remap have no public protocol, so only lighting is
    // exposed.
    public static let tartarusProUSBLightingEffects: [LightingEffectKind] = [.off, .staticColor, .spectrum, .wave, .reactive, .pulseRandom, .pulseSingle, .pulseDual]

    public static let tartarusProUSBLightingZones: [USBLightingZoneDescriptor] = [USBLightingZoneDescriptor(id: "backlight", label: "Backlight", ledIDs: [0x05])]

    public static let tartarusProUSB = DeviceProfile(
        id: .tartarusPro, productName: "Tartarus Pro", transport: .usb, supportedProducts: [0x0244], usbTransactionID: 0x1F, buttonLayout: ButtonSlotLayout(visibleSlots: [], writableSlots: []), supportsAdvancedLightingEffects: true, supportedLightingEffects: tartarusProUSBLightingEffects,
        usbLightingLEDIDs: [0x05], usbLightingZones: tartarusProUSBLightingZones, supportsLightingBrightnessControls: true, formFactor: .keypad, supportsDPIControls: false, supportsPollRateControls: false, supportsPowerManagementControls: false, supportsButtonRemapControls: false,
        usbBrightnessLEDIDs: [0x00], isLocallyValidated: false)

    // MARK: - Razer Mouse Dock (accessory, 0x007E)

    // OpenRazer-backed lighting accessory (razeraccessory_driver.c): extended-matrix effects
    // on the single logo LED (0x00) plus brightness on 0x0F:0x04. Contributor hardware
    // validation confirmed static color, spectrum, and brightness writes with transaction
    // 0x1F; the dock does not answer the effect-state (0x0F:0x82) or brightness (0x0F:0x84)
    // reads, so effect state and brightness report unavailable after reconnect. OpenRazer
    // lists static, spectrum, breathing, and custom effects for this dock but no wave or
    // reactive effects, so only the supported subset is exposed.
    public static let mouseDockUSBLightingEffects: [LightingEffectKind] = [.off, .staticColor, .spectrum, .pulseRandom, .pulseSingle, .pulseDual]

    public static let mouseDockUSBLightingZones: [USBLightingZoneDescriptor] = [USBLightingZoneDescriptor(id: "logo", label: "Logo", ledIDs: [0x00])]

    public static let mouseDockUSB = DeviceProfile(
        id: .mouseDock, productName: "Mouse Dock", transport: .usb, supportedProducts: [0x007E], usbTransactionID: 0x1F, buttonLayout: ButtonSlotLayout(visibleSlots: [], writableSlots: []), supportsAdvancedLightingEffects: true, supportedLightingEffects: mouseDockUSBLightingEffects,
        usbLightingLEDIDs: [0x00], usbLightingZones: mouseDockUSBLightingZones, softwareLightingFrameLayout: .mouseDockUSB, supportedSoftwareLightingPresets: SoftwareLightingPresetID.batteryMeterAndAnimatedPresets, supportsLightingBrightnessControls: true, supportsLightingStateReads: false,
        formFactor: .accessory, supportsDPIControls: false, supportsPollRateControls: false, supportsPowerManagementControls: false, supportsButtonRemapControls: false, usbBrightnessLEDIDs: [0x00], isLocallyValidated: false)

    public static let all: [DeviceProfile] = [
        basiliskV3XUSB, basiliskV3USB, basiliskV3ProUSB, basiliskV335KUSB, basiliskV3XBluetooth, basiliskV3ProBluetooth, orochiV2Bluetooth, nagaProUSB, nagaProBluetooth, nagaV2ProUSB, nagaV2ProBluetooth, basiliskUSB, lanceheadTEUSB, huntsmanMiniUSB, tartarusProUSB, mouseDockUSB
    ]

    public static func resolve(vendorID: Int, productID: Int, transport: DeviceTransportKind) -> DeviceProfile? { all.first(where: { $0.matches(vendorID: vendorID, productID: productID, transport: transport) }) }

    public static func resolveBluetoothFallback(name: String?) -> DeviceProfile? {
        guard let normalizedName = normalizedBluetoothFallbackName(name) else { return nil }
        return all.first { profile in
            guard profile.transport == .bluetooth else { return false }
            let normalizedProduct = normalizedBluetoothFallbackName(profile.productName) ?? ""
            return normalizedName == normalizedProduct || normalizedName.contains(normalizedProduct) || normalizedProduct.contains(normalizedName)
        }
    }

    private static func normalizedBluetoothFallbackName(_ name: String?) -> String? { BluetoothNameMatcher.normalized(name) }

    public static func maximumDPI(for profileID: DeviceProfileID?) -> Int {
        switch profileID {
        case .basiliskV3XHyperspeed: return 18_000
        case .basiliskV3: return 26_000
        case .basiliskV3Pro: return 30_000
        case .basiliskV335K: return 35_000
        case .orochiV2: return 18_000
        case .nagaPro: return 20_000
        case .nagaV2Pro: return 30_000
        case .basilisk: return 16_000
        case .lanceheadTournamentEdition: return 16_000
        // The Huntsman Mini, Tartarus Pro, and Mouse Dock have no DPI hardware; their
        // profiles disable DPI controls, so this value is never surfaced.
        case .huntsmanMini, .tartarusPro, .mouseDock: return defaultMaximumDPI
        case nil: return defaultMaximumDPI
        }
    }

    public static func dpiRange(for profileID: DeviceProfileID?) -> ClosedRange<Int> { minimumDPI...maximumDPI(for: profileID) }

    public static func dpiRange(for device: MouseDevice?) -> ClosedRange<Int> {
        guard let device else { return minimumDPI...defaultMaximumDPI }
        let resolvedProfileID = resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)?.id ?? device.profile_id
        return dpiRange(for: resolvedProfileID)
    }

    public static func sliderMaximumDPI(for profileID: DeviceProfileID?) -> Int { maximumDPI(for: profileID) }

    public static func sliderDpiRange(for profileID: DeviceProfileID?) -> ClosedRange<Int> { minimumDPI...sliderMaximumDPI(for: profileID) }

    public static func sliderFineMaximumDPI(for profileID: DeviceProfileID?) -> Int { min(maximumDPI(for: profileID), sliderLowAnchorDPI) }

    public static func sliderFineDpiRange(for profileID: DeviceProfileID?) -> ClosedRange<Int> { minimumDPI...sliderFineMaximumDPI(for: profileID) }

    public static func sliderScaleMarkerValues(for profileID: DeviceProfileID?) -> [Int] {
        let segments = sliderSegments(for: profileID)
        guard let first = segments.first else { return [minimumDPI] }

        var markers = [first.dpiRange.lowerBound]
        for segment in segments where markers.last != segment.dpiRange.upperBound { markers.append(segment.dpiRange.upperBound) }
        return markers
    }

    public static func clampDPI(_ value: Int, profileID: DeviceProfileID?) -> Int {
        let range = dpiRange(for: profileID)
        return max(range.lowerBound, min(range.upperBound, value))
    }

    public static func clampDPI(_ value: Int, device: MouseDevice?) -> Int {
        let range = dpiRange(for: device)
        return max(range.lowerBound, min(range.upperBound, value))
    }

    public static func clampDpiStageCount(_ count: Int) -> Int { max(minimumDpiStageCount, min(maximumDpiStageCount, count)) }

    public static func dpiSliderPosition(for value: Int, profileID: DeviceProfileID?) -> Double {
        let clamped = clampDPI(value, profileID: profileID)
        let segments = sliderSegments(for: profileID)
        guard let segment = segments.first(where: { clamped <= $0.dpiRange.upperBound }) ?? segments.last else { return 0 }
        guard segment.dpiRange.lowerBound < segment.dpiRange.upperBound else { return segment.positionRange.upperBound }

        let localFraction = Double(clamped - segment.dpiRange.lowerBound) / Double(segment.dpiRange.upperBound - segment.dpiRange.lowerBound)
        return segment.positionRange.lowerBound + (segment.positionRange.upperBound - segment.positionRange.lowerBound) * localFraction
    }

    public static func dpi(forSliderPosition position: Double, profileID: DeviceProfileID?) -> Int {
        let clampedPosition = max(0, min(1, position))
        let segments = sliderSegments(for: profileID)
        guard let segment = segments.first(where: { clampedPosition <= $0.positionRange.upperBound }) ?? segments.last else { return minimumDPI }

        guard segment.positionRange.lowerBound < segment.positionRange.upperBound else { return segment.dpiRange.upperBound }

        let localFraction = (clampedPosition - segment.positionRange.lowerBound) / (segment.positionRange.upperBound - segment.positionRange.lowerBound)
        let rawValue = Double(segment.dpiRange.lowerBound) + localFraction * Double(segment.dpiRange.upperBound - segment.dpiRange.lowerBound)
        return quantizedSliderDPI(rawValue, step: segment.step, within: segment.dpiRange)
    }

    private static func quantizedSliderDPI(_ value: Double, step: Int, within range: ClosedRange<Int>) -> Int {
        let quantized = Int(round(value / Double(step)) * Double(step))
        return max(range.lowerBound, min(range.upperBound, quantized))
    }

    private static func sliderSegments(for profileID: DeviceProfileID?) -> [DpiSliderSegment] {
        let maximum = sliderMaximumDPI(for: profileID)
        guard maximum > minimumDPI else { return [DpiSliderSegment(positionRange: 0...1, dpiRange: minimumDPI...maximum, step: sliderFineStepDPI)] }

        let lowUpper = min(maximum, sliderLowAnchorDPI)
        if maximum <= sliderLowAnchorDPI { return [DpiSliderSegment(positionRange: 0...1, dpiRange: minimumDPI...maximum, step: sliderFineStepDPI)] }

        var segments = [DpiSliderSegment(positionRange: 0...sliderLowAnchorPosition, dpiRange: minimumDPI...lowUpper, step: sliderFineStepDPI)]

        let midUpper = min(maximum, sliderMidAnchorDPI)
        if maximum <= sliderMidAnchorDPI {
            segments.append(DpiSliderSegment(positionRange: sliderLowAnchorPosition...1, dpiRange: lowUpper...maximum, step: sliderMidStepDPI))
            return segments
        }

        segments.append(DpiSliderSegment(positionRange: sliderLowAnchorPosition...sliderMidAnchorPosition, dpiRange: lowUpper...midUpper, step: sliderMidStepDPI))

        let highUpper = min(maximum, sliderHighAnchorDPI)
        if maximum <= sliderHighAnchorDPI {
            segments.append(DpiSliderSegment(positionRange: sliderMidAnchorPosition...1, dpiRange: midUpper...maximum, step: sliderHighStepDPI))
            return segments
        }

        segments.append(DpiSliderSegment(positionRange: sliderMidAnchorPosition...sliderHighAnchorPosition, dpiRange: midUpper...highUpper, step: sliderHighStepDPI))
        segments.append(DpiSliderSegment(positionRange: sliderHighAnchorPosition...1, dpiRange: highUpper...maximum, step: sliderExtremeStepDPI))
        return segments
    }

    /// Stores DPI slider segment data.
    private struct DpiSliderSegment {
        let positionRange: ClosedRange<Double>
        let dpiRange: ClosedRange<Int>
        let step: Int
    }

    public static func supportsIndependentXYDPI(for profileID: DeviceProfileID?) -> Bool {
        switch profileID {
        case .basiliskV3, .basiliskV3Pro, .basiliskV335K, .basilisk, .lanceheadTournamentEdition: return true
        case .basiliskV3XHyperspeed, .orochiV2, .nagaPro, .nagaV2Pro, .huntsmanMini, .tartarusPro, .mouseDock, nil: return false
        }
    }

    public static func supportsIndependentXYDPI(for device: MouseDevice?) -> Bool {
        guard let device else { return false }
        return resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)?.supportsIndependentXYDPI ?? supportsIndependentXYDPI(for: device.profile_id)
    }
}
