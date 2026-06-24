import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

/// Exercises app state onboard content behavior.
final class AppStateOnboardContentTests: XCTestCase {
    func testBluetoothOnboardStaleButtonEditDoesNotOverwriteNewSelectedProfile() async throws {
        let device = makeRefactorTestDevice(id: "onboard-bt-stale-button-edit-device", transport: .bluetooth, serial: "ONBOARD-BT-STALE-BUTTON-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [400, 800, 1300, 1600, 6400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))
            ])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 1, name: "Base", dpiValues: [400, 800, 1300, 1600, 6400], buttonBindings: [4: ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [400, 1200, 1300], buttonBindings: [4: ButtonBindingDraft(kind: .mouseForward, hidKey: 5, turboEnabled: false, turboRate: 0x8E)]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.selectedOnboardProfileID == 1 && appState.editorStore.editableStageCount == 5 && appState.editorStore.buttonBindingKind(for: 4) == .rightClick } }

        await backend.holdOnboardUpdate(deviceID: device.id, profileID: 1)
        await MainActor.run { appState.editorStore.updateButtonBindingKind(slot: 4, kind: .mouseBack) }
        await backend.waitForOnboardUpdateToStart(deviceID: device.id, profileID: 1)

        await appState.editorStore.selectOnboardProfile(2)
        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.selectedOnboardProfileID == 2 && appState.editorStore.editableStageCount == 3 && appState.editorStore.buttonBindingKind(for: 4) == .mouseForward } }

        let profile1ReadCountBeforeRelease = await backend.onboardReadCount(deviceID: device.id, profileID: 1)
        await backend.releaseOnboardUpdate(deviceID: device.id, profileID: 1)
        try await waitForRefactorCondition { await backend.onboardReadCount(deviceID: device.id, profileID: 1) > profile1ReadCountBeforeRelease }
        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.selectedOnboardProfileID == 2 && appState.editorStore.editableStageCount == 3 && appState.editorStore.buttonBindingKind(for: 4) == .mouseForward } }
    }

    func testBluetoothOnboardStaleButtonReadbackDoesNotOverwriteLocalEdit() async throws {
        let device = makeRefactorTestDevice(id: "onboard-bt-stale-button-readback-device", transport: .bluetooth, serial: "ONBOARD-BT-STALE-READBACK-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [400, 800, 1300, 1600, 6400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))
            ])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [400, 1200, 1300], buttonBindings: [4: ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E)]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        await backend.holdOnboardProfileButtonRead(deviceID: device.id, profileID: 2)
        let selectionTask = Task { await appState.editorStore.selectOnboardProfile(2) }
        await backend.waitForOnboardProfileButtonReadToStart(deviceID: device.id, profileID: 2)

        await MainActor.run { appState.editorStore.updateButtonBindingKind(slot: 4, kind: .mouseForward) }
        await backend.releaseOnboardProfileButtonRead(deviceID: device.id, profileID: 2)
        await selectionTask.value

        try await waitForRefactorCondition { await backend.recordedOnboardUpdates().contains { update in update.profileID == 2 && update.mutation.buttonBindings?[4]?.kind == .mouseForward } }

        let visibleKind = await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) }
        let updates = await backend.recordedOnboardUpdates()
        let buttonReadCount = await backend.onboardButtonReadCount(deviceID: device.id, profileID: 2)

        XCTAssertEqual(visibleKind, .mouseForward)
        XCTAssertEqual(updates.last?.profileID, 2)
        XCTAssertEqual(updates.last?.mutation.buttonBindings?[4]?.kind, .mouseForward)
        XCTAssertEqual(buttonReadCount, 1)
    }

    func testBluetoothOnboardProfileLightingEditUpdatesSelectedStoredProfile() async throws {
        let device = makeRefactorTestDevice(id: "onboard-bt-stored-lighting-device", transport: .bluetooth, serial: "ONBOARD-BT-STORED-LIGHTING-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [400, 800, 1300, 1600, 6400], activeStage: 2), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))
            ])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400], brightnessByLEDID: [1: 80, 4: 80, 10: 80], staticColorByLEDID: [1: RGBPatch(r: 0, g: 0, b: 255), 4: RGBPatch(r: 0, g: 0, b: 255), 10: RGBPatch(r: 0, g: 0, b: 255)]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)

        await MainActor.run {
            appState.editorStore.editableLedBrightness = 220
            appState.editorStore.scheduleAutoApplyLedBrightness()
        }

        try await waitForRefactorCondition {
            let updates = await backend.recordedOnboardUpdates()
            return updates.contains { update in update.profileID == 2 && update.mutation.brightnessByLEDID?[1] == 220 }
        }

        let applyCount = await backend.applyCount()
        let updates = await backend.recordedOnboardUpdates()
        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(updates.last?.profileID, 2)
        XCTAssertEqual(updates.last?.mutation.brightnessByLEDID?[1], 220)
    }

    func testIndividualUSBLightingZoneEditUpdatesOnlySelectedOnboardLED() async throws {
        let device = makeRefactorTestDevice(id: "onboard-usb-individual-lighting-device", transport: .usb, serial: "ONBOARD-USB-INDIVIDUAL-LIGHTING-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb-hid", batteryPercent: 88, dpiValues: [400, 800, 1300, 1600, 6400], activeStage: 2), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))
            ])
        await backend.setOnboardInventory(OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 1, name: "Base", brightnessByLEDID: [1: 80, 4: 80, 10: 80], staticColorByLEDID: [1: RGBPatch(r: 0, g: 0, b: 255), 4: RGBPatch(r: 0, g: 0, b: 255), 10: RGBPatch(r: 0, g: 0, b: 255)]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        await MainActor.run {
            appState.editorStore.editableLightingEffect = .staticColor
            appState.editorStore.editableUSBLightingZoneID = "logo"
            appState.editorStore.editableColor = RGBColor(r: 255, g: 0, b: 64)
            appState.editorStore.scheduleAutoApplyLightingEffect()
        }

        try await waitForRefactorCondition {
            let updates = await backend.recordedOnboardUpdates()
            return updates.contains { update in update.profileID == 1 && update.mutation.staticColorByLEDID == [4: RGBPatch(r: 255, g: 0, b: 64)] }
        }
    }

    func testScheduledOnboardProfileLightingApplyClearsPendingLocalEdits() async throws {
        let device = makeRefactorTestDevice(id: "onboard-scheduled-lighting-clears-pending-device", transport: .bluetooth, serial: "ONBOARD-SCHEDULED-LIGHTING-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "bluetooth", batteryPercent: 74, dpiValues: [400, 800, 1300, 1600, 6400], activeStage: 2), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))
            ])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400], brightnessByLEDID: [1: 80, 4: 80, 10: 80], staticColorByLEDID: [1: RGBPatch(r: 0, g: 0, b: 255), 4: RGBPatch(r: 0, g: 0, b: 255), 10: RGBPatch(r: 0, g: 0, b: 255)]), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)

        await MainActor.run {
            appState.editorStore.editableLedBrightness = 211
            appState.editorStore.scheduleAutoApplyLedBrightness()
        }

        try await waitForRefactorCondition {
            let updates = await backend.recordedOnboardUpdates()
            return updates.contains { update in update.profileID == 2 && update.mutation.brightnessByLEDID?[1] == 211 }
        }

        try await waitForRefactorCondition { await MainActor.run { appState.applyController.shouldHydrateEditable(for: device) } }
    }

    func testSelectedUSBOnboardProfileScrollEditUpdatesStoredProfile() async throws {
        let device = makeRefactorTestDevice(id: "onboard-scroll-edit-device", transport: .usb, serial: "ONBOARD-SCROLL-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400], scrollMode: 1, scrollAcceleration: true, scrollSmartReel: false), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)
        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.selectedOnboardProfileID == 2 && appState.editorStore.onboardProfileSummaries.first(where: { $0.profileID == 2 })?.isActive == true && appState.editorStore.editableScrollMode == 1 && appState.editorStore.editableScrollAcceleration == true
                    && appState.editorStore.editableScrollSmartReel == false
            }
        }

        await MainActor.run {
            appState.editorStore.editableScrollMode = 0
            appState.editorStore.scheduleAutoApplyScrollMode()
            appState.editorStore.editableScrollAcceleration = false
            appState.editorStore.scheduleAutoApplyScrollAcceleration()
            appState.editorStore.editableScrollSmartReel = true
            appState.editorStore.scheduleAutoApplyScrollSmartReel()
        }

        try await waitForRefactorCondition { await backend.recordedOnboardUpdates().count == 3 }

        let updates = await backend.recordedOnboardUpdates()
        let applyCount = await backend.applyCount()
        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(updates.map(\.profileID), [2, 2, 2])
        XCTAssertEqual(updates.compactMap { $0.mutation.scrollMode }, [0])
        XCTAssertEqual(updates.compactMap { $0.mutation.scrollAcceleration }, [false])
        XCTAssertEqual(updates.compactMap { $0.mutation.scrollSmartReel }, [true])
    }

    func testLiveUSBScrollStateHydratesOverStaleActiveOnboardSnapshot() async throws {
        let device = makeRefactorTestDevice(id: "live-scroll-hydration-device", transport: .usb, serial: "LIVE-SCROLL-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let initialState = makeRefactorTestState(
            device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5, scrollMode: 0, scrollAcceleration: false, scrollSmartReel: false)
        )
        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: initialState])
        await backend.setOnboardInventory(OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 1, name: "Base", scrollMode: 0, scrollAcceleration: false, scrollSmartReel: false), forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        try await waitForRefactorCondition { await backend.onboardReadCount(deviceID: device.id, profileID: 1) > 0 }

        let updatedState = makeRefactorTestState(
            device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5, scrollMode: 1, scrollAcceleration: false, scrollSmartReel: false)
        )
        await backend.setState(updatedState, forDeviceID: device.id)

        let refreshed = await appState.deviceController.refreshState(for: device)
        XCTAssertTrue(refreshed)
        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.editableScrollMode == 1 } }
    }

    func testFailedOnboardProfileDpiEditDoesNotFallbackToLiveApply() async throws {
        let device = makeRefactorTestDevice(id: "onboard-dpi-failure-device", transport: .usb, serial: "ONBOARD-DPI-FAILURE-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 3200], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        await backend.setOnboardInventory(
            OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1, 2], profiles: [makeRefactorOnboardProfileSummary(profileID: 1, name: "Base", isActive: true), makeRefactorOnboardProfileSummary(profileID: 2, name: "Stored 2", isActive: false)]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(makeRefactorOnboardProfileSnapshot(profileID: 2, name: "Stored 2", dpiValues: [1200, 2400]), forDeviceID: device.id)
        await backend.setOnboardUpdateFailure("stored profile write unavailable")

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.selectOnboardProfile(2)
        await MainActor.run {
            appState.editorStore.editableStageCount = 2
            appState.editorStore.editableStagePairs = [DpiPair(x: 1500, y: 1500), DpiPair(x: 2600, y: 2600), DpiPair(x: 3200, y: 3200), DpiPair(x: 6400, y: 6400), DpiPair(x: 12000, y: 12000)]
            appState.editorStore.editableActiveStage = 2
        }

        await appState.editorStore.applyDpiStages()

        let updates = await backend.recordedOnboardUpdates()
        let applyCount = await backend.applyCount()
        let errorMessage = await MainActor.run { appState.deviceStore.errorMessage }
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(errorMessage, "Failed to update onboard profile: stored profile write unavailable")
    }
}
