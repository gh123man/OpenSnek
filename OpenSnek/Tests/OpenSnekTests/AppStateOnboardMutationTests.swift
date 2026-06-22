import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

final class AppStateOnboardMutationTests: XCTestCase {
    func testCreatingOnboardProfileCanCopyExistingSlot() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-copy-create-device",
            transport: .usb,
            serial: "ONBOARD-COPY-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        let copiedBinding = ButtonBindingDraft(kind: .mouseForward, hidKey: 4, turboEnabled: false, turboRate: 0x8E)
        let sourceSnapshot = makeRefactorOnboardProfileSnapshot(
            profileID: 3,
            name: "Stored 3",
            dpiValues: [3200, 6400],
            buttonBindings: [4: copiedBinding],
            brightnessByLEDID: [1: 210, 4: 180, 10: 150],
            staticColorByLEDID: [
                1: RGBPatch(r: 10, g: 20, b: 30),
                4: RGBPatch(r: 40, g: 50, b: 60),
                10: RGBPatch(r: 70, g: 80, b: 90)
            ]
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 74,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 5
                    )
                )
            ]
        )
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1,
                maxProfileID: 5,
                assignedProfileIDs: [1, 3],
                profiles: [
                    makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true),
                    makeRefactorOnboardProfileSummary(profileID: 3, name: "Stored 3", isActive: false)
                ]
            ),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(sourceSnapshot, forDeviceID: device.id)

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)
        await appState.editorStore.createOnboardProfile(
            name: "Copied",
            targetProfileID: 2,
            copyFromProfileID: 3
        )

        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })?.displayName == "Copied"
            }
        }

        let creates = await backend.recordedOnboardCreates()
        let create = try XCTUnwrap(creates.first)
        XCTAssertEqual(create.targetProfileID, 2)
        XCTAssertEqual(create.mutation.metadata?.name, "Copied")
        XCTAssertEqual(create.mutation.dpi?.pairs.map(\.x), [3200, 6400])
        XCTAssertEqual(create.mutation.buttonBindings?[4], copiedBinding)
        XCTAssertEqual(create.mutation.brightnessByLEDID, sourceSnapshot.brightnessByLEDID)
        XCTAssertEqual(create.mutation.staticColorByLEDID, sourceSnapshot.staticColorByLEDID)
        let sourceReadCount = await backend.onboardReadCount(deviceID: device.id, profileID: 3)
        XCTAssertEqual(sourceReadCount, 1)
        let activations = await backend.recordedOnboardActivations()
        XCTAssertEqual(activations.map(\.profileID), [2])
    }

    func testRenamingOnboardProfileUpdatesCachedSummaryWithoutRefreshingInventory() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-rename-device",
            transport: .usb,
            serial: "ONBOARD-RENAME-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        defer { clearRefactorPreferences(for: device) }
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 74,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 5
                    )
                )
            ]
        )
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1,
                maxProfileID: 5,
                assignedProfileIDs: [1, 2],
                profiles: [
                    makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true),
                    makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)
                ]
            ),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400]),
            forDeviceID: device.id
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)

        await appState.editorStore.renameSelectedOnboardProfile(name: "Renamed")

        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.selectedOnboardProfileName == "Renamed" &&
                    appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })?.displayName == "Renamed"
            }
        }

        let renames = await backend.recordedOnboardRenames()
        XCTAssertEqual(renames.map(\.profileID), [2])
        XCTAssertEqual(renames.first?.name, "Renamed")
        let listCountAfterRename = await backend.onboardListCount(deviceID: device.id)
        XCTAssertEqual(listCountAfterRename, 1)
    }

    func testMetadataObjectOnboardProfileRenamePreservesLoadedSnapshotForNextEdit() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-rename-metadata-object-device",
            transport: .usb,
            serial: "ONBOARD-RENAME-METADATA-OBJECT-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 74,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 5
                    )
                )
            ]
        )
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1,
                maxProfileID: 5,
                assignedProfileIDs: [1, 2],
                profiles: [
                    makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true),
                    makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)
                ]
            ),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(
            OnboardProfileSnapshot(
                profileID: 2,
                metadata: OnboardProfileMetadata(name: "Stored 2"),
                dpi: OnboardDPIProfileSnapshot(
                    scalar: DpiPair(x: 1200, y: 1200),
                    activeStage: 0,
                    pairs: [DpiPair(x: 1200, y: 1200), DpiPair(x: 2400, y: 2400)],
                    stageIDs: [0x21, 0x22],
                    marker: 0xA5
                ),
                buttonBindings: [4: ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E)],
                brightnessByLEDID: [1: 64]
            ),
            forDeviceID: device.id
        )
        await backend.setRenameReturnsMetadataOnly(true)

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)

        await appState.editorStore.renameSelectedOnboardProfile(name: "Renamed")
        await MainActor.run {
            appState.editorStore.editableStageCount = 2
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 1400, y: 1400),
                DpiPair(x: 2600, y: 2600),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400),
                DpiPair(x: 12000, y: 12000)
            ]
            appState.editorStore.editableActiveStage = 1
        }
        await appState.editorStore.applyDpiStages()

        try await waitForRefactorCondition {
            await backend.recordedOnboardUpdates().count == 1
        }

        let update = await backend.recordedOnboardUpdates().first
        XCTAssertEqual(update?.profileID, 2)
        XCTAssertEqual(update?.mutation.dpi?.stageIDs, [0x21, 0x22])
        XCTAssertEqual(update?.mutation.dpi?.marker, 0xA5)
    }

    func testRenamedOnboardProfilePreservesProjectedNameAcrossStaleInventoryRefresh() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-rename-stale-inventory-device",
            transport: .usb,
            serial: "ONBOARD-RENAME-STALE-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 74,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 5
                    )
                )
            ]
        )
        let staleInventory = OnboardProfileInventory(
            activeProfileID: 1,
            maxProfileID: 5,
            assignedProfileIDs: [1, 2],
            profiles: [
                makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true),
                makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)
            ]
        )
        await backend.setOnboardInventory(staleInventory, forDeviceID: device.id)
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400]),
            forDeviceID: device.id
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)

        await appState.editorStore.renameSelectedOnboardProfile(name: "Renamed")
        await backend.setOnboardInventory(staleInventory, forDeviceID: device.id)
        await appState.editorStore.refreshOnboardProfiles()

        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.selectedOnboardProfileName == "Renamed" &&
                    appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })?.displayName == "Renamed"
            }
        }

        let listCountAfterStaleRefresh = await backend.onboardListCount(deviceID: device.id)
        XCTAssertEqual(listCountAfterStaleRefresh, 2)
    }

    func testProjectedOnboardProfileNameDoesNotResurrectUnassignedSlot() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-rename-unassigned-refresh-device",
            transport: .usb,
            serial: "ONBOARD-RENAME-UNASSIGNED-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 74,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 5
                    )
                )
            ]
        )
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1,
                maxProfileID: 5,
                assignedProfileIDs: [1, 2],
                profiles: [
                    makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true),
                    makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)
                ]
            ),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400]),
            forDeviceID: device.id
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)

        await appState.editorStore.renameSelectedOnboardProfile(name: "Renamed")
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1,
                maxProfileID: 5,
                assignedProfileIDs: [1],
                profiles: [
                    makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true)
                ]
            ),
            forDeviceID: device.id
        )
        await appState.editorStore.refreshOnboardProfiles()

        try await waitForRefactorCondition {
            await MainActor.run {
                let slot = appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })
                return appState.editorStore.selectedOnboardProfileID == 1 &&
                    slot?.isAssigned == false &&
                    slot?.metadata == nil
            }
        }
    }

    func testDeletingActiveOnboardProfileActivatesNextAssignedSlot() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-delete-active-device",
            transport: .usb,
            serial: "ONBOARD-DELETE-ACTIVE-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 74,
                        dpiValues: [1200, 2400],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 2,
                        onboardProfileCount: 5
                    )
                )
            ]
        )
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 2,
                maxProfileID: 5,
                assignedProfileIDs: [1, 2, 3],
                profiles: [
                    makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: false),
                    makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: true),
                    makeRefactorOnboardProfileSummary(profileID: 3, name: "Stored 3", isActive: false)
                ]
            ),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400]),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(profileID: 3, name: "Stored 3", dpiValues: [3200, 6400]),
            forDeviceID: device.id
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)

        await appState.editorStore.deleteSelectedOnboardProfile()

        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.selectedOnboardProfileID == 3 &&
                    appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })?.isAssigned == false &&
                    appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 3 })?.isActive == true &&
                    appState.deviceStore.state?.active_onboard_profile == 3 &&
                    appState.editorStore.stageValue(0) == 3200
            }
        }

        let deletes = await backend.recordedOnboardDeletes()
        XCTAssertEqual(deletes.map(\.profileID), [2])
        let activations = await backend.recordedOnboardActivations()
        XCTAssertEqual(activations.map(\.profileID), [3])
    }

    func testSelectedOnboardProfileDpiEditUpdatesActiveOnboardProfile() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-inactive-edit-device",
            transport: .usb,
            serial: "ONBOARD-INACTIVE-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 74,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 5
                    )
                )
            ]
        )
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1,
                maxProfileID: 5,
                assignedProfileIDs: [1, 2],
                profiles: [
                    makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true),
                    makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)
                ]
            ),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400]),
            forDeviceID: device.id
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)
        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })?.isActive == true &&
                    appState.deviceStore.state?.active_onboard_profile == 2
            }
        }
        await MainActor.run {
            appState.editorStore.editableStageCount = 2
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 1500, y: 1500),
                DpiPair(x: 2600, y: 2600),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400),
                DpiPair(x: 12000, y: 12000)
            ]
            appState.editorStore.editableActiveStage = 2
        }

        await appState.editorStore.applyDpiStages()

        try await waitForRefactorCondition {
            await backend.recordedOnboardUpdates().count == 1
        }

        let updates = await backend.recordedOnboardUpdates()
        let activations = await backend.recordedOnboardActivations()
        let applyCount = await backend.applyCount()
        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(activations.map(\.profileID), [2])
        XCTAssertEqual(updates.first?.profileID, 2)
        XCTAssertEqual(updates.first?.mutation.dpi?.pairs.map(\.x), [1500, 2600])
        XCTAssertEqual(updates.first?.mutation.dpi?.activeStage, 1)
    }

    func testBluetoothOnboardProfileDeviceEditorChangesUpdateStoredProfile() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-bt-stored-editor-device",
            transport: .bluetooth,
            serial: "ONBOARD-BT-STORED-EDITOR-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "bluetooth",
                        batteryPercent: 74,
                        dpiValues: [400, 800, 1300, 1600, 6400],
                        activeStage: 2
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 5
                    )
                )
            ]
        )
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1,
                maxProfileID: 5,
                assignedProfileIDs: [1, 2],
                profiles: [
                    makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true),
                    makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)
                ]
            ),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(
                profileID: 1,
                name: "Base",
                dpiValues: [400, 800, 1300, 1600, 6400],
                brightnessByLEDID: [1: 128, 4: 128, 10: 128],
                staticColorByLEDID: [1: RGBPatch(r: 0, g: 0, b: 255), 4: RGBPatch(r: 0, g: 0, b: 255), 10: RGBPatch(r: 0, g: 0, b: 255)]
            ),
            forDeviceID: device.id
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await MainActor.run {
            appState.editorStore.editableStageCount = 3
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 500, y: 500),
                DpiPair(x: 900, y: 900),
                DpiPair(x: 1400, y: 1400),
                DpiPair(x: 1600, y: 1600),
                DpiPair(x: 6400, y: 6400)
            ]
            appState.editorStore.editableActiveStage = 3
        }

        await appState.editorStore.applyDpiStages()
        try await waitForRefactorCondition {
            await backend.recordedOnboardUpdates().count == 1
        }

        await MainActor.run {
            appState.editorStore.editableLightingEffect = .staticColor
            appState.editorStore.editableUSBLightingZoneID = "all"
            appState.editorStore.editableColor = RGBColor(r: 255, g: 0, b: 0)
            appState.editorStore.scheduleAutoApplyLedColor()
        }
        try await waitForRefactorCondition {
            let updates = await backend.recordedOnboardUpdates()
            return updates.contains { update in
                update.profileID == 1 &&
                    update.mutation.staticColorByLEDID?[1] == RGBPatch(r: 255, g: 0, b: 0)
            }
        }

        await MainActor.run {
            appState.editorStore.editableLedBrightness = 200
            appState.editorStore.scheduleAutoApplyLedBrightness()
        }
        try await waitForRefactorCondition {
            let updates = await backend.recordedOnboardUpdates()
            return updates.contains { update in
                update.profileID == 1 &&
                    update.mutation.brightnessByLEDID?[1] == 200
            }
        }

        await MainActor.run {
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .mouseForward)
        }
        try await waitForRefactorCondition {
            await backend.recordedOnboardUpdates().count == 4
        }

        let updates = await backend.recordedOnboardUpdates()
        let patches = await backend.recordedPatches()
        XCTAssertEqual(patches.count, 0)
        XCTAssertEqual(updates.map(\.profileID), [1, 1, 1, 1])
        XCTAssertEqual(updates[0].mutation.dpi?.pairs.map(\.x), [500, 900, 1400])
        XCTAssertEqual(updates[0].mutation.dpi?.activeStage, 2)
        XCTAssertEqual(updates[1].mutation.staticColorByLEDID?[1], RGBPatch(r: 255, g: 0, b: 0))
        XCTAssertEqual(updates[2].mutation.brightnessByLEDID?[1], 200)
        XCTAssertEqual(updates[3].mutation.buttonBindings?[4]?.kind, .mouseForward)
    }

    func testBluetoothOnboardProfileButtonEditUpdatesSelectedStoredProfile() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-bt-selected-button-device",
            transport: .bluetooth,
            serial: "ONBOARD-BT-SELECTED-BUTTON-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "bluetooth",
                        batteryPercent: 74,
                        dpiValues: [400, 1200, 1300],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 5
                    )
                )
            ]
        )
        let baseBinding = ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E)
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1,
                maxProfileID: 5,
                assignedProfileIDs: [1, 2],
                profiles: [
                    makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true),
                    makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)
                ]
            ),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", buttonBindings: [4: baseBinding]),
            forDeviceID: device.id
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)

        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.selectedOnboardProfileID == 2 &&
                    appState.editorStore.selectedOnboardProfileIsActive &&
                    appState.editorStore.buttonBindingKind(for: 4) == .rightClick
            }
        }
        try await waitForRefactorCondition {
            await backend.onboardButtonReadCount(deviceID: device.id, profileID: 2) >= 1
        }

        await MainActor.run {
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .mouseForward)
        }

        try await waitForRefactorCondition {
            await backend.recordedOnboardUpdates().count == 1
        }

        let updates = await backend.recordedOnboardUpdates()
        let patches = await backend.recordedPatches()
        let visibleKind = await MainActor.run {
            appState.editorStore.buttonBindingKind(for: 4)
        }
        XCTAssertEqual(patches.count, 0)
        XCTAssertEqual(updates.first?.profileID, 2)
        XCTAssertEqual(updates.first?.mutation.buttonBindings?[4]?.kind, .mouseForward)
        XCTAssertEqual(visibleKind, .mouseForward)
    }

    func testBluetoothOnboardProfileSwitchHydratesProfileSpecificButtonBindings() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-bt-switch-button-device",
            transport: .bluetooth,
            serial: "ONBOARD-BT-SWITCH-BUTTON-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "bluetooth",
                        batteryPercent: 74,
                        dpiValues: [400, 1200, 1300],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 5
                    )
                )
            ]
        )
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1,
                maxProfileID: 5,
                assignedProfileIDs: [1, 2, 3],
                profiles: [
                    makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true),
                    makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false),
                    makeRefactorOnboardProfileSummary(profileID: 3, name: "Stored 3", isActive: false)
                ]
            ),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(
                profileID: 2,
                name: "Stored 2",
                buttonBindings: [4: ButtonBindingDraft(kind: .mouseBack, hidKey: 4, turboEnabled: false, turboRate: 0x8E)]
            ),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(
                profileID: 3,
                name: "Stored 3",
                buttonBindings: [4: ButtonBindingDraft(kind: .mouseForward, hidKey: 5, turboEnabled: false, turboRate: 0x8E)]
            ),
            forDeviceID: device.id
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        await appState.editorStore.selectOnboardProfile(2)
        let profile2Kind = await MainActor.run {
            appState.editorStore.buttonBindingKind(for: 4)
        }

        await appState.editorStore.selectOnboardProfile(3)
        let profile3Kind = await MainActor.run {
            appState.editorStore.buttonBindingKind(for: 4)
        }
        let profile2ButtonReadCount = await backend.onboardButtonReadCount(deviceID: device.id, profileID: 2)
        let profile3ButtonReadCount = await backend.onboardButtonReadCount(deviceID: device.id, profileID: 3)
        let patches = await backend.recordedPatches()

        XCTAssertEqual(profile2Kind, .mouseBack)
        XCTAssertEqual(profile3Kind, .mouseForward)
        XCTAssertEqual(profile2ButtonReadCount, 1)
        XCTAssertEqual(profile3ButtonReadCount, 1)
        XCTAssertTrue(patches.isEmpty)
    }

}
