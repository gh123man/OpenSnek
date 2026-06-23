import Foundation
import OpenSnekAppSupport
import OpenSnekCore

@MainActor
extension AppStateEditorController {
    private struct AdaptedLightingContent {
        let brightness: [Int: Int]
        let staticColors: [Int: RGBPatch]
        let effect: LightingEffectPatch?
    }

    func supportsProfilePicker(device: MouseDevice) -> Bool {
        device.profile_id != nil
    }

    func localProfiles() -> [OpenSnekLocalProfile] {
        preferenceStore.loadOpenSnekLocalProfiles()
    }

    func visibleLocalProfilesForReplacement() -> [OpenSnekLocalProfile] {
        guard let device = deviceStore.selectedDevice else {
            return localProfiles().filter { $0.syntheticSourceKey == nil }
        }
        return localProfiles().filter { profile in
            !shouldHideSyntheticLocalProfile(profile, for: device)
        }
    }

    func createLocalProfile(name: String, copying sourceID: UUID?) {
        let content = contentForNewLocalProfile(copying: sourceID)
        _ = preferenceStore.createOpenSnekLocalProfile(
            name: name,
            content: content
        )
        bumpOnboardProfilesRevision()
        bumpUSBButtonProfilesRevision()
    }

    func createLocalProfileFromMouse(name: String) async {
        guard let device = deviceStore.selectedDevice else {
            createLocalProfile(name: name, copying: nil)
            return
        }
        do {
            if supportsProfilePicker(device: device), !supportsOnboardProfileCRUD(device: device) {
                try await hydrateSingleSlotProfileFromMouse(device: device)
            }
            _ = preferenceStore.createOpenSnekLocalProfile(
                name: name,
                content: currentLocalProfileContent(device: device)
            )
            deviceStore.errorMessage = nil
            bumpOnboardProfilesRevision()
            bumpUSBButtonProfilesRevision()
        } catch {
            AppLog.error("AppState", "create local profile from mouse failed device=\(device.id): \(error.localizedDescription)")
            deviceStore.errorMessage = "Failed to create profile from mouse: \(error.localizedDescription)"
        }
    }

    func renameLocalProfile(id: UUID, name: String) {
        let updated = preferenceStore.updateOpenSnekLocalProfile(id: id, name: name)
        if let device = deviceStore.selectedDevice,
           selectedSingleSlotLocalProfile(device: device)?.id == id,
           let updated {
            setSelectedSingleSlotProfileName(updated.name, device: device)
        }
        bumpOnboardProfilesRevision()
        bumpUSBButtonProfilesRevision()
    }

    func deleteLocalProfile(id: UUID) {
        if let device = deviceStore.selectedDevice,
           selectedSingleSlotLocalProfile(device: device)?.id == id {
            clearSelectedSingleSlotLocalProfile(device: device)
        }
        preferenceStore.deleteOpenSnekLocalProfile(id: id)
        bumpOnboardProfilesRevision()
        bumpUSBButtonProfilesRevision()
    }

    func singleSlotProfileSummary(device: MouseDevice) -> OnboardProfileSummary {
        let selectedName = selectedSingleSlotProfileName(device: device)
        let metadata = selectedName.map {
            OnboardProfileMetadata(identifier: UUID(), name: $0)
        }
        return OnboardProfileSummary(
            profileID: 1,
            metadata: metadata,
            isAssigned: true,
            isActive: true,
            isBaseProfile: true
        )
    }

    func singleSlotLocalProfile(device: MouseDevice) -> OpenSnekLocalProfile? {
        let key = DevicePreferenceStore.localProfileSyntheticSourceKey(device: device, slot: 1)
        return preferenceStore.loadOpenSnekLocalProfiles().first { $0.syntheticSourceKey == key }
    }

    func removeSingleSlotSyntheticLocalProfile(device: MouseDevice) {
        let key = DevicePreferenceStore.localProfileSyntheticSourceKey(device: device, slot: 1)
        let syntheticProfiles = preferenceStore.loadOpenSnekLocalProfiles().filter { $0.syntheticSourceKey == key }
        guard !syntheticProfiles.isEmpty else { return }
        for profile in syntheticProfiles {
            preferenceStore.deleteOpenSnekLocalProfile(id: profile.id)
        }
        bumpOnboardProfilesRevision()
        bumpUSBButtonProfilesRevision()
    }

