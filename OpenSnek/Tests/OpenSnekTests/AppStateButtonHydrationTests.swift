import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

final class AppStateButtonHydrationTests: XCTestCase {
    func testUSBRefreshDoesNotApplyPersistedButtonBindingsWithoutUserAction() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-no-auto-button-apply",
            transport: .usb,
            serial: "USB-NO-AUTO-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.savePersistedButtonBindings(
            device: device,
            bindings: [
                4: ButtonBindingDraft(
                    kind: .rightClick,
                    hidKey: 4,
                    turboEnabled: false,
                    turboRate: 0x8E,
                    clutchDPI: nil
                )
            ],
            profile: 1
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 88,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 1
                    )
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        let applyCount = await backend.applyCount()
        let binding = await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) }
        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(binding, .default)
    }

    func testUSBButtonHydrationPrefersDeviceReadbackOverPersistedCache() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-button-device",
            transport: .usb,
            serial: "USB-BTN-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.savePersistedButtonBindings(
            device: device,
            bindings: [
                4: ButtonBindingDraft(
                    kind: .leftClick,
                    hidKey: 4,
                    turboEnabled: false,
                    turboRate: 0x8E,
                    clutchDPI: nil
                )
            ],
            profile: 1
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 88,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 1
                    )
                )
            ]
        )
        await backend.setButtonBindingBlock(
            [0x01, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00],
            forDeviceID: device.id,
            slot: 4,
            profile: 1
        )
        await backend.setButtonBindingBlock(
            [0x01, 0x01, 0x02, 0x00, 0x00, 0x00, 0x00],
            forDeviceID: device.id,
            slot: 4,
            profile: 0
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        try await waitForRefactorCondition(timeout: 2.0) {
            await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) == .rightClick }
        }

        let binding = await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) }
        XCTAssertEqual(binding, .rightClick)
    }

    func testStateRefreshStaysConnectedWhileUSBButtonHydrationIsInFlight() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-refresh-hydration-device",
            transport: .usb,
            serial: "USB-REFRESH-HYDRATION-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 88,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 1
                    )
                )
            ]
        )
        await backend.setButtonBindingBlock(
            try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 1, profileID: .basiliskV3Pro)),
            forDeviceID: device.id,
            slot: 1,
            profile: 1
        )
        await backend.holdButtonBindingRead(deviceID: device.id, slot: 1, profile: 1)

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        try await waitForRefactorCondition {
            await backend.buttonReadCount(for: device.id) > 0
        }

        let connectionState = await MainActor.run {
            appState.deviceStore.connectionState(for: device)
        }
        let controlsEnabled = await MainActor.run {
            appState.deviceStore.selectedDeviceControlsEnabled
        }
        let isRefreshingState = await MainActor.run {
            appState.deviceStore.isRefreshingState
        }

        XCTAssertEqual(connectionState, .connected)
        XCTAssertTrue(controlsEnabled)
        XCTAssertFalse(isRefreshingState)

        await backend.releaseButtonBindingRead(deviceID: device.id, slot: 1, profile: 1)
    }

    func testUSBWheelTiltDefaultHydrationUsesDefaultPickerSelection() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-tilt-default-device",
            transport: .usb,
            serial: "USB-TILT-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 81,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 1
                    )
                )
            ]
        )
        await backend.setButtonBindingBlock(
            try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 52, profileID: .basiliskV3Pro)),
            forDeviceID: device.id,
            slot: 52,
            profile: 1
        )
        await backend.setButtonBindingBlock(
            try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 52, profileID: .basiliskV3Pro)),
            forDeviceID: device.id,
            slot: 52,
            profile: 0
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        try await waitForRefactorCondition {
            await MainActor.run { appState.editorStore.buttonBindingKind(for: 52) == .default }
        }

        let binding = await MainActor.run { appState.editorStore.buttonBindingKind(for: 52) }
        XCTAssertEqual(binding, .default)
    }

    func testUSBButtonHydrationIgnoresPlaceholderSerialCacheWhenReadbackIsUnavailable() async throws {
        struct LegacyPersistedBinding: Codable {
            let kindRaw: String
            let hidKey: Int
            let turboEnabled: Bool
            let turboRate: Int
        }

        let device = makeRefactorTestDevice(
            id: "usb-zero-serial-device",
            transport: .usb,
            serial: "000000000000",
            onboardProfileCount: 2
        )
        let defaults = UserDefaults.standard
        let legacyKey = "buttonBindings.serial:000000000000.profile2"
        let currentKey = "buttonBindings.\(DevicePersistenceKeys.key(for: device)).profile2"
        let previousLegacyData = defaults.data(forKey: legacyKey)
        let previousCurrentData = defaults.data(forKey: currentKey)
        let staleBindings = [
            "4": LegacyPersistedBinding(
                kindRaw: ButtonBindingKind.rightClick.rawValue,
                hidKey: 4,
                turboEnabled: false,
                turboRate: 0x8E
            )
        ]
        defaults.set(try JSONEncoder().encode(staleBindings), forKey: legacyKey)
        defaults.removeObject(forKey: currentKey)
        defer {
            if let previousLegacyData {
                defaults.set(previousLegacyData, forKey: legacyKey)
            } else {
                defaults.removeObject(forKey: legacyKey)
            }
            if let previousCurrentData {
                defaults.set(previousCurrentData, forKey: currentKey)
            } else {
                defaults.removeObject(forKey: currentKey)
            }
        }

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
                        activeOnboardProfile: 2,
                        onboardProfileCount: 2
                    )
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        let selectedProfile = await MainActor.run { appState.editorStore.editableUSBButtonProfile }
        let binding = await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) }

        XCTAssertEqual(selectedProfile, 2)
        XCTAssertEqual(binding, .default)
    }

    func testSwitchingUSBButtonProfileInvalidatesHydrationCache() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-device",
            transport: .usb,
            serial: "USB-PROFILE-\(UUID().uuidString)",
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
                        batteryPercent: 77,
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
            ButtonBindingSupport.buildUSBFunctionBlock(
                slot: 4,
                kind: .leftClick,
                hidKey: 4,
                turboEnabled: false,
                turboRate: 0x8E,
                clutchDPI: nil,
                profileID: .basiliskV3Pro
            ),
            forDeviceID: device.id,
            slot: 4,
            profile: 1
        )
        await backend.setButtonBindingBlock(
            ButtonBindingSupport.buildUSBFunctionBlock(
                slot: 4,
                kind: .leftClick,
                hidKey: 4,
                turboEnabled: false,
                turboRate: 0x8E,
                clutchDPI: nil,
                profileID: .basiliskV3Pro
            ),
            forDeviceID: device.id,
            slot: 4,
            profile: 0
        )
        await backend.setButtonBindingBlock(
            ButtonBindingSupport.buildUSBFunctionBlock(
                slot: 4,
                kind: .rightClick,
                hidKey: 4,
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

        try await waitForRefactorCondition {
            await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) == .leftClick }
        }

        await MainActor.run {
            appState.editorStore.updateUSBButtonProfile(2)
        }

        try await waitForRefactorCondition(timeout: 2.0) {
            await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) == .rightClick }
        }

        let selectedProfile = await MainActor.run { appState.editorStore.editableUSBButtonProfile }
        let updatedBinding = await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) }
        XCTAssertEqual(selectedProfile, 2)
        XCTAssertEqual(updatedBinding, .rightClick)
    }

    func testUSBButtonProfileSummariesReflectDefaultAndCustomSlots() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-summary-device",
            transport: .usb,
            serial: "USB-PROFILE-SUMMARY-\(UUID().uuidString)",
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
                        batteryPercent: 80,
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
            profile: 1
        )
        await backend.setButtonBindingBlock(
            ButtonBindingSupport.buildUSBFunctionBlock(
                slot: 4,
                kind: .rightClick,
                hidKey: 4,
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
                guard summaries.count == 3 else { return false }
                return summaries.first(where: { $0.profile == 2 })?.isCustomized == true &&
                    summaries.first(where: { $0.profile == 3 })?.isCustomized == false
            }
        }

        let summaries = await MainActor.run { appState.editorStore.visibleUSBButtonProfiles }
        XCTAssertEqual(summaries.map(\.profile), [1, 2, 3])
        XCTAssertEqual(summaries.first(where: { $0.profile == 1 })?.isCustomized, false)
        XCTAssertEqual(summaries.first(where: { $0.profile == 2 })?.isCustomized, true)
        XCTAssertEqual(summaries.first(where: { $0.profile == 3 })?.isCustomized, false)
    }

    func testDuplicateSelectedUSBButtonProfileEnqueuesProfileActionAndSelectsTarget() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-duplicate-device",
            transport: .usb,
            serial: "USB-PROFILE-DUPLICATE-\(UUID().uuidString)",
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
                        batteryPercent: 79,
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
                kind: .rightClick,
                hidKey: 4,
                turboEnabled: false,
                turboRate: 0x8E,
                clutchDPI: nil,
                profileID: .basiliskV3Pro
            ),
            forDeviceID: device.id,
            slot: 4,
            profile: 1
        )
        await backend.setButtonBindingBlock(
            ButtonBindingSupport.buildUSBFunctionBlock(
                slot: 4,
                kind: .rightClick,
                hidKey: 4,
                turboEnabled: false,
                turboRate: 0x8E,
                clutchDPI: nil,
                profileID: .basiliskV3Pro
            ),
            forDeviceID: device.id,
            slot: 4,
            profile: 0
        )
        await backend.setButtonBindingBlock(
            try XCTUnwrap(ButtonBindingSupport.defaultUSBFunctionBlock(for: 4, profileID: .basiliskV3Pro)),
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

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        try await waitForRefactorCondition(timeout: 2.0) {
            await MainActor.run {
                appState.editorStore.canDuplicateSelectedUSBButtonProfile &&
                    appState.editorStore.buttonBindingKind(for: 4) == .rightClick
            }
        }

        await appState.editorStore.duplicateSelectedUSBButtonProfile()

        let patches = await backend.recordedPatches()
        let selectedProfile = await MainActor.run { appState.editorStore.editableUSBButtonProfile }
        let duplicatedBinding = await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) }

        XCTAssertEqual(patches.last?.usbButtonProfileAction?.kind, .duplicateToPersistentSlot)
        XCTAssertEqual(patches.last?.usbButtonProfileAction?.sourceProfile, 1)
        XCTAssertEqual(patches.last?.usbButtonProfileAction?.targetProfile, 2)
        XCTAssertEqual(selectedProfile, 2)
        XCTAssertEqual(duplicatedBinding, .rightClick)
    }

    func testResetSelectedUSBButtonProfileEnqueuesResetActionAndClearsCachedBindings() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-profile-reset-device",
            transport: .usb,
            serial: "USB-PROFILE-RESET-\(UUID().uuidString)",
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
                        batteryPercent: 78,
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
            ButtonBindingSupport.buildUSBFunctionBlock(
                slot: 4,
                kind: .rightClick,
                hidKey: 4,
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
        try await waitForRefactorCondition {
            await MainActor.run { appState.editorStore.visibleOnboardProfileCount == 2 }
        }
        await MainActor.run {
            appState.editorStore.updateUSBButtonProfile(2)
        }

        try await waitForRefactorCondition(timeout: 2.0) {
            await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) == .rightClick }
        }

        await appState.editorStore.resetSelectedUSBButtonProfile()

        let patches = await backend.recordedPatches()
        let binding = await MainActor.run { appState.editorStore.buttonBindingKind(for: 4) }
        let expectedDefaultKind = ButtonBindingSupport.defaultButtonBinding(for: 4, profileID: device.profile_id).kind

        XCTAssertEqual(patches.last?.usbButtonProfileAction?.kind, .resetPersistentSlot)
        XCTAssertEqual(patches.last?.usbButtonProfileAction?.targetProfile, 2)
        XCTAssertEqual(binding, expectedDefaultKind)
    }

}
