import Foundation
import OpenSnekAppSupport
import OpenSnekCore

extension OnboardProfileSnapshot {
    var isMetadataOnly: Bool {
        dpi == nil &&
            buttonBindings.isEmpty &&
            brightnessByLEDID.isEmpty &&
            staticColorByLEDID.isEmpty &&
            scrollMode == nil &&
            scrollAcceleration == nil &&
            scrollSmartReel == nil
    }

    func replacingMetadata(_ metadata: OnboardProfileMetadata) -> OnboardProfileSnapshot {
        OnboardProfileSnapshot(
            profileID: profileID,
            metadata: metadata,
            dpi: dpi,
            buttonBindings: buttonBindings,
            brightnessByLEDID: brightnessByLEDID,
            staticColorByLEDID: staticColorByLEDID,
            scrollMode: scrollMode,
            scrollAcceleration: scrollAcceleration,
            scrollSmartReel: scrollSmartReel
        )
    }

    func replacingButtonBindings(_ bindings: [Int: ButtonBindingDraft]) -> OnboardProfileSnapshot {
        OnboardProfileSnapshot(
            profileID: profileID,
            metadata: metadata,
            dpi: dpi,
            buttonBindings: bindings,
            brightnessByLEDID: brightnessByLEDID,
            staticColorByLEDID: staticColorByLEDID,
            scrollMode: scrollMode,
            scrollAcceleration: scrollAcceleration,
            scrollSmartReel: scrollSmartReel
        )
    }

    func replacingDPI(_ dpi: OnboardDPIProfileSnapshot?) -> OnboardProfileSnapshot {
        OnboardProfileSnapshot(
            profileID: profileID,
            metadata: metadata,
            dpi: dpi,
            buttonBindings: buttonBindings,
            brightnessByLEDID: brightnessByLEDID,
            staticColorByLEDID: staticColorByLEDID,
            scrollMode: scrollMode,
            scrollAcceleration: scrollAcceleration,
            scrollSmartReel: scrollSmartReel
        )
    }
}

extension OnboardProfileMutation {
    func preservingDpiIdentity(from snapshot: OnboardProfileSnapshot?) -> OnboardProfileMutation {
        guard let dpi, let previousDPI = snapshot?.dpi else { return self }
        let stageIDs = dpi.stageIDs.isEmpty ? previousDPI.stageIDs : dpi.stageIDs
        let marker = dpi.marker ?? previousDPI.marker
        guard stageIDs != dpi.stageIDs || marker != dpi.marker else { return self }

        return OnboardProfileMutation(
            metadata: metadata,
            dpi: OnboardDPIProfileSnapshot(
                scalar: dpi.scalar,
                activeStage: dpi.activeStage,
                pairs: dpi.pairs,
                stageIDs: stageIDs,
                marker: marker
            ),
            buttonBindings: buttonBindings,
            brightnessByLEDID: brightnessByLEDID,
            staticColorByLEDID: staticColorByLEDID,
            scrollMode: scrollMode,
            scrollAcceleration: scrollAcceleration,
            scrollSmartReel: scrollSmartReel
        )
    }
}
