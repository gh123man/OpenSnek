import Foundation
import OpenSnekAppSupport
import OpenSnekCore

/// Adds selection lighting behavior to `AppStateEditorController`.
@MainActor
extension AppStateEditorController {
    func liveUSBButtonProfile(for device: MouseDevice) -> Int {
        let count = max(1, device.onboard_profile_count)
        let hardwareActiveProfile = max(1, min(count, editorStore.activeOnboardProfile))
        let overrideProfile = softwareActiveUSBButtonProfileOverrideByDeviceID[device.id].map { max(1, min(count, $0)) }
        if overrideProfile == hardwareActiveProfile {
            softwareActiveUSBButtonProfileOverrideByDeviceID.removeValue(forKey: device.id)
            return hardwareActiveProfile
        }
        return overrideProfile ?? hardwareActiveProfile
    }

    func liveUSBButtonProfile() -> Int {
        guard let device = deviceStore.selectedDevice else { return editorStore.activeOnboardProfile }
        return liveUSBButtonProfile(for: device)
    }

    func selectedUSBButtonProfileHasUnsavedChanges() -> Bool {
        guard let device = deviceStore.selectedDevice else { return false }
        guard editorStore.supportsMultipleOnboardProfiles else { return false }
        return usbButtonProfileHasUnsavedChanges(device: device, profile: editorStore.editableUSBButtonProfile)
    }

    func usbButtonProfileHasUnsavedChanges(device: MouseDevice, profile: Int) -> Bool {
        let writableSlots = device.button_layout?.writableSlots ?? buttonSlots.map(\.slot)
        let draftBindings: [Int: ButtonBindingDraft]
        if editorStore.editableUSBButtonProfile == profile {
            draftBindings = editorStore.editableButtonBindings
        } else {
            draftBindings = cachedButtonBindings(device: device, profile: profile)
        }
        let persistedBindings = cachedButtonBindings(device: device, profile: profile)
        return writableSlots.contains { slot in
            let fallback = defaultButtonBinding(for: slot, device: device)
            return (draftBindings[slot] ?? fallback) != (persistedBindings[slot] ?? fallback)
        }
    }

    func setLiveUSBButtonProfileOverride(_ profile: Int, for device: MouseDevice) {
        let clamped = max(1, min(editorStore.visibleOnboardProfileCount, profile))
        let hardwareActiveProfile = max(1, min(editorStore.visibleOnboardProfileCount, editorStore.activeOnboardProfile))
        if clamped == hardwareActiveProfile {
            softwareActiveUSBButtonProfileOverrideByDeviceID.removeValue(forKey: device.id)
        } else {
            softwareActiveUSBButtonProfileOverrideByDeviceID[device.id] = clamped
        }
        bumpUSBButtonProfilesRevision()
    }

    func usbButtonProfileSummaries() -> [USBButtonProfileSummary] {
        guard let device = deviceStore.selectedDevice, editorStore.supportsMultipleOnboardProfiles else { return [] }
        let count = max(1, editorStore.visibleOnboardProfileCount)
        let hardwareActiveProfile = max(1, min(count, editorStore.activeOnboardProfile))
        let liveActiveProfile = max(1, min(count, liveUSBButtonProfile(for: device)))

        return (1...count).map { profile in
            USBButtonProfileSummary(
                profile: profile,
                isHardwareActive: profile == hardwareActiveProfile,
                isLiveActive: profile == liveActiveProfile,
                isCustomized: profileHasCustomBindings(device: device, profile: profile)
            )
        }
    }

    func defaultButtonBinding(for slot: Int) -> ButtonBindingDraft {
        ButtonBindingSupport.defaultButtonBinding(for: slot, profileID: deviceStore.selectedDevice?.profile_id)
    }

    func currentLightingEffectPatch() -> LightingEffectPatch {
        LightingEffectPatch(
            kind: editorStore.editableLightingEffect,
            primary: RGBPatch(r: editorStore.editableColor.r, g: editorStore.editableColor.g, b: editorStore.editableColor.b),
            secondary: RGBPatch(r: editorStore.editableSecondaryColor.r, g: editorStore.editableSecondaryColor.g, b: editorStore.editableSecondaryColor.b),
            waveDirection: editorStore.editableLightingWaveDirection,
            reactiveSpeed: editorStore.editableLightingReactiveSpeed
        )
    }

