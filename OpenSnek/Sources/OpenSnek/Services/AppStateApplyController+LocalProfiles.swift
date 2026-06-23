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
        let patch = DevicePatch(
            scrollMode: device.transport == .usb ? content.scrollMode : nil,
            scrollAcceleration: device.transport == .usb ? content.scrollAcceleration : nil,
            scrollSmartReel: device.transport == .usb ? content.scrollSmartReel : nil,
            dpiStages: dpiPatchValues?.isEmpty == false ? dpiPatchValues : nil,
            dpiStagePairs: dpiPatchPairs?.isEmpty == false ? dpiPatchPairs : nil,
            activeStage: activeStage,
            ledBrightness: content.brightnessByLEDID.values.max(),
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
        for slot in content.buttonBindings.keys.sorted() {
            guard let draft = content.buttonBindings[slot] else { continue }
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

    private func localProfileLightingPatch(
        _ content: OpenSnekLocalProfileContent,
        device: MouseDevice
    ) -> LocalProfileLightingPatch {
        guard device.showsLightingControls else {
            return LocalProfileLightingPatch(rgb: nil, effect: nil, ledIDs: nil)
        }
        if let effect = content.lightingEffect,
           device.supports_advanced_lighting_effects {
            return LocalProfileLightingPatch(rgb: nil, effect: effect, ledIDs: nil)
        }
        let rgb = content.staticColorByLEDID.sorted(by: { $0.key < $1.key }).first?.value
        return LocalProfileLightingPatch(rgb: rgb, effect: nil, ledIDs: nil)
    }
}
