import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

struct RecordedOnboardUpdate {
    let deviceID: String
    let profileID: Int
    let mutation: OnboardProfileMutation
}

struct RecordedOnboardCreate {
    let deviceID: String
    let targetProfileID: Int?
    let replaceAssignedProfile: Bool
    let mutation: OnboardProfileMutation
}

struct RecordedOnboardRename {
    let deviceID: String
    let profileID: Int
    let name: String
}

actor AppStateRefactorStubBackend: DeviceBackend, ApplyOptionsSupportingBackend {
    nonisolated var usesRemoteServiceTransport: Bool { false }

    private let devices: [MouseDevice]
    private var stateByDeviceID: [String: MouseState]
    private var fastByDeviceID: [String: DpiFastSnapshot]
    private let shouldUseFastPolling: Bool
    private let holdFirstApply: Bool
    private var applyPatches: [DevicePatch] = []
    private var applyReadbackPolicies: [ApplyReadbackPolicy] = []
    private var applyInvocationCount = 0
    private var activeApplyCount = 0
    private var maxObservedConcurrentApplies = 0
    private var firstApplyStartedContinuation: CheckedContinuation<Void, Never>?
    private var firstApplyReleaseContinuation: CheckedContinuation<Void, Never>?
    private var buttonBindingBlocks: [String: [UInt8]] = [:]
    private var buttonReadCountByDeviceID: [String: Int] = [:]
    private var heldButtonReadKeys: Set<String> = []
    private var startedHeldButtonReadKeys: Set<String> = []
    private var buttonReadStartedContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var buttonReadReleaseContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var readCountByDeviceID: [String: Int] = [:]
    private var fastReadInvocationCount = 0
    private var fastReadCountByDeviceID: [String: Int] = [:]
    private var onboardInventoryByDeviceID: [String: OnboardProfileInventory] = [:]
    private var onboardSnapshotsByKey: [String: OnboardProfileSnapshot] = [:]
    private var onboardListCountByDeviceID: [String: Int] = [:]
    private var onboardReadCountByKey: [String: Int] = [:]
    private var onboardCoreReadCountByKey: [String: Int] = [:]
    private var onboardButtonReadCountByKey: [String: Int] = [:]
    private var onboardUpdates: [RecordedOnboardUpdate] = []
    private var onboardCreates: [RecordedOnboardCreate] = []
    private var onboardRenames: [RecordedOnboardRename] = []
    private var onboardDeletes: [(deviceID: String, profileID: Int)] = []
    private var onboardActivations: [(deviceID: String, profileID: Int)] = []
    private var onboardListFailureMessage: String?
    private var onboardUpdateFailureMessage: String?
    private var renameReturnsMetadataOnly = false
    private var onboardEvents: [String] = []
    private var heldOnboardProfileLists: Set<String> = []
    private var startedHeldOnboardProfileLists: Set<String> = []
    private var onboardProfileListStartedContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var onboardProfileListReleaseContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var heldOnboardProfileReads: Set<String> = []
    private var startedHeldOnboardProfileReads: Set<String> = []
    private var onboardProfileReadStartedContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var onboardProfileReadReleaseContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var heldOnboardProfileButtonReads: Set<String> = []
    private var startedHeldOnboardProfileButtonReads: Set<String> = []
    private var onboardProfileButtonReadStartedContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var onboardProfileButtonReadReleaseContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var heldOnboardUpdates: Set<String> = []
    private var startedHeldOnboardUpdates: Set<String> = []
    private var onboardUpdateStartedContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var onboardUpdateReleaseContinuations: [String: CheckedContinuation<Void, Never>] = [:]
    private var softwareLightingStatusByDeviceID: [String: SoftwareLightingEngineStatus] = [:]
    private var softwareLightingStartsByDeviceID: [String: Int] = [:]
    private var softwareLightingStopsByDeviceID: [String: Int] = [:]
    private var softwareLightingDeviceStopsByDeviceID: [String: Int] = [:]

    init(
        devices: [MouseDevice],
        stateByDeviceID: [String: MouseState],
        shouldUseFastPolling: Bool = false,
        holdFirstApply: Bool = false
    ) {
        self.devices = devices
        self.stateByDeviceID = stateByDeviceID
        self.fastByDeviceID = stateByDeviceID.reduce(into: [:]) { partialResult, entry in
            if let active = entry.value.dpi_stages.active_stage,
               let values = entry.value.dpi_stages.values {
                partialResult[entry.key] = DpiFastSnapshot(active: active, values: values)
            }
        }
        self.shouldUseFastPolling = shouldUseFastPolling
        self.holdFirstApply = holdFirstApply
    }

    func listDevices() async throws -> [MouseDevice] {
        devices
    }

    func readState(device: MouseDevice) async throws -> MouseState {
        readCountByDeviceID[device.id, default: 0] += 1
        guard let state = stateByDeviceID[device.id] else {
            throw NSError(domain: "AppStateRefactorCharacterizationTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing state for \(device.id)"
            ])
        }
        return state
    }

    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot? {
        fastReadInvocationCount += 1
        fastReadCountByDeviceID[device.id, default: 0] += 1
        return fastByDeviceID[device.id]
    }

    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool {
        shouldUseFastPolling
    }

    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .granted,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func apply(device: MouseDevice, patch: DevicePatch, options: ApplyOptions) async throws -> MouseState {
        applyInvocationCount += 1
        activeApplyCount += 1
        maxObservedConcurrentApplies = max(maxObservedConcurrentApplies, activeApplyCount)
        applyReadbackPolicies.append(options.readbackPolicy)

        defer {
            activeApplyCount -= 1
        }

        if holdFirstApply, applyInvocationCount == 1 {
            firstApplyStartedContinuation?.resume()
            firstApplyStartedContinuation = nil
            await withCheckedContinuation { continuation in
                firstApplyReleaseContinuation = continuation
            }
        }

        applyPatches.append(patch)

        guard let current = stateByDeviceID[device.id] else {
            throw NSError(domain: "AppStateRefactorCharacterizationTests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Missing apply state for \(device.id)"
            ])
        }

        let next = stateApplying(patch, to: current)
        stateByDeviceID[device.id] = next
        if let active = next.dpi_stages.active_stage,
           let values = next.dpi_stages.values {
            fastByDeviceID[device.id] = DpiFastSnapshot(active: active, values: values)
        }
        return next
    }

    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? {
        nil
    }

    func debugUSBReadButtonBinding(device: MouseDevice, slot: Int, profile: Int) async throws -> [UInt8]? {
        buttonReadCountByDeviceID[device.id, default: 0] += 1
        let key = buttonKey(deviceID: device.id, slot: slot, profile: profile)
        if heldButtonReadKeys.contains(key) {
            startedHeldButtonReadKeys.insert(key)
            buttonReadStartedContinuations[key]?.resume()
            buttonReadStartedContinuations[key] = nil
            await withCheckedContinuation { continuation in
                buttonReadReleaseContinuations[key] = continuation
            }
            heldButtonReadKeys.remove(key)
            buttonReadReleaseContinuations[key] = nil
        }
        return buttonBindingBlocks[key]
    }

    func startSoftwareLighting(
        device: MouseDevice,
        request: SoftwareLightingEffectRequest
    ) async throws -> SoftwareLightingEngineStatus {
        softwareLightingStartsByDeviceID[device.id, default: 0] += 1
        let status = SoftwareLightingEngineStatus(deviceID: device.id, state: .running, request: request)
        softwareLightingStatusByDeviceID[device.id] = status
        return status
    }

    func stopSoftwareLighting(deviceID: String) async -> SoftwareLightingEngineStatus? {
        softwareLightingStopsByDeviceID[deviceID, default: 0] += 1
        let status = SoftwareLightingEngineStatus(
            deviceID: deviceID,
            state: .stopped,
            request: softwareLightingStatusByDeviceID[deviceID]?.request
        )
        softwareLightingStatusByDeviceID[deviceID] = status
        return status
    }

    func stopSoftwareLighting(device: MouseDevice) async -> SoftwareLightingEngineStatus? {
        softwareLightingDeviceStopsByDeviceID[device.id, default: 0] += 1
        return await stopSoftwareLighting(deviceID: device.id)
    }

    func softwareLightingStatus(deviceID: String) async -> SoftwareLightingEngineStatus? {
        softwareLightingStatusByDeviceID[deviceID]
    }

    func listOnboardProfiles(device: MouseDevice) async throws -> OnboardProfileInventory {
        onboardListCountByDeviceID[device.id, default: 0] += 1
        if let onboardListFailureMessage {
            throw NSError(domain: "AppStateRefactorCharacterizationTests", code: 91, userInfo: [
                NSLocalizedDescriptionKey: onboardListFailureMessage
            ])
        }
        if heldOnboardProfileLists.contains(device.id) {
            startedHeldOnboardProfileLists.insert(device.id)
            onboardProfileListStartedContinuations[device.id]?.resume()
            onboardProfileListStartedContinuations[device.id] = nil
            await withCheckedContinuation { continuation in
                onboardProfileListReleaseContinuations[device.id] = continuation
            }
            heldOnboardProfileLists.remove(device.id)
            onboardProfileListReleaseContinuations[device.id] = nil
        }
        return currentOnboardInventory(for: device)
    }

    private func currentOnboardInventory(for device: MouseDevice) -> OnboardProfileInventory {
        if let inventory = onboardInventoryByDeviceID[device.id] {
            return inventory
        }
        let active = stateByDeviceID[device.id]?.active_onboard_profile ?? 1
        return OnboardProfileInventory(
            activeProfileID: active,
            maxProfileID: max(1, device.onboard_profile_count),
            assignedProfileIDs: [1],
            profiles: [
                makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: active == 1)
            ]
        )
    }

    func readOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot {
        let key = onboardSnapshotKey(deviceID: device.id, profileID: profileID)
        onboardReadCountByKey[key, default: 0] += 1
        onboardEvents.append("read:\(profileID)")
        if heldOnboardProfileReads.contains(key) {
            startedHeldOnboardProfileReads.insert(key)
            onboardProfileReadStartedContinuations[key]?.resume()
            onboardProfileReadStartedContinuations[key] = nil
            await withCheckedContinuation { continuation in
                onboardProfileReadReleaseContinuations[key] = continuation
            }
            heldOnboardProfileReads.remove(key)
            onboardProfileReadReleaseContinuations[key] = nil
        }
        if let snapshot = onboardSnapshotsByKey[key] {
            return snapshot
        }
        return makeRefactorOnboardProfileSnapshot(profileID: profileID, name: "Profile \(profileID)")
    }

    func readOnboardProfileCore(device: MouseDevice, profileID: Int) async throws -> OnboardProfileSnapshot {
        let key = onboardSnapshotKey(deviceID: device.id, profileID: profileID)
        onboardCoreReadCountByKey[key, default: 0] += 1
        onboardEvents.append("read-core:\(profileID)")
        if heldOnboardProfileReads.contains(key) {
            startedHeldOnboardProfileReads.insert(key)
            onboardProfileReadStartedContinuations[key]?.resume()
            onboardProfileReadStartedContinuations[key] = nil
            await withCheckedContinuation { continuation in
                onboardProfileReadReleaseContinuations[key] = continuation
            }
            heldOnboardProfileReads.remove(key)
            onboardProfileReadReleaseContinuations[key] = nil
        }
        let snapshot = onboardSnapshotsByKey[key] ?? makeRefactorOnboardProfileSnapshot(
            profileID: profileID,
            name: "Profile \(profileID)"
        )
        return OnboardProfileSnapshot(
            profileID: snapshot.profileID,
            metadata: snapshot.metadata,
            dpi: snapshot.dpi,
            buttonBindings: [:],
            brightnessByLEDID: snapshot.brightnessByLEDID,
            staticColorByLEDID: snapshot.staticColorByLEDID,
            scrollMode: snapshot.scrollMode,
            scrollAcceleration: snapshot.scrollAcceleration,
            scrollSmartReel: snapshot.scrollSmartReel
        )
    }

    func readOnboardProfileButtonBindings(device: MouseDevice, profileID: Int) async throws -> [Int: ButtonBindingDraft] {
        let key = onboardSnapshotKey(deviceID: device.id, profileID: profileID)
        onboardButtonReadCountByKey[key, default: 0] += 1
        onboardEvents.append("read-buttons:\(profileID)")
        if heldOnboardProfileButtonReads.contains(key) {
            startedHeldOnboardProfileButtonReads.insert(key)
            onboardProfileButtonReadStartedContinuations[key]?.resume()
            onboardProfileButtonReadStartedContinuations[key] = nil
            await withCheckedContinuation { continuation in
                onboardProfileButtonReadReleaseContinuations[key] = continuation
            }
            heldOnboardProfileButtonReads.remove(key)
            onboardProfileButtonReadReleaseContinuations[key] = nil
        }
        return onboardSnapshotsByKey[key]?.buttonBindings ?? [:]
    }

    func createOnboardProfile(
        device: MouseDevice,
        mutation: OnboardProfileMutation,
        targetProfileID: Int?,
        replaceAssignedProfile: Bool
    ) async throws -> OnboardProfileSnapshot {
        let inventory = currentOnboardInventory(for: device)
        let target = targetProfileID ?? inventory.assignableProfileIDs.first ?? 2
        guard target >= 2, target <= inventory.maxProfileID else {
            throw NSError(domain: "AppStateRefactorCharacterizationTests", code: 92, userInfo: [
                NSLocalizedDescriptionKey: "Invalid profile target \(target)"
            ])
        }
        guard replaceAssignedProfile || !inventory.assignedProfileIDs.contains(target) else {
            throw NSError(domain: "AppStateRefactorCharacterizationTests", code: 93, userInfo: [
                NSLocalizedDescriptionKey: "Profile target \(target) is already assigned"
            ])
        }
        onboardCreates.append(RecordedOnboardCreate(
            deviceID: device.id,
            targetProfileID: targetProfileID,
            replaceAssignedProfile: replaceAssignedProfile,
            mutation: mutation
        ))
        let snapshot = OnboardProfileSnapshot(
            profileID: target,
            metadata: mutation.metadata ?? OnboardProfileMetadata(name: "Profile \(target)"),
            dpi: mutation.dpi,
            buttonBindings: mutation.buttonBindings ?? [:],
            brightnessByLEDID: mutation.brightnessByLEDID ?? [:],
            staticColorByLEDID: mutation.staticColorByLEDID ?? [:],
            scrollMode: mutation.scrollMode,
            scrollAcceleration: mutation.scrollAcceleration,
            scrollSmartReel: mutation.scrollSmartReel
        )
        onboardSnapshotsByKey[onboardSnapshotKey(deviceID: device.id, profileID: target)] = snapshot
        var summaries = inventory.profiles.filter { $0.profileID != target }
        summaries.append(OnboardProfileSummary(
            profileID: target,
            metadata: snapshot.metadata,
            isAssigned: true,
            isActive: target == inventory.activeProfileID,
            isBaseProfile: false
        ))
        let assigned = Set(inventory.assignedProfileIDs + [target])
        onboardInventoryByDeviceID[device.id] = OnboardProfileInventory(
            activeProfileID: inventory.activeProfileID,
            maxProfileID: inventory.maxProfileID,
            assignedProfileIDs: Array(assigned).sorted(),
            profiles: summaries
        )
        return snapshot
    }

    func renameOnboardProfile(device: MouseDevice, profileID: Int, name: String) async throws -> OnboardProfileSnapshot {
        onboardRenames.append(RecordedOnboardRename(
            deviceID: device.id,
            profileID: profileID,
            name: name
        ))
        let current = try await readOnboardProfile(device: device, profileID: profileID)
        let updated = OnboardProfileSnapshot(
            profileID: profileID,
            metadata: current.metadata.renamed(name),
            dpi: current.dpi,
            buttonBindings: current.buttonBindings,
            brightnessByLEDID: current.brightnessByLEDID,
            staticColorByLEDID: current.staticColorByLEDID,
            scrollMode: current.scrollMode,
            scrollAcceleration: current.scrollAcceleration,
            scrollSmartReel: current.scrollSmartReel
        )
        onboardSnapshotsByKey[onboardSnapshotKey(deviceID: device.id, profileID: profileID)] = updated
        let inventory = currentOnboardInventory(for: device)
        let summaries = inventory.profiles.filter { $0.profileID != profileID } + [
            OnboardProfileSummary(
                profileID: profileID,
                metadata: updated.metadata,
                isAssigned: true,
                isActive: profileID == inventory.activeProfileID,
                isBaseProfile: profileID == 1
            )
        ]
        onboardInventoryByDeviceID[device.id] = OnboardProfileInventory(
            activeProfileID: inventory.activeProfileID,
            maxProfileID: inventory.maxProfileID,
            assignedProfileIDs: inventory.assignedProfileIDs,
            profiles: summaries
        )
        if renameReturnsMetadataOnly {
            return OnboardProfileSnapshot(profileID: profileID, metadata: updated.metadata)
        }
        return updated
    }

    func updateOnboardProfile(
        device: MouseDevice,
        profileID: Int,
        mutation: OnboardProfileMutation
    ) async throws -> OnboardProfileSnapshot {
        onboardUpdates.append(RecordedOnboardUpdate(
            deviceID: device.id,
            profileID: profileID,
            mutation: mutation
        ))
        let key = onboardSnapshotKey(deviceID: device.id, profileID: profileID)
        if heldOnboardUpdates.contains(key) {
            startedHeldOnboardUpdates.insert(key)
            onboardUpdateStartedContinuations[key]?.resume()
            onboardUpdateStartedContinuations[key] = nil
            await withCheckedContinuation { continuation in
                onboardUpdateReleaseContinuations[key] = continuation
            }
            heldOnboardUpdates.remove(key)
            onboardUpdateReleaseContinuations[key] = nil
        }
        if let onboardUpdateFailureMessage {
            throw NSError(domain: "AppStateRefactorCharacterizationTests", code: 96, userInfo: [
                NSLocalizedDescriptionKey: onboardUpdateFailureMessage
            ])
        }
        let current = try await readOnboardProfile(device: device, profileID: profileID)
        let updated = OnboardProfileSnapshot(
            profileID: profileID,
            metadata: mutation.metadata ?? current.metadata,
            dpi: mutation.dpi ?? current.dpi,
            buttonBindings: mutation.buttonBindings ?? current.buttonBindings,
            brightnessByLEDID: mutation.brightnessByLEDID ?? current.brightnessByLEDID,
            staticColorByLEDID: mutation.staticColorByLEDID ?? current.staticColorByLEDID,
            scrollMode: mutation.scrollMode ?? current.scrollMode,
            scrollAcceleration: mutation.scrollAcceleration ?? current.scrollAcceleration,
            scrollSmartReel: mutation.scrollSmartReel ?? current.scrollSmartReel
        )
        onboardSnapshotsByKey[onboardSnapshotKey(deviceID: device.id, profileID: profileID)] = updated
        return updated
    }

    func deleteOnboardProfile(device: MouseDevice, profileID: Int) async throws -> OnboardProfileInventory {
        onboardDeletes.append((device.id, profileID))
        let inventory = currentOnboardInventory(for: device)
        let assigned = inventory.assignedProfileIDs.filter { $0 != profileID }
        let summaries = inventory.profiles.map { summary in
            if summary.profileID == profileID {
                return OnboardProfileSummary(
                    profileID: profileID,
                    metadata: nil,
                    isAssigned: false,
                    isActive: false,
                    isBaseProfile: false
                )
            }
            return OnboardProfileSummary(
                profileID: summary.profileID,
                metadata: summary.metadata,
                isAssigned: summary.isAssigned,
                isActive: summary.isActive && summary.profileID != profileID,
                isBaseProfile: summary.isBaseProfile
            )
        }
        let next = OnboardProfileInventory(
            activeProfileID: inventory.activeProfileID,
            maxProfileID: inventory.maxProfileID,
            assignedProfileIDs: assigned,
            profiles: summaries
        )
        onboardInventoryByDeviceID[device.id] = next
        return next
    }

    func activateOnboardProfile(device: MouseDevice, profileID: Int) async throws -> MouseState {
        let inventory = currentOnboardInventory(for: device)
        guard inventory.assignedProfileIDs.contains(profileID) else {
            throw NSError(domain: "AppStateRefactorCharacterizationTests", code: 94, userInfo: [
                NSLocalizedDescriptionKey: "Profile \(profileID) is not assigned"
            ])
        }
        onboardActivations.append((device.id, profileID))
        onboardEvents.append("activate:\(profileID)")
        let summaries = inventory.profiles.map { summary in
            OnboardProfileSummary(
                profileID: summary.profileID,
                metadata: summary.metadata,
                isAssigned: summary.isAssigned,
                isActive: summary.profileID == profileID,
                isBaseProfile: summary.isBaseProfile
            )
        }
        onboardInventoryByDeviceID[device.id] = OnboardProfileInventory(
            activeProfileID: profileID,
            maxProfileID: inventory.maxProfileID,
            assignedProfileIDs: inventory.assignedProfileIDs,
            profiles: summaries
        )
        guard let current = stateByDeviceID[device.id] else {
            throw NSError(domain: "AppStateRefactorCharacterizationTests", code: 95, userInfo: [
                NSLocalizedDescriptionKey: "Missing state for \(device.id)"
            ])
        }
        let updated = stateWithActiveOnboardProfile(profileID, from: current)
        stateByDeviceID[device.id] = updated
        return updated
    }

    func refreshActiveOnboardProfile(device: MouseDevice) async throws -> MouseState {
        try await readState(device: device)
    }

    func waitForFirstApplyToStart() async {
        if applyInvocationCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            firstApplyStartedContinuation = continuation
        }
    }

    func releaseFirstApply() {
        firstApplyReleaseContinuation?.resume()
        firstApplyReleaseContinuation = nil
    }

    func recordedPatches() -> [DevicePatch] {
        applyPatches
    }

    func recordedApplyReadbackPolicies() -> [ApplyReadbackPolicy] {
        applyReadbackPolicies
    }

    func applyCount() -> Int {
        applyInvocationCount
    }

    func maxConcurrentApplies() -> Int {
        maxObservedConcurrentApplies
    }

    func readCount(for deviceID: String) -> Int {
        readCountByDeviceID[deviceID, default: 0]
    }

    func fastReadCount() -> Int {
        fastReadInvocationCount
    }

    func fastReadCount(for deviceID: String) -> Int {
        fastReadCountByDeviceID[deviceID, default: 0]
    }

    func setButtonBindingBlock(_ block: [UInt8], forDeviceID deviceID: String, slot: Int, profile: Int) {
        buttonBindingBlocks[buttonKey(deviceID: deviceID, slot: slot, profile: profile)] = block
    }

    func buttonReadCount(for deviceID: String) -> Int {
        buttonReadCountByDeviceID[deviceID, default: 0]
    }

    func holdButtonBindingRead(deviceID: String, slot: Int, profile: Int) {
        heldButtonReadKeys.insert(buttonKey(deviceID: deviceID, slot: slot, profile: profile))
    }

    func releaseButtonBindingRead(deviceID: String, slot: Int, profile: Int) {
        let key = buttonKey(deviceID: deviceID, slot: slot, profile: profile)
        heldButtonReadKeys.remove(key)
        buttonReadReleaseContinuations[key]?.resume()
        buttonReadReleaseContinuations[key] = nil
    }

    func setOnboardInventory(_ inventory: OnboardProfileInventory, forDeviceID deviceID: String) {
        onboardInventoryByDeviceID[deviceID] = inventory
    }

    func setOnboardSnapshot(_ snapshot: OnboardProfileSnapshot, forDeviceID deviceID: String) {
        onboardSnapshotsByKey[onboardSnapshotKey(deviceID: deviceID, profileID: snapshot.profileID)] = snapshot
    }

    func setState(_ state: MouseState, forDeviceID deviceID: String) {
        stateByDeviceID[deviceID] = state
        if let active = state.dpi_stages.active_stage,
           let values = state.dpi_stages.values {
            fastByDeviceID[deviceID] = DpiFastSnapshot(active: active, values: values)
        }
    }

    func setSoftwareLightingStatus(_ status: SoftwareLightingEngineStatus) {
        softwareLightingStatusByDeviceID[status.deviceID] = status
    }

    func softwareLightingStartCount(for deviceID: String) -> Int {
        softwareLightingStartsByDeviceID[deviceID, default: 0]
    }

    func softwareLightingStopCount(for deviceID: String) -> Int {
        softwareLightingStopsByDeviceID[deviceID, default: 0]
    }

    func softwareLightingDeviceStopCount(for deviceID: String) -> Int {
        softwareLightingDeviceStopsByDeviceID[deviceID, default: 0]
    }

    func setRenameReturnsMetadataOnly(_ value: Bool) {
        renameReturnsMetadataOnly = value
    }

    func onboardReadCount(deviceID: String, profileID: Int) -> Int {
        onboardReadCountByKey[onboardSnapshotKey(deviceID: deviceID, profileID: profileID), default: 0]
    }

    func onboardCoreReadCount(deviceID: String, profileID: Int) -> Int {
        onboardCoreReadCountByKey[onboardSnapshotKey(deviceID: deviceID, profileID: profileID), default: 0]
    }

    func onboardButtonReadCount(deviceID: String, profileID: Int) -> Int {
        onboardButtonReadCountByKey[onboardSnapshotKey(deviceID: deviceID, profileID: profileID), default: 0]
    }

    func onboardListCount(deviceID: String) -> Int {
        onboardListCountByDeviceID[deviceID, default: 0]
    }

    func setOnboardListFailure(_ message: String?) {
        onboardListFailureMessage = message
    }

    func holdOnboardProfileList(deviceID: String) {
        heldOnboardProfileLists.insert(deviceID)
    }

    func waitForOnboardProfileListToStart(deviceID: String) async {
        if startedHeldOnboardProfileLists.contains(deviceID) {
            return
        }
        await withCheckedContinuation { continuation in
            onboardProfileListStartedContinuations[deviceID] = continuation
        }
    }

    func releaseOnboardProfileList(deviceID: String) {
        heldOnboardProfileLists.remove(deviceID)
        onboardProfileListReleaseContinuations[deviceID]?.resume()
        onboardProfileListReleaseContinuations[deviceID] = nil
    }

    func holdOnboardProfileRead(deviceID: String, profileID: Int) {
        heldOnboardProfileReads.insert(onboardSnapshotKey(deviceID: deviceID, profileID: profileID))
    }

    func waitForOnboardProfileReadToStart(deviceID: String, profileID: Int) async {
        let key = onboardSnapshotKey(deviceID: deviceID, profileID: profileID)
        if startedHeldOnboardProfileReads.contains(key) {
            return
        }
        await withCheckedContinuation { continuation in
            onboardProfileReadStartedContinuations[key] = continuation
        }
    }

    func releaseOnboardProfileRead(deviceID: String, profileID: Int) {
        let key = onboardSnapshotKey(deviceID: deviceID, profileID: profileID)
        heldOnboardProfileReads.remove(key)
        onboardProfileReadReleaseContinuations[key]?.resume()
        onboardProfileReadReleaseContinuations[key] = nil
    }

    func holdOnboardProfileButtonRead(deviceID: String, profileID: Int) {
        heldOnboardProfileButtonReads.insert(onboardSnapshotKey(deviceID: deviceID, profileID: profileID))
    }

    func waitForOnboardProfileButtonReadToStart(deviceID: String, profileID: Int) async {
        let key = onboardSnapshotKey(deviceID: deviceID, profileID: profileID)
        if startedHeldOnboardProfileButtonReads.contains(key) {
            return
        }
        await withCheckedContinuation { continuation in
            onboardProfileButtonReadStartedContinuations[key] = continuation
        }
    }

    func releaseOnboardProfileButtonRead(deviceID: String, profileID: Int) {
        let key = onboardSnapshotKey(deviceID: deviceID, profileID: profileID)
        heldOnboardProfileButtonReads.remove(key)
        onboardProfileButtonReadReleaseContinuations[key]?.resume()
        onboardProfileButtonReadReleaseContinuations[key] = nil
    }

    func holdOnboardUpdate(deviceID: String, profileID: Int) {
        heldOnboardUpdates.insert(onboardSnapshotKey(deviceID: deviceID, profileID: profileID))
    }

    func waitForOnboardUpdateToStart(deviceID: String, profileID: Int) async {
        let key = onboardSnapshotKey(deviceID: deviceID, profileID: profileID)
        if startedHeldOnboardUpdates.contains(key) {
            return
        }
        await withCheckedContinuation { continuation in
            onboardUpdateStartedContinuations[key] = continuation
        }
    }

    func releaseOnboardUpdate(deviceID: String, profileID: Int) {
        let key = onboardSnapshotKey(deviceID: deviceID, profileID: profileID)
        heldOnboardUpdates.remove(key)
        onboardUpdateReleaseContinuations[key]?.resume()
        onboardUpdateReleaseContinuations[key] = nil
    }

    func recordedOnboardUpdates() -> [RecordedOnboardUpdate] {
        onboardUpdates
    }

    func setOnboardUpdateFailure(_ message: String?) {
        onboardUpdateFailureMessage = message
    }

    func recordedOnboardCreates() -> [RecordedOnboardCreate] {
        onboardCreates
    }

    func recordedOnboardRenames() -> [RecordedOnboardRename] {
        onboardRenames
    }

    func recordedOnboardDeletes() -> [(deviceID: String, profileID: Int)] {
        onboardDeletes
    }

    func recordedOnboardActivations() -> [(deviceID: String, profileID: Int)] {
        onboardActivations
    }

    func recordedOnboardEvents() -> [String] {
        onboardEvents
    }

    private func buttonKey(deviceID: String, slot: Int, profile: Int) -> String {
        "\(deviceID)#\(slot)#\(profile)"
    }

    private func onboardSnapshotKey(deviceID: String, profileID: Int) -> String {
        "\(deviceID)#\(profileID)"
    }

    private func stateWithActiveOnboardProfile(_ profileID: Int, from current: MouseState) -> MouseState {
        MouseState(
            device: current.device,
            connection: current.connection,
            battery_percent: current.battery_percent,
            charging: current.charging,
            dpi: current.dpi,
            dpi_stages: current.dpi_stages,
            poll_rate: current.poll_rate,
            sleep_timeout: current.sleep_timeout,
            device_mode: current.device_mode,
            low_battery_threshold_raw: current.low_battery_threshold_raw,
            scroll_mode: current.scroll_mode,
            scroll_acceleration: current.scroll_acceleration,
            scroll_smart_reel: current.scroll_smart_reel,
            active_onboard_profile: profileID,
            onboard_profile_count: current.onboard_profile_count,
            led_value: current.led_value,
            capabilities: current.capabilities
        )
    }

    private func stateApplying(_ patch: DevicePatch, to current: MouseState) -> MouseState {
        let nextStages: [Int]? = patch.dpiStages ?? current.dpi_stages.values
        let nextActive = patch.activeStage ?? current.dpi_stages.active_stage
        let resolvedStages = DpiStages(active_stage: nextActive, values: nextStages)
        let nextDpi: DpiPair? = {
            guard let values = nextStages, !values.isEmpty else {
                return current.dpi
            }
            let activeIndex = max(0, min(values.count - 1, nextActive ?? 0))
            return DpiPair(x: values[activeIndex], y: values[activeIndex])
        }()

        return MouseState(
            device: current.device,
            connection: current.connection,
            battery_percent: current.battery_percent,
            charging: current.charging,
            dpi: nextDpi,
            dpi_stages: resolvedStages,
            poll_rate: patch.pollRate ?? current.poll_rate,
            sleep_timeout: patch.sleepTimeout ?? current.sleep_timeout,
            device_mode: patch.deviceMode ?? current.device_mode,
            low_battery_threshold_raw: patch.lowBatteryThresholdRaw ?? current.low_battery_threshold_raw,
            scroll_mode: patch.scrollMode ?? current.scroll_mode,
            scroll_acceleration: patch.scrollAcceleration ?? current.scroll_acceleration,
            scroll_smart_reel: patch.scrollSmartReel ?? current.scroll_smart_reel,
            active_onboard_profile: current.active_onboard_profile,
            onboard_profile_count: current.onboard_profile_count,
            led_value: patch.ledBrightness ?? current.led_value,
            capabilities: current.capabilities
        )
    }
}

