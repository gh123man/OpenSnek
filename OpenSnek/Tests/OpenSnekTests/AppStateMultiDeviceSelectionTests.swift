import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

/// Exercises app state multi device selection behavior.
final class AppStateMultiDeviceSelectionTests: XCTestCase {
    func testSelectingVisibleDeviceWithoutCachedStateStartsImmediateRefresh() async throws {
        let alphaDevice = makeTestDevice(
            id: "alpha-device",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "ALPHA",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let betaDevice = makeTestDevice(
            id: "beta-device",
            productName: "Beta Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "BETA",
                locationID: 2
            ),
            profile: .basiliskV3XHyperspeed
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [alphaDevice],
            stateByDeviceID: [
                alphaDevice.id: makeTestState(
                    device: alphaDevice,
                    connection: "usb",
                    batteryPercent: 81,
                    dpiValues: [1200, 2400, 3600],
                    activeStage: 0
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await backend.setState(
            makeTestState(
                device: betaDevice,
                connection: "bluetooth",
                batteryPercent: 72,
                dpiValues: [3200, 4800, 6400],
                activeStage: 1
            ),
            for: betaDevice.id
        )

        await MainActor.run {
            _ = appState.deviceController.applyDeviceList([alphaDevice, betaDevice], source: "test")
            appState.deviceStore.selectDevice(betaDevice.id)
        }

        try await waitForAppStateCondition {
            await backend.readCount(for: betaDevice.id) == 1
        }

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }

        XCTAssertEqual(selectedDeviceID, betaDevice.id)
        XCTAssertEqual(selectedDpi, 4800)
    }

    func testSelectedUnavailableDeviceWithCachedStateDisconnectsAndLocksControls() async {
        let usbDevice = makeTestDevice(
            id: "usb-dongle",
            productName: "Zeta Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-IDLE",
                locationID: 2
            ),
            profile: .basiliskV3Pro
        )
        let initialState = makeTestState(
            device: usbDevice,
            connection: "usb",
            batteryPercent: 72,
            dpiValues: [800, 900, 2000, 1100, 1200],
            activeStage: 2
        )
        let backend = DisconnectingMultiDeviceStubBackend(
            devices: [usbDevice],
            stateByDeviceID: [usbDevice.id: initialState]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await backend.setUnavailable(true)
        await appState.deviceStore.refreshState()
        await appState.deviceStore.pollDevicePresence()
        let immediateStatus = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let immediateControlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }

        await MainActor.run {
            _ = appState.deviceController.applyDeviceList([], source: "test")
        }

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }

        XCTAssertEqual(immediateStatus, "Disconnected")
        XCTAssertFalse(immediateControlsEnabled)
        XCTAssertEqual(status, "Disconnected")
        XCTAssertFalse(controlsEnabled)
    }

    func testSelectedUnavailableDeviceRecoveryStartsImmediateRefresh() async throws {
        let usbDevice = makeTestDevice(
            id: "usb-recovery",
            productName: "Zeta Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-RECOVER",
                locationID: 2
            ),
            profile: .basiliskV3Pro
        )
        let restoredState = makeTestState(
            device: usbDevice,
            connection: "usb",
            batteryPercent: 72,
            dpiValues: [800, 900, 2000, 1100, 1200],
            activeStage: 2
        )
        let backend = DisconnectingMultiDeviceStubBackend(
            devices: [usbDevice],
            stateByDeviceID: [usbDevice.id: restoredState]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await backend.setUnavailable(true)
        await appState.deviceStore.refreshState()
        await backend.setUnavailable(false)

        await MainActor.run {
            _ = appState.deviceController.applyDeviceList([], source: "test")
            _ = appState.deviceController.applyDeviceList([usbDevice], source: "test")
        }

        try await waitForAppStateCondition {
            await MainActor.run {
                appState.deviceStore.state?.dpi?.x == 2000
            }
        }

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        XCTAssertEqual(status, "Connected")
    }

