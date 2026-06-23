import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

final class AppStateApplyAndDPICharacterizationTests: XCTestCase {
    func testNewlyEnabledDPIStageSeedsDistinctValueBeforeApply() async {
        let appState = await MainActor.run {
            AppState(
                launchRole: .app,
                backend: AppStateRefactorStubBackend(devices: [], stateByDeviceID: [:]),
                autoStart: false
            )
        }

        await MainActor.run {
            appState.editorStore.editableStageCount = 1
            appState.editorStore.editableStageValues = [1200, 1200, 3200, 6400, 12000]
            appState.editorStore.seedNewlyEnabledDPIStage(at: 1)

            XCTAssertEqual(appState.editorStore.stageValue(0), 1200)
            XCTAssertEqual(appState.editorStore.stageValue(1), 800)
        }
    }

    func testApplyWithoutSelectedDeviceShowsNoDeviceSelectedError() async throws {
        let backend = AppStateRefactorStubBackend(devices: [], stateByDeviceID: [:])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.editorStore.applyPollRate()

        try await waitForRefactorCondition {
            await MainActor.run { appState.deviceStore.errorMessage == "No device selected" }
        }

        let applyCount = await backend.applyCount()
        XCTAssertEqual(applyCount, 0)
    }

    func testQueuedAppliesStaySerializedAndDoNotHydrateOverNewerDrafts() async throws {
        let device = makeRefactorTestDevice(
            id: "queued-apply-device",
            transport: .usb,
            serial: "QUEUE-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 81,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 0
                    )
                )
            ],
            holdFirstApply: true
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.editablePollRate = 500
        }
        await appState.editorStore.applyPollRate()
        await backend.waitForFirstApplyToStart()

        await MainActor.run {
            appState.editorStore.editablePollRate = 250
        }
        await appState.editorStore.applyPollRate()
        await backend.releaseFirstApply()

        try await waitForRefactorCondition(timeout: 2.0) {
            await backend.applyCount() == 2
        }

        let patches = await backend.recordedPatches()
        let maxConcurrentApplies = await backend.maxConcurrentApplies()
        let editablePollRate = await MainActor.run { appState.editorStore.editablePollRate }
        let livePollRate = await MainActor.run { appState.deviceStore.state?.poll_rate }

        XCTAssertEqual(maxConcurrentApplies, 1)
        XCTAssertEqual(patches.map(\.pollRate), [500, 250])
        XCTAssertEqual(editablePollRate, 250)
        XCTAssertEqual(livePollRate, 250)
    }

    func testStageApplySuppressesFastPollingTemporarily() async throws {
        let device = makeRefactorTestDevice(
            id: "dpi-stage-device",
            transport: .usb,
            serial: "DPI-\(UUID().uuidString)",
            onboardProfileCount: 1
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
                    )
                )
            ],
            shouldUseFastPolling: true
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.editableStageCount = 3
            appState.editorStore.editableStageValues = [1000, 2000, 3000, 6400, 12000]
            appState.editorStore.editableActiveStage = 3
        }
        await appState.editorStore.applyDpiStages()

        try await waitForRefactorCondition {
            await backend.applyCount() >= 1
        }

        await appState.deviceStore.refreshDpiFast()
        let initialFastReadCount = await backend.fastReadCount()
        XCTAssertEqual(initialFastReadCount, 0)

        try await Task.sleep(nanoseconds: 1_000_000_000)

        await appState.deviceStore.refreshDpiFast()
        let finalFastReadCount = await backend.fastReadCount()
        XCTAssertEqual(finalFastReadCount, 1)
    }

    func testStageApplyPreservesExactNonHundredDpiValues() async throws {
        let device = makeRefactorTestDevice(
            id: "dpi-exact-device",
            transport: .usb,
            serial: "DPI-EXACT-\(UUID().uuidString)",
            onboardProfileCount: 1
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
                    )
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.editableStageCount = 3
            appState.editorStore.editableStageValues = [1555, 2444, 3777, 6400, 12000]
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 1555, y: 1555),
                DpiPair(x: 2444, y: 2444),
                DpiPair(x: 3777, y: 3777),
                DpiPair(x: 6400, y: 6400),
                DpiPair(x: 12000, y: 12000)
            ]
            appState.editorStore.editableActiveStage = 2
        }
        await appState.editorStore.applyDpiStages()

        try await waitForRefactorCondition {
            await backend.applyCount() == 1
        }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.first)
        XCTAssertEqual(patch.dpiStages, [1555, 2444, 3777])
        XCTAssertEqual(
            patch.dpiStagePairs,
            [
                DpiPair(x: 1555, y: 1555),
                DpiPair(x: 2444, y: 2444),
                DpiPair(x: 3777, y: 3777)
            ]
        )
        XCTAssertEqual(patch.activeStage, 1)
    }

    func testActiveStageSelectionAppliesActiveStageOnly() async throws {
        let device = makeRefactorTestDevice(
            id: "active-stage-only-device",
            transport: .usb,
            serial: "ACTIVE-STAGE-ONLY-\(UUID().uuidString)",
            onboardProfileCount: 1
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
                    )
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.editableStageCount = 3
            appState.editorStore.editableStageValues = [800, 1600, 3200, 6400, 12000]
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 800, y: 800),
                DpiPair(x: 1600, y: 1600),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400),
                DpiPair(x: 12000, y: 12000)
            ]
            appState.editorStore.editableActiveStage = 3
            appState.editorStore.scheduleAutoApplyActiveStage()
        }

        try await waitForRefactorCondition {
            await backend.applyCount() == 1
        }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.first)
        XCTAssertNil(patch.dpiStages)
        XCTAssertNil(patch.dpiStagePairs)
        XCTAssertEqual(patch.activeStage, 2)
    }

    func testPendingActiveStageSelectionDoesNotFlapOnStaleBackendState() async throws {
        let device = makeRefactorTestDevice(
            id: "active-stage-no-flap-device",
            transport: .usb,
            serial: "ACTIVE-STAGE-NO-FLAP-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        let staleState = makeRefactorTestState(
            device: device,
            telemetry: RefactorTestStateTelemetry(
                connection: "usb",
                batteryPercent: 74,
                dpiValues: [800, 1600, 3200],
                activeStage: 0
            )
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: staleState]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.editableStageCount = 3
            appState.editorStore.editableStageValues = [800, 1600, 3200, 6400, 12000]
            appState.editorStore.editableStagePairs = [
                DpiPair(x: 800, y: 800),
                DpiPair(x: 1600, y: 1600),
                DpiPair(x: 3200, y: 3200),
                DpiPair(x: 6400, y: 6400),
                DpiPair(x: 12000, y: 12000)
            ]
            appState.editorStore.editableActiveStage = 3
            appState.editorStore.scheduleAutoApplyActiveStage()
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id,
                state: staleState,
                updatedAt: Date().addingTimeInterval(0.1)
            )
        }

        let activeAfterStaleUpdate = await MainActor.run {
            appState.editorStore.editableActiveStage
        }
        XCTAssertEqual(activeAfterStaleUpdate, 3)

        try await waitForRefactorCondition {
            await backend.applyCount() == 1
        }
        let activeAfterApply = await MainActor.run {
            appState.editorStore.editableActiveStage
        }
        XCTAssertEqual(activeAfterApply, 3)
    }

    func testOnboardActiveStageSelectionWaitsForLiveConfirmationBeforeHydratingStaleState() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-active-stage-no-flap-device",
            transport: .usb,
            serial: "ONBOARD-ACTIVE-STAGE-NO-FLAP-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        let dpiValues = [600, 800, 1000, 1200, 1400]
        let staleState = makeRefactorTestState(
            device: device,
            telemetry: RefactorTestStateTelemetry(
                connection: "usb",
                batteryPercent: 74,
                dpiValues: dpiValues,
                activeStage: 4
            ),
            options: RefactorTestStateOptions(
                activeOnboardProfile: 1,
                onboardProfileCount: 5
            )
        )
        let confirmedState = makeRefactorTestState(
            device: device,
            telemetry: RefactorTestStateTelemetry(
                connection: "usb",
                batteryPercent: 74,
                dpiValues: dpiValues,
                activeStage: 0
            ),
            options: RefactorTestStateOptions(
                activeOnboardProfile: 1,
                onboardProfileCount: 5
            )
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: staleState]
        )
        await backend.setOnboardInventory(
            OnboardProfileInventory(
                activeProfileID: 1,
                maxProfileID: 5,
                assignedProfileIDs: [1],
                profiles: [
                    makeRefactorOnboardProfileSummary(profileID: 1, name: "Main", isActive: true)
                ]
            ),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(
            makeRefactorOnboardProfileSnapshot(
                profileID: 1,
                name: "Main",
                dpiValues: dpiValues,
                activeStage: 4
            ),
            forDeviceID: device.id
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.selectedOnboardProfileID == 1 &&
                    appState.editorStore.editableActiveStage == 5
            }
        }

        await MainActor.run {
            appState.editorStore.setEditableActiveStage(1, source: "test.onboardActiveStage")
            appState.editorStore.scheduleAutoApplyActiveStage()
        }

        try await waitForRefactorCondition {
            await backend.recordedOnboardUpdates().count == 1
        }
        await MainActor.run {
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id,
                state: staleState,
                updatedAt: Date().addingTimeInterval(1)
            )
        }

        let activeAfterStaleUpdate = await MainActor.run {
            appState.editorStore.editableActiveStage
        }
        XCTAssertEqual(activeAfterStaleUpdate, 1)

        await MainActor.run {
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id,
                state: confirmedState,
                updatedAt: Date().addingTimeInterval(2)
            )
        }

        let activeAfterConfirmation = await MainActor.run {
            appState.editorStore.editableActiveStage
        }
        let canHydrateAfterConfirmation = await MainActor.run {
            appState.applyController.shouldHydrateEditable(for: device)
        }
        XCTAssertEqual(activeAfterConfirmation, 1)
        XCTAssertTrue(canHydrateAfterConfirmation)
    }

    func testHydratedEditableDpiStagesClampToSelectedDeviceLimit() async throws {
        let device = makeRefactorTestDevice(
            id: "dpi-clamp-device",
            transport: .bluetooth,
            serial: "DPI-CLAMP-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "bluetooth",
                        batteryPercent: 74,
                        dpiValues: [800, 20_000, 24_000],
                        activeStage: 1
                    )
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        try await waitForRefactorCondition {
            await MainActor.run { appState.editorStore.stageValue(1) == 18_000 }
        }

        let editableValues = await MainActor.run {
            Array(appState.editorStore.editableStageValues.prefix(appState.editorStore.editableStageCount))
        }
        let selectedDPIRange = await MainActor.run {
            DeviceProfiles.dpiRange(for: appState.editorStore.selectedDeviceProfileID)
        }

        XCTAssertEqual(editableValues, [800, 18_000, 18_000])
        XCTAssertEqual(selectedDPIRange, 100...18_000)
    }

}
