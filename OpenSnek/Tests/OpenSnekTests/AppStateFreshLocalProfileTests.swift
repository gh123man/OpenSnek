import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

/// Exercises app state fresh local profile behavior.
final class AppStateFreshLocalProfileTests: XCTestCase {
    func testMappedBluetoothCreateDoesNotBackfillUnsupportedScrollFields() {
        let bluetoothDevice = makeRefactorTestDevice(id: "fresh-local-profile-bt-fill", transport: .bluetooth, serial: "FRESH-BT-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let usbDevice = makeRefactorTestDevice(id: "fresh-local-profile-usb-fill", transport: .usb, serial: "FRESH-USB-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro)
        let mutation = makeFreshMappedProfileMutation()

        XCTAssertFalse(mutation.needsMappedContentFill(for: bluetoothDevice))
        XCTAssertTrue(mutation.needsMappedContentFill(for: usbDevice))
    }

    func testFreshLocalProfileUsesDefaultsAndAssignsSelectedMappedSlot() async throws {
        clearSavedButtonProfiles()
        defer { clearSavedButtonProfiles() }

        let device = makeFreshLocalProfileDevice()
        let oldSnapshot = makeFreshLocalProfileOnboardSnapshot(profileID: 2, identifier: UUID(), name: "Old Slot", dpiValues: [900, 1800], activeStage: 0)
        let backend = makeFreshLocalProfileBackend(device: device, activeProfile: 2, dpiValues: [900, 1800])
        await backend.setOnboardInventory(makeFreshLocalProfileInventory(activeProfile: 2, maxProfileID: 5, snapshots: [oldSnapshot]), forDeviceID: device.id)
        await backend.setOnboardSnapshot(oldSnapshot, forDeviceID: device.id)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }
        await appState.deviceStore.refreshDevices()
        await appState.editorStore.refreshOnboardProfiles()
        await MainActor.run {
            appState.editorStore.editableStageCount = 2
            appState.editorStore.editableStagePairs = [DpiPair(x: 900, y: 900), DpiPair(x: 1800, y: 1800), DpiPair(x: 3200, y: 3200), DpiPair(x: 6400, y: 6400), DpiPair(x: 10_000, y: 10_000)]
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .mouseForward)
            appState.editorStore.editableLedBrightness = 12
            appState.editorStore.editableColor = RGBColor(r: 90, g: 80, b: 70)
            appState.editorStore.editableLightingEffect = .wave
            appState.editorStore.editableScrollMode = 1
            appState.editorStore.editableScrollAcceleration = true
            appState.editorStore.editableScrollSmartReel = true
        }

        await appState.editorStore.createFreshLocalProfileAndReplaceSelected(name: "Fresh Defaults")

        try await waitForRefactorCondition { await backend.recordedOnboardCreates().count == 1 }

        let profile = try XCTUnwrap(DevicePreferenceStore().loadOpenSnekLocalProfiles().first { $0.name == "Fresh Defaults" })
        let expectedSlots = try XCTUnwrap(DeviceProfiles.resolve(vendorID: device.vendor_id, productID: device.product_id, transport: device.transport)?.buttonLayout.writableSlots)
        let defaultColor = RGBPatch(r: 0, g: 255, b: 0)
        XCTAssertEqual(profile.content.dpi?.values, [800, 1600, 3200])
        XCTAssertEqual(profile.content.dpi?.activeStage, 0)
        XCTAssertEqual(Set(profile.content.buttonBindings.keys), Set(expectedSlots))
        XCTAssertEqual(profile.content.buttonBindings[4], ButtonBindingSupport.defaultButtonBinding(for: 4, profileID: device.profile_id))
        XCTAssertEqual(profile.content.brightnessByLEDID, [1: 64, 4: 64, 10: 64])
        XCTAssertEqual(profile.content.staticColorByLEDID, [1: defaultColor, 4: defaultColor, 10: defaultColor])
        XCTAssertEqual(profile.content.scrollMode, 0)
        XCTAssertEqual(profile.content.scrollAcceleration, false)
        XCTAssertEqual(profile.content.scrollSmartReel, false)

        let creates = await backend.recordedOnboardCreates()
        let create = try XCTUnwrap(creates.first)
        XCTAssertEqual(create.targetProfileID, 2)
        XCTAssertTrue(create.replaceAssignedProfile)
        XCTAssertEqual(create.mutation.metadata?.name, "Fresh Defaults")
        XCTAssertEqual(create.mutation.dpi?.values, [800, 1600, 3200])
        XCTAssertEqual(create.mutation.buttonBindings?[4], profile.content.buttonBindings[4])
        XCTAssertEqual(create.mutation.brightnessByLEDID, [1: 64, 4: 64, 10: 64])
        XCTAssertEqual(create.mutation.staticColorByLEDID, profile.content.staticColorByLEDID)
        XCTAssertEqual(create.mutation.scrollMode, 0)
        XCTAssertEqual(create.mutation.scrollAcceleration, false)
        XCTAssertEqual(create.mutation.scrollSmartReel, false)
    }
}

