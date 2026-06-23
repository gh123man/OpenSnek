import Foundation
import OpenSnekAppSupport
import OpenSnekCore

@MainActor
extension AppStateEditorController {
    func readLatestOnboardProfileSnapshot(
        device: MouseDevice,
        profileID: Int,
        storeForEditing: Bool = true
    ) async throws -> OnboardProfileSnapshot {
        let snapshot = try await environment.backend.readOnboardProfile(device: device, profileID: profileID)
        if storeForEditing {
            storeCurrentOnboardProfileSnapshot(snapshot, device: device, source: "readOnboardProfile")
        }
        return snapshot
    }

    func readLatestOnboardProfileCoreSnapshot(
        device: MouseDevice,
        profileID: Int
    ) async throws -> OnboardProfileSnapshot {
        try await environment.backend.readOnboardProfileCore(device: device, profileID: profileID)
    }

    func updateCachedOnboardInventoryActiveProfile(deviceID: String, activeProfileID: Int) {
        guard let inventory = onboardProfileInventoryByDeviceID[deviceID] else { return }
        let profiles = synthesizedOnboardProfileSummaries(from: inventory).map { summary in
            OnboardProfileSummary(
                profileID: summary.profileID,
                metadata: summary.metadata,
                isAssigned: summary.isAssigned,
                isActive: summary.profileID == activeProfileID,
                isBaseProfile: summary.isBaseProfile
            )
        }
        onboardProfileInventoryByDeviceID[deviceID] = OnboardProfileInventory(
            activeProfileID: activeProfileID,
            maxProfileID: inventory.maxProfileID,
            assignedProfileIDs: inventory.assignedProfileIDs,
            profiles: profiles
        )
    }

    func storeSelectedDeviceState(_ state: MouseState, for device: MouseDevice) -> MouseState {
        let merged = state.merged(with: deviceStore.state)
        guard deviceStore.selectedDeviceID == device.id else { return merged }
        deviceStore.state = merged
        deviceStore.lastUpdated = Date()
        return merged
    }

    func storeActiveOnboardProfileState(
        _ state: MouseState,
        for device: MouseDevice,
        fallbackActiveProfileID: Int
    ) -> Int {
        let merged = storeSelectedDeviceState(state, for: device)
        let active = merged.active_onboard_profile ?? fallbackActiveProfileID
        updateCachedOnboardInventoryActiveProfile(deviceID: device.id, activeProfileID: active)
        lastHardwareActiveOnboardProfileIDByDeviceID[device.id] = active
        return active
    }

    func isOnboardProfileActive(deviceID: String, profileID: Int) -> Bool {
        if let inventory = onboardProfileInventoryByDeviceID[deviceID] {
            return inventory.activeProfileID == profileID || inventory.summary(for: profileID)?.isActive == true
        }
        return deviceStore.state?.active_onboard_profile == profileID
    }

    func nextAssignedOnboardProfile(afterDeleting profileID: Int, in inventory: OnboardProfileInventory) -> Int? {
        let assigned = inventory.assignedProfileIDs.filter { $0 != profileID }.sorted()
        return assigned.first(where: { $0 > profileID }) ?? assigned.first
    }

    func handleActiveOnboardProfilePresentation(from state: MouseState) {
        guard let device = deviceStore.selectedDevice,
              supportsOnboardProfileCRUD(device: device),
              let active = state.active_onboard_profile else {
            return
        }
        let previousActive = lastHardwareActiveOnboardProfileIDByDeviceID[device.id]
        let selected = selectedOnboardProfileIDByDeviceID[device.id]
        let activeChanged = previousActive != nil && active != previousActive
        let reloadRequired = onboardProfileReloadRequiredDeviceIDs.contains(device.id)
        let shouldFollowActive = selected == nil || selected == previousActive || activeChanged
        if shouldFollowActive {
            selectedOnboardProfileIDByDeviceID[device.id] = active
        }
        lastHardwareActiveOnboardProfileIDByDeviceID[device.id] = active
        updateCachedOnboardInventoryActiveProfile(deviceID: device.id, activeProfileID: active)
        bumpOnboardProfilesRevision()
        if manualOnboardProfileActivationTargetByDeviceID[device.id] == active {
            AppLog.debug(
                "AppState",
                "active onboard profile presentation skipped duplicate manual load device=\(device.id) active=\(active)"
            )
            return
        }
        guard environment.launchRole == .app else {
            AppLog.debug(
                "AppState",
                "active onboard profile presentation skipped service profile load device=\(device.id) active=\(active)"
            )
            return
        }
        guard shouldFollowActive, activeChanged || reloadRequired else { return }
        onboardProfileReloadRequiredDeviceIDs.remove(device.id)

        applyController.cancelPendingLocalEditsForSelectionChange()
        scheduleActiveOnboardProfileLoad(device: device, profileID: active)
    }