    func localProfileCanApply(_ profile: OpenSnekLocalProfile, to device: MouseDevice) -> Bool {
        let storedProfile = preferenceStore
            .loadOpenSnekLocalProfiles()
            .first(where: { $0.id == profile.id }) ?? profile
        if let content = repairContent(forEmptyLocalProfile: storedProfile, device: device) {
            return adaptedLocalProfileContent(content, for: device).hasApplicableFields
        }
        return adaptedLocalProfileContent(storedProfile.content, for: device).hasApplicableFields
    }

    func repairEmptyLocalProfilesForSelectedDevice(device: MouseDevice) {
        let profiles = preferenceStore.loadOpenSnekLocalProfiles()
        var repairedAny = false
        for profile in profiles where shouldRepairEmptyLocalProfile(profile) {
            guard repairEmptyLocalProfile(profile, device: device) != nil else { continue }
            repairedAny = true
        }
        if repairedAny {
            bumpOnboardProfilesRevision()
            bumpUSBButtonProfilesRevision()
        }
    }

    func syncLocalProfile(from snapshot: OnboardProfileSnapshot, device: MouseDevice, source: String) {
        guard supportsOnboardProfileCRUD(device: device) else { return }
        guard shouldSyncOnboardSnapshotToLocalProfile(snapshot, device: device, source: source) else { return }
        _ = preferenceStore.upsertOpenSnekLocalProfile(from: snapshot, device: device)
        bumpOnboardProfilesRevision()
        bumpUSBButtonProfilesRevision()
    }

    func syncSelectedMappedLocalProfileFromEditor(device: MouseDevice) {
        guard supportsOnboardProfileCRUD(device: device),
              let snapshot = currentSelectedOnboardProfileSnapshot(device: device) else {
            return
        }
        let name = onboardProfileInventoryByDeviceID[device.id]?
            .summary(for: snapshot.profileID)?
            .displayName ?? snapshot.metadata.name
        _ = preferenceStore.upsertOpenSnekLocalProfile(
            name: name,
            content: currentLocalProfileContent(device: device),
            onboardIdentifier: snapshot.metadata.identifier,
            device: device
        )
        bumpOnboardProfilesRevision()
        bumpUSBButtonProfilesRevision()
    }

    func syncSingleSlotLocalProfileFromEditor(device: MouseDevice, name _: String? = nil) {
        removeSingleSlotSyntheticLocalProfile(device: device)
    }

    func syncSingleSlotLocalProfileFromPersistedSnapshot(device: MouseDevice) {
        removeSingleSlotSyntheticLocalProfile(device: device)
    }

    func syncSelectedSingleSlotLocalProfileFromEditor(device: MouseDevice) {
        guard supportsProfilePicker(device: device),
              !supportsOnboardProfileCRUD(device: device),
              let profile = selectedSingleSlotLocalProfile(device: device) else {
            return
        }
        guard preferenceStore.updateOpenSnekLocalProfile(
            id: profile.id,
            content: currentLocalProfileContent(device: device),
            sourceDeviceProfileID: device.profile_id,
            sourceTransport: device.transport
        ) != nil else {
            clearSelectedSingleSlotLocalProfile(device: device)
            return
        }
        bumpOnboardProfilesRevision()
        bumpUSBButtonProfilesRevision()
    }

    func markSingleSlotPersistedSettingsRestored(
        snapshot: PersistedDeviceSettingsSnapshot,
        device: MouseDevice
    ) {
        guard supportsProfilePicker(device: device),
              !supportsOnboardProfileCRUD(device: device),
              shouldRestorePersistedSettingsOnConnect(for: device),
              let profile = selectedSingleSlotLocalProfile(device: device) else {
            return
        }
        _ = preferenceStore.updateOpenSnekLocalProfile(
            id: profile.id,
            content: localProfileContent(from: snapshot),
            sourceDeviceProfileID: device.profile_id,
            sourceTransport: device.transport
        )
        setSelectedSingleSlotProfileName(profile.name, device: device)
        bumpUSBButtonProfilesRevision()
    }

