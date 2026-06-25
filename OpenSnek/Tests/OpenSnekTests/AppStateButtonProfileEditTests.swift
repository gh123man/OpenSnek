import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

/// Exercises app state button profile edit behavior.
final class AppStateButtonProfileEditTests: XCTestCase {
    func testDefaultDPIButtonAppliesAsDPICycleOn35K() async throws {
        let device = MouseDevice(
            id: "usb-35k-default-dpi-cycle-device", vendor_id: 0x1532, product_id: 0x00CB, product_name: "Basilisk V3 35K", transport: .usb, path_b64: "", serial: "USB-35K-DPI-\(UUID().uuidString)", firmware: "1.0.0", location_id: 1, profile_id: .basiliskV335K,
            supports_advanced_lighting_effects: true, onboard_profile_count: 5)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 76, dpiValues: [800, 1600, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()
        await MainActor.run { appState.editorStore.updateButtonBindingKind(slot: 96, kind: .default) }

        try await waitForRefactorCondition(timeout: 2.0) { await backend.recordedPatches().contains(where: { $0.buttonBinding?.slot == 96 && $0.buttonBinding?.kind == .dpiCycle }) }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.last(where: { $0.buttonBinding?.slot == 96 }))
        let selectedKind = await MainActor.run { appState.editorStore.buttonBindingKind(for: 96) }
        XCTAssertEqual(patch.buttonBinding?.kind, .dpiCycle)
        XCTAssertEqual(patch.buttonBinding?.persistentProfile, 1)
        XCTAssertEqual(patch.buttonBinding?.writePersistentLayer, true)
        XCTAssertEqual(patch.buttonBinding?.writeDirectLayer, true)
        XCTAssertEqual(selectedKind, .default)
    }

