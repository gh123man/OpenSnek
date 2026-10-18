import Foundation
import OpenSnekCore

/// The zone scope shown by the USB lighting card's zone picker.
///
/// The card used to keep this as private view state that was never written back to the editor store,
/// so the picker could read "All Zones" while the store still held a single zone from an earlier
/// per-zone edit. Every static-effect apply then targeted that one zone's LED, which looked like
/// "switching Off to Static only lights the wheel". Deriving the mode from the stored zone id keeps
/// the picker and the apply path in agreement.
enum LightingZoneEditMode: String, CaseIterable, Identifiable {
    case allZones
    case individualZones

    /// The stored zone id that means "every zone".
    static let allZonesZoneID = "all"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allZones: return "All Zones"
        case .individualZones: return "Individual Zones"
        }
    }

    init(zoneID: String) { self = zoneID == Self.allZonesZoneID ? .allZones : .individualZones }

    /// Resolves the zone id to store when this mode is selected.
    ///
    /// Switching to individual zones needs a concrete zone; the first available zone is used when the
    /// current id is the "all" sentinel.
    func resolvedZoneID(currentZoneID: String, availableZoneIDs: [String]) -> String {
        switch self {
        case .allZones: return Self.allZonesZoneID
        case .individualZones:
            guard currentZoneID == Self.allZonesZoneID || !availableZoneIDs.contains(currentZoneID) else { return currentZoneID }
            return availableZoneIDs.first ?? Self.allZonesZoneID
        }
    }

    /// The LED ids a static-colour apply should target, or `nil` for every LED of the profile.
    static func staticColorLEDIDs(zoneID: String, zones: [USBLightingZoneDescriptor]) -> [UInt8]? {
        guard zoneID != allZonesZoneID else { return nil }
        return zones.first(where: { $0.id == zoneID })?.ledIDs
    }
}