    func startSoftwareLighting() async {
        guard let device = deviceStore.selectedDevice else {
            deviceStore.errorMessage = "No device selected"
            return
        }
        guard device.supportsSoftwareLightingEffects else {
            deviceStore.errorMessage = "Software lighting is not supported for this device."
            return
        }

        let request = editorStore.softwareLightingEffectRequest()
        guard device.supportsSoftwareLightingPreset(request.presetID) else {
            deviceStore.errorMessage = "\(request.presetID.label) is not supported for this device."
            return
        }
        preferenceStore.persistSoftwareLightingRequest(request, device: device)

        do {
            let status = try await environment.backend.startSoftwareLighting(
                device: device,
                request: request
            )
            deviceStore.softwareLightingStatusByDeviceID[device.id] = status
            deviceStore.errorMessage = nil
        } catch {
            deviceStore.errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func startPersistedSoftwareLightingOnConnectIfNeeded(
        for device: MouseDevice,
        reassertRunning: Bool = false
    ) async -> Bool {
        let autoStartKey = DevicePersistenceKeys.key(for: device)
        guard !isTearingDown else {
            AppLog.debug(
                "LightingTrace",
                "software lighting persisted start skipped reason=tearingDown " +
                    "device=\(device.id) key=\(autoStartKey)"
            )
            return false
        }
        guard device.supportsSoftwareLightingEffects else {
            AppLog.debug(
                "LightingTrace",
                "software lighting persisted start skipped reason=unsupported " +
                    "device=\(device.id) key=\(autoStartKey)"
            )
            return false
        }
        guard preferenceStore.loadSoftwareLightingApplyOnConnect(device: device) else {
            AppLog.debug(
                "LightingTrace",
                "software lighting persisted start skipped reason=applyOnConnectDisabled " +
                    "device=\(device.id) key=\(autoStartKey)"
            )
            return false
        }
        guard !softwareLightingAutoStartInFlightKeys.contains(autoStartKey) else {
            AppLog.debug(
                "LightingTrace",
                "software lighting persisted start skipped reason=inFlight " +
                    "device=\(device.id) key=\(autoStartKey)"
            )
            return false
        }

        let request = supportedSoftwareLightingRequest(
            preferenceStore.loadPersistedSoftwareLightingRequest(device: device)
                ?? SoftwareLightingEffectRequest(presetID: .flame),
            for: device
        )
        let previousStatus = deviceStore.softwareLightingStatusByDeviceID[device.id]
        if !reassertRunning,
           previousStatus?.state == .running,
           previousStatus?.request == request {
            AppLog.debug(
                "LightingTrace",
                "software lighting persisted start skipped reason=alreadyRunning " +
                    "device=\(device.id) key=\(autoStartKey) " +
                    "status=\(SoftwareLightingDiagnostics.statusSummary(previousStatus))"
            )
            return false
        }

        softwareLightingAutoStartInFlightKeys.insert(autoStartKey)
        defer {
            softwareLightingAutoStartInFlightKeys.remove(autoStartKey)
        }

        AppLog.event(
            "LightingTrace",
            "software lighting persisted start requested device=\(device.id) " +
                "key=\(autoStartKey) reassertRunning=\(reassertRunning) " +
                "request=\(SoftwareLightingDiagnostics.requestSummary(request)) " +
                "previousStatus=\(SoftwareLightingDiagnostics.statusSummary(previousStatus))"
        )
        do {
            let status = try await environment.backend.startSoftwareLighting(
                device: device,
                request: request
            )
            deviceStore.softwareLightingStatusByDeviceID[device.id] = status
            if deviceStore.selectedDeviceID == device.id {
                editorStore.editableSoftwareLightingApplyOnConnect = true
                editorStore.applySoftwareLightingEffectRequest(request)
                deviceStore.errorMessage = nil
            }
            AppLog.event(
                "LightingTrace",
                "software lighting \(reassertRunning ? "reasserted" : "auto-started") on connect " +
                    "device=\(device.id) key=\(autoStartKey) " +
                    "status=\(SoftwareLightingDiagnostics.statusSummary(status))"
            )
            return true
        } catch {
            AppLog.warning(
                "LightingTrace",
                "software lighting auto-start failed device=\(device.id) " +
                    "key=\(autoStartKey): \(error.localizedDescription)"
            )
            if deviceStore.selectedDeviceID == device.id {
                deviceStore.errorMessage = error.localizedDescription
            }
            return false
        }
    }

    func supportedSoftwareLightingRequest(
        _ request: SoftwareLightingEffectRequest,
        for device: MouseDevice
    ) -> SoftwareLightingEffectRequest {
        guard device.supportsSoftwareLightingPreset(request.presetID) else {
            return SoftwareLightingEffectRequest(
                presetID: device.supportedSoftwareLightingPresets.first ?? .flame
            )
        }
        return request
    }

    func stopSoftwareLighting() async {
        guard let device = deviceStore.selectedDevice else { return }
        let status = await environment.backend.stopSoftwareLighting(device: device)
        if let status {
            deviceStore.softwareLightingStatusByDeviceID[device.id] = status
        } else {
            deviceStore.softwareLightingStatusByDeviceID.removeValue(forKey: device.id)
        }
    }

    func persistedSettingsRestorePlan(device: MouseDevice) -> PersistedSettingsRestorePlan? {
        guard shouldRestorePersistedSettingsOnConnect(for: device),
              let snapshot = loadPersistedSettingsSnapshot(device: device) else {
            return nil
        }

        let normalizedZoneID = normalizedLightingZoneID(
            for: device,
            preferredZoneID: snapshot.usbLightingZoneID
        )
        let lightingEffect: LightingEffectPatch?
        if let persistedLightingEffect = snapshot.lightingEffect {
            let supportedEffects = DeviceProfiles
                .resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)?
                .supportedLightingEffects ?? LightingEffectKind.allCases
            lightingEffect = supportedEffects.contains(persistedLightingEffect.kind) ? persistedLightingEffect : nil
        } else {
            lightingEffect = nil
        }

        let patch = DevicePatch(
            pollRate: snapshot.pollRate,
            sleepTimeout: snapshot.sleepTimeout,
            lowBatteryThresholdRaw: snapshot.lowBatteryThresholdRaw,
            scrollMode: device.supportsScrollModeControls ? snapshot.scrollMode : nil,
            scrollAcceleration: device.supportsScrollModeControls ? snapshot.scrollAcceleration : nil,
            scrollSmartReel: device.supportsScrollModeControls ? snapshot.scrollSmartReel : nil,
            dpiStages: Array(snapshot.stageValues.prefix(snapshot.stageCount)),
            dpiStagePairs: Array(snapshot.stagePairs.prefix(snapshot.stageCount)),
            activeStage: max(0, min(snapshot.stageCount - 1, snapshot.activeStage - 1)),
            ledBrightness: device.supportsLightingBrightnessControls ? snapshot.ledBrightness : nil,
            ledRGB: lightingEffect == nil
                ? snapshot.primaryLightingColor.map { RGBPatch(r: $0.r, g: $0.g, b: $0.b) }
                : nil,
            lightingEffect: lightingEffect,
            usbLightingZoneLEDIDs: {
                if let lightingEffect, lightingEffect.kind == .staticColor {
                    return usbLightingZoneLEDIDs(for: device, zoneID: normalizedZoneID)
                }
                if lightingEffect == nil {
                    return usbLightingZoneLEDIDs(for: device, zoneID: normalizedZoneID)
                }
                return nil
            }()
        )
        return PersistedSettingsRestorePlan(
            snapshot: snapshot,
            patch: patch,
            buttonBindings: snapshot.buttonBindings
        )
    }

    func persistedLightingPresentationPlan(device: MouseDevice) -> PersistedLightingRestorePlan? {
        guard device.showsLightingControls else { return nil }

        let normalizedZoneID = normalizedLightingZoneID(
            for: device,
            preferredZoneID: loadPersistedLightingZoneID(device: device)
        )
        let persistedColor = loadPersistedLightingColor(device: device, zoneID: normalizedZoneID)

        if device.supports_advanced_lighting_effects,
           let persistedEffect = loadPersistedLightingEffect(device: device) {
            let supportedEffects = DeviceProfiles
                .resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)?
                .supportedLightingEffects ?? LightingEffectKind.allCases
            let resolvedKind = supportedEffects.contains(persistedEffect.kind)
                ? persistedEffect.kind
                : (supportedEffects.first ?? .staticColor)

            let primaryPatch: RGBPatch
            if resolvedKind.usesPrimaryColor {
                guard let persistedColor else {
                    AppLog.debug(
                        "AppState",
                        "skipping persisted lighting restore missing-primary-color id=\(device.id) kind=\(resolvedKind.rawValue)"
                    )
                    return nil
                }
                primaryPatch = RGBPatch(r: persistedColor.r, g: persistedColor.g, b: persistedColor.b)
            } else if let persistedColor {
                primaryPatch = RGBPatch(r: persistedColor.r, g: persistedColor.g, b: persistedColor.b)
            } else {
                primaryPatch = RGBPatch(r: 0, g: 0, b: 0)
            }

            let effect = LightingEffectPatch(
                kind: resolvedKind,
                primary: primaryPatch,
                secondary: RGBPatch(
                    r: persistedEffect.secondaryColor.r,
                    g: persistedEffect.secondaryColor.g,
                    b: persistedEffect.secondaryColor.b
                ),
                waveDirection: persistedEffect.waveDirection,
                reactiveSpeed: persistedEffect.reactiveSpeed
            )
            return PersistedLightingRestorePlan(
                primaryColor: persistedColor,
                lightingEffect: effect,
                usbLightingZoneID: resolvedKind == .staticColor ? normalizedZoneID : "all"
            )
        }

        guard let persistedColor else { return nil }
        return PersistedLightingRestorePlan(
            primaryColor: persistedColor,
            lightingEffect: nil,
            usbLightingZoneID: normalizedZoneID
        )
    }

