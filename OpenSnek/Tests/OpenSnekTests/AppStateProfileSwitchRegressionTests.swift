import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

/// Verifies V3 Pro profile-switch hydration regressions.
final class AppStateProfileSwitchRegressionTests: XCTestCase {
    func testMappedProfileSwitchProjectsActiveSnapshotDPIIntoSelectedState() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeProfileSwitchDevice(id: "profile-switch-dpi-state")
        let travelProfile = makeProfileSwitchTravelProfile(sourceDevice: device)
        let travelIdentifier = try XCTUnwrap(travelProfile.onboardIdentifier)
        let baseSnapshot = makeProfileSwitchSnapshot(
            profileID: 1,
            identifier: UUID(),
            name: "Base",
            dpiValues: [800, 1600, 3200, 6400, 12_000],
            activeStage: 0
        )
        let travelSnapshot = makeProfileSwitchSnapshot(
            profileID: 2,
            identifier: travelIdentifier,
            name: "V3 Pro Travel",
            dpiValues: [600, 30_000],
            activeStage: 1
        )
        let backend = makeProfileSwitchBackend(
            device: device,
            activeProfile: 1,
            dpiValues: [800, 1600, 3200, 6400, 12_000]
        )
        await backend.setOnboardInventory(
            makeProfileSwitchInventory(activeProfile: 1, maxProfileID: 5, snapshots: [baseSnapshot, travelSnapshot]),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(baseSnapshot, forDeviceID: device.id)
        await backend.setOnboardSnapshot(travelSnapshot, forDeviceID: device.id)

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        await appState.editorStore.selectOnboardProfile(2)

        let selectedState = await MainActor.run {
            (
                appState.deviceStore.state?.active_onboard_profile,
                appState.deviceStore.state?.dpi?.x,
                appState.deviceStore.state?.dpi_stages.active_stage,
                appState.deviceStore.state?.dpi_stages.values,
                appState.editorStore.editableStageCount,
                Array(appState.editorStore.editableStagePairs.prefix(2)).map(\.x)
            )
        }
        XCTAssertEqual(selectedState.0, 2)
        XCTAssertEqual(selectedState.1, 30_000)
        XCTAssertEqual(selectedState.2, 1)
        XCTAssertEqual(selectedState.3, [600, 30_000])
        XCTAssertEqual(selectedState.4, 2)
        XCTAssertEqual(selectedState.5, [600, 30_000])
    }

    func testConnectHydrationDoesNotReplaceReducedActiveProfileWithRawPaddedDPIStages() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeProfileSwitchDevice(id: "profile-switch-connect-dpi-state")
        let baseSnapshot = makeProfileSwitchSnapshot(
            profileID: 1,
            identifier: UUID(),
            name: "Base",
            dpiValues: [800, 1600, 3200, 6400, 12_000],
            activeStage: 0
        )
        let workSnapshot = makeProfileSwitchSnapshot(
            profileID: 2,
            identifier: UUID(),
            name: "Work",
            dpiValues: [600, 30_000],
            activeStage: 1
        )
        let backend = makeProfileSwitchBackend(
            device: device,
            activeProfile: 2,
            dpiValues: [600, 30_000, 8000, 12_000, 16_000]
        )
        await backend.setOnboardInventory(
            makeProfileSwitchInventory(activeProfile: 2, maxProfileID: 5, snapshots: [baseSnapshot, workSnapshot]),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(baseSnapshot, forDeviceID: device.id)
        await backend.setOnboardSnapshot(workSnapshot, forDeviceID: device.id)

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()

        let connectHydrationState = await MainActor.run {
            (
                appState.editorStore.selectedOnboardProfileID,
                appState.deviceStore.state?.active_onboard_profile,
                appState.deviceStore.state?.dpi_stages.values,
                appState.editorStore.editableStageCount
            )
        }
        XCTAssertEqual(connectHydrationState.0, 2)
        XCTAssertEqual(connectHydrationState.1, 2)
        XCTAssertEqual(connectHydrationState.2, [600, 30_000, 8000, 12_000, 16_000])
        XCTAssertNotEqual(connectHydrationState.3, 5)

        try await waitForRefactorCondition {
            await MainActor.run {
                appState.editorStore.selectedOnboardProfileID == 2 &&
                    appState.editorStore.editableStageCount == 2 &&
                    appState.editorStore.stageValue(0) == 600 &&
                    appState.editorStore.stageValue(1) == 30_000
            }
        }

        let profileHydrationState = await MainActor.run {
            (
                appState.deviceStore.state?.dpi_stages.values,
                appState.editorStore.editableStageCount,
                Array(appState.editorStore.editableStagePairs.prefix(2)).map(\.x)
            )
        }
        XCTAssertEqual(profileHydrationState.0, [600, 30_000])
        XCTAssertEqual(profileHydrationState.1, 2)
        XCTAssertEqual(profileHydrationState.2, [600, 30_000])

        try await waitForRefactorCondition {
            await backend.recordedOnboardDPIProjections().count == 1
        }
        let listCount = await backend.onboardListCount(deviceID: device.id)
        let coreReadCount = await backend.onboardCoreReadCount(deviceID: device.id, profileID: 2)
        let dpiProjections = await backend.recordedOnboardDPIProjections()
        XCTAssertEqual(listCount, 1)
        XCTAssertEqual(coreReadCount, 1)
        XCTAssertEqual(dpiProjections.count, 1)
        XCTAssertEqual(dpiProjections.first?.deviceID, device.id)
        XCTAssertEqual(dpiProjections.first?.profileID, 2)
        XCTAssertEqual(dpiProjections.first?.dpi.values, [600, 30_000])
    }

