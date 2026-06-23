import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

final class AppStateLocalProfileTests: XCTestCase {
    func testReadingMappedOnboardProfileAutoSyncsLocalProfileByUUID() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeMappedProfileDevice(id: "local-profile-read-sync")
        let identifier = UUID()
        let snapshot = makeLocalProfileOnboardSnapshot(
            profileID: 2,
            identifier: identifier,
            name: "Stored 2",
            dpiValues: [1200, 2400],
            activeStage: 1
        )
        let backend = makeLocalProfileBackend(device: device, activeProfile: 2, dpiValues: [800, 1600])
        await backend.setOnboardInventory(
            makeLocalProfileInventory(activeProfile: 2, maxProfileID: 5, snapshots: [snapshot]),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(snapshot, forDeviceID: device.id)

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        try await waitForLocalProfiles { profiles in
            profiles.contains { $0.onboardIdentifier == identifier }
        }

        let profile = try XCTUnwrap(DevicePreferenceStore().loadOpenSnekLocalProfiles().first)
        XCTAssertEqual(profile.name, "Stored 2")
        XCTAssertEqual(profile.onboardIdentifier, identifier)
        XCTAssertEqual(profile.sourceDeviceProfileID, .basiliskV3Pro)
        XCTAssertEqual(profile.sourceTransport, .usb)
        XCTAssertEqual(profile.content.dpi?.values, [1200, 2400])
        XCTAssertEqual(profile.content.dpi?.activeStage, 1)
    }

    func testMappedOnboardProfileDPIEditUpdatesSameLocalUUIDProfile() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeMappedProfileDevice(id: "local-profile-edit-sync")
        let identifier = UUID()
        let snapshot = makeLocalProfileOnboardSnapshot(
            profileID: 2,
            identifier: identifier,
            name: "Stored 2",
            dpiValues: [800, 1600],
            activeStage: 0
        )
        let backend = makeLocalProfileBackend(device: device, activeProfile: 2, dpiValues: [800, 1600])
        await backend.setOnboardInventory(
            makeLocalProfileInventory(activeProfile: 2, maxProfileID: 5, snapshots: [snapshot]),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(snapshot, forDeviceID: device.id)

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        try await waitForLocalProfiles { $0.contains { $0.onboardIdentifier == identifier } }
        let localID = try XCTUnwrap(DevicePreferenceStore().loadOpenSnekLocalProfiles().first?.id)

        await MainActor.run {
            appState.editorStore.editableStageCount = 2
            appState.editorStore.editableStageValues = [1200, 2400]
            appState.editorStore.setEditableActiveStage(2, source: "test.localProfile")
        }
        await appState.editorStore.applyDpiStages()

        try await waitForLocalProfiles { profiles in
            profiles.first(where: { $0.id == localID })?.content.dpi?.values == [1200, 2400]
        }

        let updated = try XCTUnwrap(DevicePreferenceStore().loadOpenSnekLocalProfiles().first)
        XCTAssertEqual(updated.id, localID)
        XCTAssertEqual(updated.onboardIdentifier, identifier)
        XCTAssertEqual(updated.content.dpi?.values, [1200, 2400])
        XCTAssertEqual(updated.content.dpi?.activeStage, 1)
        let updates = await backend.recordedOnboardUpdates()
        XCTAssertEqual(updates.map(\.profileID), [2])
    }