    func testSwitchingUSBDevicesDoesNotPreserveUnsavedButtonWorkspaceAcrossDevices() async throws {
        let firstDevice = makeRefactorTestDevice(id: "usb-workspace-a", transport: .usb, serial: "USB-WORKSPACE-A-\(UUID().uuidString)", onboardProfileCount: 5)
        let secondDevice = makeRefactorTestDevice(id: "usb-workspace-b", transport: .usb, serial: "USB-WORKSPACE-B-\(UUID().uuidString)", onboardProfileCount: 5)
        defer {
            clearRefactorPreferences(for: firstDevice)
            clearRefactorPreferences(for: secondDevice)
        }

        let backend = AppStateRefactorStubBackend(
            devices: [firstDevice, secondDevice],
            stateByDeviceID: [
                firstDevice.id: makeRefactorTestState(device: firstDevice, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 76, dpiValues: [800, 1600, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5)),
                secondDevice.id: makeRefactorTestState(device: secondDevice, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 81, dpiValues: [800, 1600, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 5))
            ])

        await backend.setButtonBindingBlock(try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 4, profileID: .basiliskV3Pro)), forDeviceID: firstDevice.id, slot: 4, profile: 1)
        await backend.setButtonBindingBlock(try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 4, profileID: .basiliskV3Pro)), forDeviceID: firstDevice.id, slot: 4, profile: 0)
        await backend.setButtonBindingBlock([0x02, 0x02, 0x00, 0x04, 0x00, 0x00, 0x00], forDeviceID: secondDevice.id, slot: 4, profile: 1)
        await backend.setButtonBindingBlock([0x02, 0x02, 0x00, 0x04, 0x00, 0x00, 0x00], forDeviceID: secondDevice.id, slot: 4, profile: 0)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()
        await MainActor.run { appState.deviceStore.selectDevice(firstDevice.id) }

        await MainActor.run {
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .rightClick)
            appState.deviceStore.selectDevice(secondDevice.id)
        }

        try await waitForRefactorCondition(timeout: 2.0) { await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) == .keyboardSimple && appState.editorStore.buttonBindingHidKey(for: 4) == 4 } }

        let bindingKind = await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) }
        let hidKey = await MainActor.run { appState.editorStore.buttonBindingHidKey(for: 4) }

        XCTAssertEqual(bindingKind, .keyboardSimple)
        XCTAssertEqual(hidKey, 4)
    }

    func testEditingMouseTurboBindingAutoAppliesToBaseProfile() async throws {
        let device = makeRefactorTestDevice(id: "usb-profile-mouse-turbo-device", transport: .usb, serial: "USB-PROFILE-MOUSE-TURBO-\(UUID().uuidString)", onboardProfileCount: 3, profileID: .basiliskV335K)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 79, dpiValues: [800, 1600, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 3))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        let expectedRate = ButtonBindingSupport.turboPressesPerSecondToRaw(7)

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .rightClick)
            appState.editorStore.updateButtonBindingTurboEnabled(slot: 4, enabled: true)
            appState.editorStore.updateButtonBindingTurboPressesPerSecond(slot: 4, pressesPerSecond: 7)
        }

        try await waitForRefactorCondition(timeout: 2.0) { await backend.recordedPatches().contains(where: { $0.buttonBinding?.slot == 4 && $0.buttonBinding?.kind == .rightClick && $0.buttonBinding?.turboEnabled == true }) }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.last(where: { $0.buttonBinding?.slot == 4 }))
        let turboEnabled = await MainActor.run { appState.editorStore.buttonBindingTurboEnabled(for: 4) }
        let kind = await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) }

        XCTAssertEqual(kind, .rightClick)
        XCTAssertTrue(turboEnabled)
        XCTAssertEqual(patch.buttonBinding?.kind, .rightClick)
        XCTAssertEqual(patch.buttonBinding?.turboEnabled, true)
        XCTAssertEqual(patch.buttonBinding?.turboRate, expectedRate)
        XCTAssertEqual(patch.buttonBinding?.persistentProfile, 1)
        XCTAssertEqual(patch.buttonBinding?.writePersistentLayer, true)
        XCTAssertEqual(patch.buttonBinding?.writeDirectLayer, true)
    }

    func testLoadingButtonProfileIntoLiveMarksProfileOperationBusyUntilApplyFinishes() async throws {
        let device = makeRefactorTestDevice(id: "usb-profile-load-busy-device", transport: .usb, serial: "USB-PROFILE-LOAD-BUSY-\(UUID().uuidString)", onboardProfileCount: 3)
        let preferenceStore = DevicePreferenceStore()
        let saved = preferenceStore.saveOpenSnekButtonProfile(name: "Travel", bindings: [4: ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil)])
        defer {
            clearSavedButtonProfiles()
            clearRefactorPreferences(for: device)
        }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 82, dpiValues: [800, 1600, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 3))],
            holdFirstApply: true)
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()

        let loadTask = Task { await appState.editorStore.loadButtonProfileSourceIntoLive(.openSnekProfile(saved.id)) }

        await backend.waitForFirstApplyToStart()

        let busyDuringApply = await MainActor.run { appState.editorStore.isButtonProfileOperationInFlight }
        XCTAssertTrue(busyDuringApply)

        await MainActor.run { XCTAssertEqual(appState.editorStore.buttonBindingKind(for: 4), .rightClick) }

        await backend.releaseFirstApply()
        await loadTask.value

        try await waitForRefactorCondition(timeout: 2.0) { await MainActor.run { !appState.editorStore.isButtonProfileOperationInFlight } }
    }

    func testSelectingSavedButtonProfileHydratesWorkingCopy() async throws {
        let device = makeRefactorTestDevice(id: "saved-button-profile-device", transport: .usb, serial: "SAVED-BUTTON-\(UUID().uuidString)", onboardProfileCount: 3)
        let preferenceStore = DevicePreferenceStore()
        let saved = preferenceStore.saveOpenSnekButtonProfile(name: "Travel", bindings: [4: ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil)])
        defer {
            clearSavedButtonProfiles()
            clearRefactorPreferences(for: device)
        }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 84, dpiValues: [800, 1600, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 3))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()
        await MainActor.run { appState.editorStore.selectButtonProfileSource(.openSnekProfile(saved.id)) }

        let binding = await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) }
        let displayName = await MainActor.run { appState.editorStore.currentButtonProfileDisplayName }
        XCTAssertEqual(binding, .rightClick)
        XCTAssertEqual(displayName, "Travel")
    }

    func testApplyCurrentButtonWorkspaceToLiveWritesBaseProfileWithoutOverwritingSavedProfileSource() async throws {
        let device = makeRefactorTestDevice(id: "saved-button-apply-device", transport: .usb, serial: "SAVED-APPLY-\(UUID().uuidString)", onboardProfileCount: 3)
        let preferenceStore = DevicePreferenceStore()
        let saved = preferenceStore.saveOpenSnekButtonProfile(name: "Travel", bindings: [4: ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil)])
        defer {
            clearSavedButtonProfiles()
            clearRefactorPreferences(for: device)
        }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 3))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()
        await MainActor.run { appState.editorStore.selectButtonProfileSource(.openSnekProfile(saved.id)) }
        await appState.editorStore.applyCurrentButtonWorkspaceToLive()

        let patches = await backend.recordedPatches()
        let slotPatch = try XCTUnwrap(patches.last(where: { $0.buttonBinding?.slot == 4 }))
        let liveDisplayName = await MainActor.run { appState.editorStore.liveButtonProfileDisplayName }
        let currentSource = await MainActor.run { appState.editorStore.currentButtonProfileSource }

        XCTAssertEqual(slotPatch.buttonBinding?.kind, .rightClick)
        XCTAssertEqual(slotPatch.buttonBinding?.persistentProfile, 1)
        XCTAssertEqual(slotPatch.buttonBinding?.writePersistentLayer, true)
        XCTAssertEqual(slotPatch.buttonBinding?.writeDirectLayer, true)
        XCTAssertEqual(currentSource, .openSnekProfile(saved.id))
        XCTAssertEqual(liveDisplayName, "Travel")
    }

    func testWriteCurrentButtonWorkspaceToMouseSlotPersistsWithoutChangingCurrentSource() async throws {
        let device = makeRefactorTestDevice(id: "saved-button-write-slot-device", transport: .usb, serial: "SAVED-WRITE-\(UUID().uuidString)", onboardProfileCount: 3)
        let preferenceStore = DevicePreferenceStore()
        let saved = preferenceStore.saveOpenSnekButtonProfile(name: "Travel", bindings: [4: ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil)])
        defer {
            clearSavedButtonProfiles()
            clearRefactorPreferences(for: device)
        }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 3))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()
        await MainActor.run { appState.editorStore.selectButtonProfileSource(.openSnekProfile(saved.id)) }
        await appState.editorStore.writeCurrentButtonWorkspaceToMouseSlot(2)

        let patches = await backend.recordedPatches()
        let slotPatch = try XCTUnwrap(patches.last(where: { $0.buttonBinding?.slot == 4 }))
        let currentSource = await MainActor.run { appState.editorStore.currentButtonProfileSource }

        XCTAssertEqual(slotPatch.buttonBinding?.kind, .rightClick)
        XCTAssertEqual(slotPatch.buttonBinding?.persistentProfile, 2)
        XCTAssertEqual(slotPatch.buttonBinding?.writePersistentLayer, true)
        XCTAssertEqual(slotPatch.buttonBinding?.writeDirectLayer, false)
        XCTAssertEqual(currentSource, .openSnekProfile(saved.id))

        await MainActor.run { appState.editorStore.selectButtonProfileSource(.mouseSlot(2)) }

        try await waitForRefactorCondition(timeout: 2.0) { await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) == .rightClick } }
    }

    func testSelectingNextOnboardButtonProfileFollowsVisibleSlotOrder() async throws {
        let device = makeRefactorTestDevice(id: "saved-button-next-slot-device", transport: .usb, serial: "SAVED-NEXT-\(UUID().uuidString)", onboardProfileCount: 3)
        let preferenceStore = DevicePreferenceStore()
        let saved = preferenceStore.saveOpenSnekButtonProfile(name: "Travel", bindings: [4: ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil)])
        defer {
            clearSavedButtonProfiles()
            clearRefactorPreferences(for: device)
        }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 74, dpiValues: [800, 1600, 2400], activeStage: 0), options: RefactorTestStateOptions(activeOnboardProfile: 1, onboardProfileCount: 3))])
        await backend.setButtonBindingBlock(try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 4, profileID: .basiliskV3Pro)), forDeviceID: device.id, slot: 4, profile: 1)
        await backend.setButtonBindingBlock(try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 4, profileID: .basiliskV3Pro)), forDeviceID: device.id, slot: 4, profile: 0)
        await backend.setButtonBindingBlock(ButtonBindingSupport.buildUSBFunctionBlock(slot: 4, kind: .mouseForward, hidKey: 4, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil, profileID: .basiliskV3Pro), forDeviceID: device.id, slot: 4, profile: 2)
        await backend.setButtonBindingBlock(ButtonBindingSupport.buildUSBFunctionBlock(slot: 4, kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil, profileID: .basiliskV3Pro), forDeviceID: device.id, slot: 4, profile: 3)
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()
        await MainActor.run { appState.editorStore.refreshButtonProfilePresentation() }

        try await waitForRefactorCondition(timeout: 2.0) {
            await MainActor.run {
                let summaries = appState.editorStore.visibleUSBButtonProfiles
                guard summaries.count == 3 else { return false }
                return summaries.first(where: { $0.profile == 2 })?.isCustomized == true && summaries.first(where: { $0.profile == 3 })?.isCustomized == true
            }
        }
        await MainActor.run {
            appState.editorStore.selectButtonProfileSource(.openSnekProfile(saved.id))
            appState.editorStore.selectNextOnboardButtonProfile()
        }

        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.currentButtonProfileSource == .mouseSlot(2) && appState.editorStore.buttonBindingKind(for: 4) == .mouseForward } }

        await MainActor.run { appState.editorStore.selectNextOnboardButtonProfile() }
        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.currentButtonProfileSource == .mouseSlot(3) && appState.editorStore.buttonBindingKind(for: 4) == .rightClick } }

        await MainActor.run { appState.editorStore.selectNextOnboardButtonProfile() }
        try await waitForRefactorCondition { await MainActor.run { appState.editorStore.currentButtonProfileSource == .mouseSlot(1) && appState.editorStore.buttonBindingKind(for: 4) == .default } }
    }

    func testSwitchingBetweenUSBDevicesReusesSessionButtonBindingCache() async throws {
        let alphaDevice = makeRefactorTestDevice(id: "usb-alpha-device", transport: .usb, serial: "USB-ALPHA-\(UUID().uuidString)", onboardProfileCount: 1)
        let betaDevice = makeRefactorTestDevice(id: "usb-beta-device", transport: .usb, serial: "USB-BETA-\(UUID().uuidString)", onboardProfileCount: 1)

        let backend = AppStateRefactorStubBackend(
            devices: [alphaDevice, betaDevice],
            stateByDeviceID: [
                alphaDevice.id: makeRefactorTestState(device: alphaDevice, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 77, dpiValues: [800, 1600, 2400], activeStage: 0)),
                betaDevice.id: makeRefactorTestState(device: betaDevice, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 78, dpiValues: [900, 1800, 2700], activeStage: 1))
            ])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()

        try await waitForRefactorCondition { await backend.buttonReadCount(for: alphaDevice.id) > 0 }
        try await Task.sleep(nanoseconds: 250_000_000)
        let alphaReadCountAfterInitialHydration = await backend.buttonReadCount(for: alphaDevice.id)

        await MainActor.run { appState.deviceStore.selectDevice(betaDevice.id) }

        try await waitForRefactorCondition { await backend.buttonReadCount(for: betaDevice.id) > 0 }
        try await Task.sleep(nanoseconds: 250_000_000)

        await MainActor.run { appState.deviceStore.selectDevice(alphaDevice.id) }

        try await Task.sleep(nanoseconds: 200_000_000)

        let alphaReadCountAfterReselect = await backend.buttonReadCount(for: alphaDevice.id)
        XCTAssertEqual(alphaReadCountAfterReselect, alphaReadCountAfterInitialHydration)
    }

}
