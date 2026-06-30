import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

/// Exercises app state onboard hydration behavior.
final class AppStateOnboardHydrationTests: XCTestCase {
    func testOnboardProfileSelectionActivatesAndHardwareProfileChangesHydrateUI() async throws {
        let device = makeRefactorTestDevice(id: "onboard-selection-device", transport: .bluetooth, serial: "ONBOARD-SELECTION-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let staleEditorColor = RGBColor(r: 1, g: 2, b: 3)
        let wheelColor = RGBColor(r: 10, g: 20, b: 30)
        let logoColor = RGBColor(r: 40, g: 50, b: 60)
        let underglowColor = RGBColor(r: 70, g: 80, b: 90)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 2, 3],
                profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false), makeRefactorOnboardProfileSummary(profileID: 3, name: "Stored 3", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(
                profileID: 3, name: "Stored 3", dpiValues: [3200, 6400], buttonBindings: [4: ButtonBindingDraft(kind: .mouseForward, hidKey: 4, turboEnabled: false, turboRate: 0x8E)], brightnessByLEDID: [1: 220, 4: 220, 10: 220],
                staticColorByLEDID: [1: RGBPatch(r: wheelColor.r, g: wheelColor.g, b: wheelColor.b), 4: RGBPatch(r: logoColor.r, g: logoColor.g, b: logoColor.b), 10: RGBPatch(r: underglowColor.r, g: underglowColor.g, b: underglowColor.b)]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)

        try await waitForRefactorCondition {
            await MainActor.run { appState.editorStore.selectedOnboardProfileID == 2 && appState.editorStore.onboardProfileSummaries.first(where: { $0.isActive })?.profileID == 2 && appState.deviceStore.state?.active_onboard_profile == 2 && appState.editorStore.stagePair(0).x == 1200 }
        }
        let selectionActivations = await backend.recordedOnboardActivations()
        XCTAssertEqual(selectionActivations.map(\.profileID), [2])

        await backend.holdOnboardProfileRead(deviceID: device.id, profileID: 3)
        await MainActor.run {
            appState.editorStore.editableLightingEffect = .wave
            appState.editorStore.editableUSBLightingZoneID = "all"
            appState.editorStore.editableColor = staleEditorColor
            appState.applyController.markLocalEditsPending()
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id, state: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [3200, 6400], activeStage: 1), options: RefactorTestStateOptions(activeOnboardProfile: 3, onboardProfileCount: 5)),
                updatedAt: Date())
        }
        await backend.waitForOnboardProfileReadToStart(deviceID: device.id, profileID: 3)

        let busyDuringHardwareProfileLoad = await MainActor.run { !appState.editorStore.isButtonProfileOperationInFlight && appState.editorStore.isOnboardProfileLoadInFlight && appState.editorStore.onboardProfileLoadStatusText == "Loading profile..." }
        XCTAssertTrue(busyDuringHardwareProfileLoad)

        await backend.releaseOnboardProfileRead(deviceID: device.id, profileID: 3)

        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.selectedOnboardProfileID == 3 && appState.editorStore.onboardProfileSummaries.first(where: { $0.isActive })?.profileID == 3 && appState.editorStore.stageValue(0) == 3200 && appState.editorStore.stageValue(1) == 6400
                    && appState.editorStore.editableLedBrightness == 220 && appState.editorStore.editableLightingEffect == .staticColor && appState.editorStore.editableUSBLightingZoneID == "scroll_wheel" && appState.editorStore.editableColor == wheelColor
                    && appState.editorStore.lightingGradientDisplayColors == [wheelColor, logoColor, underglowColor] && appState.editorStore.buttonBindingKind(for: 4) == .mouseForward
            }
        }
        let busyAfterHardwareProfileLoad = await MainActor.run { appState.editorStore.isButtonProfileOperationInFlight || appState.editorStore.isOnboardProfileLoadInFlight }
        XCTAssertFalse(busyAfterHardwareProfileLoad)
    }

    func testLoadedActiveOnboardProfileDpiSurvivesStaleLiveDpiHydration() async throws {
        let device = makeRefactorTestDevice(id: "onboard-profile-dpi-live-overwrite-device", transport: .bluetooth, serial: "ONBOARD-PROFILE-DPI-LIVE-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [400, 800, 1300, 1600, 6400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))
            ])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)

        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.selectedOnboardProfileID == 2 && appState.editorStore.editableStageCount == 2 && appState.editorStore.stageValue(0) == 1200 && appState.editorStore.stageValue(1) == 2400 } }

        await MainActor.run {
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id,
                state: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 75, dpiValues: [400, 800, 1300, 1600, 6400], activeStage: 4), options: RefactorTestStateOptions(activeOnboardProfile: 2, onboardProfileCount: 5)),
                updatedAt: Date())
        }

        let hydrated = await MainActor.run { (appState.editorStore.editableStageCount, appState.editorStore.stageValue(0), appState.editorStore.stageValue(1), appState.editorStore.editableActiveStage) }
        XCTAssertEqual(hydrated.0, 2)
        XCTAssertEqual(hydrated.1, 1200)
        XCTAssertEqual(hydrated.2, 2400)
        XCTAssertEqual(hydrated.3, 1)
    }

    func testServiceActiveOnboardProfileUpdatesHydrateProfileUI() async throws {
        let device = makeRefactorTestDevice(id: "onboard-service-active-update-device", transport: .bluetooth, serial: "ONBOARD-SERVICE-ACTIVE-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 2, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 2, maxProfileID: 5, assignedProfileIDs: [1, 2, 3],
                profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: false), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: true), makeRefactorOnboardProfileSummary(profileID: 3, name: "Stored 3", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [800, 1600, 3200]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 3, name: "Stored 3", dpiValues: [1200, 2400]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .service, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.selectedOnboardProfileID == 2 && appState.editorStore.editableStageCount == 3 && appState.editorStore.stageValue(0) == 800 && appState.editorStore.stageValue(2) == 3200 } }

        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 3, maxProfileID: 5, assignedProfileIDs: [1, 2, 3],
                profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: false), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false), makeRefactorOnboardProfileSummary(profileID: 3, name: "Stored 3", isActive: true)]), forDeviceID: device.id)

        await MainActor.run {
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id, state: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 2, onboardProfileCount: 5)),
                updatedAt: Date())
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id, state: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [1200, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 3, onboardProfileCount: 5)),
                updatedAt: Date())
        }
        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.selectedOnboardProfileID == 3 && appState.editorStore.editableStageCount == 2 && appState.editorStore.stageValue(0) == 1200 && appState.editorStore.stageValue(1) == 2400 } }

        let listCount = await backend.onboardListCount(deviceID: device.id)
        let readCount = await backend.onboardReadCount(deviceID: device.id, profileID: 3)
        let coreReadCount = await backend.onboardCoreReadCount(deviceID: device.id, profileID: 3)
        let activations = await backend.recordedOnboardActivations()
        let loading = await MainActor.run { appState.editorStore.isOnboardProfileLoadInFlight }
        XCTAssertEqual(listCount, 1)
        XCTAssertEqual(readCount, 0)
        XCTAssertEqual(coreReadCount, 1)
        XCTAssertTrue(activations.isEmpty)
        XCTAssertFalse(loading)
    }

    func testRefreshingOnboardProfilesHydratesActiveLightingWhenNoSnapshotIsLoaded() async throws {
        let device = makeRefactorTestDevice(id: "onboard-refresh-lighting-device", transport: .usb, serial: "ONBOARD-REFRESH-LIGHTING-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let staleEditorColor = RGBColor(r: 1, g: 2, b: 3)
        let activeProfileColor = RGBColor(r: 255, g: 0, b: 180)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 2, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 2, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: false), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: true)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", brightnessByLEDID: [1: 210, 4: 210, 10: 210], staticColorByLEDID: [1: RGBPatch(r: activeProfileColor.r, g: activeProfileColor.g, b: activeProfileColor.b)]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.editableLightingEffect = .wave
            appState.editorStore.editableUSBLightingZoneID = "all"
            appState.editorStore.editableColor = staleEditorColor
        }

        await appState.editorStore.refreshOnboardProfiles()

        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.selectedOnboardProfileID == 2 && appState.editorStore.editableLightingEffect == .staticColor && appState.editorStore.editableLedBrightness == 210 && appState.editorStore.editableColor == activeProfileColor } }
        let activeReadCount = await backend.onboardReadCount(deviceID: device.id, profileID: 2)
        XCTAssertEqual(activeReadCount, 1)
    }

    func testBluetoothOnboardProfileRefreshHydratesMissingActiveSnapshotOnce() async throws {
        let device = makeRefactorTestDevice(id: "onboard-bt-refresh-inventory-only-device", transport: .bluetooth, serial: "ONBOARD-BT-REFRESH-INVENTORY-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 2, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 2, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: false), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: true)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400], brightnessByLEDID: [1: 210], staticColorByLEDID: [1: RGBPatch(r: 255, g: 0, b: 180)]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()

        await appState.editorStore.refreshOnboardProfiles()

        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.selectedOnboardProfileID == 2 && appState.editorStore.onboardProfileSummaries.first(where: { $0.isActive })?.profileID == 2 } }
        let listCount = await backend.onboardListCount(deviceID: device.id)
        let activeReadCount = await backend.onboardReadCount(deviceID: device.id, profileID: 2)
        let editableStageCount = await MainActor.run { appState.editorStore.editableStageCount }
        XCTAssertEqual(listCount, 1)
        XCTAssertEqual(activeReadCount, 1)
        XCTAssertEqual(editableStageCount, 2)

        await appState.editorStore.refreshOnboardProfiles()

        let listCountAfterSecondRefresh = await backend.onboardListCount(deviceID: device.id)
        let activeReadCountAfterSecondRefresh = await backend.onboardReadCount(deviceID: device.id, profileID: 2)
        XCTAssertEqual(listCountAfterSecondRefresh, 2)
        XCTAssertEqual(activeReadCountAfterSecondRefresh, 1)
    }

    func testBluetoothOnboardProfileRefreshDoesNotRollbackPendingDPIEdit() async throws {
        let device = makeRefactorTestDevice(id: "onboard-bt-refresh-dpi-race-device", transport: .bluetooth, serial: "ONBOARD-BT-REFRESH-DPI-RACE-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        await backend.setOnboardInventory(OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 1, name: "Base", dpiValues: [800, 1600, 3200], brightnessByLEDID: [1: 128], staticColorByLEDID: [1: RGBPatch(r: 0, g: 0, b: 255)]), forDeviceID: device.id)
        await backend.holdOnboardProfileRead(deviceID: device.id, profileID: 1)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()

        let refreshTask = Task { await appState.editorStore.refreshOnboardProfiles() }
        await backend.waitForOnboardProfileReadToStart(deviceID: device.id, profileID: 1)

        await MainActor.run {
            appState.editorStore.updateStage(0, value: 1200)
            appState.editorStore.scheduleAutoApplyDpi()
        }
        await backend.releaseOnboardProfileRead(deviceID: device.id, profileID: 1)
        await refreshTask.value

        let visibleDPIAfterStaleRefresh = await MainActor.run { appState.editorStore.stageValue(0) }
        XCTAssertEqual(visibleDPIAfterStaleRefresh, 1200, "Stale onboard-profile refresh rolled the pending DPI edit back in the visible editor state")

        try await waitForRefactorCondition { await backend.recordedOnboardUpdates().count == 1 }
        let updates = await backend.recordedOnboardUpdates()
        let finalVisibleDPI = await MainActor.run { appState.editorStore.stageValue(0) }
        XCTAssertEqual(updates.first?.mutation.dpi?.pairs.first?.x, 1200)
        XCTAssertEqual(finalVisibleDPI, 1200)
    }

    func testBluetoothLiveDpiPresentationDoesNotRollbackPendingOnboardDPIEdit() async throws {
        let device = makeRefactorTestDevice(id: "onboard-bt-live-dpi-pending-edit-device", transport: .bluetooth, serial: "ONBOARD-BT-LIVE-DPI-PENDING-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let staleState = makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))
        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: staleState])
        await backend.setOnboardInventory(OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 1, name: "Base", dpiValues: [800, 1600, 3200], brightnessByLEDID: [1: 128], staticColorByLEDID: [1: RGBPatch(r: 0, g: 0, b: 255)]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await MainActor.run {
            XCTAssertEqual(appState.editorStore.stageValue(0), 800)

            appState.editorStore.updateStage(0, value: 1200)
            appState.editorStore.scheduleAutoApplyDpi()
            appState.editorController.hydrateLiveDpiPresentation(from: staleState)

            XCTAssertEqual(appState.editorStore.stageValue(0), 1200, "Live DPI presentation should not rewrite visible stage values while a local DPI edit is pending")
        }
    }

    func testBluetoothBackendDPIUpdateSelectsStageFromLiveDPIWhenActiveStageIsStale() async throws {
        let device = makeRefactorTestDevice(id: "onboard-bt-live-dpi-stage-match-device", transport: .bluetooth, serial: "ONBOARD-BT-LIVE-DPI-STAGE-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let initialState = makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))
        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: initialState])

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()

        try await waitForRefactorCondition { await MainActor.run { appState.deviceStore.state?.dpi?.x == 800 && appState.editorStore.editableActiveStage == 1 && appState.editorStore.stageValue(2) == 3200 } }

        await MainActor.run {
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id,
                state: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0, dpiValue: 3200), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5)),
                updatedAt: Date().addingTimeInterval(1))
        }

        let visible = await MainActor.run { (appState.deviceStore.state?.dpi?.x, appState.deviceStore.state?.dpi_stages.active_stage, appState.editorStore.editableActiveStage, appState.editorStore.stageValue(2)) }
        XCTAssertEqual(visible.0, 3200)
        XCTAssertEqual(visible.1, 0)
        XCTAssertEqual(visible.2, 3, "The DPI stages card should follow the live DPI value even when the backend active-stage field is stale.")
        XCTAssertEqual(visible.3, 3200)
    }

}