    func testDiagnosticsExposePollingVsRealtimeHIDAndDisableControlsWhenDisconnected() async throws {
        let usbDevice = makeTestDevice(
            id: "usb-diagnostics",
            productName: "Zeta Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-DIAG",
                locationID: 3
            ),
            profile: .basiliskV3Pro
        )
        let initialState = makeTestState(
            device: usbDevice,
            connection: "usb",
            batteryPercent: 68,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [usbDevice],
            stateByDeviceID: [usbDevice.id: initialState],
            shouldUseFastDPIPolling: true
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await appState.deviceStore.refreshConnectionDiagnostics(for: usbDevice)

        let pollingLines = await MainActor.run { appState.deviceStore.diagnosticsConnectionLines(for: usbDevice) }
        let controlsInitiallyEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }
        XCTAssertTrue(pollingLines.contains("DPI updates: Polling fallback active"))
        XCTAssertTrue(controlsInitiallyEnabled)

        await backend.setShouldUseFastDPIPolling(false)
        await appState.deviceStore.refreshConnectionDiagnostics(for: usbDevice)

        let passiveLines = await MainActor.run { appState.deviceStore.diagnosticsConnectionLines(for: usbDevice) }
        XCTAssertTrue(passiveLines.contains("DPI updates: Real-time HID active"))

        await backend.emitDeviceListUpdate([])