    func loadSelectedSingleSlotProfileFromMouse() async {
        guard !isTearingDown,
              let device = deviceStore.selectedDevice,
              supportsProfilePicker(device: device),
              !supportsOnboardProfileCRUD(device: device) else {
            return
        }
        do {
            try await hydrateSingleSlotProfileFromMouse(device: device)
            deviceStore.errorMessage = nil
        } catch {
            AppLog.error("AppState", "load single-slot profile from mouse failed device=\(device.id): \(error.localizedDescription)")
            deviceStore.errorMessage = "Failed to load profile from mouse: \(error.localizedDescription)"
        }
    }

    func applyLastSyncedSingleSlotProfile() async {
        guard let device = deviceStore.selectedDevice,
              !supportsOnboardProfileCRUD(device: device),
              let profile = singleSlotLocalProfile(device: device) else {
            return
        }
        await replaceSelectedProfile(with: profile.id)
    }

    func replaceSelectedProfile(with localProfileID: UUID) async {
        guard !isTearingDown,
              let device = deviceStore.selectedDevice,
              let storedProfile = preferenceStore.loadOpenSnekLocalProfiles().first(where: { $0.id == localProfileID }) else {
            return
        }
        let localProfile = repairEmptyLocalProfile(storedProfile, device: device) ?? storedProfile
        guard localProfileCanApply(localProfile, to: device) else {
            return
        }
        do {
            await applyController.cancelAndDrainPendingLocalEditsForSelectionChange()
            applyController.cancelPendingPersistedSettingsRestore(for: device)
            try await backupSelectedProfileBeforeReplacement(device: device)
            if supportsOnboardProfileCRUD(device: device) {
                try await replaceSelectedMappedOnboardProfile(localProfile, device: device)
            } else {
                try await replaceSelectedSingleSlotProfile(localProfile, device: device)
            }
        } catch {
            AppLog.error("AppState", "replace profile failed device=\(device.id): \(error.localizedDescription)")
            deviceStore.errorMessage = "Failed to replace profile: \(error.localizedDescription)"
        }
    }

    private func contentForNewLocalProfile(copying sourceID: UUID?) -> OpenSnekLocalProfileContent {
        if let sourceID,
           let source = preferenceStore.loadOpenSnekLocalProfiles().first(where: { $0.id == sourceID }),
           source.content.hasApplicableFields {
            return source.content
        }
        guard let device = deviceStore.selectedDevice else {
            return OpenSnekLocalProfileContent()
        }
        return currentLocalProfileContent(device: device)
    }

    private func repairEmptyLocalProfile(
        _ profile: OpenSnekLocalProfile,
        device: MouseDevice
    ) -> OpenSnekLocalProfile? {
        guard let content = repairContent(forEmptyLocalProfile: profile, device: device) else {
            return nil
        }
        return preferenceStore.updateOpenSnekLocalProfile(
            id: profile.id,
            content: content,
            sourceDeviceProfileID: device.profile_id,
            sourceTransport: device.transport
        )
    }

    private func repairContent(
        forEmptyLocalProfile profile: OpenSnekLocalProfile,
        device: MouseDevice
    ) -> OpenSnekLocalProfileContent? {
        guard shouldRepairEmptyLocalProfile(profile) else { return nil }
        let content = repairSourceContent(for: device)
        guard adaptedLocalProfileContent(content, for: device).hasApplicableFields else {
            return nil
        }
        return content
    }

    private func shouldRepairEmptyLocalProfile(_ profile: OpenSnekLocalProfile) -> Bool {
        profile.syntheticSourceKey == nil &&
            profile.onboardIdentifier == nil &&
            !profile.content.hasApplicableFields
    }

    private func repairSourceContent(for device: MouseDevice) -> OpenSnekLocalProfileContent {
        return currentLocalProfileContent(device: device)
    }

    private func shouldHideSyntheticLocalProfile(_ profile: OpenSnekLocalProfile, for device: MouseDevice) -> Bool {
        guard profile.syntheticSourceKey != nil else { return false }
        guard supportsProfilePicker(device: device), !supportsOnboardProfileCRUD(device: device) else {
            return false
        }
        return true
    }

    private func hydrateSingleSlotProfileFromMouse(device: MouseDevice) async throws {
        let state = try await environment.backend.readState(device: device)
        let merged = storeSelectedDeviceState(state, for: device)
        hydrateEditable(from: merged)
        await hydrateButtonBindingsIfNeeded(device: device)
        await hydrateLightingStateIfNeeded(device: device)
    }

