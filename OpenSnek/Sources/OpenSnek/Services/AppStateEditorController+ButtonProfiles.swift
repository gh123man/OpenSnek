import Foundation
import OpenSnekAppSupport
import OpenSnekCore

@MainActor
extension AppStateEditorController {
    func hydrateButtonBindingsIfNeeded(device: MouseDevice) async {
        guard !isTearingDown else { return }
        guard !(device.transport == .bluetooth && supportsOnboardProfileCRUD(device: device)) else { return }
        let source = buttonProfileSource(for: device)
        if case .openSnekProfile = source {
            let bindings = currentSourceBindings(for: device)
            if !shouldPreserveLocalButtonWorkspace(device: device),
               hydratedButtonBindingsKey == nil || !bindingsEqual(editorStore.editableButtonBindings, bindings, device: device) {
                editorStore.editableButtonBindings = bindings
            }
            if buttonProfileLiveBindingsByDeviceID[device.id] == nil {
                let defaultSlot = defaultMouseButtonProfileSource(for: device)
                setLiveButtonProfileSource(
                    .mouseSlot(defaultSlot),
                    bindings: cachedButtonBindings(device: device, profile: defaultSlot),
                    for: device
                )
            }
            return
        }

        let profile = editorStore.editableUSBButtonProfile
        let hydrationKey = buttonBindingsHydrationKey(device: device, profile: profile)
        if device.transport == .usb,
           buttonBindingsCacheByHydrationKey[hydrationKey] == nil,
           !buttonBindingsReadbackAttemptedKeys.contains(hydrationKey),
           !buttonBindingsReadbackInFlightKeys.contains(hydrationKey) {
            buttonBindingsReadbackAttemptedKeys.insert(hydrationKey)
            buttonBindingsReadbackInFlightKeys.insert(hydrationKey)
            bumpUSBButtonProfilesRevision()
            await refreshUSBButtonBindingsFromDevice(device: device, hydrationKey: hydrationKey, profile: profile)
        }
        guard buttonProfileSource(for: device) == source,
              editorStore.editableUSBButtonProfile == profile else {
            return
        }
        let cached = cachedButtonBindings(device: device, profile: profile)
        if device.transport != .usb || buttonBindingsCacheByHydrationKey[hydrationKey] != nil {
            buttonBindingsCacheByHydrationKey[hydrationKey] = cached
        }
        bumpUSBButtonProfilesRevision()

        if (!shouldPreserveLocalButtonWorkspace(device: device) && hydratedButtonBindingsKey != hydrationKey) ||
            (!bindingsEqual(editorStore.editableButtonBindings, cached, device: device) && !shouldPreserveLocalButtonWorkspace(device: device)) {
            editorStore.editableButtonBindings = cached
            hydratedButtonBindingsKey = hydrationKey
        }

        if buttonProfileLiveBindingsByDeviceID[device.id] == nil,
           liveButtonProfileSource(for: device) == .mouseSlot(profile) {
            setLiveButtonProfileSource(.mouseSlot(profile), bindings: cached, for: device)
        }

        if device.transport != .usb {
            AppLog.debug(
                "AppState",
                "hydrated button bindings from persisted cache id=\(device.id) profile=\(profile) slots=\(cached.keys.sorted())"
            )
            return
        }

        guard buttonBindingsCacheByHydrationKey[hydrationKey] != nil else {
            AppLog.debug(
                "AppState",
                "usb button hydration has no device snapshot id=\(device.id) profile=\(profile)"
            )
            return
        }
    }