    func testReplacingMappedAssignedSlotBacksUpThenWritesChosenLocalProfile() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeMappedProfileDevice(id: "local-profile-replace-mapped")
        let oldIdentifier = UUID()
        let oldSnapshot = makeLocalProfileOnboardSnapshot(
            profileID: 2,
            identifier: oldIdentifier,
            name: "Old Slot",
            dpiValues: [800, 1600],
            activeStage: 0
        )
        let replacement = DevicePreferenceStore().createOpenSnekLocalProfile(
            name: "Travel",
            content: OpenSnekLocalProfileContent(
                dpi: OnboardDPIProfileSnapshot(
                    scalar: DpiPair(x: 3000, y: 3000),
                    activeStage: 0,
                    pairs: [DpiPair(x: 3000, y: 3000), DpiPair(x: 6000, y: 6000)]
                ),
                buttonBindings: [
                    4: ButtonBindingDraft(kind: .mouseForward, hidKey: 4, turboEnabled: false, turboRate: 0x8E)
                ],
                brightnessByLEDID: [1: 88],
                staticColorByLEDID: [1: RGBPatch(r: 20, g: 30, b: 40)],
                scrollMode: 1,
                scrollAcceleration: true,
                scrollSmartReel: false
            )
        )
        let backend = makeLocalProfileBackend(device: device, activeProfile: 2, dpiValues: [800, 1600])
        await backend.setOnboardInventory(
            makeLocalProfileInventory(activeProfile: 2, maxProfileID: 5, snapshots: [oldSnapshot]),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(oldSnapshot, forDeviceID: device.id)

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.replaceSelectedProfile(with: replacement.id)

        try await waitForRefactorCondition {
            await backend.recordedOnboardCreates().count == 1
        }

        let creates = await backend.recordedOnboardCreates()
        let create = try XCTUnwrap(creates.first)
        XCTAssertEqual(create.targetProfileID, 2)
        XCTAssertTrue(create.replaceAssignedProfile)
        XCTAssertEqual(create.mutation.metadata?.name, "Travel")
        XCTAssertEqual(create.mutation.dpi?.values, [3000, 6000])
        XCTAssertEqual(create.mutation.buttonBindings?[4]?.kind, .mouseForward)
        XCTAssertEqual(create.mutation.scrollMode, 1)
        let readCount = await backend.onboardReadCount(deviceID: device.id, profileID: 2)
        XCTAssertGreaterThanOrEqual(readCount, 1)

        let profiles = DevicePreferenceStore().loadOpenSnekLocalProfiles()
        let backedUpOldSlot = profiles.first { $0.onboardIdentifier == oldIdentifier }
        let adoptedReplacement = profiles.first { $0.id == replacement.id }
        XCTAssertEqual(backedUpOldSlot?.name, "Old Slot")
        XCTAssertEqual(adoptedReplacement?.onboardIdentifier, create.mutation.metadata?.identifier)
        XCTAssertEqual(profiles.filter { $0.name == "Travel" }.count, 1)
    }

