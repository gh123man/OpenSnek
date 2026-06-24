import Foundation
import OpenSnekAppSupport
import OpenSnekCore

/// Adds button profiles behavior to `AppStateApplyController`.
@MainActor
extension AppStateApplyController {
    func makeButtonBindingPatch(
        slot: Int,
        persistentProfile: Int,
        writePersistentLayer: Bool = true,
        writeDirectLayer: Bool
    ) -> ButtonBindingPatch {
        let resolved = editorStore.editableButtonBindings[slot] ?? editorController.defaultButtonBinding(for: slot)
        let applied: ButtonBindingDraft
        if resolved.kind == .default {
            applied = ButtonBindingSupport.semanticDefaultButtonBinding(
                for: slot,
                profileID: deviceStore.selectedDevice?.profile_id
            ) ?? resolved
        } else {
            applied = resolved
        }
        return ButtonBindingPatch(
            slot: slot,
            kind: applied.kind,
            hidKey: applied.kind == .keyboardSimple ? applied.hidKey : nil,
            hidModifiers: applied.kind == .keyboardSimple ? applied.hidModifiers : nil,
            turboEnabled: applied.kind.supportsTurbo ? applied.turboEnabled : false,
            turboRate: applied.kind.supportsTurbo && applied.turboEnabled ? applied.turboRate : nil,
            clutchDPI: applied.kind == .dpiClutch ? applied.clutchDPI ?? ButtonBindingSupport.defaultDPIClutchDPI(for: deviceStore.selectedDevice?.profile_id) : nil,
            persistentProfile: persistentProfile,
            writePersistentLayer: writePersistentLayer,
            writeDirectLayer: writeDirectLayer
        )
    }

    func makeButtonBindingPatch(
        slot: Int,
        draft: ButtonBindingDraft,
        profileID: DeviceProfileID?,
        persistentProfile: Int,
        writePersistentLayer: Bool = true,
        writeDirectLayer: Bool
    ) -> ButtonBindingPatch {
        let applied: ButtonBindingDraft
        if draft.kind == .default {
            applied = ButtonBindingSupport.semanticDefaultButtonBinding(
                for: slot,
                profileID: profileID
            ) ?? draft
        } else {
            applied = draft
        }
        return ButtonBindingPatch(
            slot: slot,
            kind: applied.kind,
            hidKey: applied.kind == .keyboardSimple ? applied.hidKey : nil,
            hidModifiers: applied.kind == .keyboardSimple ? applied.hidModifiers : nil,
            turboEnabled: applied.kind.supportsTurbo ? applied.turboEnabled : false,
            turboRate: applied.kind.supportsTurbo && applied.turboEnabled ? applied.turboRate : nil,
            clutchDPI: applied.kind == .dpiClutch
                ? applied.clutchDPI ?? ButtonBindingSupport.defaultDPIClutchDPI(for: profileID)
                : nil,
            persistentProfile: persistentProfile,
            writePersistentLayer: writePersistentLayer,
            writeDirectLayer: writeDirectLayer
        )
    }

    func applyButtonBinding(slot: Int) async {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        if supportsOnboardProfileEditorWrites(device: selectedDevice) {
            let draft = editorStore.editableButtonBindings[slot] ?? editorController.defaultButtonBinding(for: slot)
            _ = await applyOnboardProfileMutationForCurrentSelection(
                OnboardProfileMutation(buttonBindings: [slot: draft])
            )
            return
        }
        let binding = makeButtonBindingPatch(
            slot: slot,
            persistentProfile: persistentProfileForSingleButtonApply(device: selectedDevice),
            writeDirectLayer: true
        )
        enqueueApply(DevicePatch(buttonBinding: binding))
    }

    func scheduleAutoApplyButton(slot: Int) {
        scheduleAutoApply(key: .button(slot), delay: 120_000_000) { [weak self] in
            guard let self else { return }
            await self.applyButtonBinding(slot: slot)
        }
    }

    func writableButtonSlots(for device: MouseDevice) -> [Int] {
        device.button_layout?.writableSlots ?? deviceStore.visibleButtonSlots.map(\.slot)
    }

    func supportsOnboardProfileCRUD(device: MouseDevice) -> Bool {
        guard device.onboard_profile_count > 1 else { return false }
        return DeviceProfiles.resolve(
            vendorID: device.vendor_id,
            productID: device.product_id,
            transport: device.transport
        )?.supportsMappedOnboardProfileCRUD == true
    }

    func supportsOnboardProfileEditorWrites(device: MouseDevice) -> Bool {
        supportsOnboardProfileCRUD(device: device)
    }