    func refreshUSBButtonBindingsFromDevice(device: MouseDevice, hydrationKey: String, profile: Int) async {
        defer {
            buttonBindingsReadbackInFlightKeys.remove(hydrationKey)
            bumpUSBButtonProfilesRevision()
        }
        guard !isTearingDown else { return }
        let workspaceEditRevisionAtStart = buttonWorkspaceEditRevision

        guard let fromDevice = await loadUSBButtonBindingsFromDevice(device: device, profile: profile) else {
            let cached = buttonBindingsCacheByHydrationKey[hydrationKey] ?? [:]
            AppLog.debug(
                "AppState",
                "usb button hydration read unavailable id=\(device.id) profile=\(profile) cachedSlots=\(cached.keys.sorted())"
            )
            return
        }
        guard !Task.isCancelled else { return }

        let selectedDeviceMatches = deviceStore.selectedDevice?.id == device.id
        let isCurrentEditableProfile = selectedDeviceMatches && hydratedButtonBindingsKey == hydrationKey
        let workspaceChangedDuringReadback = buttonWorkspaceEditRevision != workspaceEditRevisionAtStart
        if isCurrentEditableProfile && workspaceChangedDuringReadback {
            AppLog.debug(
                "AppState",
                "skipped stale USB button readback id=\(device.id) profile=\(profile) dueToLocalEdits=true"
            )
            return
        }

        var hydrated = buttonBindingsCacheByHydrationKey[hydrationKey]
            ?? [:]
        hydrated.merge(fromDevice) { _, readback in readback }
        buttonBindingsCacheByHydrationKey[hydrationKey] = hydrated
        savePersistedButtonBindings(device: device, bindings: hydrated, profile: profile)

        if hydratedButtonBindingsKey == hydrationKey {
            editorStore.editableButtonBindings = hydrated
        }
        if liveButtonProfileSource(for: device) == .mouseSlot(profile) {
            setLiveButtonProfileSource(.mouseSlot(profile), bindings: hydrated, for: device)
        }

        AppLog.debug(
            "AppState",
            "hydrated button bindings from USB readback id=\(device.id) profile=\(profile) slots=\(fromDevice.keys.sorted())"
        )
    }

    func primeUSBButtonProfileSummariesIfNeeded(device: MouseDevice) {
        guard device.transport == .usb, editorStore.supportsMultipleOnboardProfiles else { return }
        guard !buttonProfileSummaryHydrationInFlightDeviceIDs.contains(device.id) else { return }

        buttonProfileSummaryHydrationInFlightDeviceIDs.insert(device.id)
        Task { @MainActor [weak self] in
            await self?.primeUSBButtonProfileSummaries(device: device)
        }
    }

    func primeUSBButtonProfileSummaries(device: MouseDevice) async {
        defer {
            buttonProfileSummaryHydrationInFlightDeviceIDs.remove(device.id)
            bumpUSBButtonProfilesRevision()
        }
        guard !isTearingDown else { return }

        let count = max(1, editorStore.visibleOnboardProfileCount)
        for profile in 1...count where profile != editorStore.editableUSBButtonProfile {
            let hydrationKey = buttonBindingsHydrationKey(device: device, profile: profile)
            guard !buttonBindingsReadbackAttemptedKeys.contains(hydrationKey),
                  !buttonBindingsReadbackInFlightKeys.contains(hydrationKey) else {
                continue
            }

            buttonBindingsReadbackAttemptedKeys.insert(hydrationKey)
            buttonBindingsReadbackInFlightKeys.insert(hydrationKey)
            bumpUSBButtonProfilesRevision()
            await refreshUSBButtonBindingsFromDevice(
                device: device,
                hydrationKey: hydrationKey,
                profile: profile
            )
        }
    }

    func loadUSBButtonBindingsFromDevice(device: MouseDevice, profile: Int) async -> [Int: ButtonBindingDraft]? {
        guard !isTearingDown, !Task.isCancelled else { return nil }
        let slots = (device.button_layout?.visibleSlots ?? buttonSlots)
            .map(\.slot)
            .filter { $0 != 6 }
        var bindings: [Int: ButtonBindingDraft] = [:]
        var readAnyBlock = false
        let persistentProfile = max(1, min(editorStore.visibleOnboardProfileCount, profile))
        let shouldReadDirect = !editorStore.supportsMultipleOnboardProfiles || persistentProfile == liveUSBButtonProfile(for: device)

        for slot in slots {
            guard !Task.isCancelled else { return nil }
            do {
                let persistentBlock = try await environment.backend.debugUSBReadButtonBinding(
                    device: device,
                    slot: slot,
                    profile: persistentProfile
                )
                guard !isTearingDown, !Task.isCancelled else { return nil }
                let directBlock = shouldReadDirect
                    ? try await environment.backend.debugUSBReadButtonBinding(device: device, slot: slot, profile: 0x00)
                    : nil
                guard !isTearingDown, !Task.isCancelled else { return nil }
                let block = directBlock ?? persistentBlock
                if let block {
                    readAnyBlock = true
                    if let draft = ButtonBindingSupport.buttonBindingDraftFromUSBFunctionBlock(
                        slot: slot,
                        functionBlock: block,
                        profileID: device.profile_id
                    ) {
                        bindings[slot] = draft
                    }
                }
            } catch {
                AppLog.debug(
                    "AppState",
                    "usb button hydration read failed id=\(device.id) slot=\(slot): \(error.localizedDescription)"
                )
            }
        }

        guard readAnyBlock else { return nil }
        return bindings
    }