    func scheduleActiveOnboardProfileLoad(device: MouseDevice, profileID: Int) {
        cancelActiveOnboardProfileLoad(deviceID: device.id)
        let token = UUID()
        activeOnboardProfileLoadTokensByDeviceID[device.id] = token
        activeOnboardProfileLoadTasksByDeviceID[device.id] = Task(priority: .userInitiated) { @MainActor [weak self, editorStore] in
            defer {
                if let self, self.activeOnboardProfileLoadTokensByDeviceID[device.id] == token {
                    self.activeOnboardProfileLoadTasksByDeviceID.removeValue(forKey: device.id)
                    self.activeOnboardProfileLoadTokensByDeviceID.removeValue(forKey: device.id)
                }
            }
            guard let self, !Task.isCancelled else { return }
            let operationID = editorStore.beginOnboardProfileLoad(statusText: "Loading profile...")
            self.activeOnboardProfileLoadOperationIDsByDeviceID[device.id] = operationID
            defer {
                editorStore.endOnboardProfileLoad(operationID)
                if self.activeOnboardProfileLoadOperationIDsByDeviceID[device.id] == operationID {
                    self.activeOnboardProfileLoadOperationIDsByDeviceID.removeValue(forKey: device.id)
                }
            }
            await self.selectOnboardProfile(profileID)
        }
    }

    func synthesizedOnboardProfileSummaries(from inventory: OnboardProfileInventory) -> [OnboardProfileSummary] {
        (1...inventory.maxProfileID).map { profileID in
            if let summary = inventory.summary(for: profileID) {
                return summary
            }
            return OnboardProfileSummary(
                profileID: profileID,
                metadata: nil,
                isAssigned: profileID == 1,
                isActive: profileID == inventory.activeProfileID,
                isBaseProfile: profileID == 1
            )
        }
    }

    func storeCurrentOnboardProfileSnapshot(
        _ snapshot: OnboardProfileSnapshot,
        device: MouseDevice,
        source: String = "snapshot",
        projectMetadataForRefresh: Bool = false
    ) {
        let priorName = onboardProfileInventoryByDeviceID[device.id]?
            .summary(for: snapshot.profileID)?
            .displayName ?? "<missing>"
        let metadataResolvedSnapshot = snapshotPreservingKnownMetadataForCoreRead(
            snapshot,
            device: device,
            source: source
        )
        let storedSnapshot: OnboardProfileSnapshot
        if metadataResolvedSnapshot.isMetadataOnly,
           let current = currentOnboardProfileSnapshotByDeviceID[device.id],
           current.profileID == metadataResolvedSnapshot.profileID,
           !current.isMetadataOnly {
            storedSnapshot = current.replacingMetadata(metadataResolvedSnapshot.metadata)
        } else {
            storedSnapshot = metadataResolvedSnapshot
        }
        currentOnboardProfileSnapshotByDeviceID[device.id] = storedSnapshot
        if projectMetadataForRefresh {
            var projectedMetadata = projectedOnboardProfileMetadataByDeviceID[device.id] ?? [:]
            projectedMetadata[storedSnapshot.profileID] = storedSnapshot.metadata
            projectedOnboardProfileMetadataByDeviceID[device.id] = projectedMetadata
        } else if projectedOnboardProfileMetadataByDeviceID[device.id]?[storedSnapshot.profileID] == storedSnapshot.metadata {
            projectedOnboardProfileMetadataByDeviceID[device.id]?.removeValue(forKey: storedSnapshot.profileID)
            if projectedOnboardProfileMetadataByDeviceID[device.id]?.isEmpty == true {
                projectedOnboardProfileMetadataByDeviceID.removeValue(forKey: device.id)
            }
            AppLog.debug(
                "AppState",
                "onboard profile metadata projection confirmed by snapshot source=\(source) device=\(device.id) profile=\(storedSnapshot.profileID) name=\"\(storedSnapshot.metadata.name)\""
            )
        }
        let inventory = onboardProfileInventoryByDeviceID[device.id] ?? synthesizedOnboardProfileInventory(
            device: device,
            including: storedSnapshot
        )
        var summaries = synthesizedOnboardProfileSummaries(from: inventory).filter { $0.profileID != storedSnapshot.profileID }
        summaries.append(OnboardProfileSummary(
            profileID: storedSnapshot.profileID,
            metadata: storedSnapshot.metadata,
            isAssigned: true,
            isActive: storedSnapshot.profileID == inventory.activeProfileID,
            isBaseProfile: storedSnapshot.profileID == 1
        ))
        let assigned = Set(inventory.assignedProfileIDs + [storedSnapshot.profileID])
        let updatedInventory = OnboardProfileInventory(
            activeProfileID: inventory.activeProfileID,
            maxProfileID: inventory.maxProfileID,
            assignedProfileIDs: Array(assigned).sorted(),
            profiles: summaries
        )
        onboardProfileInventoryByDeviceID[device.id] = inventoryApplyingProjectedOnboardMetadata(
            updatedInventory,
            deviceID: device.id,
            source: source,
            confirmMatchingProjections: false
        )
        let storedName = onboardProfileInventoryByDeviceID[device.id]?
            .summary(for: storedSnapshot.profileID)?
            .displayName ?? "<missing>"
        syncLocalProfile(from: storedSnapshot, device: device, source: source)
        AppLog.debug(
            "AppState",
            "onboard profile snapshot stored source=\(source) device=\(device.id) profile=\(storedSnapshot.profileID) priorName=\"\(priorName)\" snapshotName=\"\(storedSnapshot.metadata.name)\" storedName=\"\(storedName)\" projected=\(projectMetadataForRefresh)"
                + " dpiCount=\(storedSnapshot.dpi?.stageCount ?? 0) dpiValues=\(storedSnapshot.dpi?.values.map(String.init).joined(separator: ",") ?? "<none>")"
        )
    }