    func supportsOnboardProfileLightingEditorWrites(device: MouseDevice) -> Bool {
        supportsOnboardProfileCRUD(device: device)
    }

    func onboardProfileLEDIDs(for device: MouseDevice) -> [UInt8] {
        let ids = DeviceProfiles.resolve(
            vendorID: device.vendor_id,
            productID: device.product_id,
            transport: device.transport
        )?.allUSBLightingLEDIDs ?? [0x01]
        return ids.isEmpty ? [0x01] : ids
    }

    func currentStaticOnboardProfileColors(for device: MouseDevice, allZones: Bool = false) -> [Int: RGBPatch] {
        let targetLEDIDs: [UInt8]
        if allZones {
            targetLEDIDs = onboardProfileLEDIDs(for: device)
        } else if let zoneLEDIDs = editorController.currentUSBLightingZoneLEDIDs(), !zoneLEDIDs.isEmpty {
            targetLEDIDs = zoneLEDIDs
        } else {
            targetLEDIDs = onboardProfileLEDIDs(for: device)
        }

        return Dictionary(
            uniqueKeysWithValues: targetLEDIDs.map { ledID in
                (
                    Int(ledID),
                    RGBPatch(
                        r: editorStore.editableColor.r,
                        g: editorStore.editableColor.g,
                        b: editorStore.editableColor.b
                    )
                )
            }
        )
    }

    func applyCurrentStaticOnboardProfileColorsIfSupported(
        for device: MouseDevice,
        allZones: Bool = false
    ) async -> Bool {
        guard supportsOnboardProfileLightingEditorWrites(device: device),
              editorStore.editableLightingEffect == .staticColor || !device.supports_advanced_lighting_effects else {
            return false
        }
        return await applyOnboardProfileMutationForCurrentSelection(
            OnboardProfileMutation(staticColorByLEDID: currentStaticOnboardProfileColors(for: device, allZones: allZones))
        )
    }

    func applyOnboardProfileMutationForCurrentSelection(_ mutation: OnboardProfileMutation) async -> Bool {
        let start = Date()
        let succeeded = await editorController.applyOnboardProfileMutationForCurrentSelection(mutation)
        if !succeeded, let activeStage = mutation.dpi?.activeStage {
            clearPendingActiveStageSelection(matching: activeStage + 1, for: deviceStore.selectedDevice)
        }
        if succeeded {
            clearPendingLocalEditsIfUnchanged(since: start)
        }
        return succeeded
    }

    func clearPendingLocalEditsIfUnchanged(since start: Date) {
        guard !applyCoordinator.hasPending else { return }
        guard (lastLocalEditAt ?? .distantPast) <= start else { return }
        hasPendingLocalEdits = false
        lastLocalEditAt = nil
        localEditDeviceIdentityKey = nil
    }

    func rememberPendingActiveStageSelection(_ stage: Int, for device: MouseDevice?) {
        guard let device else { return }
        let count = DeviceProfiles.clampDpiStageCount(editorStore.editableStageCount)
        pendingActiveStageSelectionByDeviceIdentityKey[deviceController.deviceIdentityKey(device)] = max(1, min(count, stage))
        AppLog.debug(
            "AppState",
            "rememberPendingActiveStage device=\(device.id) requested=\(stage) " +
            "stored=\(pendingActiveStageSelection(for: device).map(String.init) ?? "nil") count=\(count)"
        )
    }

    func clearPendingActiveStageSelection(matching stage: Int, for device: MouseDevice?) {
        guard let device else { return }
        let key = deviceController.deviceIdentityKey(device)
        guard pendingActiveStageSelectionByDeviceIdentityKey[key] == stage else { return }
        pendingActiveStageSelectionByDeviceIdentityKey.removeValue(forKey: key)
        AppLog.debug("AppState", "clearPendingActiveStage device=\(device.id) stage=\(stage)")
    }

    func shouldTreatCurrentSourceAsExactMouseSlot(device: MouseDevice) -> Int? {
        guard case .mouseSlot(let slot)? = editorController.currentButtonProfileSource(),
              !editorController.buttonWorkspaceHasUnsavedSourceChanges(device: device) else {
            return nil
        }
        return slot
    }

    func persistentProfileForSingleButtonApply(device: MouseDevice) -> Int {
        guard device.transport == .usb, editorStore.supportsMultipleOnboardProfiles else {
            return editorStore.editableUSBButtonProfile
        }
        return 1
    }

