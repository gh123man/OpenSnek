import Foundation
import OpenSnekAppSupport
import OpenSnekCore

@MainActor
extension AppStateEditorController {
    func currentOnboardProfileMutation(
        device: MouseDevice,
        metadata: OnboardProfileMetadata? = nil
    ) -> OnboardProfileMutation {
        let count = DeviceProfiles.clampDpiStageCount(editorStore.editableStageCount)
        let pairs = Array(editorStore.editableStagePairs.prefix(count)).map { pair in
            DpiPair(
                x: DeviceProfiles.clampDPI(pair.x, device: device),
                y: DeviceProfiles.clampDPI(pair.y, device: device)
            )
        }
        let activeStage = max(0, min(count - 1, editorStore.editableActiveStage - 1))
        let scalar = pairs.indices.contains(activeStage) ? pairs[activeStage] : pairs.first
        let brightness = Dictionary(
            uniqueKeysWithValues: lightingLEDIDs(for: device).map { ledID in
                (Int(ledID), editorStore.editableLedBrightness)
            }
        )
        let colors: [Int: RGBPatch]
        if editorStore.editableLightingEffect == .staticColor || !device.supports_advanced_lighting_effects {
            colors = Dictionary(
                uniqueKeysWithValues: lightingLEDIDs(for: device).map { ledID in
                    (Int(ledID), RGBPatch(r: editorStore.editableColor.r, g: editorStore.editableColor.g, b: editorStore.editableColor.b))
                }
            )
        } else {
            colors = [:]
        }
        return OnboardProfileMutation(
            metadata: metadata,
            dpi: OnboardDPIProfileSnapshot(
                scalar: scalar,
                activeStage: activeStage,
                pairs: pairs,
                stageIDs: currentSelectedOnboardProfileSnapshot(device: device)?.dpi?.stageIDs ?? [],
                marker: currentSelectedOnboardProfileSnapshot(device: device)?.dpi?.marker
            ),
            buttonBindings: editorStore.editableButtonBindings,
            brightnessByLEDID: brightness,
            staticColorByLEDID: colors.isEmpty ? nil : colors,
            scrollMode: device.transport == .usb ? editorStore.editableScrollMode : nil,
            scrollAcceleration: device.transport == .usb ? editorStore.editableScrollAcceleration : nil,
            scrollSmartReel: device.transport == .usb ? editorStore.editableScrollSmartReel : nil
        )
    }

    func onboardProfileMutation(
        copying snapshot: OnboardProfileSnapshot,
        metadata: OnboardProfileMetadata
    ) -> OnboardProfileMutation {
        OnboardProfileMutation(
            metadata: metadata,
            dpi: snapshot.dpi,
            buttonBindings: snapshot.buttonBindings,
            brightnessByLEDID: snapshot.brightnessByLEDID,
            staticColorByLEDID: snapshot.staticColorByLEDID,
            scrollMode: snapshot.scrollMode,
            scrollAcceleration: snapshot.scrollAcceleration,
            scrollSmartReel: snapshot.scrollSmartReel
        )
    }

    func snapshotWithCachedButtonBindings(
        _ snapshot: OnboardProfileSnapshot,
        device: MouseDevice
    ) -> OnboardProfileSnapshot {
        let metadataResolvedSnapshot: OnboardProfileSnapshot
        if let metadata = onboardProfileInventoryByDeviceID[device.id]?.summary(for: snapshot.profileID)?.metadata {
            metadataResolvedSnapshot = snapshot.replacingMetadata(metadata)
        } else {
            metadataResolvedSnapshot = snapshot
        }
        guard !(device.transport == .bluetooth && supportsOnboardProfileCRUD(device: device)) else {
            return metadataResolvedSnapshot
        }
        let cached = cachedButtonBindings(device: device, profile: max(1, snapshot.profileID))
        guard !cached.isEmpty else { return metadataResolvedSnapshot }
        return metadataResolvedSnapshot.replacingButtonBindings(cached)
    }

    func shouldHydrateOnboardProfileButtonsInline(device: MouseDevice) -> Bool {
        device.transport == .bluetooth && supportsOnboardProfileCRUD(device: device)
    }