    func testMappedProfileSwitchPreservesKnownAdvancedLightingEffect() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeProfileSwitchDevice(id: "profile-switch-lighting-effect")
        let travelProfile = makeProfileSwitchTravelProfile(sourceDevice: device)
        let travelIdentifier = try XCTUnwrap(travelProfile.onboardIdentifier)
        let baseSnapshot = makeProfileSwitchSnapshot(
            profileID: 1,
            identifier: UUID(),
            name: "Base",
            dpiValues: [800, 1600, 3200],
            activeStage: 0
        )
        let travelSnapshot = makeProfileSwitchSnapshot(
            profileID: 2,
            identifier: travelIdentifier,
            name: "V3 Pro Travel",
            dpiValues: [600, 30_000],
            activeStage: 1
        )
        let backend = makeProfileSwitchBackend(device: device, activeProfile: 1, dpiValues: [800, 1600, 3200])
        await backend.setOnboardInventory(
            makeProfileSwitchInventory(activeProfile: 1, maxProfileID: 5, snapshots: [baseSnapshot, travelSnapshot]),
            forDeviceID: device.id
        )
        await backend.setOnboardSnapshot(baseSnapshot, forDeviceID: device.id)
        await backend.setOnboardSnapshot(travelSnapshot, forDeviceID: device.id)

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()

        await appState.editorStore.selectOnboardProfile(2)

        let lightingState = await MainActor.run {
            (
                appState.editorStore.editableLightingEffect,
                appState.editorStore.editableLightingWaveDirection,
                DevicePreferenceStore()
                    .loadOpenSnekLocalProfiles()
                    .first { $0.onboardIdentifier == travelIdentifier }?
                    .content
                    .lightingEffect
            )
        }
        XCTAssertEqual(lightingState.0, .wave)
        XCTAssertEqual(lightingState.1, .right)
        XCTAssertEqual(lightingState.2?.kind, .wave)
        XCTAssertEqual(lightingState.2?.waveDirection, .right)
    }
}

private func makeProfileSwitchDevice(id: String) -> MouseDevice {
    makeRefactorTestDevice(
        id: id,
        transport: .usb,
        serial: "PROFILE-SWITCH-\(UUID().uuidString)",
        onboardProfileCount: 5,
        profileID: .basiliskV3Pro
    )
}

private func makeProfileSwitchBackend(
    device: MouseDevice,
    activeProfile: Int,
    dpiValues: [Int]
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
                    scrollMode: device.supportsScrollModeControls ? 0 : nil,
                    scrollAcceleration: device.supportsScrollModeControls ? false : nil,
                    scrollSmartReel: device.supportsScrollModeControls ? false : nil
                )
            )
        ]
    )
}

private func makeProfileSwitchInventory(
    activeProfile: Int,
    maxProfileID: Int,
    snapshots: [OnboardProfileSnapshot]
) -> OnboardProfileInventory {
    OnboardProfileInventory(
        activeProfileID: activeProfile,
        maxProfileID: maxProfileID,
        assignedProfileIDs: snapshots.map(\.profileID).sorted(),
        profiles: snapshots.map { snapshot in
            OnboardProfileSummary(
                profileID: snapshot.profileID,
                metadata: snapshot.metadata,
                isAssigned: true,
                isActive: snapshot.profileID == activeProfile,
                isBaseProfile: snapshot.profileID == 1
            )
        }
    )
}

private func makeProfileSwitchSnapshot(
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

private func makeProfileSwitchTravelProfile(sourceDevice: MouseDevice) -> OpenSnekLocalProfile {
    DevicePreferenceStore().upsertOpenSnekLocalProfile(
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
}