func makeRefactorTestDevice(
    id: String,
    transport: DeviceTransportKind,
    serial: String,
    onboardProfileCount: Int,
    profileID: DeviceProfileID? = nil
) -> MouseDevice {
    let resolvedProfileID = profileID ?? (transport == .bluetooth ? .basiliskV3XHyperspeed : .basiliskV3Pro)
    let productID: Int
    switch (transport, resolvedProfileID) {
    case (.usb, .basiliskV3):
        productID = 0x0099
    case (.usb, .basiliskV335K):
        productID = 0x00CB
    case (.bluetooth, .basiliskV3Pro):
        productID = 0x00AC
    case (.bluetooth, _):
        productID = 0x00BA
    default:
        productID = 0x00AB
    }
    return MouseDevice(
        id: id,
        vendor_id: transport == .bluetooth ? 0x068E : 0x1532,
        product_id: productID,
        product_name: transport == .bluetooth ? "Refactor BT Mouse" : "Refactor USB Mouse",
        transport: transport,
        path_b64: "",
        serial: serial,
        firmware: "1.0.0",
        location_id: 1,
        profile_id: resolvedProfileID,
        supports_advanced_lighting_effects: true,
        onboard_profile_count: onboardProfileCount
    )
}

func makeRefactorUSBLightingRestoreDevice(
    id: String,
    serial: String
) -> MouseDevice {
    MouseDevice(
        id: id,
        vendor_id: 0x1532,
        product_id: 0x00B9,
        product_name: "Refactor USB Lighting Restore Mouse",
        transport: .usb,
        path_b64: "",
        serial: serial,
        firmware: "1.0.0",
        location_id: 1,
        profile_id: .basiliskV3XHyperspeed,
        supports_advanced_lighting_effects: true,
        onboard_profile_count: 1
    )
}