    private func snapshotPreservingKnownMetadataForCoreRead(
        _ snapshot: OnboardProfileSnapshot,
        device: MouseDevice,
        source: String
    ) -> OnboardProfileSnapshot {
        guard source.localizedCaseInsensitiveContains("core") else { return snapshot }
        if let metadata = onboardProfileInventoryByDeviceID[device.id]?
            .summary(for: snapshot.profileID)?
            .metadata {
            return snapshot.replacingMetadata(metadata)
        }
        if let current = currentOnboardProfileSnapshotByDeviceID[device.id],
           current.profileID == snapshot.profileID {
            return snapshot.replacingMetadata(current.metadata)
        }
        return snapshot
    }

    func inventoryApplyingProjectedOnboardMetadata(
        _ inventory: OnboardProfileInventory,
        deviceID: String,
        source: String,
        confirmMatchingProjections: Bool
    ) -> OnboardProfileInventory {
        guard let projections = projectedOnboardProfileMetadataByDeviceID[deviceID], !projections.isEmpty else {
            return inventory
        }

        var remainingProjections = projections
        let assignedProfileIDs = Set(inventory.assignedProfileIDs)
        let summaries = (1...inventory.maxProfileID).map { profileID -> OnboardProfileSummary in
            let existing = inventory.summary(for: profileID)
            let baseSummary = existing ?? OnboardProfileSummary(
                profileID: profileID,
                metadata: nil,
                isAssigned: assignedProfileIDs.contains(profileID),
                isActive: profileID == inventory.activeProfileID,
                isBaseProfile: profileID == 1
            )
            guard let projected = projections[profileID] else {
                return baseSummary
            }

            guard baseSummary.isAssigned else {
                remainingProjections.removeValue(forKey: profileID)
                AppLog.debug(
                    "AppState",
                    "onboard profile metadata projection dropped for unassigned profile source=\(source) device=\(deviceID) profile=\(profileID)"
                )
                return baseSummary
            }

            if baseSummary.isAssigned, baseSummary.metadata == projected {
                if !confirmMatchingProjections {
                    return baseSummary
                }
                remainingProjections.removeValue(forKey: profileID)
                AppLog.debug(
                    "AppState",
                    "onboard profile metadata projection confirmed by inventory source=\(source) device=\(deviceID) profile=\(profileID) name=\"\(projected.name)\""
                )
                return baseSummary
            }

            AppLog.warning(
                "AppState",
                "onboard profile inventory returned stale metadata; preserving projected name source=\(source) device=\(deviceID) profile=\(profileID) incomingAssigned=\(baseSummary.isAssigned) incomingName=\"\(baseSummary.metadata?.name ?? "<nil>")\" projectedName=\"\(projected.name)\""
            )
            return OnboardProfileSummary(
                profileID: profileID,
                metadata: projected,
                isAssigned: true,
                isActive: profileID == inventory.activeProfileID,
                isBaseProfile: profileID == 1
            )
        }

        if remainingProjections.isEmpty {
            projectedOnboardProfileMetadataByDeviceID.removeValue(forKey: deviceID)
        } else {
            projectedOnboardProfileMetadataByDeviceID[deviceID] = remainingProjections
        }

        return OnboardProfileInventory(
            activeProfileID: inventory.activeProfileID,
            maxProfileID: inventory.maxProfileID,
            assignedProfileIDs: assignedProfileIDs.sorted(),
            profiles: summaries
        )
    }

    func inventoryPreservingKnownOnboardMetadata(
        _ inventory: OnboardProfileInventory,
        deviceID: String
    ) -> OnboardProfileInventory {
        let existing = onboardProfileInventoryByDeviceID[deviceID]
        let assignedProfileIDs = Set(inventory.assignedProfileIDs)
        let profiles = (1...inventory.maxProfileID).map { profileID -> OnboardProfileSummary in
            let incoming = inventory.summary(for: profileID)
            let isAssigned = assignedProfileIDs.contains(profileID)
            let metadata = isAssigned ? incoming?.metadata ?? existing?.summary(for: profileID)?.metadata : nil
            return OnboardProfileSummary(
                profileID: profileID,
                metadata: metadata,
                isAssigned: isAssigned,
                isActive: profileID == inventory.activeProfileID,
                isBaseProfile: profileID == 1
            )
        }
        return OnboardProfileInventory(
            activeProfileID: inventory.activeProfileID,
            maxProfileID: inventory.maxProfileID,
            assignedProfileIDs: inventory.assignedProfileIDs,
            profiles: profiles
        )
    }