    func persistButtonBinding(_ binding: ButtonBindingPatch, device: MouseDevice, profile: Int) {
        guard device.transport != .usb else { return }
        preferenceStore.persistButtonBinding(binding, device: device, profile: profile)
    }

    func cachePersistedButtonBinding(_ binding: ButtonBindingPatch, device: MouseDevice, profile: Int) {
        let hydrationKey = buttonBindingsHydrationKey(device: device, profile: profile)
        let updatedDraft = ButtonBindingSupport.normalizedDefaultRepresentation(
            for: binding.slot,
            draft: ButtonBindingDraft(
                kind: binding.kind,
                hidKey: binding.kind == .keyboardSimple ? max(4, min(231, binding.hidKey ?? 4)) : 4,
                hidModifiers: binding.kind == .keyboardSimple ? max(0, min(255, binding.hidModifiers ?? 0)) : 0,
                turboEnabled: binding.kind.supportsTurbo ? binding.turboEnabled : false,
                turboRate: ButtonBindingSupport.clampTurboRate(
                    binding.turboRate ?? ButtonBindingSupport.defaultTurboRate
                ),
                clutchDPI: binding.kind == .dpiClutch
                    ? DeviceProfiles.clampDPI(
                        binding.clutchDPI ?? ButtonBindingSupport.defaultBasiliskDPIClutchDPI,
                        device: device
                    )
                    : nil
            ),
            profileID: device.profile_id
        )
        var merged = buttonBindingsCacheByHydrationKey[hydrationKey]
            ?? [:]
        merged[binding.slot] = updatedDraft
        buttonBindingsCacheByHydrationKey[hydrationKey] = merged
        if editorStore.editableUSBButtonProfile == profile,
           hydratedButtonBindingsKey == hydrationKey,
           deviceStore.selectedDevice?.id == device.id {
            editorStore.editableButtonBindings[binding.slot] = updatedDraft
        }
        if liveButtonProfileSource(for: device) == .mouseSlot(profile), binding.writeDirectLayer {
            setLiveButtonProfileSource(.mouseSlot(profile), bindings: merged, for: device)
        }
        buttonBindingsReadbackAttemptedKeys.insert(hydrationKey)
        bumpUSBButtonProfilesRevision()
    }

    func savePersistedButtonBindings(device: MouseDevice, bindings: [Int: ButtonBindingDraft], profile: Int) {
        guard device.transport != .usb else { return }
        guard !supportsOnboardProfileCRUD(device: device) else { return }
        preferenceStore.savePersistedButtonBindings(device: device, bindings: bindings, profile: profile)
    }

    func saveCachedButtonBindings(device: MouseDevice, bindings: [Int: ButtonBindingDraft], profile: Int) {
        let hydrationKey = buttonBindingsHydrationKey(device: device, profile: profile)
        buttonBindingsCacheByHydrationKey[hydrationKey] = bindings
        savePersistedButtonBindings(device: device, bindings: bindings, profile: profile)
        buttonBindingsReadbackAttemptedKeys.insert(hydrationKey)
        if editorStore.editableUSBButtonProfile == profile {
            hydratedButtonBindingsKey = hydrationKey
            editorStore.editableButtonBindings = bindings
        }
        if liveButtonProfileSource(for: device) == .mouseSlot(profile) {
            setLiveButtonProfileSource(.mouseSlot(profile), bindings: bindings, for: device)
        }
        bumpUSBButtonProfilesRevision()
    }

    func loadPersistedButtonBindings(device: MouseDevice, profile: Int) -> [Int: ButtonBindingDraft] {
        guard device.transport != .usb else { return [:] }
        return preferenceStore.loadPersistedButtonBindings(device: device, profile: profile)
    }