    func readOnboardProfileButtonBindingsForSelection(device: MouseDevice, profileID: Int) async {
        let workspaceEditRevisionAtStart = buttonWorkspaceEditRevision
        let hadPendingLocalEditAtStart = hasPendingButtonWorkspaceEdit(device: device, profileID: profileID)
        do {
            let bindings = try await environment.backend.readOnboardProfileButtonBindings(
                device: device,
                profileID: profileID
            )
            guard deviceStore.selectedDeviceID == device.id,
                  selectedOnboardProfileIDByDeviceID[device.id] == profileID else {
                return
            }
            storeOnboardProfileButtonBindings(
                bindings,
                device: device,
                profileID: profileID,
                workspaceEditRevisionAtStart: workspaceEditRevisionAtStart,
                hadPendingLocalEditAtStart: hadPendingLocalEditAtStart
            )
        } catch {
            AppLog.debug(
                "AppState",
                "onboard profile button hydration failed device=\(device.id) profile=\(profileID): \(error.localizedDescription)"
            )
        }
    }

    func scheduleOnboardProfileButtonHydration(device: MouseDevice, profileID: Int) {
        cancelOnboardProfileButtonHydration(deviceID: device.id)
        guard deviceStore.selectedDeviceID == device.id else { return }
        let token = UUID()
        onboardProfileButtonHydrationTokensByDeviceID[device.id] = token
        onboardProfileButtonHydrationTasksByDeviceID[device.id] = Task(priority: .utility) { @MainActor [weak self] in
            defer {
                if let self, self.onboardProfileButtonHydrationTokensByDeviceID[device.id] == token {
                    self.onboardProfileButtonHydrationTasksByDeviceID.removeValue(forKey: device.id)
                    self.onboardProfileButtonHydrationTokensByDeviceID.removeValue(forKey: device.id)
                }
            }
            guard let self, !Task.isCancelled else { return }
            let workspaceEditRevisionAtStart = self.buttonWorkspaceEditRevision
            let hadPendingLocalEditAtStart = self.hasPendingButtonWorkspaceEdit(device: device, profileID: profileID)
            do {
                let bindings = try await self.environment.backend.readOnboardProfileButtonBindings(
                    device: device,
                    profileID: profileID
                )
                guard !Task.isCancelled,
                      self.deviceStore.selectedDeviceID == device.id,
                      self.selectedOnboardProfileIDByDeviceID[device.id] == profileID else {
                    return
                }
                self.storeOnboardProfileButtonBindings(
                    bindings,
                    device: device,
                    profileID: profileID,
                    workspaceEditRevisionAtStart: workspaceEditRevisionAtStart,
                    hadPendingLocalEditAtStart: hadPendingLocalEditAtStart
                )
            } catch {
                AppLog.debug(
                    "AppState",
                    "onboard profile button hydration failed device=\(device.id) profile=\(profileID): \(error.localizedDescription)"
                )
            }
        }
    }