    func applyPersistedLightingRestorePlanToEditor(_ plan: PersistedLightingRestorePlan) {
        if let primaryColor = plan.primaryColor {
            editorStore.editableColor = primaryColor
        }
        editorStore.editableUSBLightingZoneID = plan.usbLightingZoneID
        if let lightingEffect = plan.lightingEffect {
            editorStore.editableLightingEffect = lightingEffect.kind
            editorStore.editableLightingWaveDirection = lightingEffect.waveDirection
            editorStore.editableLightingReactiveSpeed = lightingEffect.reactiveSpeed
            editorStore.editableSecondaryColor = RGBColor(
                r: lightingEffect.secondary.r,
                g: lightingEffect.secondary.g,
                b: lightingEffect.secondary.b
            )
        } else {
            editorStore.editableLightingEffect = .staticColor
        }
        ensureEditableStaticLightingZoneSelection()
    }

    func currentUSBLightingZoneLEDIDs() -> [UInt8]? {
        guard editorStore.editableLightingEffect == .staticColor else { return nil }
        guard editorStore.editableUSBLightingZoneID != "all" else { return nil }
        return editorStore.visibleUSBLightingZones.first(where: { $0.id == editorStore.editableUSBLightingZoneID })?.ledIDs
    }

    func lightingGradientDisplayColors() -> [RGBColor] {
        guard let selectedDevice = deviceStore.selectedDevice else {
            return [editorStore.editableColor]
        }
        guard editorStore.editableLightingEffect == .staticColor,
              editorStore.visibleUSBLightingZones.count > 1 else {
            return [editorStore.editableColor]
        }

        let selectedZoneID = normalizedLightingZoneID(
            for: selectedDevice,
            preferredZoneID: editorStore.editableUSBLightingZoneID
        )
        let onboardProfileColors = onboardProfileLightingColorsByDeviceID[selectedDevice.id]
        let globalColor = loadPersistedLightingColor(device: selectedDevice)
        return editorStore.visibleUSBLightingZones.map { zone in
            if selectedZoneID != "all", zone.id == selectedZoneID {
                return editorStore.editableColor
            }
            if let profileColor = onboardProfileColors?[zone.id] {
                return profileColor
            }
            return loadPersistedLightingColor(device: selectedDevice, zoneID: zone.id)
                ?? globalColor
                ?? editorStore.editableColor
        }
    }

