import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

/// Exercises remote service snapshot hydration behavior.
final class RemoteServiceSnapshotHydrationTests: XCTestCase {
    func testLocalBridgeMergedApplyStatePreservesBatteryAcrossBluetoothDelta() {
        let previous = makeSnapshotState(
            device: makeSnapshotDevice(
                id: "delta-device",
                productName: "Delta Mouse",
                identity: SnapshotDeviceIdentity(
                    transport: .bluetooth,
                    serial: "DELTA",
                    locationID: 9
                ),
                profile: .basiliskV3Pro
            ),
            connection: "bluetooth",
            batteryPercent: 83,
            dpiValues: [800, 1600, 2400],
            activeStage: 1
        )
        let delta = MouseState(
            device: previous.device,
            connection: previous.connection,
            battery_percent: nil,
            charging: nil,
            dpi: nil,
            dpi_stages: DpiStages(active_stage: nil, values: nil),
            poll_rate: nil,
            sleep_timeout: nil,
            device_mode: nil,
            low_battery_threshold_raw: nil,
            scroll_mode: nil,
            scroll_acceleration: nil,
            scroll_smart_reel: nil,
            active_onboard_profile: nil,
            onboard_profile_count: nil,
            led_value: 20,
            capabilities: previous.capabilities
        )

        let merged = LocalBridgeBackend.mergedApplyState(delta, previous: previous)

        XCTAssertEqual(merged.battery_percent, 83)
        XCTAssertEqual(merged.charging, false)
        XCTAssertEqual(merged.led_value, 20)
    }

