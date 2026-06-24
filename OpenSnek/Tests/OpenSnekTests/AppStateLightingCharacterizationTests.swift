import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

/// Exercises app state lighting characterization behavior.
final class AppStateLightingCharacterizationTests: XCTestCase {
    func testUSBLightingZoneSwitchLoadsPersistedZoneSpecificColor() async throws {
        let device = makeRefactorMultiZoneUSBLightingDevice(id: "usb-zone-switch-lighting-device", serial: "USB-ZONE-SWITCH-\(UUID().uuidString)")
        let wheelColor = RGBColor(r: 40, g: 50, b: 60)
        let logoColor = RGBColor(r: 70, g: 80, b: 90)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistLightingColor(wheelColor, device: device, zoneID: "scroll_wheel")
        preferenceStore.persistLightingColor(logoColor, device: device, zoneID: "logo")
        preferenceStore.persistLightingZoneID("scroll_wheel", device: device)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [], stateByDeviceID: [:])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await MainActor.run { _ = appState.deviceController.applyDeviceList([device], source: "refresh") }

        let initialColor = await MainActor.run { appState.editorStore.editableColor }
        let initialZone = await MainActor.run { appState.editorStore.editableUSBLightingZoneID }
        XCTAssertEqual(initialZone, "scroll_wheel")
        XCTAssertEqual(initialColor, wheelColor)

        await MainActor.run { appState.editorStore.updateUSBLightingZoneID("logo") }

        let selectedZoneColor = await MainActor.run { appState.editorStore.editableColor }
        let selectedZone = await MainActor.run { appState.editorStore.editableUSBLightingZoneID }
        let applyCount = await backend.applyCount()