    func currentLocalProfileContent(device: MouseDevice) -> OpenSnekLocalProfileContent {
        let count = DeviceProfiles.clampDpiStageCount(editorStore.editableStageCount)
        let pairs = Array(editorStore.editableStagePairs.prefix(count)).map { pair in
            DpiPair(
                x: DeviceProfiles.clampDPI(pair.x, profileID: device.profile_id),
                y: DeviceProfiles.clampDPI(pair.y, profileID: device.profile_id)
            )
        }
        let activeStage = max(0, min(max(0, count - 1), editorStore.editableActiveStage - 1))
        let scalar = pairs.indices.contains(activeStage) ? pairs[activeStage] : pairs.first
        let lightingLEDIDs = lightingLEDIDs(for: device)
        let brightness = Dictionary(uniqueKeysWithValues: lightingLEDIDs.map { (Int($0), editorStore.editableLedBrightness) })
        let staticColors = Dictionary(uniqueKeysWithValues: lightingLEDIDs.map { ledID in
            (
                Int(ledID),
                RGBPatch(
                    r: editorStore.editableColor.r,
                    g: editorStore.editableColor.g,
                    b: editorStore.editableColor.b
                )
            )
        })
        return OpenSnekLocalProfileContent(
            dpi: OnboardDPIProfileSnapshot(
                scalar: scalar,
                activeStage: activeStage,
                pairs: pairs,
                stageIDs: currentSelectedOnboardProfileSnapshot(device: device)?.dpi?.stageIDs ?? [],
                marker: currentSelectedOnboardProfileSnapshot(device: device)?.dpi?.marker
            ),
            buttonBindings: editorStore.editableButtonBindings,
            brightnessByLEDID: brightness,
            staticColorByLEDID: staticColors,
            lightingEffect: device.supports_advanced_lighting_effects ? currentLightingEffectPatch() : nil,
            scrollMode: device.transport == .usb ? editorStore.editableScrollMode : nil,
            scrollAcceleration: device.transport == .usb ? editorStore.editableScrollAcceleration : nil,
            scrollSmartReel: device.transport == .usb ? editorStore.editableScrollSmartReel : nil
        )
    }

    func localProfileContent(from snapshot: PersistedDeviceSettingsSnapshot) -> OpenSnekLocalProfileContent {
        let pairs = !snapshot.stagePairs.isEmpty
            ? snapshot.stagePairs
            : snapshot.stageValues.map { DpiPair(x: $0, y: $0) }
        let count = DeviceProfiles.clampDpiStageCount(max(snapshot.stageCount, pairs.count))
        let resolvedPairs = Array(pairs.prefix(count))
        let activeIndex = max(0, min(max(0, count - 1), snapshot.activeStage - 1))
        let scalar = resolvedPairs.indices.contains(activeIndex) ? resolvedPairs[activeIndex] : resolvedPairs.first
        let staticColors: [Int: RGBPatch]
        if let color = snapshot.primaryLightingColor {
            staticColors = [1: RGBPatch(r: color.r, g: color.g, b: color.b)]
        } else {
            staticColors = [:]
        }
        return OpenSnekLocalProfileContent(
            dpi: OnboardDPIProfileSnapshot(
                scalar: scalar,
                activeStage: activeIndex,
                pairs: resolvedPairs
            ),
            buttonBindings: snapshot.buttonBindings,
            brightnessByLEDID: snapshot.ledBrightness.map { [1: $0] } ?? [:],
            staticColorByLEDID: staticColors,
            lightingEffect: snapshot.lightingEffect,
            scrollMode: snapshot.scrollMode,
            scrollAcceleration: snapshot.scrollAcceleration,
            scrollSmartReel: snapshot.scrollSmartReel
        )
    }

