import Foundation
import OpenSnekAppSupport
import OpenSnekCore

@MainActor
extension AppStateApplyController {
    private struct LocalProfileLightingPatch {
        let rgb: RGBPatch?
        let effect: LightingEffectPatch?
        let ledIDs: [UInt8]?
    }

    @discardableResult
    func applyLocalProfileContent(
        _ content: OpenSnekLocalProfileContent,
        to device: MouseDevice
    ) async -> Bool {
        let dpiPairs = content.dpi?.pairs
        let dpiStageCount = DeviceProfiles.clampDpiStageCount(dpiPairs?.count ?? 0)
        let dpiPatchPairs = dpiPairs.map { Array($0.prefix(dpiStageCount)) }
        let dpiPatchValues = dpiPatchPairs?.map(\.x)
        let activeStage = content.dpi?.activeStage.map { active in
            max(0, min(max(0, dpiStageCount - 1), active))
        }
        let lightingPatch = localProfileLightingPatch(content, device: device)
        let supportsScrollModeControls = device.supportsScrollModeControls
        let patch = DevicePatch(
            scrollMode: supportsScrollModeControls ? content.scrollMode : nil,
            scrollAcceleration: supportsScrollModeControls ? content.scrollAcceleration : nil,
            scrollSmartReel: supportsScrollModeControls ? content.scrollSmartReel : nil,
            dpiStages: dpiPatchValues?.isEmpty == false ? dpiPatchValues : nil,
            dpiStagePairs: dpiPatchPairs?.isEmpty == false ? dpiPatchPairs : nil,
            activeStage: activeStage,
            ledBrightness: device.supportsLightingBrightnessControls ? content.brightnessByLEDID.values.max() : nil,
            ledRGB: lightingPatch.rgb,
            lightingEffect: lightingPatch.effect,
            usbLightingZoneLEDIDs: lightingPatch.ledIDs
        )

        let persistLightingZoneID = lightingPatch.ledIDs == nil ? "all" : editorStore.editableUSBLightingZoneID
        if !patch.isEmpty {
            let succeeded = await apply(
                device: device,
                patch: patch,
                behavior: ApplyBehavior(
                    markApplyingState: true,
                    shouldFocusOnActivity: true,
                    shouldSurfaceApplyFailure: true,
                    persistLightingZoneID: persistLightingZoneID,
                    clearLocalEditsOnSuccess: false,
                    backendApplyOptions: ApplyOptions()
                )
            )
            guard succeeded else { return false }
        }

        let persistentProfile = persistentProfileForRestoredLiveButtons(device: device)
        let buttonBindings = localProfileButtonBindingsToApply(content.buttonBindings, device: device)
        for slot in buttonBindings.keys.sorted() {
            guard let draft = buttonBindings[slot] else { continue }
            let succeeded = await apply(
                device: device,
                patch: DevicePatch(
                    buttonBinding: makeButtonBindingPatch(
                        slot: slot,
                        draft: draft,
                        profileID: device.profile_id,
                        persistentProfile: persistentProfile,
                        writePersistentLayer: true,
                        writeDirectLayer: true
                    )
                ),
                behavior: ApplyBehavior(
                    markApplyingState: true,
                    shouldFocusOnActivity: true,
                    shouldSurfaceApplyFailure: true,
                    persistLightingZoneID: persistLightingZoneID,
                    clearLocalEditsOnSuccess: false,
                    backendApplyOptions: ApplyOptions(readbackPolicy: .skipStateReadback)
                )
            )
            guard succeeded else { return false }
        }

        editorController.setLiveUSBButtonProfileOverride(persistentProfile, for: device)
        editorController.markButtonWorkspaceAppliedToLive(bindings: content.buttonBindings, exactSource: nil)
        return true
    }

    private func localProfileButtonBindingsToApply(
        _ bindings: [Int: ButtonBindingDraft],
        device: MouseDevice
    ) -> [Int: ButtonBindingDraft] {
        bindings.filter { slot, draft in
            shouldApplyLocalProfileButtonBinding(slot: slot, draft: draft, device: device)
        }
    }

    private func shouldApplyLocalProfileButtonBinding(
        slot: Int,
        draft: ButtonBindingDraft,
        device: MouseDevice
    ) -> Bool {
        let current = editorStore.editableButtonBindings[slot]
            ?? editorController.defaultButtonBinding(for: slot, device: device)
        return normalizedProfileButtonBinding(draft, slot: slot, device: device)
            != normalizedProfileButtonBinding(current, slot: slot, device: device)
    }

    private func normalizedProfileButtonBinding(
        _ draft: ButtonBindingDraft,
        slot: Int,
        device: MouseDevice
    ) -> ButtonBindingDraft {
        let availableKinds = Set(ButtonBindingSupport.availableButtonBindingKinds(profileID: device.profile_id))
        let resolved = availableKinds.contains(draft.kind)
            ? draft
            : ButtonBindingSupport.defaultButtonBinding(for: slot, profileID: device.profile_id)
        // Single-slot profile switches can contain full button snapshots. Avoid
        // no-op default writes because some devices ACK the meaningful remap but
        // reject a redundant live-layer default restore, which would make the UI
        // forget the selected local profile even though the switch succeeded.
        return ButtonBindingSupport.normalizedDefaultRepresentation(
            for: slot,
            draft: resolved,
            profileID: device.profile_id
        )
    }

    private func localProfileLightingPatch(
        _ content: OpenSnekLocalProfileContent,
        device: MouseDevice
    ) -> LocalProfileLightingPatch {
        guard device.showsLightingControls else {
            return LocalProfileLightingPatch(rgb: nil, effect: nil, ledIDs: nil)
        }
        if let effect = content.lightingEffect, effect.kind == .staticColor {
            return LocalProfileLightingPatch(rgb: effect.primary, effect: nil, ledIDs: nil)
        }
        if let effect = content.lightingEffect, device.supports_advanced_lighting_effects {
            return LocalProfileLightingPatch(rgb: nil, effect: effect, ledIDs: nil)
        }
        let rgb = content.staticColorByLEDID.sorted(by: { $0.key < $1.key }).first?.value
        return LocalProfileLightingPatch(rgb: rgb, effect: nil, ledIDs: nil)
    }
}
