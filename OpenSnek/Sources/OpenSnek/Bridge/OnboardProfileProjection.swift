import Foundation
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

/// Adds scoped helpers for `OnboardProfileSnapshot`.
extension OnboardProfileSnapshot {
    func renamed(_ metadata: OnboardProfileMetadata) -> OnboardProfileSnapshot {
        OnboardProfileSnapshot(profileID: profileID, metadata: metadata, dpi: dpi, buttonBindings: buttonBindings, brightnessByLEDID: brightnessByLEDID, staticColorByLEDID: staticColorByLEDID, scrollMode: scrollMode, scrollAcceleration: scrollAcceleration, scrollSmartReel: scrollSmartReel)
    }
}

/// Adds scoped helpers for `OnboardProfileMutation`.
extension OnboardProfileMutation {
    func needsMappedContentFill(for device: MouseDevice) -> Bool {
        if dpi == nil { return true }
        if buttonBindings == nil { return true }
        if device.supportsLightingBrightnessControls, brightnessByLEDID == nil { return true }
        if device.showsLightingControls, staticColorByLEDID == nil { return true }
        if device.supportsScrollModeControls {
            if scrollMode == nil { return true }
            if scrollAcceleration == nil { return true }
            if scrollSmartReel == nil { return true }
        }
        return false
    }

    var withoutMetadata: OnboardProfileMutation {
        OnboardProfileMutation(metadata: nil, dpi: dpi, buttonBindings: buttonBindings, brightnessByLEDID: brightnessByLEDID, staticColorByLEDID: staticColorByLEDID, scrollMode: scrollMode, scrollAcceleration: scrollAcceleration, scrollSmartReel: scrollSmartReel)
    }

    func fillingMissingMappedContent(from snapshot: OnboardProfileSnapshot?) -> OnboardProfileMutation {
        guard let snapshot else { return self }
        return OnboardProfileMutation(
            metadata: metadata, dpi: dpi ?? snapshot.dpi, buttonBindings: buttonBindings ?? snapshot.buttonBindings, brightnessByLEDID: brightnessByLEDID ?? snapshot.brightnessByLEDID, staticColorByLEDID: staticColorByLEDID ?? snapshot.staticColorByLEDID,
            scrollMode: scrollMode ?? snapshot.scrollMode, scrollAcceleration: scrollAcceleration ?? snapshot.scrollAcceleration, scrollSmartReel: scrollSmartReel ?? snapshot.scrollSmartReel)
    }

    func projectedSnapshot(profileID: Int, metadata: OnboardProfileMetadata) -> OnboardProfileSnapshot {
        OnboardProfileSnapshot(
            profileID: profileID, metadata: metadata, dpi: dpi, buttonBindings: buttonBindings ?? [:], brightnessByLEDID: brightnessByLEDID ?? [:], staticColorByLEDID: staticColorByLEDID ?? [:], scrollMode: scrollMode, scrollAcceleration: scrollAcceleration, scrollSmartReel: scrollSmartReel)
    }
}