    func adaptedLocalProfileContent(
        _ content: OpenSnekLocalProfileContent,
        for device: MouseDevice
    ) -> OpenSnekLocalProfileContent {
        let dpi = content.dpi.map { adaptDPI($0, for: device) }
        let buttonBindings = adaptedButtonBindings(content.buttonBindings, for: device)
        let lighting = adaptedLighting(content, for: device)
        return OpenSnekLocalProfileContent(
            dpi: dpi,
            buttonBindings: buttonBindings,
            brightnessByLEDID: lighting.brightness,
            staticColorByLEDID: lighting.staticColors,
            lightingEffect: lighting.effect,
            scrollMode: device.transport == .usb ? content.scrollMode : nil,
            scrollAcceleration: device.transport == .usb ? content.scrollAcceleration : nil,
            scrollSmartReel: device.transport == .usb ? content.scrollSmartReel : nil
        )
    }

    func onboardProfileMutation(
        from localProfile: OpenSnekLocalProfile,
        device: MouseDevice,
        metadata: OnboardProfileMetadata
    ) -> OnboardProfileMutation {
        let content = adaptedLocalProfileContent(localProfile.content, for: device)
        let staticColors = content.staticColorByLEDID.isEmpty ? nil : content.staticColorByLEDID
        return OnboardProfileMutation(
            metadata: metadata,
            dpi: content.dpi,
            buttonBindings: content.buttonBindings,
            brightnessByLEDID: content.brightnessByLEDID.isEmpty ? nil : content.brightnessByLEDID,
            staticColorByLEDID: staticColors,
            scrollMode: device.transport == .usb ? content.scrollMode : nil,
            scrollAcceleration: device.transport == .usb ? content.scrollAcceleration : nil,
            scrollSmartReel: device.transport == .usb ? content.scrollSmartReel : nil
        )
    }

    private func shouldSyncOnboardSnapshotToLocalProfile(
        _ snapshot: OnboardProfileSnapshot,
        device: MouseDevice,
        source: String
    ) -> Bool {
        guard !snapshot.metadata.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if !source.localizedCaseInsensitiveContains("core") {
            return true
        }
        return onboardProfileInventoryByDeviceID[device.id]?
            .summary(for: snapshot.profileID)?
            .metadata?
            .identifier == snapshot.metadata.identifier
    }

    private func backupSelectedProfileBeforeReplacement(device: MouseDevice) async throws {
        if supportsOnboardProfileCRUD(device: device) {
            guard let selected = selectedOnboardProfileID() else { return }
            let inventory = onboardProfileInventoryByDeviceID[device.id]
            guard inventory?.assignedProfileIDs.contains(selected) == true else { return }
            let snapshot = try await readLatestOnboardProfileSnapshot(
                device: device,
                profileID: selected,
                storeForEditing: false
            )
            syncLocalProfile(from: snapshot, device: device, source: "backupBeforeReplace")
            return
        }

        removeSingleSlotSyntheticLocalProfile(device: device)
    }

    private func replaceSelectedMappedOnboardProfile(
        _ localProfile: OpenSnekLocalProfile,
        device: MouseDevice
    ) async throws {
        guard let selected = selectedOnboardProfileID() else {
            throw AppStateLocalProfileError.noSelectedProfile
        }
        let onboardIdentifier = localProfile.onboardIdentifier ?? UUID()
        if localProfile.onboardIdentifier == nil {
            _ = preferenceStore.updateOpenSnekLocalProfile(
                id: localProfile.id,
                onboardIdentifier: onboardIdentifier,
                sourceDeviceProfileID: device.profile_id,
                sourceTransport: device.transport
            )
        }
        let metadata = OnboardProfileMetadata(
            identifier: onboardIdentifier,
            name: localProfile.name
        )
        let mutation = onboardProfileMutation(from: localProfile, device: device, metadata: metadata)
        let snapshot: OnboardProfileSnapshot
        if selected == 1 {
            snapshot = try await environment.backend.updateOnboardProfile(
                device: device,
                profileID: selected,
                mutation: mutation
            )
        } else {
            snapshot = try await environment.backend.createOnboardProfile(
                device: device,
                mutation: mutation,
                targetProfileID: selected,
                replaceAssignedProfile: true
            )
        }
        storeCurrentOnboardProfileSnapshot(
            snapshot,
            device: device,
            source: "replaceOnboardProfileFromLocal",
            projectMetadataForRefresh: true
        )
        let state = try await environment.backend.activateOnboardProfile(device: device, profileID: snapshot.profileID)
        let active = storeActiveOnboardProfileState(state, for: device, fallbackActiveProfileID: snapshot.profileID)
        selectedOnboardProfileIDByDeviceID[device.id] = active
        if active == snapshot.profileID {
            hydrateEditable(from: snapshot, device: device)
        } else {
            let activeSnapshot = try await readLatestOnboardProfileSnapshot(device: device, profileID: active)
            hydrateEditable(from: activeSnapshot, device: device)
        }
        deviceStore.errorMessage = nil
        bumpOnboardProfilesRevision()
    }

