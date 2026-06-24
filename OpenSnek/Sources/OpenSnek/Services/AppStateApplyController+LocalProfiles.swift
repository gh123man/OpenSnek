import Foundation
import OpenSnekAppSupport
import OpenSnekCore

/// Adds local profiles behavior to `AppStateApplyController`.
@MainActor extension AppStateApplyController {
    /// Stores local profile lighting patch data.
    private struct LocalProfileLightingPatch {
        let rgb: RGBPatch?
        let effect: LightingEffectPatch?
        let ledIDs: [UInt8]?
    }

    /// Stores local profile device patch data.
    private struct LocalProfileDevicePatch {
        let patch: DevicePatch
        let persistLightingZoneID: String
    }

    /// Stores local profile DPI patch data.
    private struct LocalProfileDPIPatch {
        let values: [Int]?
        let pairs: [DpiPair]?
        let activeStage: Int?
    }

    @discardableResult func applyLocalProfileContent(_ content: OpenSnekLocalProfileContent, to device: MouseDevice) async -> Bool {
        let devicePatch = localProfileDevicePatch(content, device: device)
        guard await applyLocalProfileDevicePatch(devicePatch, device: device) else { return false }
        guard await applyLocalProfileButtonBindings(content.buttonBindings, device: device, persistLightingZoneID: devicePatch.persistLightingZoneID) else { return false }

        let persistentProfile = persistentProfileForRestoredLiveButtons(device: device)
        editorController.setLiveUSBButtonProfileOverride(persistentProfile, for: device)
        editorController.markButtonWorkspaceAppliedToLive(bindings: content.buttonBindings, exactSource: nil)
        return true
    }

    private func localProfileDevicePatch(_ content: OpenSnekLocalProfileContent, device: MouseDevice) -> LocalProfileDevicePatch {
        let dpiPatch = localProfileDPIPatch(content.dpi)
        let lightingPatch = localProfileLightingPatch(content, device: device)
        let supportsScrollModeControls = device.supportsScrollModeControls
        let patch = DevicePatch(
            scrollMode: supportsScrollModeControls ? content.scrollMode : nil, scrollAcceleration: supportsScrollModeControls ? content.scrollAcceleration : nil, scrollSmartReel: supportsScrollModeControls ? content.scrollSmartReel : nil,
            dpiStages: dpiPatch.values?.isEmpty == false ? dpiPatch.values : nil, dpiStagePairs: dpiPatch.pairs?.isEmpty == false ? dpiPatch.pairs : nil, activeStage: dpiPatch.activeStage, ledBrightness: device.supportsLightingBrightnessControls ? content.brightnessByLEDID.values.max() : nil,
            ledRGB: lightingPatch.rgb, lightingEffect: lightingPatch.effect, usbLightingZoneLEDIDs: lightingPatch.ledIDs)

        let persistLightingZoneID = lightingPatch.ledIDs == nil ? "all" : editorStore.editableUSBLightingZoneID
        return LocalProfileDevicePatch(patch: patch, persistLightingZoneID: persistLightingZoneID)
    }

    private func localProfileDPIPatch(_ dpi: OnboardDPIProfileSnapshot?) -> LocalProfileDPIPatch {
        let sourcePairs = dpi?.pairs
        let count = DeviceProfiles.clampDpiStageCount(sourcePairs?.count ?? 0)
        let pairs = sourcePairs.map { Array($0.prefix(count)) }
        let values = pairs?.map(\.x)
        let activeStage = dpi?.activeStage.map { active in max(0, min(max(0, count - 1), active)) }
        return LocalProfileDPIPatch(values: values, pairs: pairs, activeStage: activeStage)
    }

    private func applyLocalProfileDevicePatch(_ devicePatch: LocalProfileDevicePatch, device: MouseDevice) async -> Bool {
        guard !devicePatch.patch.isEmpty else { return true }
        let behavior = ApplyBehavior(markApplyingState: true, shouldFocusOnActivity: true, shouldSurfaceApplyFailure: true, persistLightingZoneID: devicePatch.persistLightingZoneID, clearLocalEditsOnSuccess: false, backendApplyOptions: ApplyOptions())
        return await apply(device: device, patch: devicePatch.patch, behavior: behavior)
    }

