import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

/// Exercises app state button workspace behavior.
final class AppStateButtonWorkspaceTests: XCTestCase {
    func testProjectSelectedUSBButtonProfileToDirectLayerEnqueuesProjectAction() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-project-device",
            transport: .usb,
            serial: "USB-PROFILE-PROJECT-\(UUID().uuidString)",
            onboardProfileCount: 2
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 82,
                        dpiValues: [800, 1600, 2400],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 2
                    )
                )
            ]
        )
        await backend.setButtonBindingBlock(
            try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 4, profileID: .basiliskV3Pro)),
            forDeviceID: device.id,
            slot: 4,
            profile: 2
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.updateUSBButtonProfile(2)
        }

        await appState.editorStore.projectSelectedUSBButtonProfileToDirectLayer()

        let patches = await backend.recordedPatches()
        XCTAssertEqual(patches.last?.usbButtonProfileAction?.kind, .projectToDirectLayer)
        XCTAssertEqual(patches.last?.usbButtonProfileAction?.targetProfile, 2)
    }

    func testLoadingStoredUSBButtonProfileOverwritesBaseProfile() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-load-device",
            transport: .usb,
            serial: "USB-PROFILE-LOAD-\(UUID().uuidString)",
            onboardProfileCount: 3
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 82,
                        dpiValues: [800, 1600, 2400],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 3
                    )
                )
            ]
        )
        await backend.setButtonBindingBlock(
            ButtonBindingSupport.buildUSBFunctionBlock(
                slot: 4,
                kind: .keyboardSimple,
                hidKey: 9,
                turboEnabled: false,
                turboRate: 0x8E,
                clutchDPI: nil,
                profileID: .basiliskV3Pro
            ),
            forDeviceID: device.id,
            slot: 4,
            profile: 2
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await appState.editorStore.loadButtonProfileSourceIntoLive(.mouseSlot(2))

        let patches = await backend.recordedPatches()
        let slotPatch = try XCTUnwrap(patches.last(where: { $0.buttonBinding?.slot == 4 }))
        XCTAssertEqual(slotPatch.buttonBinding?.persistentProfile, 1)
        XCTAssertEqual(slotPatch.buttonBinding?.writePersistentLayer, true)
        XCTAssertEqual(slotPatch.buttonBinding?.writeDirectLayer, true)
        XCTAssertEqual(slotPatch.buttonBinding?.kind, .keyboardSimple)
    }

    func testReloadingKnownStoredUSBButtonProfileSkipsExtraDeviceReadback() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-reload-device",
            transport: .usb,
            serial: "USB-PROFILE-RELOAD-\(UUID().uuidString)",
            onboardProfileCount: 3
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 82,
                        dpiValues: [800, 1600, 2400],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 3
                    )
                )
            ]
        )
        await backend.setButtonBindingBlock(
            ButtonBindingSupport.buildUSBFunctionBlock(
                slot: 4,
                kind: .keyboardSimple,
                hidKey: 9,
                turboEnabled: false,
                turboRate: 0x8E,
                clutchDPI: nil,
                profileID: .basiliskV3Pro
            ),
            forDeviceID: device.id,
            slot: 4,
            profile: 2
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await appState.editorStore.loadButtonProfileSourceIntoLive(.mouseSlot(2))
        try await Task.sleep(nanoseconds: 120_000_000)

        let readsAfterFirstLoad = await backend.buttonReadCount(for: device.id)

        await appState.editorStore.loadButtonProfileSourceIntoLive(.mouseSlot(2))
        try await Task.sleep(nanoseconds: 120_000_000)

        let readsAfterSecondLoad = await backend.buttonReadCount(for: device.id)
        XCTAssertEqual(readsAfterSecondLoad, readsAfterFirstLoad)
    }

    func testStoredUSBButtonProfileDisplaysMatchingSavedProfileName() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-match-device",
            transport: .usb,
            serial: "USB-PROFILE-MATCH-\(UUID().uuidString)",
            onboardProfileCount: 3
        )
        let preferenceStore = DevicePreferenceStore()
        let matchingBindings = [
            4: ButtonBindingDraft(
                kind: .keyboardSimple,
                hidKey: 9,
                turboEnabled: false,
                turboRate: 0x8E,
                clutchDPI: nil
            )
        ]
        preferenceStore.saveOpenSnekButtonProfile(name: "Travel", bindings: matchingBindings)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 82,
                        dpiValues: [800, 1600, 2400],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 3
                    )
                )
            ]
        )
        await backend.setButtonBindingBlock(
            ButtonBindingSupport.buildUSBFunctionBlock(
                slot: 4,
                kind: .keyboardSimple,
                hidKey: 9,
                turboEnabled: false,
                turboRate: 0x8E,
                clutchDPI: nil,
                profileID: .basiliskV3Pro
            ),
            forDeviceID: device.id,
            slot: 4,
            profile: 2
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.refreshButtonProfilePresentation()
        }

        try await waitForRefactorCondition(timeout: 2.0) {
            await MainActor.run {
                appState.editorStore.buttonProfileSourceMatchDescription(.mouseSlot(2)) == "Travel"
            }
        }
    }

    func testLoadableMouseButtonSourcesHideDefaultStoredSlots() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-loadable-device",
            transport: .usb,
            serial: "USB-PROFILE-LOADABLE-\(UUID().uuidString)",
            onboardProfileCount: 4
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 82,
                        dpiValues: [800, 1600, 2400],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 4
                    )
                )
            ]
        )
        await backend.setButtonBindingBlock(
            ButtonBindingSupport.buildUSBFunctionBlock(
                slot: 4,
                kind: .keyboardSimple,
                hidKey: 9,
                turboEnabled: false,
                turboRate: 0x8E,
                clutchDPI: nil,
                profileID: .basiliskV3Pro
            ),
            forDeviceID: device.id,
            slot: 4,
            profile: 2
        )
        await backend.setButtonBindingBlock(
            try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 4, profileID: .basiliskV3Pro)),
            forDeviceID: device.id,
            slot: 4,
            profile: 3
        )
        await backend.setButtonBindingBlock(
            try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 4, profileID: .basiliskV3Pro)),
            forDeviceID: device.id,
            slot: 4,
            profile: 4
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.refreshButtonProfilePresentation()
        }

        try await waitForRefactorCondition(timeout: 2.0) {
            await MainActor.run {
                let summaries = appState.editorStore.visibleUSBButtonProfiles
                guard summaries.count == 4 else { return false }
                return summaries.first(where: { $0.profile == 2 })?.isCustomized == true &&
                    summaries.first(where: { $0.profile == 3 })?.isCustomized == false &&
                    summaries.first(where: { $0.profile == 4 })?.isCustomized == false
            }
        }

        let loadableSlots = await MainActor.run {
            appState.editorStore.loadableMouseButtonSources.compactMap { source -> Int? in
                guard case .mouseSlot(let slot) = source else { return nil }
                return slot
            }
        }
        let writableSlots = await MainActor.run {
            appState.editorStore.writableMouseButtonSources.compactMap { source -> Int? in
                guard case .mouseSlot(let slot) = source else { return nil }
                return slot
            }
        }
        XCTAssertEqual(loadableSlots, [1, 2])
        XCTAssertEqual(writableSlots, [2, 3, 4])
    }

    func testSavingCurrentButtonWorkspaceAsNewProfileUpdatesSavedLibraryImmediately() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-save-source-device",
            transport: .usb,
            serial: "USB-PROFILE-SAVE-SOURCE-\(UUID().uuidString)",
            onboardProfileCount: 3
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 82,
                        dpiValues: [800, 1600, 2400],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 3
                    )
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        await MainActor.run {
            _ = appState.editorStore.saveCurrentButtonWorkspaceAsNewProfile(name: "Bar")
        }

        let savedNames = await MainActor.run {
            appState.editorStore.savedButtonProfiles.map(\.name)
        }
        XCTAssertTrue(savedNames.contains("Bar"))
    }

    func testSavingSelectedUSBButtonProfileUsesExplicitButtonWriteWithoutActivation() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-save-device",
            transport: .usb,
            serial: "USB-PROFILE-SAVE-\(UUID().uuidString)",
            onboardProfileCount: 3
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 76,
                        dpiValues: [800, 1600, 2400],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 3
                    )
                )
            ]
        )
        await backend.setButtonBindingBlock(
            try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 4, profileID: .basiliskV3Pro)),
            forDeviceID: device.id,
            slot: 4,
            profile: 2
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.updateUSBButtonProfile(2)
        }

        try await waitForRefactorCondition {
            await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) == .default }
        }

        await MainActor.run {
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .rightClick)
        }

        let hasUnsavedChanges = await MainActor.run { appState.editorStore.selectedUSBButtonProfileHasUnsavedChanges }
        XCTAssertTrue(hasUnsavedChanges)

        await appState.editorStore.saveSelectedUSBButtonProfile()

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.last)
        XCTAssertEqual(patch.buttonBinding?.persistentProfile, 2)
        XCTAssertEqual(patch.buttonBinding?.kind, .rightClick)
        XCTAssertEqual(patch.buttonBinding?.writeDirectLayer, false)
        XCTAssertNil(patch.usbButtonProfileAction)

        try await waitForRefactorCondition(timeout: 2.0) {
            await MainActor.run { !appState.editorStore.selectedUSBButtonProfileHasUnsavedChanges }
        }

        let liveProfile = await MainActor.run { appState.editorStore.liveUSBButtonProfile }
        let pendingChanges = await MainActor.run { appState.editorStore.selectedUSBButtonProfileHasUnsavedChanges }
        XCTAssertEqual(liveProfile, 1)
        XCTAssertFalse(pendingChanges)
    }

    func testSaveAndActivateSelectedUSBButtonProfileProjectsLiveProfileOverride() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-save-activate-device",
            transport: .usb,
            serial: "USB-PROFILE-SAVE-ACTIVATE-\(UUID().uuidString)",
            onboardProfileCount: 3
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 76,
                        dpiValues: [800, 1600, 2400],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 3
                    )
                )
            ]
        )
        await backend.setButtonBindingBlock(
            try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 4, profileID: .basiliskV3Pro)),
            forDeviceID: device.id,
            slot: 4,
            profile: 2
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.updateUSBButtonProfile(2)
        }

        try await waitForRefactorCondition {
            await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) == .default }
        }

        await MainActor.run {
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .rightClick)
        }

        await appState.editorStore.saveSelectedUSBButtonProfile(activateAfterSave: true)

        let patches = await backend.recordedPatches()
        let buttonPatch = try XCTUnwrap(patches.first(where: { $0.buttonBinding != nil }))
        let projectPatch = try XCTUnwrap(patches.last(where: { $0.usbButtonProfileAction?.kind == .projectToDirectLayer }))
        XCTAssertEqual(buttonPatch.buttonBinding?.persistentProfile, 2)
        XCTAssertEqual(buttonPatch.buttonBinding?.writeDirectLayer, false)
        XCTAssertEqual(projectPatch.usbButtonProfileAction?.targetProfile, 2)

        let liveProfile = await MainActor.run { appState.editorStore.liveUSBButtonProfile }
        let summaries = await MainActor.run { appState.editorStore.visibleUSBButtonProfiles }
        XCTAssertEqual(liveProfile, 2)
        XCTAssertEqual(summaries.first(where: { $0.profile == 2 })?.isLiveActive, true)
        XCTAssertEqual(summaries.first(where: { $0.profile == 1 })?.isHardwareActive, true)
    }

    func testEditingProjectedStoredUSBButtonProfileAutoAppliesToBaseAndDirectLayer() async throws {
        for (profileID, onboardProfileCount) in [
            (DeviceProfileID.basiliskV3, 5),
            (.basiliskV335K, 5)
        ] {
            let device = makeRefactorTestDevice(
                id: "usb-profile-projected-auto-apply-\(profileID.rawValue)",
                transport: .usb,
                serial: "USB-PROFILE-PROJECTED-AUTO-\(profileID.rawValue)-\(UUID().uuidString)",
                onboardProfileCount: onboardProfileCount,
                profileID: profileID
            )
            defer { clearRefactorPreferences(for: device) }

            let backend = AppStateRefactorStubBackend(
                devices: [device],
                stateByDeviceID: [
                    device.id: makeRefactorTestState(
                        device: device,
                        telemetry: RefactorTestStateTelemetry(
                            connection: "usb",
                            batteryPercent: 76,
                            dpiValues: [800, 1600, 2400],
                            activeStage: 0
                        ),
                        options: RefactorTestStateOptions(
                            activeOnboardProfile: 1,
                            onboardProfileCount: onboardProfileCount
                        )
                    )
                ]
            )
            await backend.setButtonBindingBlock(
                try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 4, profileID: profileID)),
                forDeviceID: device.id,
                slot: 4,
                profile: 2
            )

            let appState = await MainActor.run {
                AppState(launchRole: .app, backend: backend, autoStart: false)
            }

            await appState.deviceStore.refreshDevices()
            await MainActor.run {
                appState.editorStore.updateUSBButtonProfile(2)
            }

            try await waitForRefactorCondition {
                await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) == .default }
            }

            await appState.editorStore.projectSelectedUSBButtonProfileToDirectLayer()

            await MainActor.run {
                appState.editorStore.updateButtonBindingKind(slot: 4, kind: .rightClick)
            }

            try await waitForRefactorCondition(timeout: 2.0) {
                await backend.recordedPatches().contains(where: { patch in
                    patch.buttonBinding?.slot == 4 && patch.buttonBinding?.kind == .rightClick
                })
            }

            let patches = await backend.recordedPatches()
            let patch = try XCTUnwrap(
                patches.last(where: { $0.buttonBinding?.slot == 4 }),
                "Missing button patch for \(profileID.rawValue)"
            )
            XCTAssertEqual(
                patch.buttonBinding?.persistentProfile,
                1,
                "Projected USB edits should persist to base slot 1 for \(profileID.rawValue)"
            )
            XCTAssertEqual(patch.buttonBinding?.writePersistentLayer, true)
            XCTAssertEqual(patch.buttonBinding?.writeDirectLayer, true)
        }
    }

    func testEditingSavedButtonProfileStillAutoAppliesToBaseAndDirectLayer() async throws {
        let device = makeRefactorTestDevice(
            id: "saved-button-auto-apply-device",
            transport: .usb,
            serial: "SAVED-BUTTON-AUTO-\(UUID().uuidString)",
            onboardProfileCount: 3,
            profileID: .basiliskV335K
        )
        let preferenceStore = DevicePreferenceStore()
        let saved = preferenceStore.saveOpenSnekButtonProfile(
            name: "Travel",
            bindings: [
                4: ButtonBindingDraft(kind: .rightClick, hidKey: 4, turboEnabled: false, turboRate: 0x8E, clutchDPI: nil)
            ]
        )
        defer {
            clearSavedButtonProfiles()
            clearRefactorPreferences(for: device)
        }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 74,
                        dpiValues: [800, 1600, 2400],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 3
                    )
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.updateUSBButtonProfile(2)
            appState.editorStore.selectButtonProfileSource(.openSnekProfile(saved.id))
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .mouseForward)
        }

        try await waitForRefactorCondition(timeout: 2.0) {
            await backend.recordedPatches().contains(where: { patch in
                patch.buttonBinding?.slot == 4 && patch.buttonBinding?.kind == .mouseForward
            })
        }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.last(where: { $0.buttonBinding?.slot == 4 }))
        XCTAssertEqual(patch.buttonBinding?.persistentProfile, 1)
        XCTAssertEqual(patch.buttonBinding?.writePersistentLayer, true)
        XCTAssertEqual(patch.buttonBinding?.writeDirectLayer, true)
    }

    func testEditingBaseProfileAutoAppliesToLiveAndPersistentSlotOne() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-base-auto-apply-device",
            transport: .usb,
            serial: "USB-PROFILE-BASE-\(UUID().uuidString)",
            onboardProfileCount: 3,
            profileID: .basiliskV335K
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 76,
                        dpiValues: [800, 1600, 2400],
                        activeStage: 0
                    ),
                    options: RefactorTestStateOptions(
                        activeOnboardProfile: 1,
                        onboardProfileCount: 3
                    )
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.updateButtonBindingKind(slot: 4, kind: .rightClick)
        }

        try await waitForRefactorCondition(timeout: 2.0) {
            await backend.recordedPatches().contains(where: { $0.buttonBinding?.slot == 4 })
        }

        try await waitForRefactorCondition(timeout: 2.0) {
            await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) == .rightClick }
        }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.last(where: { $0.buttonBinding?.slot == 4 }))
        let binding = await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) }
        XCTAssertEqual(patch.buttonBinding?.persistentProfile, 1)
        XCTAssertEqual(patch.buttonBinding?.writePersistentLayer, true)
        XCTAssertEqual(patch.buttonBinding?.writeDirectLayer, true)
        XCTAssertEqual(binding, .rightClick)
        XCTAssertEqual(patches.compactMap(\.buttonBinding).map(\.slot), [4])
    }

}