    func testSingleSlotDeviceExposesPickerSlotAndHidesConnectBehaviorCard() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeSingleSlotProfileDevice(id: "local-profile-single-slot-picker")
        let backend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [800, 1600])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        let presentation = await MainActor.run {
            (
                appState.editorStore.supportsProfilePicker,
                appState.editorStore.supportsOnboardProfileCRUD,
                appState.editorStore.showsConnectBehaviorCard,
                appState.editorStore.connectBehavior,
                appState.editorStore.onboardProfileSummaries
            )
        }
        XCTAssertTrue(presentation.0)
        XCTAssertFalse(presentation.1)
        XCTAssertFalse(presentation.2)
        XCTAssertEqual(presentation.3, .useMouseSettings)
        XCTAssertEqual(presentation.4.count, 1)
        XCTAssertEqual(presentation.4.first?.profileID, 1)
        XCTAssertTrue(presentation.4.first?.isAssigned == true)
        XCTAssertTrue(presentation.4.first?.isActive == true)

        await MainActor.run {
            appState.editorStore.updateConnectBehavior(.restoreOpenSnekSettings)
        }
        let updatedBehavior = await MainActor.run { appState.editorStore.connectBehavior }
        XCTAssertEqual(updatedBehavior, .restoreOpenSnekSettings)
    }

    func testSingleSlotMouseReadsDoNotCreateSyntheticLocalProfiles() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeSingleSlotProfileDevice(id: "local-profile-single-slot-hidden-backup")
        let backend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [800, 1600])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await appState.editorStore.loadSelectedSingleSlotProfileFromMouse()
        await appState.editorStore.loadSelectedSingleSlotProfileFromMouse()

        let backupPresentation = await MainActor.run {
            (
                appState.editorStore.localProfiles.filter { $0.syntheticSourceKey != nil },
                appState.editorStore.visibleLocalProfilesForReplacement
            )
        }
        XCTAssertTrue(backupPresentation.0.isEmpty)
        XCTAssertTrue(backupPresentation.1.isEmpty)

        await appState.editorStore.createLocalProfileFromMouse(name: "Mouse Capture")

        let createdPresentation = await MainActor.run {
            (
                appState.editorStore.localProfiles.filter { $0.syntheticSourceKey != nil },
                appState.editorStore.visibleLocalProfilesForReplacement
            )
        }
        XCTAssertTrue(createdPresentation.0.isEmpty)
        XCTAssertEqual(createdPresentation.1.map(\.name), ["Mouse Capture"])
    }

    func testSingleSlotUseMouseSettingsAppliesDoNotCreateSyntheticLocalProfiles() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeSingleSlotProfileDevice(id: "local-profile-use-mouse-settings")
        let backend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [800, 1600])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        let behavior = await MainActor.run { appState.editorStore.connectBehavior }
        XCTAssertEqual(behavior, .useMouseSettings)

        await MainActor.run {
            appState.editorStore.editableStageCount = 2
            appState.editorStore.editableStageValues = [1200, 2400]
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 1200, y: 1200),
                DpiPair(x: 2400, y: 2400),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400),
                DpiPair(x: 10_000, y: 10_000)
            ]
            appState.editorStore.setEditableActiveStage(1, source: "test.singleSlotUseMouseSettings")
        }
        await appState.editorStore.applyDpiStages()

        try await waitForRefactorCondition {
            await backend.recordedPatches().contains { $0.dpiStages == [1200, 2400] }
        }

        let profilePresentation = await MainActor.run {
            (
                appState.editorStore.localProfiles.filter { $0.syntheticSourceKey != nil },
                appState.editorStore.visibleLocalProfilesForReplacement
            )
        }
        XCTAssertTrue(profilePresentation.0.isEmpty)
        XCTAssertTrue(profilePresentation.1.isEmpty)
    }

    func testSingleSlotUseMouseSettingsColdLaunchShowsBaseProfileAndDoesNotPersistToKnownProfile() async throws {
        clearSavedButtonProfiles()
        let device = makeSingleSlotProfileDevice(id: "local-profile-use-mouse-cold")
        defer { clearRefactorPreferences(for: device) }

        let preferenceStore = DevicePreferenceStore()
        let localProfile = preferenceStore.createOpenSnekLocalProfile(
            name: "Travel",
            content: singleSlotLocalProfileContent(dpiValues: [1200, 2400])
        )
        preferenceStore.persistSelectedLocalProfileID(localProfile.id, device: device)
        preferenceStore.persistConnectBehavior(.useMouseSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            singleSlotSettingsSnapshot(dpiValues: [1200, 2400]),
            device: device
        )

        let backend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [400, 800])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()

        let summary = await MainActor.run {
            appState.editorStore.onboardProfileSummaries.first
        }
        XCTAssertEqual(summary?.displayName, "Base Profile")
        XCTAssertNil(summary?.metadata)
        let initialPatches = await backend.recordedPatches()
        XCTAssertTrue(initialPatches.isEmpty)

        await MainActor.run {
            appState.editorStore.editableStageCount = 2
            appState.editorStore.editableStageValues = [500, 1000]
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 500, y: 500),
                DpiPair(x: 1000, y: 1000),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400),
                DpiPair(x: 10_000, y: 10_000)
            ]
            appState.editorStore.setEditableActiveStage(0, source: "test.singleSlotUseMouseSettingsColdLaunch")
        }
        await appState.editorStore.applyDpiStages()

        try await waitForRefactorCondition {
            await backend.recordedPatches().contains { $0.dpiStages == [500, 1000] }
        }

        let storedProfile = try XCTUnwrap(
            preferenceStore.loadOpenSnekLocalProfiles().first { $0.id == localProfile.id }
        )
        XCTAssertEqual(storedProfile.content.dpi?.pairs.map(\.x), [1200, 2400])
    }

    func testSingleSlotSelectingRestoreLastProfileShowsKnownProfileAndPersistsEdits() async throws {
        clearSavedButtonProfiles()
        let device = makeSingleSlotProfileDevice(id: "local-profile-restore-toggle")
        defer { clearRefactorPreferences(for: device) }

        let preferenceStore = DevicePreferenceStore()
        let localProfile = preferenceStore.createOpenSnekLocalProfile(
            name: "Travel",
            content: singleSlotLocalProfileContent(dpiValues: [1200, 2400])
        )
        preferenceStore.persistSelectedLocalProfileID(localProfile.id, device: device)
        preferenceStore.persistConnectBehavior(.useMouseSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            singleSlotSettingsSnapshot(dpiValues: [1200, 2400]),
            device: device
        )

        let backend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [400, 800])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()

        let initialSummary = await MainActor.run {
            appState.editorStore.onboardProfileSummaries.first
        }
        XCTAssertEqual(initialSummary?.displayName, "Base Profile")

        await MainActor.run {
            appState.editorStore.updateConnectBehavior(.restoreOpenSnekSettings)
        }

        let restoredSummary = await MainActor.run {
            appState.editorStore.onboardProfileSummaries.first
        }
        XCTAssertEqual(restoredSummary?.metadata?.name, "Travel")

        await MainActor.run {
            appState.editorStore.editableStageCount = 2
            appState.editorStore.editableStageValues = [500, 1000]
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 500, y: 500),
                DpiPair(x: 1000, y: 1000),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400),
                DpiPair(x: 10_000, y: 10_000)
            ]
            appState.editorStore.setEditableActiveStage(0, source: "test.singleSlotRestoreToggle")
        }
        await appState.editorStore.applyDpiStages()

        try await waitForRefactorCondition {
            await backend.recordedPatches().contains { $0.dpiStages == [500, 1000] }
        }

        let updatedProfile = try XCTUnwrap(
            preferenceStore.loadOpenSnekLocalProfiles().first { $0.id == localProfile.id }
        )
        XCTAssertEqual(updatedProfile.content.dpi?.pairs.map(\.x), [500, 1000])
    }

    func testSingleSlotRestoreLastProfileShowsKnownLocalProfileOnFreshLaunch() async throws {
        clearSavedButtonProfiles()
        let device = makeSingleSlotProfileDevice(id: "local-profile-restore-known")
        defer { clearRefactorPreferences(for: device) }

        let preferenceStore = DevicePreferenceStore()
        let replacement = preferenceStore.createOpenSnekLocalProfile(
            name: "Travel",
            content: singleSlotLocalProfileContent(dpiValues: [1200, 2400])
        )
        let firstBackend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [800, 1600])
        let firstAppState = await MainActor.run {
            AppState(launchRole: .app, backend: firstBackend, autoStart: false)
        }
        await firstAppState.deviceStore.refreshDevices()
        await firstAppState.editorStore.replaceSelectedProfile(with: replacement.id)

        try await waitForRefactorCondition {
            await firstBackend.recordedPatches().contains { $0.dpiStages == [1200, 2400] }
        }
        XCTAssertEqual(preferenceStore.loadSelectedLocalProfileID(device: device), replacement.id)

        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        let secondBackend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [400, 800])
        let secondAppState = await MainActor.run {
            AppState(launchRole: .app, backend: secondBackend, autoStart: false)
        }
        await secondAppState.deviceStore.refreshDevices()

        try await waitForRefactorCondition {
            let restored = await secondBackend.recordedPatches().contains { $0.dpiStages == [1200, 2400] }
            let profileName = await MainActor.run {
                secondAppState.editorStore.onboardProfileSummaries.first?.metadata?.name
            }
            return restored && profileName == "Travel"
        }

        let summary = await MainActor.run {
            secondAppState.editorStore.onboardProfileSummaries.first
        }
        XCTAssertEqual(summary?.metadata?.name, "Travel")
    }

    func testSingleSlotRestoreLastProfileInfersKnownLocalProfileWhenSelectionPointerIsMissing() async throws {
        clearSavedButtonProfiles()
        let device = makeSingleSlotProfileDevice(id: "local-profile-restore-matched")
        defer { clearRefactorPreferences(for: device) }

        let preferenceStore = DevicePreferenceStore()
        let localProfile = preferenceStore.createOpenSnekLocalProfile(
            name: "Travel",
            content: singleSlotLocalProfileContent(dpiValues: [1200, 2400])
        )
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            singleSlotSettingsSnapshot(dpiValues: [1200, 2400]),
            device: device
        )
        XCTAssertNil(preferenceStore.loadSelectedLocalProfileID(device: device))

        let backend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [400, 800])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()

        try await waitForRefactorCondition {
            let restored = await backend.recordedPatches().contains { $0.dpiStages == [1200, 2400] }
            let profileName = await MainActor.run {
                appState.editorStore.onboardProfileSummaries.first?.metadata?.name
            }
            return restored &&
                profileName == "Travel" &&
                preferenceStore.loadSelectedLocalProfileID(device: device) == localProfile.id
        }
    }

    func testSingleSlotKnownLocalProfileEditsPersistAfterReplacement() async throws {
        clearSavedButtonProfiles()
        let device = makeSingleSlotProfileDevice(id: "local-profile-edit-known")
        defer { clearRefactorPreferences(for: device) }

        let preferenceStore = DevicePreferenceStore()
        let replacement = preferenceStore.createOpenSnekLocalProfile(
            name: "Editable",
            content: singleSlotLocalProfileContent(dpiValues: [800, 1600])
        )
        let backend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [800, 1600])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.replaceSelectedProfile(with: replacement.id)

        await MainActor.run {
            appState.editorStore.editableStageCount = 2
            appState.editorStore.editableStageValues = [1000, 2000]
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 1000, y: 1000),
                DpiPair(x: 2000, y: 2000),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400),
                DpiPair(x: 10_000, y: 10_000)
            ]
        }
        await appState.editorStore.applyDpiStages()

        try await waitForRefactorCondition {
            let updated = preferenceStore.loadOpenSnekLocalProfiles().first { $0.id == replacement.id }
            return updated?.content.dpi?.values == [1000, 2000]
        }

        let updated = try XCTUnwrap(preferenceStore.loadOpenSnekLocalProfiles().first { $0.id == replacement.id })
        XCTAssertEqual(updated.content.dpi?.values, [1000, 2000])
        XCTAssertEqual(preferenceStore.loadSelectedLocalProfileID(device: device), replacement.id)
        XCTAssertNil(updated.syntheticSourceKey)
    }

    func testSingleSlotRestartDeletesLegacySyntheticBackupAndRepairsEmptyProfilesFromCurrentMouse() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeSingleSlotProfileDevice(id: "local-profile-empty-repair")
        let sourceKey = DevicePreferenceStore.localProfileSyntheticSourceKey(device: device, slot: 1)
        let emptyProfile = DevicePreferenceStore().createOpenSnekLocalProfile(
            name: "asdf",
            content: OpenSnekLocalProfileContent()
        )
        _ = DevicePreferenceStore().upsertOpenSnekLocalProfile(
            name: "test1",
            content: OpenSnekLocalProfileContent(
                dpi: OnboardDPIProfileSnapshot(
                    scalar: DpiPair(x: 1400, y: 1400),
                    activeStage: 1,
                    pairs: [
                        DpiPair(x: 700, y: 700),
                        DpiPair(x: 1400, y: 1400)
                    ]
                ),
                brightnessByLEDID: [1: 70],
                staticColorByLEDID: [1: RGBPatch(r: 12, g: 34, b: 56)]
            ),
            syntheticSourceKey: sourceKey,
            device: device
        )
        let backend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [800, 1600])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        let repaired = try XCTUnwrap(
            DevicePreferenceStore().loadOpenSnekLocalProfiles().first { $0.id == emptyProfile.id }
        )
        XCTAssertEqual(repaired.name, "asdf")
        XCTAssertEqual(repaired.content.dpi?.values, [800, 1600])
        XCTAssertEqual(repaired.content.dpi?.activeStage, 0)
        XCTAssertEqual(repaired.content.brightnessByLEDID[1], 64)
        XCTAssertEqual(repaired.content.staticColorByLEDID[1], RGBPatch(r: 0, g: 255, b: 0))
        XCTAssertEqual(repaired.sourceDeviceProfileID, .basiliskV3XHyperspeed)
        XCTAssertEqual(repaired.sourceTransport, .bluetooth)
        XCTAssertNil(DevicePreferenceStore().loadOpenSnekLocalProfiles().first { $0.syntheticSourceKey == sourceKey })

        let canApply = await MainActor.run {
            appState.editorStore.localProfileCanApply(repaired)
        }
        XCTAssertTrue(canApply)

        await appState.editorStore.replaceSelectedProfile(with: emptyProfile.id)
        try await waitForRefactorCondition {
            await backend.recordedPatches().contains { $0.dpiStages == [800, 1600] }
        }

        XCTAssertNil(DevicePreferenceStore().loadOpenSnekLocalProfiles().first { $0.syntheticSourceKey == sourceKey })
    }

    func testCreatingLocalProfileByCopyingEmptyLegacyProfileUsesCurrentEditorContent() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeSingleSlotProfileDevice(id: "local-profile-empty-copy")
        let emptyProfile = DevicePreferenceStore().createOpenSnekLocalProfile(
            name: "Empty Legacy",
            content: OpenSnekLocalProfileContent()
        )
        let backend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [900, 1800])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.createLocalProfile(name: "Copy", copying: emptyProfile.id)
        }

        let copied = try XCTUnwrap(
            DevicePreferenceStore().loadOpenSnekLocalProfiles().first { $0.name == "Copy" }
        )
        XCTAssertEqual(copied.content.dpi?.values, [900, 1800])
        XCTAssertTrue(copied.content.hasApplicableFields)
    }

    func testSingleSlotSwitchingCreatedProfilesRefreshesEditorState() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeSingleSlotProfileDevice(id: "local-profile-switch-editor")
        let backend = makeLocalProfileBackend(device: device, activeProfile: 1, dpiValues: [800, 1600])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.editableStageCount = 3
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 800, y: 800),
                DpiPair(x: 1400, y: 1400),
                DpiPair(x: 2000, y: 2000),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400)
            ]
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .mouseForward)
            appState.editorStore.createLocalProfile(name: "Alpha", copying: nil)

            appState.editorStore.editableStageCount = 2
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 600, y: 600),
                DpiPair(x: 1000, y: 1000),
                DpiPair(x: 2000, y: 2000),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400)
            ]
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .mouseBack)
            appState.editorStore.createLocalProfile(name: "Beta", copying: nil)
            appState.editorStore.scheduleAutoApplyDpi()
        }

        let profiles = DevicePreferenceStore().loadOpenSnekLocalProfiles()
        let alpha = try XCTUnwrap(profiles.first { $0.name == "Alpha" })
        let beta = try XCTUnwrap(profiles.first { $0.name == "Beta" })
        XCTAssertEqual(alpha.content.dpi?.values, [800, 1400, 2000])
        XCTAssertEqual(beta.content.dpi?.values, [600, 1000])

        await appState.editorStore.replaceSelectedProfile(with: alpha.id)
        let alphaState = await MainActor.run {
            (
                appState.editorStore.editableStageCount,
                Array(appState.editorStore.editableStagePairs.prefix(3)).map(\.x),
                appState.editorStore.buttonBindingKind(for: 4)
            )
        }
        XCTAssertEqual(alphaState.0, 3)
        XCTAssertEqual(alphaState.1, [800, 1400, 2000])
        XCTAssertEqual(alphaState.2, .mouseForward)
        try await Task.sleep(nanoseconds: 600_000_000)
        let patchesAfterAlpha = await backend.recordedPatches()
        XCTAssertFalse(
            patchesAfterAlpha.contains { $0.dpiStages == [600, 1000] },
            "Replacing with Alpha should cancel stale scheduled Beta DPI writes"
        )

        await appState.editorStore.replaceSelectedProfile(with: beta.id)
        let betaState = await MainActor.run {
            (
                appState.editorStore.editableStageCount,
                Array(appState.editorStore.editableStagePairs.prefix(2)).map(\.x),
                appState.editorStore.buttonBindingKind(for: 4)
            )
        }
        XCTAssertEqual(betaState.0, 2)
        XCTAssertEqual(betaState.1, [600, 1000])
        XCTAssertEqual(betaState.2, .mouseBack)
    }

    func testSingleSlotReplacementWaitsForInFlightLocalApplyBeforeSwitching() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeSingleSlotProfileDevice(id: "local-profile-switch-in-flight")
        let backend = makeLocalProfileBackend(
            device: device,
            activeProfile: 1,
            dpiValues: [800, 1600],
            holdFirstApply: true
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.editableStageCount = 3
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 800, y: 800),
                DpiPair(x: 1400, y: 1400),
                DpiPair(x: 2000, y: 2000),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400)
            ]
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .mouseForward)
            appState.editorStore.createLocalProfile(name: "Alpha", copying: nil)

            appState.editorStore.editableStageCount = 2
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 600, y: 600),
                DpiPair(x: 1000, y: 1000),
                DpiPair(x: 2000, y: 2000),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400)
            ]
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .mouseBack)
            appState.editorStore.createLocalProfile(name: "Beta", copying: nil)
            appState.editorStore.scheduleAutoApplyDpi()
        }

        let alpha = try XCTUnwrap(DevicePreferenceStore().loadOpenSnekLocalProfiles().first { $0.name == "Alpha" })
        await backend.waitForFirstApplyToStart()

        let replacementTask = Task {
            await appState.editorStore.replaceSelectedProfile(with: alpha.id)
        }
        try await Task.sleep(nanoseconds: 120_000_000)
        let applyCountWhileHeld = await backend.applyCount()
        XCTAssertEqual(
            applyCountWhileHeld,
            1,
            "Profile replacement should wait for the already-running local edit apply to finish"
        )

        await backend.releaseFirstApply()
        await replacementTask.value

        let alphaState = await MainActor.run {
            (
                appState.editorStore.editableStageCount,
                Array(appState.editorStore.editableStagePairs.prefix(3)).map(\.x),
                appState.editorStore.buttonBindingKind(for: 4)
            )
        }
        XCTAssertEqual(alphaState.0, 3)
        XCTAssertEqual(alphaState.1, [800, 1400, 2000])
        XCTAssertEqual(alphaState.2, .mouseForward)
        let maxConcurrentApplies = await backend.maxConcurrentApplies()
        XCTAssertEqual(maxConcurrentApplies, 1)

        let dpiPatches = await backend.recordedPatches().compactMap(\.dpiStages)
        XCTAssertEqual(dpiPatches.last, [800, 1400, 2000])
    }

    func testCrossDeviceV3ProLocalProfileAppliesSupportedFieldsToHyperSpeed() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let sourceDevice = makeMappedProfileDevice(id: "local-profile-cross-source")
        let targetDevice = makeSingleSlotProfileDevice(id: "local-profile-cross-target")
        let source = DevicePreferenceStore().upsertOpenSnekLocalProfile(
            name: "V3 Pro Travel",
            content: OpenSnekLocalProfileContent(
                dpi: OnboardDPIProfileSnapshot(
                    scalar: DpiPair(x: 30_000, y: 31_000),
                    activeStage: 1,
                    pairs: [
                        DpiPair(x: 600, y: 700),
                        DpiPair(x: 30_000, y: 31_000)
                    ]
                ),
                buttonBindings: [
                    4: ButtonBindingDraft(kind: .mouseForward, hidKey: 4, turboEnabled: false, turboRate: 0x8E),
                    15: ButtonBindingDraft(kind: .dpiClutch, hidKey: 4, turboEnabled: false, turboRate: 0x8E)
                ],
                brightnessByLEDID: [1: 42, 4: 96, 10: 128],
                staticColorByLEDID: [4: RGBPatch(r: 11, g: 22, b: 33)],
                lightingEffect: LightingEffectPatch(
                    kind: .wave,
                    primary: RGBPatch(r: 11, g: 22, b: 33),
                    waveDirection: .right
                ),
                scrollMode: 1,
                scrollAcceleration: true,
                scrollSmartReel: true
            ),
            onboardIdentifier: UUID(),
            device: sourceDevice
        )
        let backend = makeLocalProfileBackend(device: targetDevice, activeProfile: 1, dpiValues: [800, 1600])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.replaceSelectedProfile(with: source.id)

        try await waitForRefactorCondition {
            await backend.recordedPatches().contains { $0.buttonBinding?.slot == 4 }
        }

        let patches = await backend.recordedPatches()
        let dpiPatch = try XCTUnwrap(patches.first { $0.dpiStages != nil })
        XCTAssertEqual(dpiPatch.dpiStages, [600, 18_000])
        XCTAssertEqual(dpiPatch.dpiStagePairs, [DpiPair(x: 600, y: 600), DpiPair(x: 18_000, y: 18_000)])
        XCTAssertEqual(dpiPatch.activeStage, 1)
        XCTAssertNil(dpiPatch.scrollMode)
        XCTAssertNil(dpiPatch.scrollAcceleration)
        XCTAssertNil(dpiPatch.scrollSmartReel)
        XCTAssertEqual(dpiPatch.ledBrightness, 128)
        XCTAssertEqual(dpiPatch.ledRGB, RGBPatch(r: 11, g: 22, b: 33))
        XCTAssertNil(dpiPatch.lightingEffect)
        XCTAssertEqual(patches.compactMap(\.buttonBinding).map(\.slot), [4])
        XCTAssertEqual(patches.compactMap(\.buttonBinding).first?.kind, .mouseForward)
    }
}