    func synthesizedOnboardProfileInventory(
        device: MouseDevice,
        including snapshot: OnboardProfileSnapshot
    ) -> OnboardProfileInventory {
        let maxProfileID = max(
            snapshot.profileID,
            max(device.onboard_profile_count, deviceStore.state?.onboard_profile_count ?? 1)
        )
        let active = max(1, min(maxProfileID, deviceStore.state?.active_onboard_profile ?? snapshot.profileID))
        let assigned = Set([1, max(1, snapshot.profileID)])
        var profiles: [OnboardProfileSummary] = []
        if snapshot.profileID != 1 {
            profiles.append(OnboardProfileSummary(
                profileID: 1,
                metadata: nil,
                isAssigned: true,
                isActive: active == 1,
                isBaseProfile: true
            ))
        }
        profiles.append(OnboardProfileSummary(
            profileID: snapshot.profileID,
            metadata: snapshot.metadata,
            isAssigned: true,
            isActive: snapshot.profileID == active,
            isBaseProfile: snapshot.profileID == 1
        ))
        return OnboardProfileInventory(
            activeProfileID: active,
            maxProfileID: maxProfileID,
            assignedProfileIDs: Array(assigned).sorted(),
            profiles: profiles
        )
    }

    func resolvedDeviceProfile(for device: MouseDevice) -> DeviceProfile? {
        DeviceProfiles.resolve(
            vendorID: device.vendor_id,
            productID: device.product_id,
            transport: device.transport
        )
    }

    func supportsOnboardProfileCRUD(device: MouseDevice) -> Bool {
        resolvedDeviceProfile(for: device)?.supportsMappedOnboardProfileCRUD == true
    }

    func shouldHydrateSelectedProfileDuringRefresh(device: MouseDevice) -> Bool {
        supportsOnboardProfileCRUD(device: device)
    }

    func lightingLEDIDs(for device: MouseDevice) -> [UInt8] {
        resolvedDeviceProfile(for: device)?.allUSBLightingLEDIDs ?? [0x01]
    }

    func onboardProfileSummaries() -> [OnboardProfileSummary] {
        guard let device = deviceStore.selectedDevice else { return [] }
        guard supportsOnboardProfileCRUD(device: device) else {
            return supportsProfilePicker(device: device) ? [singleSlotProfileSummary(device: device)] : []
        }
        if let inventory = onboardProfileInventoryByDeviceID[device.id] {
            return synthesizedOnboardProfileSummaries(from: inventory)
        }
        return []
    }

    func selectedOnboardProfileID() -> Int? {
        guard let device = deviceStore.selectedDevice else { return nil }
        guard supportsOnboardProfileCRUD(device: device) else {
            return supportsProfilePicker(device: device) ? 1 : nil
        }
        return selectedOnboardProfileIDByDeviceID[device.id] ?? deviceStore.state?.active_onboard_profile
    }

    func selectedOnboardProfileName() -> String {
        guard let selected = selectedOnboardProfileID() else {
            AppLog.debug("AppState", "selected onboard profile name fallback: no selected profile")
            return "Onboard Profile"
        }
        let summaries = onboardProfileSummaries()
        guard let summary = summaries.first(where: { $0.profileID == selected }) else {
            AppLog.debug(
                "AppState",
                "selected onboard profile name fallback: missing summary selected=\(selected) visible=\(summaries.map(\.profileID).map(String.init).joined(separator: ","))"
            )
            return "Onboard Profile"
        }
        return summary.isAssigned ? summary.displayName : "None"
    }

    func selectedOnboardProfileIsActive() -> Bool {
        guard let device = deviceStore.selectedDevice,
              let selected = selectedOnboardProfileID() else { return false }
        guard supportsOnboardProfileCRUD(device: device) else {
            return supportsProfilePicker(device: device) && selected == 1
        }
        return isOnboardProfileActive(deviceID: device.id, profileID: selected)
    }