    func storeOnboardProfileButtonBindings(
        _ bindings: [Int: ButtonBindingDraft],
        device: MouseDevice,
        profileID: Int,
        workspaceEditRevisionAtStart: UInt64? = nil,
        hadPendingLocalEditAtStart: Bool = false
    ) {
        let snapshot = currentOnboardProfileSnapshotByDeviceID[device.id]
        let persistentProfileID = max(1, profileID)
        let hydrationKey = buttonBindingsHydrationKey(device: device, profile: persistentProfileID)

        guard let snapshot, snapshot.profileID == profileID else {
            AppLog.debug(
                "AppState",
                "onboard profile button hydration stale-drop device=\(device.id) profile=\(profileID) " +
                "currentProfile=\(snapshot.map { String($0.profileID) } ?? "nil") bindings=\(buttonBindingsDebugSummary(bindings))"
            )
            bumpUSBButtonProfilesRevision()
            return
        }

        let isSelectedEditableProfile = selectedOnboardProfileIDByDeviceID[device.id] == profileID &&
            deviceStore.selectedDeviceID == device.id &&
            hydratedButtonBindingsKey == hydrationKey
        let workspaceChangedDuringReadback = workspaceEditRevisionAtStart.map {
            buttonWorkspaceEditRevision != $0
        } ?? false
        if isSelectedEditableProfile,
           workspaceChangedDuringReadback ||
           hadPendingLocalEditAtStart ||
           buttonWorkspaceEditRevisionByHydrationKey[hydrationKey] != nil {
            AppLog.debug(
                "AppState",
                "onboard profile button hydration stale-drop device=\(device.id) profile=\(profileID) " +
                "dueToLocalEdits=true bindings=\(buttonBindingsDebugSummary(bindings))"
            )
            bumpUSBButtonProfilesRevision()
            return
        }

        buttonBindingsCacheByHydrationKey[hydrationKey] = bindings
        buttonBindingsReadbackAttemptedKeys.insert(hydrationKey)

        let updatedSnapshot = snapshot.replacingButtonBindings(bindings)
        storeCurrentOnboardProfileSnapshot(
            updatedSnapshot,
            device: device,
            source: "readOnboardProfileButtonBindings"
        )
        if selectedOnboardProfileIDByDeviceID[device.id] == profileID,
           deviceStore.selectedDeviceID == device.id {
            hydratedButtonBindingsKey = hydrationKey
            editorStore.editableButtonBindings = bindings
            bumpUSBButtonProfilesRevision()
        }
        AppLog.debug(
            "AppState",
            "onboard profile button hydration ok device=\(device.id) profile=\(profileID) bindings=\(buttonBindingsDebugSummary(bindings))"
        )
    }

    func cacheSelectedOnboardProfileButtonBindings(
        _ bindings: [Int: ButtonBindingDraft],
        device: MouseDevice,
        profileID: Int,
        appliedEditRevision: UInt64? = nil
    ) {
        let persistentProfileID = max(1, profileID)
        let hydrationKey = buttonBindingsHydrationKey(device: device, profile: persistentProfileID)
        buttonBindingsCacheByHydrationKey[hydrationKey] = bindings
        savePersistedButtonBindings(device: device, bindings: bindings, profile: persistentProfileID)
        buttonBindingsReadbackAttemptedKeys.insert(hydrationKey)
        if let appliedEditRevision,
           let pendingEditRevision = buttonWorkspaceEditRevisionByHydrationKey[hydrationKey],
           pendingEditRevision <= appliedEditRevision {
            buttonWorkspaceEditRevisionByHydrationKey.removeValue(forKey: hydrationKey)
        }
        if selectedOnboardProfileIDByDeviceID[device.id] == profileID,
           deviceStore.selectedDeviceID == device.id {
            hydratedButtonBindingsKey = hydrationKey
            editorStore.editableButtonBindings = bindings
            bumpUSBButtonProfilesRevision()
        }
    }

    func currentSelectedOnboardProfileSnapshot(device: MouseDevice) -> OnboardProfileSnapshot? {
        guard let selected = selectedOnboardProfileIDByDeviceID[device.id] else { return nil }
        guard let snapshot = currentOnboardProfileSnapshotByDeviceID[device.id],
              snapshot.profileID == selected else {
            return nil
        }
        return snapshot
    }

    func rgbColor(from patch: RGBPatch) -> RGBColor {
        RGBColor(r: patch.r, g: patch.g, b: patch.b)
    }

    func onboardProfileLightingZoneColors(from snapshot: OnboardProfileSnapshot, device: MouseDevice) -> [String: RGBColor] {
        guard !snapshot.staticColorByLEDID.isEmpty else { return [:] }
        let profile = resolvedDeviceProfile(for: device)
        let targets = profile?.lightingTargets() ?? lightingLEDIDs(for: device).map { ledID in
            USBLightingTargetDescriptor(
                zoneID: String(format: "led_%02x", ledID),
                zoneLabel: String(format: "LED 0x%02X", ledID),
                ledID: ledID
            )
        }

        var colors: [String: RGBColor] = [:]
        for target in targets where colors[target.zoneID] == nil {
            guard let patch = snapshot.staticColorByLEDID[Int(target.ledID)] else { continue }
            colors[target.zoneID] = rgbColor(from: patch)
        }
        if colors.isEmpty, let first = snapshot.staticColorByLEDID.sorted(by: { $0.key < $1.key }).first {
            colors["all"] = rgbColor(from: first.value)
        }
        return colors
    }