    func persistentProfileForRestoredLiveButtons(device: MouseDevice) -> Int {
        guard device.transport == .usb, device.onboard_profile_count > 1 else {
            return 1
        }
        return 1
    }

    func applyCurrentButtonWorkspaceToLive() async {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        let slots = writableButtonSlots(for: selectedDevice)
        let persistentProfile = selectedDevice.transport == .usb && editorStore.supportsMultipleOnboardProfiles
            ? 1
            : (shouldTreatCurrentSourceAsExactMouseSlot(device: selectedDevice) ?? editorStore.activeOnboardProfile)

        for slot in slots {
            let patch = DevicePatch(
                buttonBinding: makeButtonBindingPatch(
                    slot: slot,
                    persistentProfile: persistentProfile,
                    writePersistentLayer: true,
                    writeDirectLayer: true
                )
            )
            let succeeded = await apply(
                device: selectedDevice,
                patch: patch,
                behavior: ApplyBehavior(
                    markApplyingState: true,
                    shouldFocusOnActivity: true,
                    shouldSurfaceApplyFailure: true,
                    persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                    clearLocalEditsOnSuccess: false,
                    backendApplyOptions: ApplyOptions()
                )
            )
            guard succeeded else { return }
        }

        if selectedDevice.transport == .usb && editorStore.supportsMultipleOnboardProfiles {
            editorController.setLiveUSBButtonProfileOverride(1, for: selectedDevice)
        } else {
            if let exactSlot = shouldTreatCurrentSourceAsExactMouseSlot(device: selectedDevice) {
                editorController.setLiveUSBButtonProfileOverride(exactSlot, for: selectedDevice)
            } else {
                editorController.setLiveUSBButtonProfileOverride(editorStore.activeOnboardProfile, for: selectedDevice)
            }
        }
        editorController.markButtonWorkspaceAppliedToLive(
            bindings: editorStore.editableButtonBindings,
            exactSource: editorController.currentButtonProfileSource()
        )
    }

    func writeCurrentButtonWorkspaceToMouseSlot(_ targetProfile: Int) async {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        let clampedTarget = max(1, min(editorStore.visibleOnboardProfileCount, targetProfile))

        for slot in writableButtonSlots(for: selectedDevice) {
            let patch = DevicePatch(
                buttonBinding: makeButtonBindingPatch(
                    slot: slot,
                    persistentProfile: clampedTarget,
                    writePersistentLayer: true,
                    writeDirectLayer: false
                )
            )
            let succeeded = await apply(
                device: selectedDevice,
                patch: patch,
                behavior: ApplyBehavior(
                    markApplyingState: true,
                    shouldFocusOnActivity: false,
                    shouldSurfaceApplyFailure: true,
                    persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                    clearLocalEditsOnSuccess: false,
                    backendApplyOptions: ApplyOptions()
                )
            )
            guard succeeded else { return }
        }

        editorController.saveCachedButtonBindings(device: selectedDevice, bindings: editorStore.editableButtonBindings, profile: clampedTarget)
    }

    func projectSelectedUSBButtonProfileToDirectLayer() async {
        guard let selectedDevice = deviceStore.selectedDevice, editorStore.supportsMultipleOnboardProfiles else { return }
        let patch = DevicePatch(
            usbButtonProfileAction: USBButtonProfileActionPatch(
                kind: .projectToDirectLayer,
                targetProfile: editorStore.editableUSBButtonProfile
            )
        )
        let succeeded = await apply(
            device: selectedDevice,
            patch: patch,
            behavior: ApplyBehavior(
                markApplyingState: true,
                shouldFocusOnActivity: true,
                shouldSurfaceApplyFailure: true,
                persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                clearLocalEditsOnSuccess: false,
                backendApplyOptions: ApplyOptions()
            )
        )
        guard succeeded else { return }
        editorController.setLiveUSBButtonProfileOverride(editorStore.editableUSBButtonProfile, for: selectedDevice)
        let bindings = editorController.cachedButtonBindings(device: selectedDevice, profile: editorStore.editableUSBButtonProfile)
        editorController.markButtonWorkspaceAppliedToLive(bindings: bindings, exactSource: .mouseSlot(editorStore.editableUSBButtonProfile))
    }

    func duplicateSelectedUSBButtonProfile() async {
        guard deviceStore.selectedDevice != nil, editorStore.supportsMultipleOnboardProfiles else { return }
        guard let targetProfile = editorStore.duplicateTargetProfiles.first?.profile else {
            return
        }
        await duplicateSelectedUSBButtonProfile(to: targetProfile)
    }