    private func replaceSelectedSingleSlotProfile(
        _ localProfile: OpenSnekLocalProfile,
        device: MouseDevice
    ) async throws {
        let content = adaptedLocalProfileContent(localProfile.content, for: device)
        singleSlotProfileApplySyncSuppressedDeviceIDs.insert(device.id)
        applyController.cancelPendingPersistedSettingsRestore(for: device)
        defer {
            singleSlotProfileApplySyncSuppressedDeviceIDs.remove(device.id)
        }
        let succeeded = await applyController.applyLocalProfileContent(content, to: device)
        guard succeeded else {
            throw AppStateLocalProfileError.applyFailed
        }
        applyLocalProfileContentToEditor(content, device: device)
        setSelectedSingleSlotLocalProfile(localProfile, device: device)
        persistCurrentSettingsSnapshot(for: device)
        removeSingleSlotSyntheticLocalProfile(device: device)
        deviceStore.errorMessage = nil
    }

    private func selectedSingleSlotProfileName(device: MouseDevice) -> String? {
        selectedSingleSlotProfileNameByDeviceID[device.id]
    }

    private func setSelectedSingleSlotProfileName(_ name: String, device: MouseDevice) {
        guard selectedSingleSlotProfileNameByDeviceID[device.id] != name else { return }
        selectedSingleSlotProfileNameByDeviceID[device.id] = name
        bumpOnboardProfilesRevision()
    }

    private func selectedSingleSlotLocalProfile(device: MouseDevice) -> OpenSnekLocalProfile? {
        guard let id = preferenceStore.loadSelectedLocalProfileID(device: device) else {
            return nil
        }
        guard let profile = preferenceStore.loadOpenSnekLocalProfiles().first(where: { $0.id == id }) else {
            clearSelectedSingleSlotLocalProfile(device: device)
            return nil
        }
        return profile
    }

    private func setSelectedSingleSlotLocalProfile(_ profile: OpenSnekLocalProfile, device: MouseDevice) {
        preferenceStore.persistSelectedLocalProfileID(profile.id, device: device)
        setSelectedSingleSlotProfileName(profile.name, device: device)
    }

    private func clearSelectedSingleSlotLocalProfile(device: MouseDevice) {
        preferenceStore.persistSelectedLocalProfileID(nil, device: device)
        selectedSingleSlotProfileNameByDeviceID.removeValue(forKey: device.id)
        bumpOnboardProfilesRevision()
    }

    private func adaptDPI(_ dpi: OnboardDPIProfileSnapshot, for device: MouseDevice) -> OnboardDPIProfileSnapshot {
        let sourcePairs = !dpi.pairs.isEmpty ? dpi.pairs : dpi.scalar.map { [$0] } ?? []
        let clampedPairs = Array(sourcePairs.prefix(DeviceProfiles.maximumDpiStageCount)).map { pair in
            if DeviceProfiles.supportsIndependentXYDPI(for: device) {
                return DpiPair(
                    x: DeviceProfiles.clampDPI(pair.x, device: device),
                    y: DeviceProfiles.clampDPI(pair.y, device: device)
                )
            }
            let scalar = DeviceProfiles.clampDPI(pair.x, device: device)
            return DpiPair(x: scalar, y: scalar)
        }
        let count = DeviceProfiles.clampDpiStageCount(clampedPairs.count)
        let active = dpi.activeStage.map { max(0, min(max(0, count - 1), $0)) }
        let scalar = active.flatMap { clampedPairs.indices.contains($0) ? clampedPairs[$0] : nil } ?? clampedPairs.first
        return OnboardDPIProfileSnapshot(
            scalar: scalar,
            activeStage: active,
            pairs: clampedPairs,
            stageIDs: dpi.stageIDs,
            marker: dpi.marker
        )
    }