    func currentActiveOnboardProfileSnapshot(for state: MouseState) -> OnboardProfileSnapshot? {
        guard let device = deviceStore.selectedDevice,
              supportsOnboardProfileCRUD(device: device),
              let snapshot = currentOnboardProfileSnapshotByDeviceID[device.id],
              !snapshot.isMetadataOnly else {
            return nil
        }
        let active = state.active_onboard_profile ?? deviceStore.state?.active_onboard_profile
        let selected = selectedOnboardProfileIDByDeviceID[device.id] ?? active
        guard snapshot.profileID == selected else { return nil }
        if let active, active != snapshot.profileID {
            return nil
        }
        return snapshot
    }

    func hydrateEditableDPI(
        from dpi: OnboardDPIProfileSnapshot,
        device: MouseDevice,
        liveDPI: DpiPair? = nil,
        activeStageOverride: Int? = nil,
        source: String = "hydrateEditableDPI"
    ) {
        let sourcePairs = !dpi.pairs.isEmpty
            ? dpi.pairs
            : dpi.scalar.map { [$0] } ?? []
        guard !sourcePairs.isEmpty else { return }

        let count = DeviceProfiles.clampDpiStageCount(sourcePairs.count)
        var nextPairs = editorStore.editableStagePairs
        for index in 0..<nextPairs.count where index < count {
            let pair = sourcePairs[index]
            nextPairs[index] = DpiPair(
                x: DeviceProfiles.clampDPI(pair.x, device: device),
                y: DeviceProfiles.clampDPI(pair.y, device: device)
            )
        }
        editorStore.editableStageCount = count
        editorStore.editableStagePairs = nextPairs
        let matchedActiveStage = liveDPI.flatMap { liveDPI in
            Self.uniqueDPIStageIndex(matching: liveDPI, in: Array(sourcePairs.prefix(count)))
        }
        let nextActiveStage = activeStageOverride.map { max(1, min(count, $0)) }
            ?? max(1, min(count, (matchedActiveStage ?? dpi.activeStage ?? 0) + 1))
        editorStore.setEditableActiveStage(
            nextActiveStage,
            source: "\(source) profileActive=\(dpi.activeStage.map(String.init) ?? "nil") " +
                "matchedLive=\(matchedActiveStage.map(String.init) ?? "nil") " +
                "override=\(activeStageOverride.map(String.init) ?? "nil")"
        )
        editorStore.normalizeExpandedXYStages()
    }

    nonisolated static func uniqueDPIStageIndex(matching liveDPI: DpiPair, in pairs: [DpiPair]) -> Int? {
        let matchingIndices = pairs.enumerated().compactMap { index, pair in
            pair.x == liveDPI.x && pair.y == liveDPI.y ? index : nil
        }
        return matchingIndices.count == 1 ? matchingIndices[0] : nil
    }

    nonisolated static func diagnosticScrollState(_ state: MouseState) -> String {
        "mode=\(state.scroll_mode.map(String.init) ?? "nil")," +
            "accel=\(state.scroll_acceleration.map(String.init) ?? "nil")," +
            "smart=\(state.scroll_smart_reel.map(String.init) ?? "nil")"
    }

    nonisolated static func diagnosticScrollSnapshot(_ snapshot: OnboardProfileSnapshot) -> String {
        "mode=\(snapshot.scrollMode.map(String.init) ?? "nil")," +
            "accel=\(snapshot.scrollAcceleration.map(String.init) ?? "nil")," +
            "smart=\(snapshot.scrollSmartReel.map(String.init) ?? "nil")"
    }

    nonisolated static func diagnosticScrollSnapshot(_ snapshot: PersistedDeviceSettingsSnapshot) -> String {
        "mode=\(snapshot.scrollMode.map(String.init) ?? "nil")," +
            "accel=\(snapshot.scrollAcceleration.map(String.init) ?? "nil")," +
            "smart=\(snapshot.scrollSmartReel.map(String.init) ?? "nil")"
    }