func makeRefactorMultiZoneUSBLightingDevice(
    id: String,
    serial: String
) -> MouseDevice {
    MouseDevice(
        id: id,
        vendor_id: 0x1532,
        product_id: 0x00AB,
        product_name: "Refactor Multi-Zone USB Lighting Mouse",
        transport: .usb,
        path_b64: "",
        serial: serial,
        firmware: "1.0.0",
        location_id: 1,
        profile_id: .basiliskV3Pro,
        supports_advanced_lighting_effects: true,
        onboard_profile_count: 1
    )
}

func makeRefactorOnboardProfileSummary(
    profileID: Int,
    name: String,
    isActive: Bool
) -> OnboardProfileSummary {
    OnboardProfileSummary(
        profileID: profileID,
        metadata: OnboardProfileMetadata(name: name),
        isAssigned: true,
        isActive: isActive,
        isBaseProfile: profileID == 1
    )
}

func makeRefactorOnboardProfileSnapshot(
    profileID: Int,
    name: String,
    dpiValues: [Int] = [800, 1600, 3200],
    activeStage: Int = 0,
    buttonBindings: [Int: ButtonBindingDraft] = [
        4: ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E)
    ],
    brightnessByLEDID: [Int: Int] = [1: 64, 4: 64, 10: 64],
    staticColorByLEDID: [Int: RGBPatch] = [:],
    scrollMode: Int? = nil,
    scrollAcceleration: Bool? = nil,
    scrollSmartReel: Bool? = nil
) -> OnboardProfileSnapshot {
    let pairs = dpiValues.map { DpiPair(x: $0, y: $0) }
    return OnboardProfileSnapshot(
        profileID: profileID,
        metadata: OnboardProfileMetadata(name: name),
        dpi: OnboardDPIProfileSnapshot(
            scalar: pairs.indices.contains(activeStage) ? pairs[activeStage] : pairs.first,
            activeStage: max(0, min(max(0, pairs.count - 1), activeStage)),
            pairs: pairs
        ),
        buttonBindings: buttonBindings,
        brightnessByLEDID: brightnessByLEDID,
        staticColorByLEDID: staticColorByLEDID,
        scrollMode: scrollMode,
        scrollAcceleration: scrollAcceleration,
        scrollSmartReel: scrollSmartReel
    )
}