    func refreshOnboardProfiles(hydrateSelectedProfile: Bool = true) async {
        guard !isTearingDown, let device = deviceStore.selectedDevice, supportsOnboardProfileCRUD(device: device) else { return }
        guard onboardProfileRefreshInFlightDeviceIDs.insert(device.id).inserted else {
            AppLog.debug("AppState", "refresh onboard profiles coalesced device=\(device.id)")
            return
        }
        defer {
            onboardProfileRefreshInFlightDeviceIDs.remove(device.id)
        }
        do {
            AppLog.debug(
                "AppState",
                "refresh onboard profiles start device=\(device.id) selected=\(selectedOnboardProfileIDByDeviceID[device.id].map(String.init) ?? "<nil>") pendingMetadataProfiles=\((projectedOnboardProfileMetadataByDeviceID[device.id]?.keys.sorted() ?? []).map(String.init).joined(separator: ","))"
            )
            let inventory = try await environment.backend.listOnboardProfiles(device: device)
            let priorNames = onboardProfileInventoryByDeviceID[device.id]?.profiles.reduce(into: [Int: String]()) { partialResult, summary in
                partialResult[summary.profileID] = summary.displayName
            } ?? [:]
            let projectedInventory = inventoryApplyingProjectedOnboardMetadata(
                inventoryPreservingKnownOnboardMetadata(inventory, deviceID: device.id),
                deviceID: device.id,
                source: "refreshOnboardProfiles",
                confirmMatchingProjections: true
            )
            onboardProfileInventoryByDeviceID[device.id] = projectedInventory
            lastHardwareActiveOnboardProfileIDByDeviceID[device.id] = inventory.activeProfileID
            let selected = selectedOnboardProfileIDByDeviceID[device.id]
            if selected == nil || !projectedInventory.assignedProfileIDs.contains(selected ?? -1) {
                selectedOnboardProfileIDByDeviceID[device.id] = projectedInventory.activeProfileID
            }

            let selectedAfterRefresh = selectedOnboardProfileIDByDeviceID[device.id] ?? projectedInventory.activeProfileID
            if hydrateSelectedProfile,
               shouldHydrateSelectedProfileDuringRefresh(device: device),
               selectedAfterRefresh == projectedInventory.activeProfileID,
               projectedInventory.assignedProfileIDs.contains(selectedAfterRefresh),
               currentOnboardProfileSnapshotByDeviceID[device.id]?.profileID != selectedAfterRefresh {
                let snapshot = try await readLatestOnboardProfileSnapshot(device: device, profileID: selectedAfterRefresh)
                if applyController.shouldHydrateEditable(for: device) {
                    hydrateEditable(from: snapshot, device: device)
                } else {
                    AppLog.debug(
                        "AppState",
                        "refresh onboard profiles skipped selected snapshot hydration pending local edit device=\(device.id) profile=\(selectedAfterRefresh)"
                    )
                }
            }

            let visibleInventory = onboardProfileInventoryByDeviceID[device.id] ?? projectedInventory
            let currentNames = visibleInventory.profiles.reduce(into: [Int: String]()) { partialResult, summary in
                partialResult[summary.profileID] = summary.displayName
            }
            let changedNames = currentNames
                .keys
                .sorted()
                .compactMap { profileID -> String? in
                    guard priorNames[profileID] != currentNames[profileID] else { return nil }
                    return "\(profileID):\"\(priorNames[profileID] ?? "<missing>")\"->\"\(currentNames[profileID] ?? "<missing>")\""
                }
                .joined(separator: ",")
            AppLog.debug(
                "AppState",
                "refresh onboard profiles ok device=\(device.id) active=\(visibleInventory.activeProfileID) assigned=\(visibleInventory.assignedProfileIDs.map(String.init).joined(separator: ",")) selected=\(selectedOnboardProfileIDByDeviceID[device.id].map(String.init) ?? "<nil>") changedNames=\(changedNames.isEmpty ? "<none>" : changedNames)"
            )
            editorStore.onboardProfileRefreshErrorMessage = nil
            bumpOnboardProfilesRevision()
        } catch {
            AppLog.error("AppState", "refresh onboard profiles failed device=\(device.id): \(error.localizedDescription)")
            editorStore.onboardProfileRefreshErrorMessage = "Failed to refresh onboard profiles: \(error.localizedDescription)"
        }
    }