    func hydrateEditableLighting(from snapshot: OnboardProfileSnapshot, device: MouseDevice) {
        if let brightness = snapshot.brightnessByLEDID.values.max() {
            editorStore.editableLedBrightness = brightness
            editorStore.noteLightingGradientColorsChanged()
        }

        let zoneColors = onboardProfileLightingZoneColors(from: snapshot, device: device)
        guard !zoneColors.isEmpty else {
            if onboardProfileLightingColorsByDeviceID.removeValue(forKey: device.id) != nil {
                editorStore.noteLightingGradientColorsChanged()
            }
            return
        }

        onboardProfileLightingColorsByDeviceID[device.id] = zoneColors
        editorStore.editableLightingEffect = .staticColor

        let visibleZoneIDs = editorStore.visibleUSBLightingZones.map(\.id)
        let currentZoneID = normalizedLightingZoneID(for: device, preferredZoneID: editorStore.editableUSBLightingZoneID)
        let resolvedZoneID: String
        if currentZoneID != "all", zoneColors[currentZoneID] != nil {
            resolvedZoneID = currentZoneID
        } else if let firstVisibleZoneID = visibleZoneIDs.first(where: { zoneColors[$0] != nil }) {
            resolvedZoneID = firstVisibleZoneID
        } else {
            resolvedZoneID = "all"
        }

        editorStore.editableUSBLightingZoneID = resolvedZoneID
        if let color = zoneColors[resolvedZoneID] ?? zoneColors["all"] ?? zoneColors.sorted(by: { $0.key < $1.key }).first?.value {
            editorStore.editableColor = color
        }
        editorStore.noteLightingGradientColorsChanged()
    }

    func hydrateEditableScroll(from snapshot: OnboardProfileSnapshot) {
        AppLog.debug(
            "AppState",
            "hydrateEditableScroll snapshot profile=\(snapshot.profileID) " +
            "scroll=\(Self.diagnosticScrollSnapshot(snapshot))"
        )
        if let scrollMode = snapshot.scrollMode {
            editorStore.editableScrollMode = max(0, min(1, scrollMode))
        }
        if let scrollAcceleration = snapshot.scrollAcceleration {
            editorStore.editableScrollAcceleration = scrollAcceleration
        }
        if let scrollSmartReel = snapshot.scrollSmartReel {
            editorStore.editableScrollSmartReel = scrollSmartReel
        }
    }

    func hydrateEditableScroll(from state: MouseState, fallbackSnapshot snapshot: OnboardProfileSnapshot? = nil) {
        if let scrollMode = state.scroll_mode ?? snapshot?.scrollMode {
            editorStore.editableScrollMode = max(0, min(1, scrollMode))
        }
        if let scrollAcceleration = state.scroll_acceleration ?? snapshot?.scrollAcceleration {
            editorStore.editableScrollAcceleration = scrollAcceleration
        }
        if let scrollSmartReel = state.scroll_smart_reel ?? snapshot?.scrollSmartReel {
            editorStore.editableScrollSmartReel = scrollSmartReel
        }
    }

    func hydrateEditable(from snapshot: OnboardProfileSnapshot, device: MouseDevice) {
        isHydrating = true
        defer { isHydrating = false }

        if let dpi = snapshot.dpi {
            hydrateEditableDPI(from: dpi, device: device, source: "hydrateEditable.onboardSnapshot")
        }
        hydrateEditableLighting(from: snapshot, device: device)
        hydrateEditableScroll(from: snapshot)
        editorStore.editableButtonBindings = snapshot.buttonBindings
        let hydrationKey = buttonBindingsHydrationKey(device: device, profile: max(1, snapshot.profileID))
        buttonBindingsCacheByHydrationKey[hydrationKey] = snapshot.buttonBindings
        buttonBindingsReadbackAttemptedKeys.insert(hydrationKey)
        hydratedButtonBindingsKey = hydrationKey
        bumpUSBButtonProfilesRevision()
    }

}