struct RefactorTestStateTelemetry {
    let connection: String
    let batteryPercent: Int
    let dpiValues: [Int]
    let activeStage: Int
    let dpiValue: Int?

    init(
        connection: String,
        batteryPercent: Int,
        dpiValues: [Int],
        activeStage: Int,
        dpiValue: Int? = nil
    ) {
        self.connection = connection
        self.batteryPercent = batteryPercent
        self.dpiValues = dpiValues
        self.activeStage = activeStage
        self.dpiValue = dpiValue
    }
}

struct RefactorTestStateOptions {
    let activeOnboardProfile: Int?
    let onboardProfileCount: Int?
    let scrollMode: Int?
    let scrollAcceleration: Bool?
    let scrollSmartReel: Bool?

    init(
        activeOnboardProfile: Int? = nil,
        onboardProfileCount: Int? = nil,
        scrollMode: Int? = nil,
        scrollAcceleration: Bool? = nil,
        scrollSmartReel: Bool? = nil
    ) {
        self.activeOnboardProfile = activeOnboardProfile
        self.onboardProfileCount = onboardProfileCount
        self.scrollMode = scrollMode
        self.scrollAcceleration = scrollAcceleration
        self.scrollSmartReel = scrollSmartReel
    }
}

func makeRefactorTestState(
    device: MouseDevice,
    telemetry: RefactorTestStateTelemetry,
    options: RefactorTestStateOptions = RefactorTestStateOptions()
) -> MouseState {
    let derivedDpiValue = telemetry.dpiValues.indices.contains(telemetry.activeStage)
        ? telemetry.dpiValues[telemetry.activeStage]
        : (telemetry.dpiValues.first ?? 0)
    let dpiValue = telemetry.dpiValue ?? derivedDpiValue
    return MouseState(
        device: DeviceSummary(
            id: device.id,
            product_name: device.product_name,
            serial: device.serial,
            transport: device.transport,
            firmware: device.firmware
        ),
        connection: telemetry.connection,
        battery_percent: telemetry.batteryPercent,
        charging: false,
        dpi: DpiPair(x: dpiValue, y: dpiValue),
        dpi_stages: DpiStages(active_stage: telemetry.activeStage, values: telemetry.dpiValues),
        poll_rate: 1000,
        sleep_timeout: 300,
        device_mode: DeviceMode(mode: 0x00, param: 0x00),
        scroll_mode: options.scrollMode,
        scroll_acceleration: options.scrollAcceleration,
        scroll_smart_reel: options.scrollSmartReel,
        active_onboard_profile: options.activeOnboardProfile,
        onboard_profile_count: options.onboardProfileCount,
        led_value: 64,
        capabilities: Capabilities(
            dpi_stages: true,
            poll_rate: true,
            power_management: true,
            button_remap: true,
            lighting: true
        )
    )
}