    func selectOnboardProfile(_ profileID: Int) async {
        guard !isTearingDown, let device = deviceStore.selectedDevice else { return }
        guard supportsOnboardProfileCRUD(device: device) else {
            guard supportsProfilePicker(device: device), profileID == 1 else { return }
            selectedOnboardProfileIDByDeviceID[device.id] = 1
            deviceStore.errorMessage = nil
            bumpOnboardProfilesRevision()
            return
        }
        applyController.cancelPendingLocalEditsForSelectionChange()
        clearButtonWorkspaceEditMarkers(deviceID: device.id)
        cancelSelectedMouseSlotHydration(deviceID: device.id)
        cancelOnboardProfileButtonHydration(deviceID: device.id)
        let start = Date()
        do {
            AppLog.debug("AppState", "select onboard profile start device=\(device.id) profile=\(profileID)")
            if onboardProfileInventoryByDeviceID[device.id] == nil {
                await refreshOnboardProfiles(hydrateSelectedProfile: false)
            }
            var inventory = onboardProfileInventoryByDeviceID[device.id]
            if inventory?.assignedProfileIDs.contains(profileID) != true,
               profileID == lastHardwareActiveOnboardProfileIDByDeviceID[device.id] {
                await refreshOnboardProfiles(hydrateSelectedProfile: false)
                inventory = onboardProfileInventoryByDeviceID[device.id]
            }
            guard let inventory,
                  profileID >= 1,
                  profileID <= inventory.maxProfileID else {
                deviceStore.errorMessage = "Profile \(profileID) is outside the supported profile range."
                return
            }
            guard inventory.assignedProfileIDs.contains(profileID) else {
                selectedOnboardProfileIDByDeviceID[device.id] = profileID
                currentOnboardProfileSnapshotByDeviceID.removeValue(forKey: device.id)
                deviceStore.errorMessage = nil
                bumpOnboardProfilesRevision()
                return
            }
            guard isOnboardProfileActive(deviceID: device.id, profileID: profileID) else {
                await activateOnboardProfile(profileID)
                return
            }
            let snapshot = snapshotWithCachedButtonBindings(
                try await readLatestOnboardProfileCoreSnapshot(device: device, profileID: profileID),
                device: device
            )
            storeCurrentOnboardProfileSnapshot(snapshot, device: device, source: "readOnboardProfileCore")
            selectedOnboardProfileIDByDeviceID[device.id] = profileID
            hydrateEditable(from: snapshot, device: device)
            if shouldHydrateOnboardProfileButtonsInline(device: device) {
                await readOnboardProfileButtonBindingsForSelection(device: device, profileID: profileID)
            } else {
                scheduleOnboardProfileButtonHydration(device: device, profileID: profileID)
            }
            deviceStore.errorMessage = nil
            bumpOnboardProfilesRevision()
            AppLog.debug(
                "AppState",
                "select onboard profile ok device=\(device.id) profile=\(profileID) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
            )
        } catch {
            AppLog.error("AppState", "select onboard profile failed profile=\(profileID): \(error.localizedDescription)")
            deviceStore.errorMessage = "Failed to load onboard profile: \(error.localizedDescription)"
        }
    }

    func activateOnboardProfile(_ profileID: Int) async {
        guard !isTearingDown, let device = deviceStore.selectedDevice, supportsOnboardProfileCRUD(device: device) else { return }
        applyController.cancelPendingLocalEditsForSelectionChange()
        clearButtonWorkspaceEditMarkers(deviceID: device.id)
        cancelSelectedMouseSlotHydration(deviceID: device.id)
        cancelOnboardProfileButtonHydration(deviceID: device.id)
        let start = Date()
        manualOnboardProfileActivationTargetByDeviceID[device.id] = profileID
        defer {
            if manualOnboardProfileActivationTargetByDeviceID[device.id] == profileID {
                manualOnboardProfileActivationTargetByDeviceID.removeValue(forKey: device.id)
            }
        }
        do {
            AppLog.debug("AppState", "activate onboard profile start device=\(device.id) profile=\(profileID)")
            let state = try await environment.backend.activateOnboardProfile(device: device, profileID: profileID)
            let active = storeActiveOnboardProfileState(state, for: device, fallbackActiveProfileID: profileID)
            selectedOnboardProfileIDByDeviceID[device.id] = active
            let snapshot = snapshotWithCachedButtonBindings(
                try await readLatestOnboardProfileCoreSnapshot(device: device, profileID: active),
                device: device
            )
            storeCurrentOnboardProfileSnapshot(snapshot, device: device, source: "activateOnboardProfileCore")
            hydrateEditable(from: snapshot, device: device)
            if shouldHydrateOnboardProfileButtonsInline(device: device) {
                await readOnboardProfileButtonBindingsForSelection(device: device, profileID: active)
            } else {
                scheduleOnboardProfileButtonHydration(device: device, profileID: active)
            }
            deviceStore.errorMessage = nil
            bumpOnboardProfilesRevision()
            AppLog.debug(
                "AppState",
                "activate onboard profile ok device=\(device.id) requested=\(profileID) active=\(active) elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
            )
        } catch {
            AppLog.error("AppState", "activate onboard profile failed profile=\(profileID): \(error.localizedDescription)")
            deviceStore.errorMessage = "Failed to activate onboard profile: \(error.localizedDescription)"
        }
    }

