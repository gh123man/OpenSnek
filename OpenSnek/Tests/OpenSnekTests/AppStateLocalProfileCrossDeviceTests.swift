import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

final class AppStateLocalProfileCrossDeviceTests: XCTestCase {
    func testHyperSpeedLocalProfileKeepsLogicalDPIStagesOnV3ProPaddedReadback() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let sourceDevice = makeCrossDeviceHyperSpeedDevice()
        let targetDevice = makeCrossDeviceV3ProDevice()
        let source = DevicePreferenceStore().upsertOpenSnekLocalProfile(
            name: "abc",
            content: crossDeviceLocalProfileContent(dpiValues: [800, 1600, 3200]),
            device: sourceDevice
        )
        let oldSnapshot = makeCrossDeviceOnboardSnapshot(
            profileID: 2,
            identifier: UUID(),
            name: "Old Slot",
            dpiValues: [800, 1600, 3200, 6400, 10_000]
        )
        let backend = makeCrossDeviceBackend(
            device: targetDevice,
            activeProfile: 2,
            dpiValues: [800, 1600, 3200, 6400, 10_000]
        )
        await backend.setPadsReducedOnboardDPIReadback(true)
        await backend.setOnboardInventory(
            makeCrossDeviceInventory(activeProfile: 2, maxProfileID: 5, snapshots: [oldSnapshot]),
            forDeviceID: targetDevice.id
        )
        await backend.setOnboardSnapshot(oldSnapshot, forDeviceID: targetDevice.id)

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await appState.editorStore.replaceSelectedProfile(with: source.id)

        try await waitForRefactorCondition {
            await backend.recordedOnboardCreates().count == 1
        }

        let editorDPI = await MainActor.run {
            (
                appState.editorStore.editableStageCount,
                Array(appState.editorStore.editableStagePairs.prefix(3)).map(\.x)
            )
        }
        XCTAssertEqual(editorDPI.0, 3)
        XCTAssertEqual(editorDPI.1, [800, 1600, 3200])

        let creates = await backend.recordedOnboardCreates()
        let create = try XCTUnwrap(creates.first)
        XCTAssertEqual(create.mutation.dpi?.values, [800, 1600, 3200])

        let stored = try XCTUnwrap(
            DevicePreferenceStore().loadOpenSnekLocalProfiles().first { $0.id == source.id }
        )
        XCTAssertEqual(stored.name, "abc")
        XCTAssertEqual(stored.content.dpi?.values, [800, 1600, 3200])
        XCTAssertEqual(stored.content.dpi?.stageIDs, [1, 2, 3, 4, 5])
    }
}

private func makeCrossDeviceHyperSpeedDevice() -> MouseDevice {
    makeRefactorTestDevice(
        id: "cross-device-v3x-source",
        transport: .usb,
        serial: "LOCAL-PROFILE-CROSS-V3X-\(UUID().uuidString)",
        onboardProfileCount: 1,
        profileID: .basiliskV3XHyperspeed
    )
}

private func makeCrossDeviceV3ProDevice() -> MouseDevice {
    makeRefactorTestDevice(
        id: "cross-device-v3pro-target",
        transport: .usb,
        serial: "LOCAL-PROFILE-CROSS-V3PRO-\(UUID().uuidString)",
        onboardProfileCount: 5,
        profileID: .basiliskV3Pro
    )
}

private func crossDeviceLocalProfileContent(dpiValues: [Int]) -> OpenSnekLocalProfileContent {
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

private func makeCrossDeviceBackend(
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
                    scrollMode: 0,
                    scrollAcceleration: false,
                    scrollSmartReel: false
                )
            )
        ]
    )
}

private func makeCrossDeviceInventory(
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

private func makeCrossDeviceOnboardSnapshot(
    profileID: Int,
    identifier: UUID,
    name: String,
    dpiValues: [Int]
) -> OnboardProfileSnapshot {
    let pairs = dpiValues.map { DpiPair(x: $0, y: $0) }
    return OnboardProfileSnapshot(
        profileID: profileID,
        metadata: OnboardProfileMetadata(identifier: identifier, name: name),
        dpi: OnboardDPIProfileSnapshot(
            scalar: pairs.first,
            activeStage: 0,
            pairs: pairs
        ),
        buttonBindings: [
            4: ButtonBindingDraft(kind: .mouseBack, hidKey: 4, turboEnabled: false, turboRate: 0x8E)
        ],
        brightnessByLEDID: [1: 64, 4: 64, 10: 64],
        staticColorByLEDID: [1: RGBPatch(r: 1, g: 2, b: 3)],
        scrollMode: 0,
        scrollAcceleration: false,
        scrollSmartReel: false
    )
}