func makeRefactorSettingsSnapshot(
    color: OpenSnekCore.RGBColor,
    zoneID: String = "all",
    lightingEffect: LightingEffectPatch? = nil,
    buttonBindings: [Int: ButtonBindingDraft] = [:]
) -> PersistedDeviceSettingsSnapshot {
    PersistedDeviceSettingsSnapshot(
        stageCount: 3,
        stageValues: [900, 1800, 3600],
        stagePairs: [
            DpiPair(x: 900, y: 900),
            DpiPair(x: 1800, y: 1800),
            DpiPair(x: 3600, y: 3600)
        ],
        activeStage: 3,
        pollRate: 500,
        sleepTimeout: 420,
        lowBatteryThresholdRaw: 0x20,
        scrollMode: 1,
        scrollAcceleration: true,
        scrollSmartReel: false,
        ledBrightness: 77,
        primaryLightingColor: color,
        lightingEffect: lightingEffect,
        usbLightingZoneID: zoneID,
        buttonBindings: buttonBindings
    )
}

func clearRefactorPreferences(for device: MouseDevice) {
    let defaults = UserDefaults.standard
    let key = DevicePersistenceKeys.key(for: device)
    let legacyKey = DevicePersistenceKeys.legacyKey(for: device)
    let prefixes = [
        "lightingColor.\(key)",
        "lightingColor.\(legacyKey)",
        "lightingZone.\(key)",
        "lightingZone.\(legacyKey)",
        "lightingEffect.\(key)",
        "lightingEffect.\(legacyKey)",
        "softwareLightingApplyOnConnect.\(key)",
        "softwareLightingRequest.\(key)",
        "connectBehavior.\(key)",
        "connectBehavior.\(legacyKey)",
        "selectedLocalProfile.\(key)",
        "selectedLocalProfile.\(legacyKey)",
        "settingsSnapshot.\(key)",
        "settingsSnapshot.\(legacyKey)",
        "buttonBindings.\(key)",
        "buttonBindings.\(legacyKey)",
        "buttonBindings.\(key).profile1",
        "buttonBindings.\(key).profile2",
        "buttonBindings.\(key).profile3",
        "buttonBindings.\(key).profile4",
        "buttonBindings.\(key).profile5",
        "buttonBindings.\(legacyKey).profile1",
        "buttonBindings.\(legacyKey).profile2",
        "buttonBindings.\(legacyKey).profile3",
        "buttonBindings.\(legacyKey).profile4",
        "buttonBindings.\(legacyKey).profile5"
    ]
    for storedKey in defaults.dictionaryRepresentation().keys
    where prefixes.contains(where: { storedKey.hasPrefix($0) }) {
        defaults.removeObject(forKey: storedKey)
    }
    clearSavedButtonProfiles()
}

func clearSavedButtonProfiles() {
    UserDefaults.standard.removeObject(forKey: "openSnekButtonProfiles")
    UserDefaults.standard.removeObject(forKey: "openSnekLocalProfiles")
    UserDefaults.standard.removeObject(forKey: "openSnekLocalProfilesMigratedFromButtonProfiles")
}

func waitForRefactorCondition(
    timeout: TimeInterval = 1.0,
    condition: @escaping @Sendable () async -> Bool
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if await condition() {
                    return
                }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            throw NSError(domain: "AppStateRefactorCharacterizationTests", code: 90, userInfo: [
                NSLocalizedDescriptionKey: "Timed out waiting for characterization condition"
            ])
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw NSError(domain: "AppStateRefactorCharacterizationTests", code: 91, userInfo: [
                NSLocalizedDescriptionKey: "Timed out waiting for characterization condition"
            ])
        }

        _ = try await group.next()
        group.cancelAll()
    }
}