    private func applyLocalProfileButtonBindings(_ bindings: [Int: ButtonBindingDraft], device: MouseDevice, persistLightingZoneID: String) async -> Bool {
        let persistentProfile = persistentProfileForRestoredLiveButtons(device: device)
        let buttonBindings = localProfileButtonBindingsToApply(bindings, device: device)
        for slot in buttonBindings.keys.sorted() {
            guard let draft = buttonBindings[slot] else { continue }
            let succeeded = await applyLocalProfileButtonBinding(slot: slot, draft: draft, device: device, persistentProfile: persistentProfile, persistLightingZoneID: persistLightingZoneID)
            guard succeeded else { return false }
        }
        return true
    }

    private func applyLocalProfileButtonBinding(slot: Int, draft: ButtonBindingDraft, device: MouseDevice, persistentProfile: Int, persistLightingZoneID: String) async -> Bool {
        let binding = makeButtonBindingPatch(slot: slot, draft: draft, profileID: device.profile_id, persistentProfile: persistentProfile, writePersistentLayer: true, writeDirectLayer: true)
        let behavior = ApplyBehavior(markApplyingState: true, shouldFocusOnActivity: true, shouldSurfaceApplyFailure: true, persistLightingZoneID: persistLightingZoneID, clearLocalEditsOnSuccess: false, backendApplyOptions: ApplyOptions(readbackPolicy: .skipStateReadback))
        return await apply(device: device, patch: DevicePatch(buttonBinding: binding), behavior: behavior)
    }

    private func localProfileButtonBindingsToApply(_ bindings: [Int: ButtonBindingDraft], device: MouseDevice) -> [Int: ButtonBindingDraft] { bindings.filter { slot, draft in shouldApplyLocalProfileButtonBinding(slot: slot, draft: draft, device: device) } }

    private func shouldApplyLocalProfileButtonBinding(slot: Int, draft: ButtonBindingDraft, device: MouseDevice) -> Bool {
        let current = editorStore.editableButtonBindings[slot] ?? editorController.defaultButtonBinding(for: slot, device: device)
        return normalizedProfileButtonBinding(draft, slot: slot, device: device) != normalizedProfileButtonBinding(current, slot: slot, device: device)
    }

    private func normalizedProfileButtonBinding(_ draft: ButtonBindingDraft, slot: Int, device: MouseDevice) -> ButtonBindingDraft {
        let availableKinds = Set(ButtonBindingSupport.availableButtonBindingKinds(profileID: device.profile_id))
        let resolved = availableKinds.contains(draft.kind) ? draft : ButtonBindingSupport.defaultButtonBinding(for: slot, profileID: device.profile_id)
        // Single-slot profile switches can contain full button snapshots. Avoid
        // no-op default writes because some devices ACK the meaningful remap but
        // reject a redundant live-layer default restore, which would make the UI
        // forget the selected local profile even though the switch succeeded.
        return ButtonBindingSupport.normalizedDefaultRepresentation(for: slot, draft: resolved, profileID: device.profile_id)
    }

    private func localProfileLightingPatch(_ content: OpenSnekLocalProfileContent, device: MouseDevice) -> LocalProfileLightingPatch {
        guard device.showsLightingControls else { return LocalProfileLightingPatch(rgb: nil, effect: nil, ledIDs: nil) }
        if let effect = content.lightingEffect, device.supports_advanced_lighting_effects { return LocalProfileLightingPatch(rgb: nil, effect: effect, ledIDs: nil) }
        let rgb = content.staticColorByLEDID.sorted(by: { $0.key < $1.key }).first?.value
        return LocalProfileLightingPatch(rgb: rgb, effect: nil, ledIDs: nil)
    }
}
