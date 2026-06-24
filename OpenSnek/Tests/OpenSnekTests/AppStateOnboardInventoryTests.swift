import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

/// Exercises app state onboard inventory behavior.
final class AppStateOnboardInventoryTests: XCTestCase {
    func testOnboardProfileSummariesGetterDoesNotStartRefresh() async throws {
        let device = makeRefactorTestDevice(id: "onboard-pure-summary-device", transport: .bluetooth, serial: "ONBOARD-PURE-SUMMARY-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 2, onboardProfileCount: 5))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()

        let summaries = await MainActor.run { appState.editorStore.onboardProfileSummaries }
        for _ in 0..<5 { await Task.yield() }

        let listCount = await backend.onboardListCount(deviceID: device.id)
        XCTAssertTrue(summaries.isEmpty)
        XCTAssertEqual(listCount, 0)
    }

    func testRefreshingOnboardProfilesUsesPillLoadingWithoutBlockingGlobalEditorControls() async throws {
        let device = makeRefactorTestDevice(id: "onboard-nonblocking-refresh-device", transport: .bluetooth, serial: "ONBOARD-NONBLOCKING-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        await backend.setOnboardInventory(OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true)]), forDeviceID: device.id)
        await backend.holdOnboardProfileList(deviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()

        async let refresh: Void = appState.editorStore.refreshOnboardProfiles()
        await backend.waitForOnboardProfileListToStart(deviceID: device.id)

        let operationState = await MainActor.run { (appState.editorStore.isButtonProfileOperationInFlight, appState.editorStore.isOnboardProfileRefreshInFlight, appState.editorStore.isOnboardProfilePillLoading) }
        XCTAssertFalse(operationState.0)
        XCTAssertTrue(operationState.1)
        XCTAssertTrue(operationState.2)

        await backend.releaseOnboardProfileList(deviceID: device.id)
        await refresh

        let finalRefreshState = await MainActor.run { (appState.editorStore.isOnboardProfileRefreshInFlight, appState.editorStore.isOnboardProfilePillLoading) }
        XCTAssertFalse(finalRefreshState.0)
        XCTAssertFalse(finalRefreshState.1)
    }

    func testFailedOnboardProfileRefreshClearsCardLoadingState() async throws {
        let device = makeRefactorTestDevice(id: "onboard-failed-refresh-device", transport: .bluetooth, serial: "ONBOARD-FAILED-REFRESH-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        await backend.setOnboardListFailure("inventory unavailable")

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        let refreshState = await MainActor.run {
            (appState.editorStore.isButtonProfileOperationInFlight, appState.editorStore.isOnboardProfileRefreshInFlight, appState.editorStore.onboardProfileRefreshErrorMessage, appState.editorStore.onboardProfileSummaries.isEmpty, appState.deviceStore.errorMessage)
        }
        XCTAssertFalse(refreshState.0)
        XCTAssertFalse(refreshState.1)
        XCTAssertEqual(refreshState.2, "Failed to refresh onboard profiles: inventory unavailable")
        XCTAssertTrue(refreshState.3)
        XCTAssertNil(refreshState.4)
    }

    func testConcurrentOnboardProfileRefreshesAreCoalesced() async throws {
        let device = makeRefactorTestDevice(id: "onboard-coalesced-refresh-device", transport: .bluetooth, serial: "ONBOARD-COALESCED-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 2, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 2, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: false), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: true)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2"), forDeviceID: device.id)
        await backend.holdOnboardProfileList(deviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()

        async let firstRefresh: Void = appState.editorStore.refreshOnboardProfiles()
        await backend.waitForOnboardProfileListToStart(deviceID: device.id)
        await appState.editorStore.refreshOnboardProfiles()

        let listCountWhileHeld = await backend.onboardListCount(deviceID: device.id)
        let readCountWhileHeld = await backend.onboardReadCount(deviceID: device.id, profileID: 2)
        XCTAssertEqual(listCountWhileHeld, 1)
        XCTAssertEqual(readCountWhileHeld, 0)

        await backend.releaseOnboardProfileList(deviceID: device.id)
        await firstRefresh

        let finalListCount = await backend.onboardListCount(deviceID: device.id)
        let finalReadCount = await backend.onboardReadCount(deviceID: device.id, profileID: 2)
        XCTAssertEqual(finalListCount, 1)
        XCTAssertEqual(finalReadCount, 1)
    }

    func testSupersededHardwareOnboardProfileLoadClearsBusyStateBeforeCancelledReadReturns() async throws {
        let device = makeRefactorTestDevice(id: "onboard-superseded-load-device", transport: .usb, serial: "ONBOARD-SUPERSEDED-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [1200, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 2, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 2, maxProfileID: 5, assignedProfileIDs: [1, 2, 3],
                profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: false), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: true), makeRefactorOnboardProfileSummary(profileID: 3, name: "Stored 3", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 3, name: "Stored 3", dpiValues: [3200, 6400]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)

        await backend.holdOnboardProfileRead(deviceID: device.id, profileID: 3)
        defer { Task { await backend.releaseOnboardProfileRead(deviceID: device.id, profileID: 3) } }
        await MainActor.run {
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id, state: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [3200, 6400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 3, onboardProfileCount: 5)),
                updatedAt: Date())
        }
        await backend.waitForOnboardProfileReadToStart(deviceID: device.id, profileID: 3)
        let busyDuringSupersededRead = await MainActor.run { !appState.editorStore.isButtonProfileOperationInFlight && appState.editorStore.isOnboardProfileLoadInFlight }
        XCTAssertTrue(busyDuringSupersededRead)

        await MainActor.run {
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id, state: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [1200, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 2, onboardProfileCount: 5)),
                updatedAt: Date())
        }

        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.selectedOnboardProfileID == 2 && appState.editorStore.stageValue(0) == 1200 && !appState.editorStore.isButtonProfileOperationInFlight && !appState.editorStore.isOnboardProfileLoadInFlight } }

        await backend.releaseOnboardProfileRead(deviceID: device.id, profileID: 3)
    }

    func testSelectingInactiveOnboardProfileReadsSnapshotAfterActivation() async throws {
        let device = makeRefactorTestDevice(id: "onboard-preload-activation-device", transport: .usb, serial: "ONBOARD-PRELOAD-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        await appState.editorStore.selectOnboardProfile(2)

        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.selectedOnboardProfileID == 2 && appState.deviceStore.state?.active_onboard_profile == 2 && appState.editorStore.stageValue(0) == 1200 } }
        let events = await backend.recordedOnboardEvents()
        XCTAssertEqual(Array(events.prefix(3)), ["read:1", "activate:2", "read-core:2"])
        let readCount = await backend.onboardReadCount(deviceID: device.id, profileID: 2)
        let coreReadCount = await backend.onboardCoreReadCount(deviceID: device.id, profileID: 2)
        XCTAssertEqual(readCount, 0)
        XCTAssertEqual(coreReadCount, 1)
    }

    func testOnboardProfileInventoryShowsEmptySlotsAndCreatesIntoSelectedSlot() async throws {
        let device = makeRefactorTestDevice(id: "onboard-empty-slot-device", transport: .usb, serial: "ONBOARD-EMPTY-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 3], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 3, name: "Stored 3", isActive: false)]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        let profileColor = RGBColor(r: 18, g: 52, b: 86)
        await MainActor.run {
            appState.editorStore.editableLightingEffect = .staticColor
            appState.editorStore.editableColor = profileColor
        }

        let initialSummaries = await MainActor.run { appState.editorStore.onboardProfileSummaries }
        XCTAssertEqual(initialSummaries.map(\.profileID), [1, 2, 3, 4, 5])
        XCTAssertEqual(initialSummaries.first(where: { $0.profileID == 2 })?.isAssigned, false)
        XCTAssertEqual(initialSummaries.first(where: { $0.profileID == 2 })?.displayName, "Profile 2")

        await appState.editorStore.selectOnboardProfile(2)
        let selectedBeforeCreate = await MainActor.run { appState.editorStore.selectedOnboardProfileID }
        let nameBeforeCreate = await MainActor.run { appState.editorStore.selectedOnboardProfileName }
        XCTAssertEqual(selectedBeforeCreate, 2)
        XCTAssertEqual(nameBeforeCreate, "None")

        await appState.editorStore.createOnboardProfile(name: "Work", targetProfileID: 2)

        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })?.isAssigned == true && appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })?.displayName == "Work"
                    && appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })?.isActive == true && appState.deviceStore.state?.active_onboard_profile == 2
            }
        }

        let creates = await backend.recordedOnboardCreates()
        XCTAssertEqual(creates.first?.targetProfileID, 2)
        let activations = await backend.recordedOnboardActivations()
        XCTAssertEqual(activations.map(\.profileID), [2])
        let listCountAfterCreate = await backend.onboardListCount(deviceID: device.id)
        XCTAssertEqual(listCountAfterCreate, 1)
        let errorMessage = await MainActor.run { appState.deviceStore.errorMessage }
        XCTAssertNil(errorMessage)
        XCTAssertEqual(creates.first?.mutation.staticColorByLEDID, [1: RGBPatch(r: profileColor.r, g: profileColor.g, b: profileColor.b), 4: RGBPatch(r: profileColor.r, g: profileColor.g, b: profileColor.b), 10: RGBPatch(r: profileColor.r, g: profileColor.g, b: profileColor.b)])
    }

    func testCreatingOnboardProfileUpdatesVisibleNameWhenInventoryWasInvalidated() async throws {
        let device = makeRefactorTestDevice(id: "onboard-invalidated-create-device", transport: .usb, serial: "ONBOARD-INVALIDATED-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        await backend.setOnboardInventory(OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true)]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await MainActor.run { appState.editorController.invalidateOnboardProfileState(for: [device.id]) }

        await appState.editorStore.createOnboardProfile(name: "Fresh Slot", targetProfileID: 2)

        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.selectedOnboardProfileID == 2 && appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })?.isAssigned == true && appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })?.displayName == "Fresh Slot"
                    && appState.editorStore.selectedOnboardProfileName == "Fresh Slot"
            }
        }
        let listCount = await backend.onboardListCount(deviceID: device.id)
        XCTAssertEqual(listCount, 1)
    }

    func testSelectingOnboardProfileRereadsDeviceSnapshot() async throws {
        let device = makeRefactorTestDevice(id: "onboard-cache-select-device", transport: .usb, serial: "ONBOARD-CACHE-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 2, 3],
                profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false), makeRefactorOnboardProfileSummary(profileID: 3, name: "Stored 3", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 3, name: "Stored 3", dpiValues: [3200, 6400]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        await appState.editorStore.selectOnboardProfile(2)
        let profile2ReadCountAfterFirstSelect = await backend.onboardCoreReadCount(deviceID: device.id, profileID: 2)
        XCTAssertEqual(profile2ReadCountAfterFirstSelect, 1)

        await appState.editorStore.selectOnboardProfile(3)
        let profile3ReadCountAfterSelect = await backend.onboardCoreReadCount(deviceID: device.id, profileID: 3)
        XCTAssertEqual(profile3ReadCountAfterSelect, 1)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1500, 2500]), forDeviceID: device.id)

        await appState.editorStore.selectOnboardProfile(2)
        let reloadedStage = await MainActor.run { appState.editorStore.stageValue(0) }
        let profile2ReadCountAfterReloadedSelect = await backend.onboardCoreReadCount(deviceID: device.id, profileID: 2)
        XCTAssertEqual(profile2ReadCountAfterReloadedSelect, 2)
        XCTAssertEqual(reloadedStage, 1500)
        let activations = await backend.recordedOnboardActivations()
        XCTAssertEqual(activations.map(\.profileID), [2, 3, 2])
    }

    func testSameIDReconnectInvalidatesLoadedOnboardProfileSnapshot() async throws {
        let device = makeRefactorTestDevice(id: "onboard-reconnect-profile-device", transport: .usb, serial: "ONBOARD-RECONNECT-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 1, name: "Base", dpiValues: [800, 1600]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(1)
        let initialReadCount = await backend.onboardReadCount(deviceID: device.id, profileID: 1)
        let initialCoreReadCount = await backend.onboardCoreReadCount(deviceID: device.id, profileID: 1)
        XCTAssertGreaterThanOrEqual(initialReadCount, 1)

        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 1, name: "Base", dpiValues: [1400, 2800]), forDeviceID: device.id)
        await MainActor.run {
            _ = appState.deviceController.applyDeviceList([device], source: "subscription")
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id, state: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5)),
                updatedAt: Date())
        }

        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.selectedOnboardProfileID == 1 && appState.editorStore.stageValue(0) == 1400 } }
        let reloadedReadCount = await backend.onboardReadCount(deviceID: device.id, profileID: 1)
        let reloadedCoreReadCount = await backend.onboardCoreReadCount(deviceID: device.id, profileID: 1)
        XCTAssertEqual(reloadedReadCount, initialReadCount)
        XCTAssertGreaterThan(reloadedCoreReadCount, initialCoreReadCount)
    }

}