private func makeMappedProfileDevice(id: String) -> MouseDevice {
    makeRefactorTestDevice(
        id: id,
        transport: .usb,
        serial: "LOCAL-PROFILE-\(UUID().uuidString)",
        onboardProfileCount: 5,
        profileID: .basiliskV3Pro
    )
}

private func makeSingleSlotProfileDevice(id: String) -> MouseDevice {
    makeRefactorTestDevice(
        id: id,
        transport: .bluetooth,
        serial: "LOCAL-PROFILE-\(UUID().uuidString)",
        onboardProfileCount: 1,
        profileID: .basiliskV3XHyperspeed
    )
}

private func makeLocalProfileBackend(
    device: MouseDevice,
    activeProfile: Int,
    dpiValues: [Int],
    holdFirstApply: Bool = false
) -> AppStateRefactorStubBackend {
    AppStateRefactorStubBackend(
        devices: [device],
        stateByDeviceID: [
            device.id: makeRefactorTestState(
                device: device,
                telemetry: RefactorTestStateTelemetry(
                    connection: device.transport.connectionLabel.lowercased(),
                    batteryPercent: 81,
                    dpiValues: dpiValues,
                    activeStage: 0
                ),
                options: RefactorTestStateOptions(
                    activeOnboardProfile: activeProfile,
                    onboardProfileCount: device.onboard_profile_count,
                    scrollMode: device.transport == .usb ? 0 : nil,
                    scrollAcceleration: device.transport == .usb ? false : nil,
                    scrollSmartReel: device.transport == .usb ? false : nil
                )
            )
        ],
        holdFirstApply: holdFirstApply
    )
}