private func makeFreshMappedProfileMutation() -> OnboardProfileMutation {
    let dpiPairs = [800, 1600, 3200].map { DpiPair(x: $0, y: $0) }
    let color = RGBPatch(r: 0, g: 255, b: 0)
    return OnboardProfileMutation(
        metadata: OnboardProfileMetadata(name: "Fresh Defaults"), dpi: OnboardDPIProfileSnapshot(scalar: dpiPairs.first, activeStage: 0, pairs: dpiPairs),
        buttonBindings: [
            1: ButtonBindingSupport.defaultButtonBinding(for: 1, profileID: .basiliskV3Pro), 2: ButtonBindingSupport.defaultButtonBinding(for: 2, profileID: .basiliskV3Pro), 3: ButtonBindingSupport.defaultButtonBinding(for: 3, profileID: .basiliskV3Pro),
            4: ButtonBindingSupport.defaultButtonBinding(for: 4, profileID: .basiliskV3Pro)
        ], brightnessByLEDID: [1: 64, 4: 64, 10: 64], staticColorByLEDID: [1: color, 4: color, 10: color])
}

private func makeFreshLocalProfileDevice() -> MouseDevice { makeRefactorTestDevice(id: "local-profile-fresh-defaults", transport: .usb, serial: "LOCAL-PROFILE-\(UUID().uuidString)", onboardProfileCount: 5, profileID: .basiliskV3Pro) }

private func makeFreshLocalProfileBackend(device: MouseDevice, activeProfile: Int, dpiValues: [Int]) -> AppStateRefactorStubBackend {
    AppStateRefactorStubBackend(
        devices: [device],
        stateByDeviceID: [
            device.id: makeRefactorTestState(
                device: device, telemetry: RefactorTestStateTelemetry(connection: device.transport.connectionLabel.lowercased(), batteryPercent: 81, dpiValues: dpiValues, activeStage: 0),
                options: RefactorTestStateOptions(
                    activeOnboardProfile: activeProfile, onboardProfileCount: device.onboard_profile_count, scrollMode: device.supportsScrollModeControls ? 0 : nil, scrollAcceleration: device.supportsScrollModeControls ? false : nil, scrollSmartReel: device.supportsScrollModeControls ? false : nil))
        ])
}

private func makeFreshLocalProfileInventory(activeProfile: Int, maxProfileID: Int, snapshots: [OnboardProfileSnapshot]) -> OnboardProfileInventory {
    let summaries = snapshots.map { snapshot in OnboardProfileSummary(profileID: snapshot.profileID, metadata: snapshot.metadata, isAssigned: true, isActive: snapshot.profileID == activeProfile, isBaseProfile: snapshot.profileID == 1) }
    return OnboardProfileInventory(activeProfileID: activeProfile, maxProfileID: maxProfileID, assignedProfileIDs: snapshots.map(\.profileID).sorted(), profiles: summaries)
}

private func makeFreshLocalProfileOnboardSnapshot(profileID: Int, identifier: UUID, name: String, dpiValues: [Int], activeStage: Int) -> OnboardProfileSnapshot {
    let pairs = dpiValues.map { DpiPair(x: $0, y: $0) }
    let active = max(0, min(max(0, pairs.count - 1), activeStage))
    return OnboardProfileSnapshot(
        profileID: profileID, metadata: OnboardProfileMetadata(identifier: identifier, name: name), dpi: OnboardDPIProfileSnapshot(scalar: pairs.indices.contains(active) ? pairs[active] : pairs.first, activeStage: active, pairs: pairs),
        buttonBindings: [4: ButtonBindingDraft(kind: .mouseBack, hidKey: 4, turboEnabled: false, turboRate: 0x8E)], brightnessByLEDID: [1: 64], staticColorByLEDID: [1: RGBPatch(r: 1, g: 2, b: 3)], scrollMode: 0, scrollAcceleration: false, scrollSmartReel: false)
}
