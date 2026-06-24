import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

/// Exercises app state restore behavior.
final class AppStateRestoreTests: XCTestCase {
    func testBluetoothPersistedSettingsSnapshotReappliesOnFirstHydration() async throws {
        let device = makeRefactorTestDevice(
            id: "bt-lighting-device",
            transport: .bluetooth,
            serial: "BT-LIGHT-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        let persistedColor = RGBColor(r: 10, g: 20, b: 30)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            makeRefactorSettingsSnapshot(
                color: persistedColor,
                buttonBindings: [
                    5: ButtonBindingDraft(
                        kind: .keyboardSimple,
                        hidKey: 80,
                        turboEnabled: false,
                        turboRate: 0x8E,
                        clutchDPI: nil
                    )
                ]
            ),
            device: device
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "bluetooth",
                        batteryPercent: 68,
                        dpiValues: [1200, 2400, 3600],
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
            await backend.applyCount() >= 2
        }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.first)
        let buttonPatch = try XCTUnwrap(patches.first(where: { $0.buttonBinding?.slot == 5 }))
        let editableColor = await MainActor.run { appState.editorStore.editableColor }
        let editableActiveStage = await MainActor.run { appState.editorStore.editableActiveStage }

        XCTAssertEqual(patch.pollRate, 500)
        XCTAssertEqual(patch.sleepTimeout, 420)
        XCTAssertEqual(patch.lowBatteryThresholdRaw, 0x20)
        XCTAssertNil(patch.scrollMode)
        XCTAssertNil(patch.scrollAcceleration)
        XCTAssertNil(patch.scrollSmartReel)
        XCTAssertEqual(patch.dpiStages, [900, 1800, 3600])
        XCTAssertEqual(patch.activeStage, 2)
        XCTAssertEqual(patch.ledRGB?.r, persistedColor.r)
        XCTAssertEqual(patch.ledRGB?.g, persistedColor.g)
        XCTAssertEqual(patch.ledRGB?.b, persistedColor.b)
        XCTAssertEqual(buttonPatch.buttonBinding?.kind, .keyboardSimple)
        XCTAssertEqual(buttonPatch.buttonBinding?.hidKey, 80)
        XCTAssertEqual(editableColor, persistedColor)
        XCTAssertEqual(editableActiveStage, 3)
    }

    func testUSBHyperSpeedPersistedSettingsRestoreOmitsUnsupportedScrollAndBrightnessFields() async throws {
        let device = makeRefactorUSBLightingRestoreDevice(
            id: "usb-hyperspeed-filter-restore-device",
            serial: "USB-HS-FILTER-\(UUID().uuidString)"
        )
        let persistedColor = RGBColor(r: 91, g: 102, b: 113)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            makeRefactorSettingsSnapshot(color: persistedColor, zoneID: "scroll_wheel"),
            device: device
        )
        defer { clearRefactorPreferences(for: device) }

        let appState = await MainActor.run {
            AppState(
                launchRole: .app,
                backend: AppStateRefactorStubBackend(devices: [], stateByDeviceID: [:]),
                autoStart: false
            )
        }

        let plan = await MainActor.run {
            appState.editorController.persistedSettingsRestorePlan(device: device)
        }
        let patch = try XCTUnwrap(plan?.patch)
        XCTAssertNil(patch.scrollMode)
        XCTAssertNil(patch.scrollAcceleration)
        XCTAssertNil(patch.scrollSmartReel)
        XCTAssertNil(patch.ledBrightness)
        XCTAssertEqual(patch.ledRGB, RGBPatch(r: persistedColor.r, g: persistedColor.g, b: persistedColor.b))
    }

    func testBluetoothHyperspeedLightingApplyPersistsSnapshotFromAppliedPatch() async throws {
        let device = makeRefactorTestDevice(
            id: "bt-hyperspeed-lighting-snapshot",
            transport: .bluetooth,
            serial: "BT-HS-LIGHT-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "bluetooth",
                        batteryPercent: 67,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 1
                    )
                )
            ],
            holdFirstApply: true
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        let appliedColor = RGBColor(r: 12, g: 34, b: 56)
        let staleEditorColor = RGBColor(r: 200, g: 210, b: 220)
        await MainActor.run {
            appState.editorStore.editableColor = appliedColor
        }

        await MainActor.run {
            appState.editorStore.scheduleAutoApplyLedColor()
        }
        await backend.waitForFirstApplyToStart()

        await MainActor.run {
            appState.editorStore.editableColor = staleEditorColor
        }
        await backend.releaseFirstApply()

        let preferenceStore = DevicePreferenceStore()
        try await waitForRefactorCondition {
            await backend.applyCount() == 1 &&
                preferenceStore.loadPersistedDeviceSettingsSnapshot(device: device) != nil
        }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.first)
        let snapshot = try XCTUnwrap(preferenceStore.loadPersistedDeviceSettingsSnapshot(device: device))

        XCTAssertEqual(patch.ledRGB?.r, appliedColor.r)
        XCTAssertEqual(patch.ledRGB?.g, appliedColor.g)
        XCTAssertEqual(patch.ledRGB?.b, appliedColor.b)
        XCTAssertEqual(preferenceStore.loadPersistedLightingColor(device: device), appliedColor)
        XCTAssertEqual(snapshot.primaryLightingColor, appliedColor)
    }

    func testUseMouseConnectBehaviorDoesNotAutoRestorePersistedSettingsSnapshot() async throws {
        let device = MouseDevice(
            id: "bt-v3-pro-lighting-zone",
            vendor_id: 0x068E,
            product_id: 0x00AC,
            product_name: "Basilisk V3 Pro",
            transport: .bluetooth,
            path_b64: "",
            serial: "BT-V3PRO-LIGHT-\(UUID().uuidString)",
            firmware: "1.0.0",
            location_id: 1,
            profile_id: .basiliskV3Pro,
            supports_advanced_lighting_effects: false,
            onboard_profile_count: 3
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistDeviceSettingsSnapshot(
            makeRefactorSettingsSnapshot(color: RGBColor(r: 10, g: 20, b: 30)),
            device: device
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "bluetooth",
                        batteryPercent: 68,
                        dpiValues: [1200, 2400, 3600],
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
        let editableActiveStage = await MainActor.run { appState.editorStore.editableActiveStage }
        let connectBehavior = await MainActor.run { appState.editorStore.connectBehavior }
        let showsCard = await MainActor.run { appState.editorStore.showsConnectBehaviorCard }
        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(editableActiveStage, 2)
        XCTAssertEqual(connectBehavior, .useMouseSettings)
        XCTAssertFalse(showsCard)
    }

    func testRestoreInProgressSkipsAdditionalRefreshReadsForSameDevice() async throws {
        let alphaDevice = makeRefactorTestDevice(
            id: "restore-refresh-selected-device",
            transport: .usb,
            serial: "RESTORE-REFRESH-SELECTED-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        let betaDevice = makeRefactorTestDevice(
            id: "restore-refresh-target-device",
            transport: .usb,
            serial: "RESTORE-REFRESH-TARGET-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: betaDevice)
        preferenceStore.persistDeviceSettingsSnapshot(
            makeRefactorSettingsSnapshot(color: RGBColor(r: 10, g: 20, b: 30)),
            device: betaDevice
        )
        defer {
            clearRefactorPreferences(for: alphaDevice)
            clearRefactorPreferences(for: betaDevice)
        }

        let backend = AppStateRefactorStubBackend(
            devices: [alphaDevice, betaDevice],
            stateByDeviceID: [
                alphaDevice.id: makeRefactorTestState(
                    device: alphaDevice,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 81,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 0
                    )
                ),
                betaDevice.id: makeRefactorTestState(
                    device: betaDevice,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 74,
                        dpiValues: [1000, 2000, 3000],
                        activeStage: 1
                    )
                )
            ],
            shouldUseFastPolling: true,
            holdFirstApply: true
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        let refreshTask = Task {
            await appState.deviceStore.refreshDevices()
        }

        await backend.waitForFirstApplyToStart()

        let readCountBefore = await backend.readCount(for: betaDevice.id)
        let fastReadCountBefore = await backend.fastReadCount(for: betaDevice.id)

        let refreshed = await appState.deviceController.refreshState(for: betaDevice)
        await appState.deviceStore.refreshDpiFast()

        let readCountAfter = await backend.readCount(for: betaDevice.id)
        let fastReadCountAfter = await backend.fastReadCount(for: betaDevice.id)

        XCTAssertFalse(refreshed)
        XCTAssertEqual(readCountAfter, readCountBefore)
        XCTAssertEqual(fastReadCountAfter, fastReadCountBefore)

        await backend.releaseFirstApply()
        await refreshTask.value
    }

    func testRestoreButtonReplayDefersIntermediateReadbacksAndVerifiesOnceAtEnd() async throws {
        let device = makeRefactorUSBLightingRestoreDevice(
            id: "usb-restore-button-readback-device",
            serial: "USB-RESTORE-BUTTON-READBACK-\(UUID().uuidString)"
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            makeRefactorSettingsSnapshot(
                color: RGBColor(r: 10, g: 20, b: 30),
                buttonBindings: [
                    4: ButtonBindingDraft(
                        kind: .mouseForward,
                        hidKey: 4,
                        turboEnabled: false,
                        turboRate: 0x8E,
                        clutchDPI: nil
                    )
                ]
            ),
            device: device
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
                        dpiValues: [1200, 2400, 3600],
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
            await backend.applyCount() >= 2
        }

        let readCount = await backend.readCount(for: device.id)
        let policies = await backend.recordedApplyReadbackPolicies()
        XCTAssertEqual(readCount, 2)
        XCTAssertTrue(policies.contains(.skipStateReadback))
        if let first = policies.first, policies.count > 1 {
            XCTAssertEqual(first, .immediateStateReadback)
            XCTAssertTrue(policies.dropFirst().allSatisfy { $0 == .skipStateReadback })
        }
    }

    func testProfiledHyperspeedUsesEditableConnectBehaviorInProfilePicker() async throws {
        let device = makeRefactorTestDevice(
            id: "bt-hyperspeed-connect-behavior",
            transport: .bluetooth,
            serial: "BT-CONNECT-BEHAVIOR-\(UUID().uuidString)",
            onboardProfileCount: 1
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "bluetooth",
                        batteryPercent: 71,
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

        let initialBehavior = await MainActor.run { appState.editorStore.connectBehavior }
        XCTAssertEqual(initialBehavior, .useMouseSettings)

        await MainActor.run {
            appState.editorStore.updateConnectBehavior(.restoreOpenSnekSettings)
        }

        let updatedBehavior = await MainActor.run { appState.editorStore.connectBehavior }
        let showsCard = await MainActor.run { appState.editorStore.showsConnectBehaviorCard }
        XCTAssertEqual(updatedBehavior, .restoreOpenSnekSettings)
        XCTAssertFalse(showsCard)
    }

    func testOnboardStorageHidesConnectBehaviorAndIgnoresRestorePreference() async throws {
        let device = makeRefactorTestDevice(
            id: "onboard-storage-connect-behavior",
            transport: .usb,
            serial: "ONBOARD-CONNECT-BEHAVIOR-\(UUID().uuidString)",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            makeRefactorSettingsSnapshot(color: RGBColor(r: 10, g: 20, b: 30)),
            device: device
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 71,
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
        await MainActor.run {
            appState.editorStore.updateConnectBehavior(.restoreOpenSnekSettings)
        }

        let connectBehavior = await MainActor.run { appState.editorStore.connectBehavior }
        let showsCard = await MainActor.run { appState.editorStore.showsConnectBehaviorCard }
        let applyCount = await backend.applyCount()
        XCTAssertEqual(connectBehavior, .useMouseSettings)
        XCTAssertFalse(showsCard)
        XCTAssertEqual(applyCount, 0)
    }

    func testUSBHyperspeedUsesProfilePickerInsteadOfOnConnectCard() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-hyperspeed-connect-behavior",
            transport: .usb,
            serial: "USB-CONNECT-BEHAVIOR-\(UUID().uuidString)",
            onboardProfileCount: 1,
            profileID: .basiliskV3XHyperspeed
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 71,
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

        let connectBehavior = await MainActor.run { appState.editorStore.connectBehavior }
        let supportsProfilePicker = await MainActor.run { appState.editorStore.supportsProfilePicker }
        let showsCard = await MainActor.run { appState.editorStore.showsConnectBehaviorCard }
        XCTAssertEqual(connectBehavior, .useMouseSettings)
        XCTAssertTrue(supportsProfilePicker)
        XCTAssertFalse(showsCard)
    }

    func testDisabledSettingStorageKeepsReconnectRehydrationSourceAtLastStoredSnapshot() async throws {
        let device = makeRefactorTestDevice(
            id: "usb-storage-gated-restore-device",
            transport: .usb,
            serial: "USB-STORAGE-GATED-RESTORE-\(UUID().uuidString)",
            onboardProfileCount: 1,
            profileID: .basiliskV3Pro
        )
        let storedSnapshot = makeRefactorSettingsSnapshot(
            color: RGBColor(r: 20, g: 30, b: 40),
            zoneID: "scroll_wheel"
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(storedSnapshot, device: device)
        UserDefaults.standard.set(false, forKey: DeveloperRuntimeOptions.settingStorageEnabledDefaultsKey)
        defer {
            UserDefaults.standard.removeObject(forKey: DeveloperRuntimeOptions.settingStorageEnabledDefaultsKey)
            clearRefactorPreferences(for: device)
        }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 71,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 1
                    )
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await MainActor.run {
            appState.deviceStore.devices = [device]
            appState.deviceStore.selectedDeviceID = device.id
            appState.deviceController.syncSelectedDevicePresentation(deviceID: device.id)
        }

        await MainActor.run {
            appState.editorStore.editableActiveStage = 1
        }
        await appState.editorStore.applyDpiStages()
        try await waitForRefactorCondition {
            await backend.applyCount() >= 1
        }

        let snapshotAfterUnstoredEdit = preferenceStore.loadPersistedDeviceSettingsSnapshot(device: device)
        XCTAssertEqual(snapshotAfterUnstoredEdit, storedSnapshot)
        let rehydrationAppState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await MainActor.run {
            rehydrationAppState.deviceStore.devices = [device]
            rehydrationAppState.deviceStore.selectedDeviceID = device.id
            rehydrationAppState.deviceController.syncSelectedDevicePresentation(deviceID: device.id)
        }

        let restoredActiveStage = await MainActor.run { rehydrationAppState.editorStore.editableActiveStage }
        XCTAssertEqual(restoredActiveStage, storedSnapshot.activeStage)
    }

    func testNonLightingApplyDoesNotOverwriteStoredSnapshotLightingFromStaleEditorState() async throws {
        let device = makeRefactorUSBLightingRestoreDevice(
            id: "usb-stale-lighting-snapshot-device",
            serial: "USB-STALE-LIGHT-\(UUID().uuidString)"
        )
        let storedSnapshot = makeRefactorSettingsSnapshot(
            color: RGBColor(r: 255, g: 255, b: 255),
            zoneID: "scroll_wheel"
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(storedSnapshot, device: device)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 73,
                        dpiValues: [800, 1600, 3200],
                        activeStage: 1
                    )
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await MainActor.run {
            appState.deviceStore.devices = [device]
            appState.deviceStore.selectedDeviceID = device.id
            appState.deviceController.syncSelectedDevicePresentation(deviceID: device.id)
            appState.editorStore.editableColor = RGBColor(r: 0, g: 255, b: 0)
            appState.editorStore.editableUSBLightingZoneID = "logo"
            appState.editorStore.editableActiveStage = 1
        }

        await appState.editorStore.applyDpiStages()
        try await waitForRefactorCondition {
            await backend.applyCount() >= 1
        }

        let snapshotAfterApply = try XCTUnwrap(
            preferenceStore.loadPersistedDeviceSettingsSnapshot(device: device)
        )
        XCTAssertEqual(snapshotAfterApply.primaryLightingColor, storedSnapshot.primaryLightingColor)
        XCTAssertEqual(snapshotAfterApply.usbLightingZoneID, storedSnapshot.usbLightingZoneID)
        XCTAssertEqual(snapshotAfterApply.lightingEffect, storedSnapshot.lightingEffect)

        let rehydrationAppState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await rehydrationAppState.deviceStore.refreshDevices()
        try await waitForRefactorCondition {
            await backend.recordedPatches().contains(where: { patch in
                patch.ledRGB?.r == storedSnapshot.primaryLightingColor?.r &&
                    patch.ledRGB?.g == storedSnapshot.primaryLightingColor?.g &&
                    patch.ledRGB?.b == storedSnapshot.primaryLightingColor?.b &&
                    patch.usbLightingZoneLEDIDs == [0x01]
            })
        }
    }

    func testUSBV3ProUsesRememberedLightingStateWithoutAutoApply() async throws {
        let device = MouseDevice(
            id: "usb-v3-pro-lighting-zone",
            vendor_id: 0x1532,
            product_id: 0x00AB,
            product_name: "Basilisk V3 Pro",
            transport: .usb,
            path_b64: "",
            serial: "USB-V3PRO-LIGHT-\(UUID().uuidString)",
            firmware: "1.0.0",
            location_id: 1,
            profile_id: .basiliskV3Pro,
            supports_advanced_lighting_effects: false,
            onboard_profile_count: 5
        )
        let persistedColor = RGBColor(r: 11, g: 22, b: 33)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistLightingColor(persistedColor, device: device, zoneID: "logo")
        preferenceStore.persistLightingZoneID("logo", device: device)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 68,
                        dpiValues: [1200, 2400, 3600],
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
        let editableColor = await MainActor.run { appState.editorStore.editableColor }
        let editableZone = await MainActor.run { appState.editorStore.editableUSBLightingZoneID }

        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(editableColor, persistedColor)
        XCTAssertEqual(editableZone, "logo")
    }

    func testUSBPersistedSettingsSnapshotReappliesOnFirstHydrationUsingSavedZone() async throws {
        let device = makeRefactorUSBLightingRestoreDevice(
            id: "usb-lighting-device",
            serial: "USB-LIGHT-\(UUID().uuidString)"
        )
        let persistedColor = RGBColor(r: 40, g: 50, b: 60)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            makeRefactorSettingsSnapshot(color: persistedColor, zoneID: "scroll_wheel"),
            device: device
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeRefactorTestState(
                    device: device,
                    telemetry: RefactorTestStateTelemetry(
                        connection: "usb",
                        batteryPercent: 73,
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

        try await waitForRefactorCondition {
            await backend.applyCount() >= 1
        }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.first)
        let editableColor = await MainActor.run { appState.editorStore.editableColor }
        let editableZone = await MainActor.run { appState.editorStore.editableUSBLightingZoneID }

        XCTAssertEqual(patch.ledRGB?.r, persistedColor.r)
        XCTAssertEqual(patch.ledRGB?.g, persistedColor.g)
        XCTAssertEqual(patch.ledRGB?.b, persistedColor.b)
        XCTAssertNil(patch.lightingEffect)
        XCTAssertEqual(patch.usbLightingZoneLEDIDs, [0x01])
        XCTAssertEqual(editableColor, persistedColor)
        XCTAssertEqual(editableZone, "scroll_wheel")
    }

    func testSelectedDevicePresentationHydratesPersistedSettingsSnapshotBeforeStateRefresh() async throws {
        let device = makeRefactorUSBLightingRestoreDevice(
            id: "usb-selected-lighting-device",
            serial: "USB-SELECTED-LIGHT-\(UUID().uuidString)"
        )
        let persistedColor = RGBColor(r: 91, g: 102, b: 113)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            makeRefactorSettingsSnapshot(color: persistedColor, zoneID: "scroll_wheel"),
            device: device
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [], stateByDeviceID: [:])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await MainActor.run {
            _ = appState.deviceController.applyDeviceList([device], source: "refresh")
        }

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let editableColor = await MainActor.run { appState.editorStore.editableColor }
        let editableZone = await MainActor.run { appState.editorStore.editableUSBLightingZoneID }
        let editableActiveStage = await MainActor.run { appState.editorStore.editableActiveStage }
        let applyCount = await backend.applyCount()

        XCTAssertEqual(selectedDeviceID, device.id)
        XCTAssertEqual(editableColor, persistedColor)
        XCTAssertEqual(editableZone, "scroll_wheel")
        XCTAssertEqual(editableActiveStage, 3)
        XCTAssertEqual(applyCount, 0)
    }

    func testSelectedDeviceLiveDpiStillHydratesWhilePersistedConnectPresentationIsHeld() async throws {
        let device = makeRefactorUSBLightingRestoreDevice(
            id: "usb-selected-live-dpi-device",
            serial: "USB-SELECTED-LIVE-DPI-\(UUID().uuidString)"
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            PersistedDeviceSettingsSnapshot(
                stageCount: 5,
                stageValues: [600, 900, 1000, 1200, 1400],
                stagePairs: [
                    DpiPair(x: 600, y: 600),
                    DpiPair(x: 900, y: 900),
                    DpiPair(x: 1000, y: 1000),
                    DpiPair(x: 1200, y: 1200),
                    DpiPair(x: 1400, y: 1400)
                ],
                activeStage: 3,
                pollRate: 500,
                sleepTimeout: 420,
                lowBatteryThresholdRaw: 0x20,
                scrollMode: 1,
                scrollAcceleration: true,
                scrollSmartReel: false,
                ledBrightness: 77,
                primaryLightingColor: RGBColor(r: 91, g: 102, b: 113),
                lightingEffect: nil,
                usbLightingZoneID: "scroll_wheel",
                buttonBindings: [:]
            ),
            device: device
        )
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [], stateByDeviceID: [:])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await MainActor.run {
            _ = appState.deviceController.applyDeviceList([device], source: "refresh")
        }

        let persistedActiveStage = await MainActor.run { appState.editorStore.editableActiveStage }
        XCTAssertEqual(persistedActiveStage, 3)

        let liveState = makeRefactorTestState(
            device: device,
            telemetry: RefactorTestStateTelemetry(
                connection: "usb",
                batteryPercent: 81,
                dpiValues: [600, 900, 1000, 1200, 1400],
                activeStage: 0
            )
        )

        await MainActor.run {
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id,
                state: liveState,
                updatedAt: Date(timeIntervalSince1970: 1_777_909_776)
            )
        }

        let liveActiveStage = await MainActor.run { appState.editorStore.editableActiveStage }
        XCTAssertEqual(liveActiveStage, 1)
    }

    func testSelectedDeviceBackendStateUpdatePreservesPendingLocalEditsWhileUpdatingLiveDpiPresentation() async {
        let device = makeRefactorTestDevice(
            id: "backend-state-pending-live-dpi-device",
            transport: .usb,
            serial: "BACKEND-STATE-PENDING-LIVE-DPI-\(UUID().uuidString)",
            onboardProfileCount: 1,
            profileID: .basiliskV3Pro
        )
        let appState = await MainActor.run {
            AppState(
                launchRole: .app,
                backend: AppStateRefactorStubBackend(devices: [], stateByDeviceID: [:]),
                autoStart: false
            )
        }

        let initialState = makeRefactorTestState(
            device: device,
            telemetry: RefactorTestStateTelemetry(
                connection: "usb",
                batteryPercent: 81,
                dpiValues: [600, 900, 1000, 1200, 1400],
                activeStage: 1
            )
        )
        let liveState = makeRefactorTestState(
            device: device,
            telemetry: RefactorTestStateTelemetry(
                connection: "usb",
                batteryPercent: 81,
                dpiValues: [600, 900, 1000, 1200, 1400],
                activeStage: 3
            )
        )

        await MainActor.run {
            _ = appState.deviceController.applyDeviceList([device], source: "refresh")
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id,
                state: initialState,
                updatedAt: Date(timeIntervalSince1970: 1_777_909_780)
            )
            appState.editorStore.editablePollRate = 500
            appState.applyController.markLocalEditsPending()
            appState.deviceController.applyBackendDeviceStateUpdate(
                deviceID: device.id,
                state: liveState,
                updatedAt: Date(timeIntervalSince1970: 1_777_909_781)
            )
        }

        let liveActiveStage = await MainActor.run { appState.editorStore.editableActiveStage }
        let editablePollRate = await MainActor.run { appState.editorStore.editablePollRate }

        XCTAssertEqual(liveActiveStage, 4)
        XCTAssertEqual(editablePollRate, 500)
    }
}