        XCTAssertEqual(selectedZone, "logo")
        XCTAssertEqual(selectedZoneColor, logoColor)
        XCTAssertEqual(applyCount, 0)
    }

    func testLightingGradientUsesActualZoneColorsInVisibleOrder() async throws {
        let device = makeRefactorMultiZoneUSBLightingDevice(id: "usb-lighting-gradient-zones-device", serial: "USB-GRADIENT-ZONES-\(UUID().uuidString)")
        let wheelColor = RGBColor(r: 255, g: 0, b: 0)
        let logoColor = RGBColor(r: 0, g: 255, b: 0)
        let underglowColor = RGBColor(r: 0, g: 0, b: 255)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistLightingColor(wheelColor, device: device, zoneID: "scroll_wheel")
        preferenceStore.persistLightingColor(RGBColor(r: 12, g: 34, b: 56), device: device, zoneID: "logo")
        preferenceStore.persistLightingColor(underglowColor, device: device, zoneID: "underglow")
        preferenceStore.persistLightingZoneID("scroll_wheel", device: device)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [], stateByDeviceID: [:])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await MainActor.run {
            _ = appState.deviceController.applyDeviceList([device], source: "refresh")
            appState.editorStore.updateUSBLightingZoneID("logo")
            appState.editorStore.editableColor = logoColor
        }

        let gradientColors = await MainActor.run { appState.editorStore.lightingGradientDisplayColors }

        XCTAssertEqual(gradientColors, [wheelColor, logoColor, underglowColor])
    }

    func testLightingGradientUsesPersistedZoneColorsWhenEditingAllZones() async throws {
        let device = makeRefactorMultiZoneUSBLightingDevice(id: "usb-lighting-gradient-all-zones-device", serial: "USB-GRADIENT-ALL-\(UUID().uuidString)")
        let globalColor = RGBColor(r: 80, g: 90, b: 100)
        let wheelColor = RGBColor(r: 255, g: 0, b: 0)
        let logoColor = RGBColor(r: 0, g: 255, b: 0)
        let underglowColor = RGBColor(r: 0, g: 0, b: 255)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistLightingColor(globalColor, device: device)
        preferenceStore.persistLightingColor(wheelColor, device: device, zoneID: "scroll_wheel")
        preferenceStore.persistLightingColor(logoColor, device: device, zoneID: "logo")
        preferenceStore.persistLightingColor(underglowColor, device: device, zoneID: "underglow")
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [], stateByDeviceID: [:])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await MainActor.run {
            _ = appState.deviceController.applyDeviceList([device], source: "refresh")
            appState.editorStore.editableUSBLightingZoneID = "all"
            appState.editorStore.editableColor = globalColor
        }

        let gradientColors = await MainActor.run { appState.editorStore.lightingGradientDisplayColors }

        XCTAssertEqual(gradientColors, [wheelColor, logoColor, underglowColor])
    }

    func testUSBStaticMultiZonePresentationDoesNotLeaveEditorOnAllZones() async throws {
        let device = makeRefactorMultiZoneUSBLightingDevice(id: "usb-multizone-static-presentation-device", serial: "USB-MULTIZONE-\(UUID().uuidString)")
        let globalColor = RGBColor(r: 10, g: 20, b: 30)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistLightingColor(globalColor, device: device)
        preferenceStore.persistLightingZoneID("all", device: device)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [], stateByDeviceID: [:])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await MainActor.run { _ = appState.deviceController.applyDeviceList([device], source: "refresh") }

        let editableZone = await MainActor.run { appState.editorStore.editableUSBLightingZoneID }
        let editableColor = await MainActor.run { appState.editorStore.editableColor }

        XCTAssertEqual(editableZone, "scroll_wheel")
        XCTAssertEqual(editableColor, globalColor)
    }

    func testApplyCurrentStaticColorToAllZonesWritesGlobalPatchAndPersistsEveryZone() async throws {
        let device = makeRefactorMultiZoneUSBLightingDevice(id: "usb-apply-all-zones-device", serial: "USB-APPLY-ALL-\(UUID().uuidString)")
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 79, dpiValues: [800, 1600, 3200], activeStage: 1))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.updateUSBLightingZoneID("logo")
            appState.editorStore.editableColor = RGBColor(r: 111, g: 122, b: 133)
        }
        let gradientRevisionBeforeApply = await MainActor.run { appState.editorStore.lightingGradientRevision }

        await appState.editorStore.applyCurrentStaticColorToAllZones()

        try await waitForRefactorCondition { await backend.applyCount() == 1 }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.first)
        let editableZone = await MainActor.run { appState.editorStore.editableUSBLightingZoneID }
        let gradientRevisionAfterApply = await MainActor.run { appState.editorStore.lightingGradientRevision }
        let preferenceStore = DevicePreferenceStore()
        let expectedColor = RGBColor(r: 111, g: 122, b: 133)
        let settingsSnapshot = try XCTUnwrap(preferenceStore.loadPersistedDeviceSettingsSnapshot(device: device))

        XCTAssertEqual(patch.lightingEffect?.kind, .staticColor)
        XCTAssertNil(patch.usbLightingZoneLEDIDs)
        XCTAssertEqual(editableZone, "logo")
        XCTAssertGreaterThan(gradientRevisionAfterApply, gradientRevisionBeforeApply)
        XCTAssertEqual(preferenceStore.loadPersistedLightingZoneID(device: device), "logo")
        XCTAssertEqual(preferenceStore.loadPersistedLightingColor(device: device), expectedColor)
        XCTAssertEqual(preferenceStore.loadPersistedLightingColor(device: device, zoneID: "scroll_wheel"), expectedColor)
        XCTAssertEqual(preferenceStore.loadPersistedLightingColor(device: device, zoneID: "logo"), expectedColor)
        XCTAssertEqual(preferenceStore.loadPersistedLightingColor(device: device, zoneID: "underglow"), expectedColor)
        XCTAssertEqual(settingsSnapshot.primaryLightingColor, expectedColor)
        XCTAssertEqual(settingsSnapshot.usbLightingZoneID, "all")
    }

    func testNormalLightingApplyStopsSoftwareLighting() async throws {
        let device = makeRefactorMultiZoneUSBLightingDevice(id: "usb-software-lighting-static-conflict-device", serial: "USB-SOFTWARE-LIGHTING-STATIC-\(UUID().uuidString)")
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 79, dpiValues: [800, 1600, 3200], activeStage: 1))])
        let runningStatus = SoftwareLightingEngineStatus(deviceID: device.id, state: .running, request: SoftwareLightingEffectRequest(presetID: .flame))
        await backend.setSoftwareLightingStatus(runningStatus)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.deviceStore.softwareLightingStatusByDeviceID[device.id] = runningStatus
            appState.editorStore.updateUSBLightingZoneID("logo")
            appState.editorStore.editableColor = RGBColor(r: 111, g: 122, b: 133)
        }

        await appState.editorStore.applyCurrentStaticColorToAllZones()

        try await waitForRefactorCondition {
            let applyCount = await backend.applyCount()
            let stopCount = await backend.softwareLightingStopCount(for: device.id)
            let deviceStopCount = await backend.softwareLightingDeviceStopCount(for: device.id)
            return applyCount == 1 && stopCount == 1 && deviceStopCount == 1
        }

        let storedStatus = await MainActor.run { appState.deviceStore.softwareLightingStatusByDeviceID[device.id] }
        XCTAssertEqual(storedStatus?.state, .stopped)
    }

    func testNonLightingApplyDoesNotStopSoftwareLighting() async throws {
        let device = makeRefactorMultiZoneUSBLightingDevice(id: "usb-software-lighting-dpi-no-conflict-device", serial: "USB-SOFTWARE-LIGHTING-DPI-\(UUID().uuidString)")
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 79, dpiValues: [800, 1600, 3200], activeStage: 1))])
        let runningStatus = SoftwareLightingEngineStatus(deviceID: device.id, state: .running, request: SoftwareLightingEffectRequest(presetID: .scrollingRainbow))
        await backend.setSoftwareLightingStatus(runningStatus)

        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.deviceStore.softwareLightingStatusByDeviceID[device.id] = runningStatus
            appState.editorStore.editablePollRate = 500
        }

        await appState.editorStore.applyPollRate()

        try await waitForRefactorCondition { await backend.applyCount() == 1 }

        let stopCount = await backend.softwareLightingStopCount(for: device.id)
        let storedStatus = await MainActor.run { appState.deviceStore.softwareLightingStatusByDeviceID[device.id] }
        XCTAssertEqual(stopCount, 0)
        XCTAssertEqual(storedStatus?.state, .running)
    }

    func testSoftwareLightingApplyOnConnectStartsPersistedRequest() async throws {
        let device = makeRefactorMultiZoneUSBLightingDevice(id: "usb-software-lighting-auto-connect-device", serial: "USB-SOFTWARE-LIGHTING-AUTO-\(UUID().uuidString)")
        clearRefactorPreferences(for: device)
        defer { clearRefactorPreferences(for: device) }

        let persistedRequest = SoftwareLightingEffectRequest(presetID: .aurora, framesPerSecond: 24, intensity: 0.8, speed: 1.4, palette: [RGBPatch(r: 12, g: 34, b: 56), RGBPatch(r: 78, g: 90, b: 123), RGBPatch(r: 145, g: 167, b: 189)])
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistSoftwareLightingApplyOnConnect(true, device: device)
        preferenceStore.persistSoftwareLightingRequest(persistedRequest, device: device)

        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 79, dpiValues: [800, 1600, 3200], activeStage: 1))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()

        try await waitForRefactorCondition { await backend.softwareLightingStartCount(for: device.id) == 1 }

        let status = await backend.softwareLightingStatus(deviceID: device.id)
        let editorState = await MainActor.run {
            (
                applyOnConnect: appState.editorStore.editableSoftwareLightingApplyOnConnect, preset: appState.editorStore.editableSoftwareLightingPreset, speed: appState.editorStore.editableSoftwareLightingSpeed, brightness: appState.editorStore.editableSoftwareLightingBrightness,
                palette: appState.editorStore.editableSoftwareLightingPalette(for: .aurora)
            )
        }

        XCTAssertEqual(status?.state, .running)
        XCTAssertEqual(status?.request, persistedRequest)
        XCTAssertTrue(editorState.applyOnConnect)
        XCTAssertEqual(editorState.preset, .aurora)
        XCTAssertEqual(editorState.speed, persistedRequest.speed)
        XCTAssertEqual(editorState.brightness, persistedRequest.intensity)
        XCTAssertEqual(editorState.palette, persistedRequest.palette.map { RGBColor(r: $0.r, g: $0.g, b: $0.b) })
    }

    func testSoftwareLightingApplyPersistsRequestDetails() async throws {
        let device = makeRefactorMultiZoneUSBLightingDevice(id: "usb-software-lighting-persist-request-device", serial: "USB-SOFTWARE-LIGHTING-PERSIST-\(UUID().uuidString)")
        clearRefactorPreferences(for: device)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 79, dpiValues: [800, 1600, 3200], activeStage: 1))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.editorStore.updateEditableSoftwareLightingPreset(.cometChase)
            appState.editorStore.editableSoftwareLightingSpeed = 0.65
            appState.editorStore.editableSoftwareLightingBrightness = 0.42
            appState.editorStore.setEditableSoftwareLightingPalette([RGBColor(r: 101, g: 102, b: 103), RGBColor(r: 201, g: 202, b: 203)], for: .cometChase)
        }

        await appState.editorStore.startSoftwareLighting()

        try await waitForRefactorCondition { await backend.softwareLightingStartCount(for: device.id) == 1 }

        let persistedRequest = DevicePreferenceStore().loadPersistedSoftwareLightingRequest(device: device)
        XCTAssertEqual(persistedRequest, SoftwareLightingEffectRequest(presetID: .cometChase, intensity: 0.42, speed: 0.65, palette: [RGBPatch(r: 101, g: 102, b: 103), RGBPatch(r: 201, g: 202, b: 203)]))
    }

    func testUSBPersistedSettingsSnapshotRestoresStaticLightingAcrossAllZones() async throws {
        let device = makeRefactorMultiZoneUSBLightingDevice(id: "usb-restore-all-zones-device", serial: "USB-RESTORE-ALL-\(UUID().uuidString)")
        let persistedColor = RGBColor(r: 61, g: 72, b: 83)
        let persistedEffect = LightingEffectPatch(kind: .staticColor, primary: RGBPatch(r: persistedColor.r, g: persistedColor.g, b: persistedColor.b))
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(makeRefactorSettingsSnapshot(color: persistedColor, zoneID: "all", lightingEffect: persistedEffect), device: device)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 73, dpiValues: [800, 1600, 3200], activeStage: 1))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()

        try await waitForRefactorCondition { await backend.applyCount() >= 1 }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.first(where: { $0.lightingEffect?.kind == .staticColor }))

        XCTAssertEqual(patch.lightingEffect?.primary.r, persistedColor.r)
        XCTAssertEqual(patch.lightingEffect?.primary.g, persistedColor.g)
        XCTAssertEqual(patch.lightingEffect?.primary.b, persistedColor.b)
        XCTAssertNil(patch.usbLightingZoneLEDIDs)
    }

    func testUSBPersistedSettingsEffectReappliesOnFirstHydration() async throws {
        let device = makeRefactorUSBLightingRestoreDevice(id: "usb-effect-device", serial: "USB-EFFECT-\(UUID().uuidString)")
        let persistedColor = RGBColor(r: 70, g: 80, b: 90)
        let persistedEffect = LightingEffectPatch(kind: .wave, primary: RGBPatch(r: persistedColor.r, g: persistedColor.g, b: persistedColor.b), secondary: RGBPatch(r: 1, g: 2, b: 3), waveDirection: .right, reactiveSpeed: 4)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(makeRefactorSettingsSnapshot(color: persistedColor, zoneID: "logo", lightingEffect: persistedEffect), device: device)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 71, dpiValues: [800, 1600, 3200], activeStage: 1))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()

        try await waitForRefactorCondition { await backend.applyCount() >= 1 }

        let patches = await backend.recordedPatches()
        let patch = try XCTUnwrap(patches.first(where: { $0.lightingEffect != nil }))
        let effect = try XCTUnwrap(patch.lightingEffect)

        XCTAssertNil(patch.ledRGB)
        XCTAssertEqual(effect.kind, .wave)
        XCTAssertEqual(effect.primary.r, persistedColor.r)
        XCTAssertEqual(effect.primary.g, persistedColor.g)
        XCTAssertEqual(effect.primary.b, persistedColor.b)
        XCTAssertEqual(effect.secondary.r, 1)
        XCTAssertEqual(effect.secondary.g, 2)
        XCTAssertEqual(effect.secondary.b, 3)
        XCTAssertEqual(effect.waveDirection, .right)
        XCTAssertEqual(effect.reactiveSpeed, 4)
        XCTAssertNil(patch.usbLightingZoneLEDIDs)
    }

    func testMissingPersistedLightingDoesNotAutoApply() async throws {
        let device = makeRefactorTestDevice(id: "usb-no-lighting", transport: .usb, serial: "USB-NO-LIGHT-\(UUID().uuidString)", onboardProfileCount: 1)
        defer { clearRefactorPreferences(for: device) }

        let backend = AppStateRefactorStubBackend(devices: [device], stateByDeviceID: [device.id: makeRefactorTestState(device: device, telemetry: RefactorTestStateTelemetry(connection: "usb", batteryPercent: 75, dpiValues: [800, 1600, 3200], activeStage: 1))])
        let appState = await MainActor.run { AppState(launchRole: .app, backend: backend, autoStart: false) }

        await appState.deviceStore.refreshDevices()

        let applyCount = await backend.applyCount()
        XCTAssertEqual(applyCount, 0)
    }

}