private func singleSlotLocalProfileContent(dpiValues: [Int]) -> OpenSnekLocalProfileContent {
    let pairs = dpiValues.map { DpiPair(x: $0, y: $0) }
    return OpenSnekLocalProfileContent(
        dpi: OnboardDPIProfileSnapshot(
            scalar: pairs.first,
            activeStage: 0,
            pairs: pairs
        ),
        brightnessByLEDID: [1: 64],
        staticColorByLEDID: [1: RGBPatch(r: 0, g: 255, b: 0)]
    )
}

private func singleSlotSettingsSnapshot(dpiValues: [Int]) -> PersistedDeviceSettingsSnapshot {
    let pairs = dpiValues.map { DpiPair(x: $0, y: $0) }
    return PersistedDeviceSettingsSnapshot(
        stageCount: pairs.count,
        stageValues: dpiValues,
        stagePairs: pairs,
        activeStage: 1,
        pollRate: nil,
        sleepTimeout: nil,
        lowBatteryThresholdRaw: nil,
        scrollMode: nil,
        scrollAcceleration: nil,
        scrollSmartReel: nil,
        ledBrightness: 64,
        primaryLightingColor: RGBColor(r: 0, g: 255, b: 0),
        lightingEffect: nil,
        usbLightingZoneID: "all",
        buttonBindings: [:]
    )
}