    func testRemoteServiceBackendUsesRemoteTransport() async {
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false)
        }

        let usesRemoteTransport = await MainActor.run { appState.environment.usesRemoteServiceTransport }
        XCTAssertTrue(usesRemoteTransport)
    }

    func testApplyRemoteServiceSnapshotHydratesSelectedState() async {
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false)
        }

        let device = makeSnapshotDevice(
            id: "snapshot-device",
            productName: "Snapshot Mouse",
            identity: SnapshotDeviceIdentity(
                transport: .usb,
                serial: "SNAPSHOT",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let state = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 2400, 6400],
            activeStage: 1
        )
        let snapshot = SharedServiceSnapshot(
            devices: [device],
            stateByDeviceID: [device.id: state],
            lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_320_000)],
            softwareLightingStatusByDeviceID: [
                device.id: SoftwareLightingEngineStatus(
                    deviceID: device.id,
                    state: .running,
                    request: SoftwareLightingEffectRequest(presetID: .aurora),
                    updatedAt: Date(timeIntervalSince1970: 1_773_320_001)
                )
            ]
        )

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
        }

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let activeStage = await MainActor.run { appState.editorStore.editableActiveStage }
        let pollRate = await MainActor.run { appState.editorStore.editablePollRate }
        let softwareLightingStatus = await MainActor.run { appState.deviceStore.selectedSoftwareLightingStatus }

        XCTAssertEqual(selectedDeviceID, device.id)
        XCTAssertEqual(selectedDpi, 2400)
        XCTAssertEqual(activeStage, 2)
        XCTAssertEqual(pollRate, 1000)
        XCTAssertEqual(softwareLightingStatus?.state, .running)
        XCTAssertEqual(softwareLightingStatus?.request?.presetID, .aurora)
    }

    func testDuplicateRemoteServiceSnapshotDoesNotRefreshDiagnostics() async throws {
        let backend = SnapshotTestRemoteBackend(shouldUseFastDPIPolling: true)
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        let device = makeSnapshotDevice(
            id: "snapshot-duplicate-device",
            productName: "Snapshot Duplicate Mouse",
            identity: SnapshotDeviceIdentity(
                transport: .usb,
                serial: "SNAPSHOT-DUPLICATE",
                locationID: 2
            ),
            profile: .basiliskV3Pro
        )
        let state = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 2400, 6400],
            activeStage: 1
        )
        let updatedAt = Date(timeIntervalSince1970: 1_773_320_010)
        let snapshot = SharedServiceSnapshot(
            devices: [device],
            stateByDeviceID: [device.id: state],
            lastUpdatedByDeviceID: [device.id: updatedAt],
            observedAtByDeviceID: [device.id: updatedAt]
        )

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
        }

        try await waitUntil {
            await backend.dpiUpdateTransportStatusRequestCount() >= 1
        }

        let requestsAfterFirstSnapshot = await backend.dpiUpdateTransportStatusRequestCount()
        let revisionAfterFirstSnapshot = await MainActor.run {
            appState.deviceStore.connectionDiagnosticsRevision
        }

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
        }
        try await Task.sleep(nanoseconds: 80_000_000)

        let requestsAfterDuplicateSnapshot = await backend.dpiUpdateTransportStatusRequestCount()
        let revisionAfterDuplicateSnapshot = await MainActor.run {
            appState.deviceStore.connectionDiagnosticsRevision
        }

        XCTAssertEqual(requestsAfterDuplicateSnapshot, requestsAfterFirstSnapshot)
        XCTAssertEqual(revisionAfterDuplicateSnapshot, revisionAfterFirstSnapshot)
    }

    func testRemoteServiceSnapshotStartsPersistedSoftwareLightingApplyOnConnectOnce() async throws {
        let device = makeSnapshotDevice(
            id: "snapshot-software-lighting-auto",
            productName: "Basilisk V3 Pro",
            identity: SnapshotDeviceIdentity(
                transport: .usb,
                serial: "SNAPSHOT-SOFTWARE-LIGHTING-\(UUID().uuidString)",
                locationID: 0x0114_0000
            ),
            profile: .basiliskV3Pro
        )
        clearSnapshotPreferences(for: device)
        defer { clearSnapshotPreferences(for: device) }

        let request = SoftwareLightingEffectRequest(
            presetID: .cometChase,
            framesPerSecond: 24,
            speed: 1.25,
            palette: [
                RGBPatch(r: 12, g: 34, b: 56),
                RGBPatch(r: 90, g: 120, b: 240)
            ]
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistSoftwareLightingApplyOnConnect(true, device: device)
        preferenceStore.persistSoftwareLightingRequest(request, device: device)

        let backend = SnapshotSoftwareLightingRemoteBackend()
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        let state = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 2400, 6400],
            activeStage: 1
        )
        let snapshot = SharedServiceSnapshot(
            devices: [device],
            stateByDeviceID: [device.id: state],
            lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_320_000)]
        )

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
        }

        try await waitUntil {
            await backend.softwareLightingStartCount(for: device.id) == 1
        }

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
        }
        try await Task.sleep(nanoseconds: 80_000_000)

        let startCount = await backend.softwareLightingStartCount(for: device.id)
        let startedRequest = await backend.softwareLightingRequest(for: device.id)
        let storedStatus = await MainActor.run {
            appState.deviceStore.softwareLightingStatusByDeviceID[device.id]
        }

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(startedRequest, request)
        XCTAssertEqual(storedStatus?.state, .running)
        XCTAssertEqual(storedStatus?.request, request)
    }

    func testRemoteServiceSnapshotRestartsPersistedSoftwareLightingWhenServiceStatusIsMissing() async throws {
        let device = makeSnapshotDevice(
            id: "snapshot-software-lighting-reconcile",
            productName: "Basilisk V3 Pro",
            identity: SnapshotDeviceIdentity(
                transport: .usb,
                serial: "SNAPSHOT-SOFTWARE-LIGHTING-RECONCILE-\(UUID().uuidString)",
                locationID: 0x0115_0000
            ),
            profile: .basiliskV3Pro
        )
        clearSnapshotPreferences(for: device)
        defer { clearSnapshotPreferences(for: device) }

        let request = SoftwareLightingEffectRequest(
            presetID: .aurora,
            framesPerSecond: 24,
            speed: 1.5
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistSoftwareLightingApplyOnConnect(true, device: device)
        preferenceStore.persistSoftwareLightingRequest(request, device: device)

        let backend = SnapshotSoftwareLightingRemoteBackend()
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        let staleRunningStatus = SoftwareLightingEngineStatus(
            deviceID: device.id,
            state: .running,
            request: request,
            updatedAt: Date(timeIntervalSince1970: 1_773_320_000)
        )
        let state = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 2400, 6400],
            activeStage: 1
        )
        let snapshot = SharedServiceSnapshot(
            devices: [device],
            stateByDeviceID: [device.id: state],
            lastUpdatedByDeviceID: [device.id: Date()]
        )

        await MainActor.run {
            appState.deviceStore.softwareLightingStatusByDeviceID[device.id] = staleRunningStatus
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
        }

        try await waitUntil {
            await backend.softwareLightingStartCount(for: device.id) == 1
        }

        let startedRequest = await backend.softwareLightingRequest(for: device.id)
        let storedStatus = await MainActor.run {
            appState.deviceStore.softwareLightingStatusByDeviceID[device.id]
        }

        XCTAssertEqual(startedRequest, request)
        XCTAssertEqual(storedStatus?.state, .running)
        XCTAssertEqual(storedStatus?.request, request)
    }

    func testRemoteServiceSnapshotDoesNotRestartAuthoritativeStoppedSoftwareLightingStatus() async throws {
        let device = makeSnapshotDevice(
            id: "snapshot-software-lighting-stopped",
            productName: "Basilisk V3 Pro",
            identity: SnapshotDeviceIdentity(
                transport: .usb,
                serial: "SNAPSHOT-SOFTWARE-LIGHTING-STOPPED-\(UUID().uuidString)",
                locationID: 0x0116_0000
            ),
            profile: .basiliskV3Pro
        )
        clearSnapshotPreferences(for: device)
        defer { clearSnapshotPreferences(for: device) }

        let request = SoftwareLightingEffectRequest(presetID: .cometChase)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistSoftwareLightingApplyOnConnect(true, device: device)
        preferenceStore.persistSoftwareLightingRequest(request, device: device)

        let backend = SnapshotSoftwareLightingRemoteBackend()
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        let state = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 2400, 6400],
            activeStage: 1
        )
        let stoppedStatus = SoftwareLightingEngineStatus(
            deviceID: device.id,
            state: .stopped,
            request: nil
        )
        let snapshot = SharedServiceSnapshot(
            devices: [device],
            stateByDeviceID: [device.id: state],
            lastUpdatedByDeviceID: [device.id: Date()],
            softwareLightingStatusByDeviceID: [device.id: stoppedStatus]
        )

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
        }
        try await Task.sleep(nanoseconds: 80_000_000)

        let startCount = await backend.softwareLightingStartCount(for: device.id)
        let storedStatus = await MainActor.run {
            appState.deviceStore.softwareLightingStatusByDeviceID[device.id]
        }

        XCTAssertEqual(startCount, 0)
        XCTAssertEqual(storedStatus?.state, .stopped)
    }

    func testRemoteServiceSnapshotClearsLatchedUSBUnavailablePresentation() async {
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: SnapshotUnavailableRemoteBackend(), autoStart: false)
        }
        let device = makeSnapshotDevice(
            id: "snapshot-usb-unavailable-latch",
            productName: "Snapshot USB Mouse",
            identity: SnapshotDeviceIdentity(
                transport: .usb,
                serial: "SNAPSHOT-USB-UNAVAILABLE",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let state = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 2400, 6400],
            activeStage: 1
        )

        await MainActor.run {
            appState.deviceStore.devices = [device]
            appState.deviceStore.selectedDeviceID = device.id
        }
        let refreshed = await appState.deviceController.refreshState(for: device)
        let revisionAfterFailure = await MainActor.run { appState.deviceStore.connectionDiagnosticsRevision }
        let statusAfterFailure = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }

        let snapshotDate = Date()
        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(
                SharedServiceSnapshot(
                    devices: [device],
                    stateByDeviceID: [device.id: state],
                    lastUpdatedByDeviceID: [device.id: snapshotDate],
                    observedAtByDeviceID: [device.id: snapshotDate]
                )
            )
        }

        let revisionAfterSnapshot = await MainActor.run { appState.deviceStore.connectionDiagnosticsRevision }
        let statusAfterSnapshot = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }

        XCTAssertFalse(refreshed)
        XCTAssertEqual(statusAfterFailure, "Disconnected")
        XCTAssertGreaterThan(revisionAfterSnapshot, revisionAfterFailure)
        XCTAssertEqual(statusAfterSnapshot, "Connected")
        XCTAssertEqual(selectedDpi, 2400)
    }

    func testRemoteServiceSnapshotsKeepSelectedEditorHydratedFromLiveState() async {
        let device = makeSnapshotDevice(
            id: "snapshot-live-dpi-device",
            productName: "Snapshot Live DPI Mouse",
            identity: SnapshotDeviceIdentity(
                transport: .usb,
                serial: "SNAPSHOT-LIVE-DPI",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            PersistedDeviceSettingsSnapshot(
                stageCount: 3,
                stageValues: [900, 1800, 3600],
                stagePairs: [
                    DpiPair(x: 900, y: 900),
                    DpiPair(x: 1800, y: 1800),
                    DpiPair(x: 3600, y: 3600)
                ],
                activeStage: 3,
                pollRate: 500,
                sleepTimeout: 420,
                lowBatteryThresholdRaw: 0x20,
                scrollMode: 1,
                scrollAcceleration: true,
                scrollSmartReel: false,
                ledBrightness: 84,
                primaryLightingColor: RGBColor(r: 10, g: 20, b: 30),
                lightingEffect: nil,
                usbLightingZoneID: "all",
                buttonBindings: [:]
            ),
            device: device
        )
        defer { clearSnapshotPreferences(for: device) }

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false)
        }

        let initialState = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let laterState = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 1600, 3200],
            activeStage: 2
        )

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(
                SharedServiceSnapshot(
                    devices: [device],
                    stateByDeviceID: [device.id: initialState],
                    lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_320_000)]
                )
            )
            appState.deviceStore.applyRemoteServiceSnapshot(
                SharedServiceSnapshot(
                    devices: [device],
                    stateByDeviceID: [device.id: laterState],
                    lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_320_001)]
                )
            )
        }

        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let activeStage = await MainActor.run { appState.editorStore.editableActiveStage }

        XCTAssertEqual(selectedDpi, 3200)
        XCTAssertEqual(activeStage, 3)
    }

    func testRemoteServiceSnapshotRestoreLastProfileMarksKnownSingleSlotProfile() async {
        clearSavedButtonProfiles()
        let device = makeSnapshotDevice(
            id: "snapshot-restore-local-profile-device",
            productName: "Snapshot Restore Mouse",
            identity: SnapshotDeviceIdentity(
                transport: .bluetooth,
                serial: "SNAPSHOT-RESTORE-LOCAL-\(UUID().uuidString)",
                locationID: 3
            ),
            profile: .basiliskV3XHyperspeed
        )
        defer {
            clearSnapshotPreferences(for: device)
            clearSavedButtonProfiles()
        }

        let preferenceStore = DevicePreferenceStore()
        let restoredProfile = preferenceStore.createOpenSnekLocalProfile(
            name: "Travel",
            content: OpenSnekLocalProfileContent(
                dpi: OnboardDPIProfileSnapshot(
                    scalar: DpiPair(x: 1200, y: 1200),
                    activeStage: 0,
                    pairs: [
                        DpiPair(x: 1200, y: 1200),
                        DpiPair(x: 2400, y: 2400)
                    ]
                )
            )
        )
        preferenceStore.persistSelectedLocalProfileID(restoredProfile.id, device: device)
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: device)
        preferenceStore.persistDeviceSettingsSnapshot(
            PersistedDeviceSettingsSnapshot(
                stageCount: 2,
                stageValues: [1200, 2400],
                stagePairs: [
                    DpiPair(x: 1200, y: 1200),
                    DpiPair(x: 2400, y: 2400)
                ],
                activeStage: 1,
                pollRate: nil,
                sleepTimeout: nil,
                lowBatteryThresholdRaw: nil,
                scrollMode: nil,
                scrollAcceleration: nil,
                scrollSmartReel: nil,
                ledBrightness: nil,
                primaryLightingColor: nil,
                lightingEffect: nil,
                usbLightingZoneID: "all",
                buttonBindings: [:]
            ),
            device: device
        )

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false)
        }
        // This models a cold-launch app client attached to the background service. The
        // service snapshot owns live values, but the restored profile name must still come
        // from the persisted local-profile selection instead of reverting to Base Profile.
        let liveState = makeSnapshotState(
            device: device,
            connection: "bluetooth",
            batteryPercent: 81,
            dpiValues: [400, 800],
            activeStage: 1
        )

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(
                SharedServiceSnapshot(
                    devices: [device],
                    stateByDeviceID: [device.id: liveState],
                    lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_320_012)]
                )
            )
        }

        let summary = await MainActor.run {
            appState.editorStore.onboardProfileSummaries.first
        }
        let selectedName = await MainActor.run {
            appState.editorStore.selectedOnboardProfileName
        }

        XCTAssertEqual(summary?.metadata?.name, "Travel")
        XCTAssertEqual(selectedName, "Travel")
    }

    func testRemoteServiceSnapshotsPreservePendingLocalEditsWhileUpdatingLiveDpiPresentation() async {
        let device = makeSnapshotDevice(
            id: "snapshot-pending-live-dpi-device",
            productName: "Snapshot Pending Live DPI Mouse",
            identity: SnapshotDeviceIdentity(
                transport: .usb,
                serial: "SNAPSHOT-PENDING-LIVE-DPI",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false)
        }

        let initialState = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let laterState = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 1600, 3200],
            activeStage: 2
        )

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(
                SharedServiceSnapshot(
                    devices: [device],
                    stateByDeviceID: [device.id: initialState],
                    lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_320_010)]
                )
            )
            appState.editorStore.editablePollRate = 500
            appState.applyController.markLocalEditsPending()
            appState.deviceStore.applyRemoteServiceSnapshot(
                SharedServiceSnapshot(
                    devices: [device],
                    stateByDeviceID: [device.id: laterState],
                    lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_320_011)]
                )
            )
        }

        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let activeStage = await MainActor.run { appState.editorStore.editableActiveStage }
        let editablePollRate = await MainActor.run { appState.editorStore.editablePollRate }

        XCTAssertEqual(selectedDpi, 3200)
        XCTAssertEqual(activeStage, 3)
        XCTAssertEqual(editablePollRate, 500)
    }

    func testRemoteServiceAppDoesNotAutoRestorePersistedLightingOnRefreshForV3Pro() async throws {
        let device = makeSnapshotDevice(
            id: "remote-lighting-restore-device",
            productName: "Remote Lighting Mouse",
            identity: SnapshotDeviceIdentity(
                transport: .usb,
                serial: "REMOTE-LIGHTING",
                locationID: 7
            ),
            profile: .basiliskV3Pro
        )
        let state = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 78,
            dpiValues: [800, 1600, 2400],
            activeStage: 1
        )
        let backend = SnapshotRecordingRemoteBackend(device: device, state: state)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistLightingColor(RGBColor(r: 255, g: 0, b: 0), device: device)
        defer {
            clearSnapshotPreferences(for: device)
        }

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        try await waitUntil(timeout: 2.0) {
            await MainActor.run { appState.deviceStore.selectedDeviceID == device.id }
        }

        let applyCount = await backend.applyCount()
        XCTAssertEqual(applyCount, 0)
    }

    func testApplyRemoteServiceSnapshotWithoutStateTriggersImmediateRemoteRead() async throws {
        let device = makeSnapshotDevice(
            id: "snapshot-remote-read-device",
            productName: "Snapshot Remote Mouse",
            identity: SnapshotDeviceIdentity(
                transport: .usb,
                serial: "SNAPSHOT-READ",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let state = makeSnapshotState(
            device: device,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 2400, 6400],
            activeStage: 1
        )
        let backend = SnapshotReadbackRemoteBackend(stateByDeviceID: [device.id: state])
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        let snapshot = SharedServiceSnapshot(
            devices: [device],
            stateByDeviceID: [:],
            lastUpdatedByDeviceID: [:]
        )

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
        }

        try await waitUntil {
            await backend.readCount(for: device.id) == 1
        }

        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        XCTAssertEqual(selectedDpi, 2400)
    }

    func testApplyRemoteServiceSnapshotHydratesPersistedButtonBindingsForSelectedDevice() async throws {
        let device = makeSnapshotDevice(
            id: "snapshot-button-device",
            productName: "Snapshot Button Mouse",
            identity: SnapshotDeviceIdentity(
                transport: .bluetooth,
                serial: "SNAPSHOT-BTN-\(UUID().uuidString)",
                locationID: 4
            ),
            profile: .basiliskV3XHyperspeed
        )
        DevicePreferenceStore().savePersistedButtonBindings(
            device: device,
            bindings: [
                5: ButtonBindingDraft(
                    kind: .keyboardSimple,
                    hidKey: 80,
                    turboEnabled: false,
                    turboRate: 0x8E,
                    clutchDPI: nil
                )
            ],
            profile: 1
        )
        defer { clearSnapshotPreferences(for: device) }

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false)
        }

        let state = makeSnapshotState(
            device: device,
            connection: "bluetooth",
            batteryPercent: 79,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let snapshot = SharedServiceSnapshot(
            devices: [device],
            stateByDeviceID: [device.id: state],
            lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_320_100)]
        )

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
        }

        try await waitUntil {
            await MainActor.run {
                appState.editorStore.buttonBindingKind(for: 5) == .keyboardSimple &&
                    appState.editorStore.buttonBindingHidKey(for: 5) == 80
            }
        }

        let bindingKind = await MainActor.run { appState.editorStore.buttonBindingKind(for: 5) }
        let hidKey = await MainActor.run { appState.editorStore.buttonBindingHidKey(for: 5) }
        XCTAssertEqual(bindingKind, .keyboardSimple)
        XCTAssertEqual(hidKey, 80)
    }

    func testApplyRemoteServiceSnapshotHydratesPersistedLightingForSelectedDevice() async throws {
        let device = makeSnapshotDevice(
            id: "snapshot-lighting-device",
            productName: "Snapshot Lighting Mouse",
            identity: SnapshotDeviceIdentity(
                transport: .bluetooth,
                serial: "SNAPSHOT-LIGHT-\(UUID().uuidString)",
                locationID: 5
            ),
            profile: .basiliskV3XHyperspeed
        )
        let persistedColor = RGBColor(r: 255, g: 255, b: 255)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistLightingColor(persistedColor, device: device)
        preferenceStore.persistLightingZoneID("all", device: device)
        defer { clearSnapshotPreferences(for: device) }

        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false)
        }

        let state = makeSnapshotState(
            device: device,
            connection: "bluetooth",
            batteryPercent: 79,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let snapshot = SharedServiceSnapshot(
            devices: [device],
            stateByDeviceID: [device.id: state],
            lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_320_101)]
        )

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
        }

        try await waitUntil {
            await MainActor.run {
                appState.editorStore.editableColor == persistedColor
            }
        }

        let editableColor = await MainActor.run { appState.editorStore.editableColor }
        XCTAssertEqual(editableColor, persistedColor)
    }

}