    func createOnboardProfile(
        name: String,
        targetProfileID: Int? = nil,
        copyFromProfileID: Int? = nil
    ) async {
        guard !isTearingDown, let device = deviceStore.selectedDevice, supportsOnboardProfileCRUD(device: device) else { return }
        cancelSelectedMouseSlotHydration(deviceID: device.id)
        do {
            let metadata = OnboardProfileMetadata(name: name)
            let mutation: OnboardProfileMutation
            if let copyFromProfileID {
                let sourceSnapshot = try await readLatestOnboardProfileSnapshot(
                    device: device,
                    profileID: copyFromProfileID,
                    storeForEditing: false
                )
                mutation = onboardProfileMutation(copying: sourceSnapshot, metadata: metadata)
            } else {
                mutation = currentOnboardProfileMutation(device: device, metadata: metadata)
            }
            let snapshot = try await environment.backend.createOnboardProfile(
                device: device,
                mutation: mutation,
                targetProfileID: targetProfileID,
                replaceAssignedProfile: false
            )
            storeCurrentOnboardProfileSnapshot(
                snapshot,
                device: device,
                source: "createOnboardProfile",
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
        } catch {
            AppLog.error("AppState", "create onboard profile failed target=\(targetProfileID.map(String.init) ?? "auto"): \(error.localizedDescription)")
            deviceStore.errorMessage = "Failed to create onboard profile: \(error.localizedDescription)"
        }
    }

    func renameSelectedOnboardProfile(name: String) async {
        guard !isTearingDown,
              let device = deviceStore.selectedDevice,
              supportsOnboardProfileCRUD(device: device),
              let selected = selectedOnboardProfileID() else { return }
        cancelSelectedMouseSlotHydration(deviceID: device.id)
        do {
            let requestedName = OnboardProfileMetadata.normalizedName(name)
            let priorName = onboardProfileInventoryByDeviceID[device.id]?
                .summary(for: selected)?
                .displayName ?? "<missing>"
            AppLog.debug(
                "AppState",
                "rename onboard profile start device=\(device.id) transport=\(device.transport.rawValue) profile=\(selected) priorName=\"\(priorName)\" requestedName=\"\(requestedName)\" active=\(deviceStore.state?.active_onboard_profile.map(String.init) ?? "<nil>")"
            )
            let snapshot = try await environment.backend.renameOnboardProfile(
                device: device,
                profileID: selected,
                name: name
            )
            storeCurrentOnboardProfileSnapshot(
                snapshot,
                device: device,
                source: "renameOnboardProfile",
                projectMetadataForRefresh: true
            )
            selectedOnboardProfileIDByDeviceID[device.id] = selected
            deviceStore.errorMessage = nil
            bumpOnboardProfilesRevision()
            let visibleName = onboardProfileInventoryByDeviceID[device.id]?
                .summary(for: selected)?
                .displayName ?? "<missing>"
            AppLog.debug(
                "AppState",
                "rename onboard profile ok device=\(device.id) profile=\(selected) requestedName=\"\(requestedName)\" snapshotName=\"\(snapshot.metadata.name)\" visibleName=\"\(visibleName)\" revision=\(editorStore.onboardProfilesRevision)"
            )
        } catch {
            AppLog.error("AppState", "rename onboard profile failed profile=\(selected): \(error.localizedDescription)")
            deviceStore.errorMessage = "Failed to rename onboard profile: \(error.localizedDescription)"
        }
    }

    func deleteSelectedOnboardProfile() async {
        guard !isTearingDown,
              let device = deviceStore.selectedDevice,
              supportsOnboardProfileCRUD(device: device),
              let selected = selectedOnboardProfileID(),
              selected >= 2 else { return }
        cancelSelectedMouseSlotHydration(deviceID: device.id)
        do {
            let wasActive = isOnboardProfileActive(deviceID: device.id, profileID: selected)
            var inventory = try await environment.backend.deleteOnboardProfile(device: device, profileID: selected)
            onboardProfileInventoryByDeviceID[device.id] = inventory
            if currentOnboardProfileSnapshotByDeviceID[device.id]?.profileID == selected {
                currentOnboardProfileSnapshotByDeviceID.removeValue(forKey: device.id)
            }

            var nextSelected: Int?
            if wasActive {
                nextSelected = nextAssignedOnboardProfile(afterDeleting: selected, in: inventory)
            } else if inventory.assignedProfileIDs.contains(inventory.activeProfileID) {
                nextSelected = inventory.activeProfileID
            } else {
                nextSelected = nextAssignedOnboardProfile(afterDeleting: selected, in: inventory)
            }

            if wasActive, let activationTarget = nextSelected {
                let state = try await environment.backend.activateOnboardProfile(device: device, profileID: activationTarget)
                let active = storeActiveOnboardProfileState(state, for: device, fallbackActiveProfileID: activationTarget)
                nextSelected = active
                let profiles = synthesizedOnboardProfileSummaries(from: inventory).map { summary in
                    OnboardProfileSummary(
                        profileID: summary.profileID,
                        metadata: summary.metadata,
                        isAssigned: summary.isAssigned,
                        isActive: summary.profileID == active,
                        isBaseProfile: summary.isBaseProfile
                    )
                }
                inventory = OnboardProfileInventory(
                    activeProfileID: active,
                    maxProfileID: inventory.maxProfileID,
                    assignedProfileIDs: inventory.assignedProfileIDs,
                    profiles: profiles
                )
                onboardProfileInventoryByDeviceID[device.id] = inventory
            }

            lastHardwareActiveOnboardProfileIDByDeviceID[device.id] = inventory.activeProfileID
            if let nextSelected {
                selectedOnboardProfileIDByDeviceID[device.id] = nextSelected
                if let snapshot = try? await readLatestOnboardProfileSnapshot(device: device, profileID: nextSelected) {
                    hydrateEditable(from: snapshot, device: device)
                }
            } else {
                selectedOnboardProfileIDByDeviceID.removeValue(forKey: device.id)
            }
            deviceStore.errorMessage = nil
            bumpOnboardProfilesRevision()
        } catch {
            AppLog.error("AppState", "delete onboard profile failed profile=\(selected): \(error.localizedDescription)")
            deviceStore.errorMessage = "Failed to delete onboard profile: \(error.localizedDescription)"
        }
    }

    func applyOnboardProfileMutationForCurrentSelection(_ mutation: OnboardProfileMutation) async -> Bool {
        guard !isTearingDown,
              let device = deviceStore.selectedDevice,
              supportsOnboardProfileCRUD(device: device),
              let selected = selectedOnboardProfileID(),
              !mutation.isEmpty else { return false }
        cancelSelectedMouseSlotHydration(deviceID: device.id)
        let startedAt = Date()
        let mutationStartedEditRevision = buttonWorkspaceEditRevision
        activeOnboardProfileMutationCount += 1
        maxConcurrentOnboardProfileMutationCount = max(
            maxConcurrentOnboardProfileMutationCount,
            activeOnboardProfileMutationCount
        )
#if DEBUG
        OpenSnekUITestSupport.recordOnboardProfileMutationStart(
            UITestProfileMutationEvent(
                device: device,
                profileID: selected,
                mutation: mutation,
                activeMutationCount: activeOnboardProfileMutationCount,
                maxConcurrentMutationCount: maxConcurrentOnboardProfileMutationCount,
                elapsed: nil,
                error: nil
            )
        )
        if activeOnboardProfileMutationCount > 1 {
            OpenSnekUITestSupport.recordOnboardProfileMutationOverlapDetected(
                device: device,
                profileID: selected,
                mutation: mutation,
                activeMutationCount: activeOnboardProfileMutationCount,
                maxConcurrentMutationCount: maxConcurrentOnboardProfileMutationCount
            )
        }
#endif
        defer {
            activeOnboardProfileMutationCount -= 1
        }
        do {
            let resolvedMutation = mutation.preservingDpiIdentity(
                from: currentSelectedOnboardProfileSnapshot(device: device)
            )
            let snapshot = try await environment.backend.updateOnboardProfile(
                device: device,
                profileID: selected,
                mutation: resolvedMutation
            )
            guard deviceStore.selectedDeviceID == device.id,
                  selectedOnboardProfileIDByDeviceID[device.id] == selected else {
                AppLog.debug(
                    "AppState",
                    "update onboard profile stale-drop device=\(device.id) profile=\(selected)"
                )
#if DEBUG
                OpenSnekUITestSupport.recordOnboardProfileMutationEnd(
                    UITestProfileMutationEvent(
                        device: device,
                        profileID: selected,
                        mutation: resolvedMutation,
                        activeMutationCount: activeOnboardProfileMutationCount,
                        maxConcurrentMutationCount: maxConcurrentOnboardProfileMutationCount,
                        elapsed: Date().timeIntervalSince(startedAt),
                        error: nil
                    )
                )
#endif
                return true
            }
            storeCurrentOnboardProfileSnapshot(
                snapshot,
                device: device,
                source: "updateOnboardProfile",
                projectMetadataForRefresh: resolvedMutation.metadata != nil
            )
            if selectedOnboardProfileIDByDeviceID[device.id] == selected {
                if let bindings = resolvedMutation.buttonBindings {
                    cacheSelectedOnboardProfileButtonBindings(
                        snapshot.buttonBindings.merging(bindings) { _, updated in updated },
                        device: device,
                        profileID: selected,
                        appliedEditRevision: mutationStartedEditRevision
                    )
                }
                hydrateEditableLighting(from: snapshot, device: device)
                hydrateEditableScroll(from: snapshot)
            }
            if selectedOnboardProfileIsActive() {
                _ = try await environment.backend.refreshActiveOnboardProfile(device: device)
            }
            bumpOnboardProfilesRevision()
#if DEBUG
            OpenSnekUITestSupport.recordOnboardProfileMutationEnd(
                UITestProfileMutationEvent(
                    device: device,
                    profileID: selected,
                    mutation: resolvedMutation,
                    activeMutationCount: activeOnboardProfileMutationCount,
                    maxConcurrentMutationCount: maxConcurrentOnboardProfileMutationCount,
                    elapsed: Date().timeIntervalSince(startedAt),
                    error: nil
                )
            )
#endif
            return true
        } catch {
            AppLog.error("AppState", "update onboard profile failed profile=\(selected): \(error.localizedDescription)")
            deviceStore.errorMessage = "Failed to update onboard profile: \(error.localizedDescription)"
#if DEBUG
            OpenSnekUITestSupport.recordOnboardProfileMutationError(
                UITestProfileMutationEvent(
                    device: device,
                    profileID: selected,
                    mutation: mutation,
                    activeMutationCount: activeOnboardProfileMutationCount,
                    maxConcurrentMutationCount: maxConcurrentOnboardProfileMutationCount,
                    elapsed: Date().timeIntervalSince(startedAt),
                    error: error
                )
            )
#endif
            return false
        }
    }

}