    private func adaptedButtonBindings(
        _ bindings: [Int: ButtonBindingDraft],
        for device: MouseDevice
    ) -> [Int: ButtonBindingDraft] {
        let writableSlots = Set(device.button_layout?.writableSlots ?? buttonSlots.map(\.slot))
        let availableKinds = Set(ButtonBindingSupport.availableButtonBindingKinds(profileID: device.profile_id))
        return bindings.reduce(into: [Int: ButtonBindingDraft]()) { partialResult, pair in
            guard writableSlots.contains(pair.key) else { return }
            let resolvedDraft: ButtonBindingDraft
            if availableKinds.contains(pair.value.kind) {
                resolvedDraft = pair.value
            } else {
                resolvedDraft = ButtonBindingSupport.defaultButtonBinding(for: pair.key, profileID: device.profile_id)
            }
            partialResult[pair.key] = ButtonBindingSupport.normalizedDefaultRepresentation(
                for: pair.key,
                draft: resolvedDraft,
                profileID: device.profile_id
            )
        }
    }

    private func adaptedLighting(
        _ content: OpenSnekLocalProfileContent,
        for device: MouseDevice
    ) -> AdaptedLightingContent {
        guard device.showsLightingControls else {
            return AdaptedLightingContent(brightness: [:], staticColors: [:], effect: nil)
        }
        let targetLEDIDs = lightingLEDIDs(for: device).map(Int.init)
        let sourceBrightness = content.brightnessByLEDID.values.max()
        let brightness = sourceBrightness.map { value in
            Dictionary(uniqueKeysWithValues: targetLEDIDs.map { ($0, value) })
        } ?? [:]

        let sourceColor = primaryStaticColor(from: content)
        let staticColors = sourceColor.map { color in
            Dictionary(uniqueKeysWithValues: targetLEDIDs.map { ($0, color) })
        } ?? [:]

        let supportedEffects = DeviceProfiles
            .resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)?
            .supportedLightingEffects ?? []
        let effect: LightingEffectPatch?
        if let lightingEffect = content.lightingEffect,
           device.supports_advanced_lighting_effects,
           supportedEffects.contains(lightingEffect.kind) {
            effect = lightingEffect
        } else {
            effect = nil
        }
        return AdaptedLightingContent(brightness: brightness, staticColors: staticColors, effect: effect)
    }

    private func primaryStaticColor(from content: OpenSnekLocalProfileContent) -> RGBPatch? {
        if let first = content.staticColorByLEDID.sorted(by: { $0.key < $1.key }).first?.value {
            return first
        }
        if let effect = content.lightingEffect, effect.kind == .staticColor || effect.kind.usesPrimaryColor {
            return effect.primary
        }
        return nil
    }

    private func applyLocalProfileContentToEditor(_ content: OpenSnekLocalProfileContent, device: MouseDevice) {
        isHydrating = true
        defer { isHydrating = false }
        if let dpi = content.dpi {
            hydrateEditableDPI(from: dpi, device: device, source: "localProfile")
        }
        if let brightness = content.brightnessByLEDID.values.max() {
            editorStore.editableLedBrightness = brightness
        }
        if let color = primaryStaticColor(from: content) {
            editorStore.editableColor = RGBColor(r: color.r, g: color.g, b: color.b)
            editorStore.editableLightingEffect = content.lightingEffect?.kind ?? .staticColor
            editorStore.noteLightingGradientColorsChanged()
        } else if let effect = content.lightingEffect {
            editorStore.editableLightingEffect = effect.kind
        }
        if device.transport == .usb {
            if let scrollMode = content.scrollMode {
                editorStore.editableScrollMode = scrollMode
            }
            if let scrollAcceleration = content.scrollAcceleration {
                editorStore.editableScrollAcceleration = scrollAcceleration
            }
            if let scrollSmartReel = content.scrollSmartReel {
                editorStore.editableScrollSmartReel = scrollSmartReel
            }
        }
        editorStore.editableButtonBindings.merge(content.buttonBindings) { _, updated in updated }
        bumpUSBButtonProfilesRevision()
    }
}

enum AppStateLocalProfileError: LocalizedError {
    case noSelectedProfile
    case applyFailed

    var errorDescription: String? {
        switch self {
        case .noSelectedProfile:
            return "No onboard profile slot is selected."
        case .applyFailed:
            return "The profile could not be applied to the device."
        }
    }
}