    func cachedButtonBindings(device: MouseDevice, profile: Int) -> [Int: ButtonBindingDraft] {
        let hydrationKey = buttonBindingsHydrationKey(device: device, profile: profile)
        return buttonBindingsCacheByHydrationKey[hydrationKey]
            ?? loadPersistedButtonBindings(device: device, profile: profile)
    }

    func defaultButtonBinding(for slot: Int, device: MouseDevice) -> ButtonBindingDraft {
        ButtonBindingSupport.defaultButtonBinding(for: slot, profileID: device.profile_id)
    }

    func profileHasCustomBindings(device: MouseDevice, profile: Int) -> Bool? {
        let hydrationKey = buttonBindingsHydrationKey(device: device, profile: profile)
        let persisted = loadPersistedButtonBindings(device: device, profile: profile)
        guard let bindings = buttonBindingsCacheByHydrationKey[hydrationKey] ?? (!persisted.isEmpty ? persisted : nil) else {
            return nil
        }

        let writableSlots = device.button_layout?.writableSlots ?? buttonSlots.map(\.slot)
        return writableSlots.contains { slot in
            (bindings[slot] ?? defaultButtonBinding(for: slot, device: device)) != defaultButtonBinding(for: slot, device: device)
        }
    }

    func savedButtonProfiles() -> [OpenSnekButtonProfile] {
        preferenceStore.loadOpenSnekButtonProfiles().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func currentButtonProfileSource() -> ButtonProfileSource? {
        guard let device = deviceStore.selectedDevice else { return nil }
        return buttonProfileSource(for: device)
    }

    func liveButtonProfileSource(for device: MouseDevice) -> ButtonProfileSource {
        buttonProfileLiveSourceByDeviceID[device.id] ?? .mouseSlot(defaultMouseButtonProfileSource(for: device))
    }

    func currentButtonProfileDisplayName() -> String {
        guard let device = deviceStore.selectedDevice else { return "Current Buttons" }
        let source = buttonProfileSource(for: device)
        let sourceName = workspaceSourceDisplayName(source)
        return buttonWorkspaceHasUnsavedSourceChanges(device: device) ? "Modified from \(sourceName)" : sourceName
    }

    func liveButtonProfileDisplayName() -> String {
        guard let device = deviceStore.selectedDevice else { return "Current Buttons" }
        let source = liveButtonProfileSource(for: device)
        let sourceName = workspaceSourceDisplayName(source)
        return bindingsEqual(liveBindings(for: device), sourceBindings(for: source, device: device), device: device) ? sourceName : "Modified from \(sourceName)"
    }

    func buttonWorkspaceHasUnsavedSourceChanges(device: MouseDevice) -> Bool {
        !bindingsEqual(editorStore.editableButtonBindings, currentSourceBindings(for: device), device: device)
    }

    func onThisMouseButtonSources() -> [ButtonProfileSource] {
        guard deviceStore.selectedDevice != nil else { return [] }
        let count = editorStore.supportsMultipleOnboardProfiles ? editorStore.visibleOnboardProfileCount : 1
        return (1...max(1, count)).map { .mouseSlot($0) }
    }

    func loadableMouseButtonSources() -> [ButtonProfileSource] {
        guard let device = deviceStore.selectedDevice else { return [] }
        return onThisMouseButtonSources().filter { source in
            guard case .mouseSlot(let slot) = source else { return false }
            if slot == 1 {
                return true
            }
            return profileHasCustomBindings(device: device, profile: slot) == true
        }
    }

    func storedMouseButtonSources() -> [ButtonProfileSource] {
        onThisMouseButtonSources().filter {
            guard case .mouseSlot(let slot) = $0 else { return false }
            return slot > 1
        }
    }

    func writableMouseButtonSources() -> [ButtonProfileSource] {
        storedMouseButtonSources()
    }

    func buttonProfileSourceMatchDescription(_ source: ButtonProfileSource) -> String? {
        guard let device = deviceStore.selectedDevice else { return nil }
        switch source {
        case .openSnekProfile:
            return nil
        case .mouseSlot(let slot):
            return savedButtonProfileMatchDescription(
                for: cachedButtonBindings(device: device, profile: slot),
                device: device
            )
        }
    }

    func refreshButtonProfilePresentation() {
        if let device = deviceStore.selectedDevice {
            primeUSBButtonProfileSummariesIfNeeded(device: device)
        }
        bumpUSBButtonProfilesRevision()
    }

}