private func makeLocalProfileInventory(
    activeProfile: Int,
    maxProfileID: Int,
    snapshots: [OnboardProfileSnapshot]
) -> OnboardProfileInventory {
    let summaries = snapshots.map { snapshot in
        OnboardProfileSummary(
            profileID: snapshot.profileID,
            metadata: snapshot.metadata,
            isAssigned: true,
            isActive: snapshot.profileID == activeProfile,
            isBaseProfile: snapshot.profileID == 1
        )
    }
    return OnboardProfileInventory(
        activeProfileID: activeProfile,
        maxProfileID: maxProfileID,
        assignedProfileIDs: snapshots.map(\.profileID).sorted(),
        profiles: summaries
    )
}

private func makeLocalProfileOnboardSnapshot(
    profileID: Int,
    identifier: UUID,
    name: String,
    dpiValues: [Int],
    activeStage: Int
) -> OnboardProfileSnapshot {
    let pairs = dpiValues.map { DpiPair(x: $0, y: $0) }
    let active = max(0, min(max(0, pairs.count - 1), activeStage))
    return OnboardProfileSnapshot(
        profileID: profileID,
        metadata: OnboardProfileMetadata(identifier: identifier, name: name),
        dpi: OnboardDPIProfileSnapshot(
            scalar: pairs.indices.contains(active) ? pairs[active] : pairs.first,
            activeStage: active,
            pairs: pairs
        ),
        buttonBindings: [
            4: ButtonBindingDraft(kind: .mouseBack, hidKey: 4, turboEnabled: false, turboRate: 0x8E)
        ],
        brightnessByLEDID: [1: 64],
        staticColorByLEDID: [1: RGBPatch(r: 1, g: 2, b: 3)],
        scrollMode: 0,
        scrollAcceleration: false,
        scrollSmartReel: false
    )
}

private func waitForLocalProfiles(
    timeout: TimeInterval = 1.0,
    condition: @escaping @Sendable ([OpenSnekLocalProfile]) async -> Bool
) async throws {
    try await waitForRefactorCondition(timeout: timeout) {
        await condition(DevicePreferenceStore().loadOpenSnekLocalProfiles())
    }
}