        try await waitForAppStateCondition {
            await MainActor.run { !appState.deviceStore.selectedDeviceControlsEnabled }
        }

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        XCTAssertEqual(status, "Disconnected")
    }

    func testConnectedStatusPillStaysGreenWhileListeningForFirstHIDEvent() async {
        let bluetoothDevice = makeTestDevice(
            id: "bt-fallback",
            productName: "Basilisk V3 Pro",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "BT-FALLBACK",
                locationID: 4
            ),
            profile: .basiliskV3Pro
        )
        let initialState = makeTestState(
            device: bluetoothDevice,
            connection: "bluetooth",
            batteryPercent: 74,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [bluetoothDevice],
            stateByDeviceID: [bluetoothDevice.id: initialState],
            shouldUseFastDPIPolling: true,
            dpiUpdateTransportStatus: .listening
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        let indicator = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator }
        let connectionTooltip = await MainActor.run { appState.deviceStore.currentDeviceConnectionTooltip }
        let tooltip = await MainActor.run { appState.deviceStore.currentDeviceStatusTooltip }

        XCTAssertEqual(indicator.label, "Connected")
        XCTAssertEqual(OpenSnekCore.RGBColor.fromColor(indicator.color), RGBColor(r: 48, g: 209, b: 88))
        XCTAssertEqual(
            connectionTooltip,
            """
            Transport: Bluetooth
            Connection state: Live
            Control transport: bluetooth
            Real-time HID: Listening for first HID event
            Input Monitoring: Granted
            """
        )
        XCTAssertEqual(
            tooltip,
            """
            Control transport: bluetooth
            Telemetry: Live
            Real-time HID: Listening for first HID event
            Input Monitoring: Granted
            """
        )
    }

    func testConnectedStatusPillWarnsWhenRealtimeHIDFallsBack() async {
        let bluetoothDevice = makeTestDevice(
            id: "bt-warning",
            productName: "Basilisk V3 Pro",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "BT-WARNING",
                locationID: 5
            ),
            profile: .basiliskV3Pro
        )
        let initialState = makeTestState(
            device: bluetoothDevice,
            connection: "bluetooth",
            batteryPercent: 71,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [bluetoothDevice],
            stateByDeviceID: [bluetoothDevice.id: initialState],
            shouldUseFastDPIPolling: true,
            dpiUpdateTransportStatus: .pollingFallback,
            hidAccessAuthorization: .denied
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        let indicator = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator }
        let connectionTooltip = await MainActor.run { appState.deviceStore.currentDeviceConnectionTooltip }
        let tooltip = await MainActor.run { appState.deviceStore.currentDeviceStatusTooltip }

        XCTAssertEqual(indicator.label, "Connected")
        XCTAssertEqual(OpenSnekCore.RGBColor.fromColor(indicator.color), RGBColor(r: 244, g: 198, b: 93))
        XCTAssertEqual(
            connectionTooltip,
            """
            Transport: Bluetooth
            Connection state: Live
            Control transport: bluetooth
            Real-time HID: Polling fallback active
            Input Monitoring: Denied
            """
        )
        XCTAssertEqual(
            tooltip,
            """
            Control transport: bluetooth
            Telemetry: Live
            Real-time HID: Polling fallback active
            Input Monitoring: Denied
            """
        )
    }

    func testConnectionDiagnosticsRevisionUpdatesWhenTransportStatusChanges() async {
        let bluetoothDevice = makeTestDevice(
            id: "bt-revision",
            productName: "Basilisk V3 Pro",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "BT-REVISION",
                locationID: 6
            ),
            profile: .basiliskV3Pro
        )
        let initialState = makeTestState(
            device: bluetoothDevice,
            connection: "bluetooth",
            batteryPercent: 69,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [bluetoothDevice],
            stateByDeviceID: [bluetoothDevice.id: initialState],
            shouldUseFastDPIPolling: true,
            dpiUpdateTransportStatus: .pollingFallback
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        let initialRevision = await MainActor.run { appState.deviceStore.connectionDiagnosticsRevision }

        await backend.setDpiUpdateTransportStatus(.listening)
        await appState.deviceStore.refreshConnectionDiagnostics(for: bluetoothDevice)

        let updatedRevision = await MainActor.run { appState.deviceStore.connectionDiagnosticsRevision }
        let indicator = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator }

        XCTAssertGreaterThan(updatedRevision, initialRevision)
        XCTAssertEqual(indicator.label, "Connected")
        XCTAssertEqual(OpenSnekCore.RGBColor.fromColor(indicator.color), RGBColor(r: 48, g: 209, b: 88))
    }

    func testSelectedStateRefreshInvalidatesConnectionDiagnosticsAndUnlocksControls() async {
        let usbDevice = makeTestDevice(
            id: "usb-refresh-unlocks-controls",
            productName: "Basilisk V3 Pro",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-UNLOCKS",
                locationID: 7
            ),
            profile: .basiliskV3Pro
        )
        let refreshedState = makeTestState(
            device: usbDevice,
            connection: "usb",
            batteryPercent: 72,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [usbDevice],
            stateByDeviceID: [usbDevice.id: refreshedState]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        await MainActor.run {
            appState.deviceStore.devices = [usbDevice]
            appState.deviceStore.selectedDeviceID = usbDevice.id
        }

        let initialRevision = await MainActor.run { appState.deviceStore.connectionDiagnosticsRevision }
        let initiallyEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }

        await appState.deviceStore.refreshState()

        let updatedRevision = await MainActor.run { appState.deviceStore.connectionDiagnosticsRevision }
        let updatedEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }

        XCTAssertFalse(initiallyEnabled)
        XCTAssertGreaterThan(updatedRevision, initialRevision)
        XCTAssertTrue(updatedEnabled)
    }

    func testFastDpiPollingDoesNotDowngradeListeningStatusToFallback() async {
        let bluetoothDevice = makeTestDevice(
            id: "bt-listening-fast",
            productName: "Basilisk V3 Pro",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "BT-LISTENING-FAST",
                locationID: 7
            ),
            profile: .basiliskV3Pro
        )
        let initialState = makeTestState(
            device: bluetoothDevice,
            connection: "bluetooth",
            batteryPercent: 66,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [bluetoothDevice],
            stateByDeviceID: [bluetoothDevice.id: initialState],
            shouldUseFastDPIPolling: true,
            dpiUpdateTransportStatus: .listening
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await appState.deviceStore.refreshDpiFast()

        let indicator = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator }
        let tooltip = await MainActor.run { appState.deviceStore.currentDeviceStatusTooltip }

        XCTAssertEqual(indicator.label, "Connected")
        XCTAssertEqual(OpenSnekCore.RGBColor.fromColor(indicator.color), RGBColor(r: 48, g: 209, b: 88))
        XCTAssertTrue(tooltip?.contains("Real-time HID: Listening for first HID event") == true)
    }

    func testFreshPassiveHeartbeatKeepsBluetoothConnectedAfterIdleTelemetryGap() async {
        let bluetoothDevice = makeTestDevice(
            id: "bt-passive-heartbeat",
            productName: "Basilisk V3 Pro",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "BT-PASSIVE-HEARTBEAT",
                locationID: 8
            ),
            profile: .basiliskV3Pro
        )
        let initialState = makeTestState(
            device: bluetoothDevice,
            connection: "bluetooth",
            batteryPercent: 73,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [bluetoothDevice],
            stateByDeviceID: [bluetoothDevice.id: initialState],
            shouldUseFastDPIPolling: false,
            dpiUpdateTransportStatus: .streamActive
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        await MainActor.run {
            appState.deviceController.storeState(
                initialState,
                for: bluetoothDevice.id,
                updatedAt: Date().addingTimeInterval(-30)
            )
            appState.deviceController.applyBackendDpiTransportStatusUpdate(
                deviceID: bluetoothDevice.id,
                status: .streamActive,
                updatedAt: Date()
            )
        }

        let indicator = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator }
        let message = await MainActor.run { appState.deviceStore.selectedDeviceInteractionMessage }

        XCTAssertEqual(indicator.label, "Connected")
        XCTAssertNil(message)
    }

    func testBackendDeviceListUpdateRemovesDisconnectedDeviceImmediately() async throws {
        let bluetoothDevice = makeTestDevice(
            id: "bt-device",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "BT-ONE",
                locationID: 1
            ),
            profile: .basiliskV3XHyperspeed
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [bluetoothDevice],
            stateByDeviceID: [
                bluetoothDevice.id: makeTestState(
                    device: bluetoothDevice,
                    connection: "bluetooth",
                    batteryPercent: 72,
                    dpiValues: [800, 1600, 2400],
                    activeStage: 1
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await backend.emitDeviceListUpdate([])

        try await waitForAppStateCondition {
            await MainActor.run { appState.deviceStore.devices.isEmpty }
        }

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let state = await MainActor.run { appState.deviceStore.state }

        XCTAssertNil(selectedDeviceID)
        XCTAssertNil(state)
    }

    func testBackendDeviceListUpdateRefreshesStateForReconnectWithStableDeviceID() async throws {
        let usbDevice = makeTestDevice(
            id: "usb-reconnect",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-ONE",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let initialState = makeTestState(
            device: usbDevice,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 1600, 3200],
            activeStage: 0
        )
        let refreshedState = makeTestState(
            device: usbDevice,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 1600, 3200],
            activeStage: 2
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [usbDevice],
            stateByDeviceID: [usbDevice.id: initialState]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        let initialReadCount = await backend.readCount(for: usbDevice.id)

        await backend.setState(refreshedState, for: usbDevice.id)
        await backend.emitDeviceListUpdate([usbDevice])

        try await waitForAppStateCondition {
            await MainActor.run { appState.deviceStore.state?.dpi?.x == 3200 }
        }

        let readCount = await backend.readCount(for: usbDevice.id)
        let activeStage = await MainActor.run { appState.deviceStore.state?.dpi_stages.active_stage }

        XCTAssertGreaterThanOrEqual(readCount, initialReadCount + 1)
        XCTAssertEqual(activeStage, 2)
    }

    func testUSBReconnectWithNewDeviceIDSeedsPreviousState() async throws {
        let originalDevice = makeTestDevice(
            id: "usb-reconnect-original",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-RECONNECT-SERIAL",
                locationID: 1
            ),
            profile: .basiliskV335K
        )
        let replacementDevice = makeTestDevice(
            id: "usb-reconnect-replacement",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-RECONNECT-SERIAL",
                locationID: 2
            ),
            profile: .basiliskV335K
        )
        let originalState = makeTestState(
            device: originalDevice,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 1600, 3200],
            activeStage: 0
        )
        let replacementState = makeTestState(
            device: replacementDevice,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 1600, 3200],
            activeStage: 2
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [originalDevice],
            stateByDeviceID: [
                originalDevice.id: originalState,
                replacementDevice.id: replacementState
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await backend.setTransientReadFailures([
            "USB device telemetry unavailable. Feature-report interface did not return usable responses."
        ], for: replacementDevice.id)
        await backend.emitDeviceListUpdate([replacementDevice])

        try await waitForAppStateCondition {
            await MainActor.run { appState.deviceStore.selectedDeviceID == replacementDevice.id }
        }

        let seededDeviceID = await MainActor.run { appState.deviceStore.state?.device.id }
        let seededDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        XCTAssertEqual(seededDeviceID, replacementDevice.id)
        XCTAssertEqual(seededDpi, 800)
    }

    func testBackendDeviceListUpdateRearmsSettingsRestoreForStableReconnect() async throws {
        let usbDevice = makeTestDevice(
            id: "usb-lighting-reconnect",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-LIGHTING-RECONNECT",
                locationID: 1
            ),
            profile: .basiliskV3XHyperspeed
        )
        let persistedColor = RGBColor(r: 11, g: 22, b: 33)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: usbDevice)
        preferenceStore.persistDeviceSettingsSnapshot(makeMultiDeviceSettingsSnapshot(color: persistedColor), device: usbDevice)
        defer { clearMultiDeviceLightingPreferences(for: usbDevice) }

        let backend = DeviceListUpdatingStubBackend(
            devices: [usbDevice],
            stateByDeviceID: [
                usbDevice.id: makeTestState(
                    device: usbDevice,
                    connection: "usb",
                    batteryPercent: 81,
                    dpiValues: [800, 1600, 3200],
                    activeStage: 0
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        try await waitForAppStateCondition {
            let patches = await backend.recordedPatches()
            return patches.filter { $0.pollRate == 500 && $0.ledRGB?.r == persistedColor.r }.count >= 1
        }

        await backend.emitDeviceListUpdate([usbDevice])

        let initialApplyCount = await backend.applyCount()

        try await waitForAppStateCondition {
            await backend.applyCount() >= initialApplyCount + 1
        }

        let patches = await backend.recordedPatches()
        let restorePatches = patches.filter { $0.pollRate == 500 }
        let restoredPrimaryRs = restorePatches.compactMap { patch in
            patch.ledRGB?.r ?? patch.lightingEffect?.primary.r
        }
        XCTAssertGreaterThanOrEqual(restorePatches.count, 2)
        XCTAssertGreaterThanOrEqual(restoredPrimaryRs.count, 2)
        XCTAssertEqual(restoredPrimaryRs[0], persistedColor.r)
        XCTAssertEqual(restoredPrimaryRs[1], persistedColor.r)
    }

    func testNonSelectedReconnectSettingsRestoreDoesNotChangeSelection() async throws {
        let alphaDevice = makeTestDevice(
            id: "alpha-selected",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "ALPHA-SELECTED",
                locationID: 1
            ),
            profile: .basiliskV3XHyperspeed
        )
        let betaDevice = makeTestDevice(
            id: "beta-restore",
            productName: "Beta Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "BETA-RESTORE",
                locationID: 2
            ),
            profile: .basiliskV3XHyperspeed
        )
        let persistedColor = RGBColor(r: 21, g: 31, b: 41)
        let preferenceStore = DevicePreferenceStore()
        preferenceStore.persistConnectBehavior(.restoreOpenSnekSettings, device: betaDevice)
        preferenceStore.persistDeviceSettingsSnapshot(makeMultiDeviceSettingsSnapshot(color: persistedColor), device: betaDevice)
        defer {
            clearMultiDeviceLightingPreferences(for: alphaDevice)
            clearMultiDeviceLightingPreferences(for: betaDevice)
        }

        let backend = DeviceListUpdatingStubBackend(
            devices: [betaDevice, alphaDevice],
            stateByDeviceID: [
                alphaDevice.id: makeTestState(
                    device: alphaDevice,
                    connection: "usb",
                    batteryPercent: 81,
                    dpiValues: [800, 1600, 3200],
                    activeStage: 0
                ),
                betaDevice.id: makeTestState(
                    device: betaDevice,
                    connection: "usb",
                    batteryPercent: 79,
                    dpiValues: [800, 1600, 3200],
                    activeStage: 1
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        try await waitForAppStateCondition {
            let applyDeviceIDs = await backend.recordedApplyDeviceIDs()
            return !applyDeviceIDs.isEmpty
        }

        let initialSelectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let initialApplyDevices = await backend.recordedApplyDeviceIDs()
        XCTAssertEqual(initialSelectedDeviceID, alphaDevice.id)
        XCTAssertTrue(initialApplyDevices.allSatisfy { $0 == betaDevice.id })

        await backend.emitDeviceListUpdate([betaDevice, alphaDevice])

        try await waitForAppStateCondition {
            let applyDeviceIDs = await backend.recordedApplyDeviceIDs()
            return applyDeviceIDs.count >= initialApplyDevices.count + 1
        }

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let applyDeviceIDs = await backend.recordedApplyDeviceIDs()

        XCTAssertEqual(selectedDeviceID, alphaDevice.id)
        XCTAssertTrue(applyDeviceIDs.allSatisfy { $0 == betaDevice.id })
        XCTAssertGreaterThanOrEqual(applyDeviceIDs.count, initialApplyDevices.count + 1)
    }

}