    func duplicateSelectedUSBButtonProfile(to targetProfile: Int) async {
        guard let selectedDevice = deviceStore.selectedDevice, editorStore.supportsMultipleOnboardProfiles else { return }
        guard targetProfile != editorStore.editableUSBButtonProfile else { return }
        if editorStore.selectedUSBButtonProfileHasUnsavedChanges {
            await saveSelectedUSBButtonProfile()
            guard !editorStore.selectedUSBButtonProfileHasUnsavedChanges else { return }
        }

        let sourceProfile = editorStore.editableUSBButtonProfile
        let patch = DevicePatch(
            usbButtonProfileAction: USBButtonProfileActionPatch(
                kind: .duplicateToPersistentSlot,
                sourceProfile: sourceProfile,
                targetProfile: targetProfile
            )
        )
        let succeeded = await apply(
            device: selectedDevice,
            patch: patch,
            behavior: ApplyBehavior(
                markApplyingState: true,
                shouldFocusOnActivity: true,
                shouldSurfaceApplyFailure: true,
                persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                clearLocalEditsOnSuccess: false,
                backendApplyOptions: ApplyOptions()
            )
        )
        guard succeeded else { return }

        let copiedBindings = editorController.cachedButtonBindings(device: selectedDevice, profile: sourceProfile)
        editorController.saveCachedButtonBindings(device: selectedDevice, bindings: copiedBindings, profile: targetProfile)
        editorController.updateUSBButtonProfile(targetProfile)
    }

    func resetSelectedUSBButtonProfile() async {
        await resetUSBButtonProfile(editorStore.editableUSBButtonProfile)
    }

    func resetUSBButtonProfile(_ targetProfile: Int) async {
        guard let selectedDevice = deviceStore.selectedDevice, editorStore.supportsMultipleOnboardProfiles else { return }
        let clampedTarget = max(1, min(editorStore.visibleOnboardProfileCount, targetProfile))
        let patch = DevicePatch(
            usbButtonProfileAction: USBButtonProfileActionPatch(
                kind: .resetPersistentSlot,
                targetProfile: clampedTarget
            )
        )
        let succeeded = await apply(
            device: selectedDevice,
            patch: patch,
            behavior: ApplyBehavior(
                markApplyingState: true,
                shouldFocusOnActivity: true,
                shouldSurfaceApplyFailure: true,
                persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                clearLocalEditsOnSuccess: false,
                backendApplyOptions: ApplyOptions()
            )
        )
        guard succeeded else { return }

        editorController.saveCachedButtonBindings(device: selectedDevice, bindings: [:], profile: clampedTarget)
        if clampedTarget == editorStore.liveUSBButtonProfile {
            await projectSelectedUSBButtonProfileToDirectLayer()
        }
    }

    func saveSelectedUSBButtonProfile(activateAfterSave: Bool = false) async {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        let profile = editorStore.editableUSBButtonProfile
        let liveProfile = editorStore.liveUSBButtonProfile
        let writableSlots = selectedDevice.button_layout?.writableSlots ?? deviceStore.visibleButtonSlots.map(\.slot)
        let persistedBindings = editorController.cachedButtonBindings(device: selectedDevice, profile: profile)
        let slotsToSave = writableSlots.filter { slot in
            let fallback = editorController.defaultButtonBinding(for: slot, device: selectedDevice)
            let draft = editorStore.editableButtonBindings[slot] ?? fallback
            let persisted = persistedBindings[slot] ?? fallback
            return draft != persisted
        }

        if slotsToSave.isEmpty {
            if activateAfterSave && profile != liveProfile {
                await projectSelectedUSBButtonProfileToDirectLayer()
            }
            return
        }

        let shouldWriteDirectLayer = !editorStore.supportsMultipleOnboardProfiles || profile == liveProfile
        for slot in slotsToSave {
            let patch = DevicePatch(
                buttonBinding: makeButtonBindingPatch(
                    slot: slot,
                    persistentProfile: profile,
                    writeDirectLayer: shouldWriteDirectLayer
                )
            )
            let succeeded = await apply(
                device: selectedDevice,
                patch: patch,
                behavior: ApplyBehavior(
                    markApplyingState: true,
                    shouldFocusOnActivity: true,
                    shouldSurfaceApplyFailure: true,
                    persistLightingZoneID: editorStore.editableUSBLightingZoneID,
                    clearLocalEditsOnSuccess: false,
                    backendApplyOptions: ApplyOptions()
                )
            )
            guard succeeded else { return }
        }

        if activateAfterSave && profile != liveProfile {
            await projectSelectedUSBButtonProfileToDirectLayer()
        }
    }

}