    func ensureEditableStaticLightingZoneSelection() {
        guard editorStore.editableLightingEffect == .staticColor,
              editorStore.visibleUSBLightingZones.count > 1 else { return }

        let visibleZoneIDs = Set(editorStore.visibleUSBLightingZones.map(\.id))
        let currentZoneID = editorStore.editableUSBLightingZoneID
        guard currentZoneID == "all" || !visibleZoneIDs.contains(currentZoneID) else { return }

        if let selectedDevice = deviceStore.selectedDevice {
            updateUSBLightingZoneID(defaultEditableStaticLightingZoneID(for: selectedDevice))
            return
        }

        if let firstZoneID = editorStore.visibleUSBLightingZones.first?.id {
            editorStore.editableUSBLightingZoneID = firstZoneID
        }
    }

    func normalizedLightingZoneID(for device: MouseDevice, preferredZoneID: String?) -> String {
        guard let preferredZoneID, preferredZoneID != "all" else { return "all" }
        let profile = DeviceProfiles.resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)
        return profile?.lightingZone(id: preferredZoneID) != nil ? preferredZoneID : "all"
    }

    func usbLightingZoneLEDIDs(for device: MouseDevice, zoneID: String) -> [UInt8]? {
        guard zoneID != "all" else { return nil }
        return DeviceProfiles
            .resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)?
            .lightingLEDIDs(for: zoneID)
    }

    func syncUSBButtonProfileSelection(from state: MouseState) {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        let count = max(1, max(selectedDevice.onboard_profile_count, state.onboard_profile_count ?? 1))
        let active = max(1, min(count, state.active_onboard_profile ?? 1))
        if let override = softwareActiveUSBButtonProfileOverrideByDeviceID[selectedDevice.id] {
            let clampedOverride = max(1, min(count, override))
            if clampedOverride == active {
                softwareActiveUSBButtonProfileOverrideByDeviceID.removeValue(forKey: selectedDevice.id)
            } else {
                softwareActiveUSBButtonProfileOverrideByDeviceID[selectedDevice.id] = clampedOverride
            }
        }
        let liveSlot = softwareActiveUSBButtonProfileOverrideByDeviceID[selectedDevice.id] ?? active

        if buttonProfileLiveSourceByDeviceID[selectedDevice.id] == nil {
            buttonProfileLiveSourceByDeviceID[selectedDevice.id] = .mouseSlot(liveSlot)
        } else if case .mouseSlot = buttonProfileLiveSourceByDeviceID[selectedDevice.id] {
            buttonProfileLiveSourceByDeviceID[selectedDevice.id] = .mouseSlot(liveSlot)
        }

        let source = buttonProfileSource(for: selectedDevice)
        switch source {
        case .mouseSlot(let slot):
            let clampedSlot = max(1, min(count, slot))
            buttonProfileWorkspaceSourceByDeviceID[selectedDevice.id] = .mouseSlot(clampedSlot)
            if editorStore.editableUSBButtonProfile != clampedSlot {
                editorStore.editableUSBButtonProfile = clampedSlot
                hydratedButtonBindingsKey = nil
            }
        case .openSnekProfile:
            break
        }
        bumpUSBButtonProfilesRevision()
    }

    func buttonBindingsHydrationKey(device: MouseDevice, profile: Int) -> String {
        "\(device.id)#\(max(1, profile))"
    }

    func editableButtonBindingsHydrationKey(device: MouseDevice) -> String {
        let profile = supportsOnboardProfileCRUD(device: device)
            ? selectedOnboardProfileIDByDeviceID[device.id] ?? editorStore.editableUSBButtonProfile
            : editorStore.editableUSBButtonProfile
        return buttonBindingsHydrationKey(device: device, profile: profile)
    }

    func hasPendingButtonWorkspaceEdit(device: MouseDevice, profileID: Int) -> Bool {
        buttonWorkspaceEditRevisionByHydrationKey[
            buttonBindingsHydrationKey(device: device, profile: profileID)
        ] != nil
    }

    func updateLightingEffect(_ kind: LightingEffectKind) {
        guard deviceStore.selectedDevice?.supports_advanced_lighting_effects == true else {
            editorStore.editableLightingEffect = .staticColor
            editorStore.editableUSBLightingZoneID = "all"
            ensureEditableStaticLightingZoneSelection()
            return
        }
        let supportedEffects = editorStore.visibleLightingEffects
        editorStore.editableLightingEffect = supportedEffects.contains(kind) ? kind : (supportedEffects.first ?? .staticColor)
        if kind != .staticColor {
            editorStore.editableUSBLightingZoneID = "all"
        } else {
            ensureEditableStaticLightingZoneSelection()
        }
    }

    func updateUSBLightingZoneID(_ zoneID: String) {
        let resolvedZoneID: String
        if let selectedDevice = deviceStore.selectedDevice {
            let normalizedZoneID = normalizedLightingZoneID(for: selectedDevice, preferredZoneID: zoneID)
            if editorStore.editableLightingEffect == .staticColor,
               editorStore.visibleUSBLightingZones.count > 1,
               normalizedZoneID == "all" {
                resolvedZoneID = defaultEditableStaticLightingZoneID(for: selectedDevice)
            } else {
                resolvedZoneID = normalizedLightingZoneID(for: selectedDevice, preferredZoneID: zoneID)
            }
            if editorStore.editableLightingEffect == .staticColor,
               let profileColor = onboardProfileLightingColorsByDeviceID[selectedDevice.id]?[resolvedZoneID] {
                editorStore.editableColor = profileColor
            } else if editorStore.editableLightingEffect == .staticColor,
               let persistedColor = loadPersistedLightingColor(device: selectedDevice, zoneID: resolvedZoneID) {
                editorStore.editableColor = persistedColor
            }
        } else {
            resolvedZoneID = zoneID
        }
        editorStore.editableUSBLightingZoneID = resolvedZoneID
    }

    func defaultEditableStaticLightingZoneID(for device: MouseDevice) -> String {
        let visibleZones = DeviceProfiles
            .resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)?
            .usbLightingZones ?? []

        let persistedZoneID = normalizedLightingZoneID(
            for: device,
            preferredZoneID: loadPersistedLightingZoneID(device: device)
        )
        if persistedZoneID != "all", visibleZones.contains(where: { $0.id == persistedZoneID }) {
            return persistedZoneID
        }
        return visibleZones.first?.id ?? "all"
    }

    func updateUSBButtonProfile(_ profile: Int) {
        selectButtonProfileSource(.mouseSlot(profile))
    }

    func selectButtonProfileSource(_ source: ButtonProfileSource) {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        switch source {
        case .mouseSlot(let profile):
            let clamped = max(1, min(editorStore.visibleOnboardProfileCount, profile))
            setButtonProfileSource(.mouseSlot(clamped), for: selectedDevice)
            editorStore.editableUSBButtonProfile = clamped
            let hydrationKey = buttonBindingsHydrationKey(device: selectedDevice, profile: clamped)
            editorStore.editableButtonBindings = cachedButtonBindings(device: selectedDevice, profile: clamped)
            hydratedButtonBindingsKey = hydrationKey
            scheduleSelectedMouseSlotHydration(
                device: selectedDevice,
                profile: clamped,
                hydrationKey: hydrationKey
            )
        case .openSnekProfile(let id):
            guard let profile = preferenceStore.loadOpenSnekButtonProfiles().first(where: { $0.id == id }) else { return }
            cancelSelectedMouseSlotHydration(deviceID: selectedDevice.id)
            setButtonProfileSource(.openSnekProfile(id), for: selectedDevice)
            hydratedButtonBindingsKey = nil
            editorStore.editableButtonBindings = profile.bindings
        }
        bumpUSBButtonProfilesRevision()
    }

    func loadButtonProfileSourceIntoLive(_ source: ButtonProfileSource) async {
        guard let selectedDevice = deviceStore.selectedDevice else { return }

        switch source {
        case .mouseSlot(let profile):
            let clamped = max(1, min(editorStore.visibleOnboardProfileCount, profile))
            var bindings = cachedButtonBindings(device: selectedDevice, profile: clamped)
            if !hasKnownButtonBindingsSnapshot(device: selectedDevice, profile: clamped) {
                guard let fromDevice = await loadUSBButtonBindingsFromDevice(device: selectedDevice, profile: clamped) else {
                    deviceStore.errorMessage = "Could not read button profile \(clamped) from the mouse."
                    return
                }
                bindings = fromDevice
                saveCachedButtonBindings(device: selectedDevice, bindings: fromDevice, profile: clamped)
            }
            deviceStore.errorMessage = nil
            setButtonProfileSource(.mouseSlot(clamped), for: selectedDevice)
            editorStore.editableUSBButtonProfile = 1
            let hydrationKey = buttonBindingsHydrationKey(device: selectedDevice, profile: clamped)
            editorStore.editableButtonBindings = bindings
            hydratedButtonBindingsKey = hydrationKey
            bumpUSBButtonProfilesRevision()
        case .openSnekProfile(let id):
            guard let profile = preferenceStore.loadOpenSnekButtonProfiles().first(where: { $0.id == id }) else { return }
            setButtonProfileSource(.openSnekProfile(id), for: selectedDevice)
            hydratedButtonBindingsKey = nil
            editorStore.editableButtonBindings = profile.bindings
        }

        bumpUSBButtonProfilesRevision()
        await applyController.applyCurrentButtonWorkspaceToLive()
    }

    func hasKnownButtonBindingsSnapshot(device: MouseDevice, profile: Int) -> Bool {
        let hydrationKey = buttonBindingsHydrationKey(device: device, profile: profile)
        if buttonBindingsCacheByHydrationKey[hydrationKey] != nil {
            return true
        }
        if device.transport != .usb, !loadPersistedButtonBindings(device: device, profile: profile).isEmpty {
            return true
        }
        return false
    }

    func refreshSelectedMouseSlotFromDeviceIfNeeded(
        device: MouseDevice,
        profile: Int,
        hydrationKey: String
    ) async {
        guard buttonProfileSource(for: device) == .mouseSlot(profile) else { return }
        let workspaceEditRevisionAtStart = buttonWorkspaceEditRevision
        AppLog.debug("AppState", "usb button slot selection hydration start id=\(device.id) profile=\(profile)")
        guard let fromDevice = await loadUSBButtonBindingsFromDevice(device: device, profile: profile) else { return }
        guard !Task.isCancelled else { return }
        guard deviceStore.selectedDevice?.id == device.id,
              buttonProfileSource(for: device) == .mouseSlot(profile),
              buttonWorkspaceEditRevision == workspaceEditRevisionAtStart else {
            return
        }

        saveCachedButtonBindings(device: device, bindings: fromDevice, profile: profile)
        editorStore.editableButtonBindings = fromDevice
        hydratedButtonBindingsKey = hydrationKey
        bumpUSBButtonProfilesRevision()
        AppLog.debug("AppState", "usb button slot selection hydration ok id=\(device.id) profile=\(profile) slots=\(fromDevice.keys.sorted())")
    }

    func scheduleSelectedMouseSlotHydration(
        device: MouseDevice,
        profile: Int,
        hydrationKey: String
    ) {
        selectedMouseSlotHydrationTasksByDeviceID.removeValue(forKey: device.id)?.cancel()
        let token = UUID()
        selectedMouseSlotHydrationTokensByDeviceID[device.id] = token
        selectedMouseSlotHydrationTasksByDeviceID[device.id] = Task(priority: .userInitiated) { @MainActor [weak self] in
            defer {
                if let self, self.selectedMouseSlotHydrationTokensByDeviceID[device.id] == token {
                    self.selectedMouseSlotHydrationTasksByDeviceID.removeValue(forKey: device.id)
                    self.selectedMouseSlotHydrationTokensByDeviceID.removeValue(forKey: device.id)
                }
            }
            guard let self, !Task.isCancelled else { return }
            if device.transport == .usb,
               self.buttonBindingsCacheByHydrationKey[hydrationKey] == nil {
                await self.refreshSelectedMouseSlotFromDeviceIfNeeded(
                    device: device,
                    profile: profile,
                    hydrationKey: hydrationKey
                )
            } else {
                await self.hydrateButtonBindingsIfNeeded(device: device)
            }
        }
    }

    func cancelSelectedMouseSlotHydration(deviceID: String) {
        selectedMouseSlotHydrationTasksByDeviceID.removeValue(forKey: deviceID)?.cancel()
        selectedMouseSlotHydrationTokensByDeviceID.removeValue(forKey: deviceID)
    }

    func selectNextOnboardButtonProfile() {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        let count = editorStore.supportsMultipleOnboardProfiles ? editorStore.visibleOnboardProfileCount : 1
        let sources = (1...max(1, count)).map { ButtonProfileSource.mouseSlot($0) }
        guard sources.count > 1 else { return }

        let currentSource = buttonProfileSource(for: selectedDevice)
        let cycleSource = sources.contains(currentSource) ? currentSource : .mouseSlot(liveUSBButtonProfile(for: selectedDevice))
        let currentIndex = sources.firstIndex(of: cycleSource) ?? 0
        let nextIndex = (currentIndex + 1) % sources.count
        selectButtonProfileSource(sources[nextIndex])
    }

    @discardableResult
    func saveCurrentButtonWorkspaceAsNewProfile(name: String) -> OpenSnekButtonProfile {
        let saved = preferenceStore.saveOpenSnekButtonProfile(
            name: normalizedButtonProfileName(name),
            bindings: editorStore.editableButtonBindings
        )
        bumpUSBButtonProfilesRevision()
        return saved
    }

    func markButtonWorkspaceAppliedToLive(bindings: [Int: ButtonBindingDraft], exactSource: ButtonProfileSource?) {
        guard let selectedDevice = deviceStore.selectedDevice else { return }
        if let exactSource {
            setLiveButtonProfileSource(exactSource, bindings: bindings, for: selectedDevice)
        } else if let currentSource = currentButtonProfileSource() {
            setLiveButtonProfileSource(currentSource, bindings: bindings, for: selectedDevice)
        } else {
            setLiveButtonProfileSource(.mouseSlot(defaultMouseButtonProfileSource(for: selectedDevice)), bindings: bindings, for: selectedDevice)
        }
    }

    func updateLightingWaveDirection(_ direction: LightingWaveDirection) {
        editorStore.editableLightingWaveDirection = direction
    }

    func updateLightingReactiveSpeed(_ speed: Int) {
        editorStore.editableLightingReactiveSpeed = max(1, min(4, speed))
    }

    func buttonBindingKind(for slot: Int) -> ButtonBindingKind {
        editorStore.editableButtonBindings[slot]?.kind ?? defaultButtonBinding(for: slot).kind
    }

    func buttonBindingHidKey(for slot: Int) -> Int {
        editorStore.editableButtonBindings[slot]?.hidKey ?? defaultButtonBinding(for: slot).hidKey
    }

    func buttonBindingHidModifiers(for slot: Int) -> Int {
        editorStore.editableButtonBindings[slot]?.hidModifiers ?? defaultButtonBinding(for: slot).hidModifiers
    }

    func buttonBindingTurboEnabled(for slot: Int) -> Bool {
        editorStore.editableButtonBindings[slot]?.turboEnabled ?? defaultButtonBinding(for: slot).turboEnabled
    }

    func buttonBindingTurboRate(for slot: Int) -> Int {
        editorStore.editableButtonBindings[slot]?.turboRate ?? defaultButtonBinding(for: slot).turboRate
    }

    func buttonBindingClutchDPI(for slot: Int) -> Int {
        editorStore.editableButtonBindings[slot]?.clutchDPI
            ?? ButtonBindingSupport.defaultDPIClutchDPI(for: deviceStore.selectedDevice?.profile_id)
            ?? 400
    }

    func shouldAutoApplyCurrentButtonWorkspaceAfterEdit() -> Bool {
        deviceStore.selectedDevice != nil
    }

    func handleButtonWorkspaceDidChange(slot: Int) {
        buttonWorkspaceEditRevision &+= 1
        if let device = deviceStore.selectedDevice {
            let hydrationKey = editableButtonBindingsHydrationKey(device: device)
            buttonWorkspaceEditRevisionByHydrationKey[hydrationKey] = buttonWorkspaceEditRevision
        }
        bumpUSBButtonProfilesRevision()
        guard shouldAutoApplyCurrentButtonWorkspaceAfterEdit() else { return }
        applyController.scheduleAutoApplyButton(slot: slot)
    }

    func updateButtonBindingKind(slot: Int, kind: ButtonBindingKind) {
        guard deviceStore.visibleButtonSlots.contains(where: { $0.slot == slot }) else { return }
        var next = editorStore.editableButtonBindings[slot] ?? defaultButtonBinding(for: slot)
        next.kind = kind
        if kind != .keyboardSimple {
            next.hidKey = 4
            next.hidModifiers = 0
        }
        if kind == .dpiClutch {
            next.clutchDPI = next.clutchDPI ?? ButtonBindingSupport.defaultDPIClutchDPI(for: deviceStore.selectedDevice?.profile_id)
        }
        if !kind.supportsTurbo {
            next.turboEnabled = false
        }
        editorStore.editableButtonBindings[slot] = next
        handleButtonWorkspaceDidChange(slot: slot)
    }

    func updateButtonBindingKeyboardShortcut(slot: Int, hidKey: Int, hidModifiers: Int) {
        guard deviceStore.visibleButtonSlots.contains(where: { $0.slot == slot }) else { return }
        var next = editorStore.editableButtonBindings[slot] ?? defaultButtonBinding(for: slot)
        next.kind = .keyboardSimple
        next.hidKey = max(4, min(231, hidKey))
        next.hidModifiers = max(0, min(255, hidModifiers))
        editorStore.editableButtonBindings[slot] = next
        handleButtonWorkspaceDidChange(slot: slot)
    }

    func updateButtonBindingTurboEnabled(slot: Int, enabled: Bool) {
        guard deviceStore.visibleButtonSlots.contains(where: { $0.slot == slot }) else { return }
        var next = editorStore.editableButtonBindings[slot] ?? defaultButtonBinding(for: slot)
        guard next.kind.supportsTurbo else { return }
        next.turboEnabled = enabled
        editorStore.editableButtonBindings[slot] = next
        handleButtonWorkspaceDidChange(slot: slot)
    }

    func updateButtonBindingTurboRate(slot: Int, rate: Int) {
        guard deviceStore.visibleButtonSlots.contains(where: { $0.slot == slot }) else { return }
        var next = editorStore.editableButtonBindings[slot] ?? defaultButtonBinding(for: slot)
        guard next.kind.supportsTurbo else { return }
        next.turboRate = ButtonBindingSupport.clampTurboRate(rate)
        editorStore.editableButtonBindings[slot] = next
        handleButtonWorkspaceDidChange(slot: slot)
    }

    func updateButtonBindingClutchDPI(slot: Int, dpi: Int) {
        guard deviceStore.visibleButtonSlots.contains(where: { $0.slot == slot }) else { return }
        var next = editorStore.editableButtonBindings[slot] ?? defaultButtonBinding(for: slot)
        guard next.kind == .dpiClutch else { return }
        next.clutchDPI = DeviceProfiles.clampDPI(dpi, profileID: deviceStore.selectedDevice?.profile_id)
        editorStore.editableButtonBindings[slot] = next
        handleButtonWorkspaceDidChange(slot: slot)
    }
}
