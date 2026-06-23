import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

final class AppStateMultiDeviceAvailabilityTests: XCTestCase {
    func testMappedOnboardProfileDevicesHideProfileButtonFromUnsupportedFootnote() async {
        let device = makeTestDevice(
            id: "profile-button-footnote-device",
            productName: "Profile Button Test Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "PROFILE-BUTTON",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let backend = MultiDeviceStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makeTestState(
                    device: device,
                    connection: "bluetooth",
                    batteryPercent: 74,
                    dpiValues: [800, 1600, 3200],
                    activeStage: 0
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        let hiddenSlots = await MainActor.run {
            appState.deviceStore.hiddenUnsupportedButtonSlots.map { $0.slot }
        }

        XCTAssertFalse(hiddenSlots.contains(106))
    }

    func testRefreshDevicesRefreshesAllDeviceCachesAndKeepsSelectedPresentationStable() async {
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
        let backend = MultiDeviceStubBackend(
            devices: [betaDevice, alphaDevice],
            stateByDeviceID: [
                alphaDevice.id: makeTestState(
                    device: alphaDevice,
                    connection: "usb",
                    batteryPercent: 81,
                    dpiValues: [1200, 2400, 3600],
                    activeStage: 0
                ),
                betaDevice.id: makeTestState(
                    device: betaDevice,
                    connection: "bluetooth",
                    batteryPercent: 72,
                    dpiValues: [3200, 4800, 6400],
                    activeStage: 1
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let initialReadOrder = await backend.recordedReadOrder()

        XCTAssertEqual(selectedDeviceID, alphaDevice.id)
        XCTAssertEqual(selectedDpi, 1200)
        XCTAssertEqual(initialReadOrder, [alphaDevice.id, betaDevice.id])

        await MainActor.run {
            appState.deviceStore.selectDevice(betaDevice.id)
        }

        let betaDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let activeStage = await MainActor.run { appState.editorStore.editableActiveStage }
        let readCountAfterSelection = await backend.readCount()

        XCTAssertEqual(betaDpi, 4800)
        XCTAssertEqual(activeStage, 2)
        XCTAssertEqual(readCountAfterSelection, 2)
    }

    func testRefreshDevicesBacksOffRepeatedlyFailingNonSelectedDevice() async {
        let bluetoothDevice = makeTestDevice(
            id: "bt-device",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "BT-OK",
                locationID: 1
            ),
            profile: .basiliskV3XHyperspeed
        )
        let unavailableDongle = makeTestDevice(
            id: "usb-dongle",
            productName: "Zeta Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-IDLE",
                locationID: 2
            ),
            profile: .basiliskV3Pro
        )
        let backend = PartiallyFailingMultiDeviceStubBackend(
            devices: [unavailableDongle, bluetoothDevice],
            stateByDeviceID: [
                bluetoothDevice.id: makeTestState(
                    device: bluetoothDevice,
                    connection: "bluetooth",
                    batteryPercent: 72,
                    dpiValues: [3200, 4800, 6400],
                    activeStage: 1
                )
            ],
            failingDeviceIDs: [unavailableDongle.id]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        let firstReadOrder = await backend.recordedReadOrder()

        await appState.deviceStore.refreshDevices()
        let secondReadOrder = await backend.recordedReadOrder()
        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }

        XCTAssertEqual(selectedDeviceID, bluetoothDevice.id)
        XCTAssertEqual(selectedDpi, 4800)
        XCTAssertEqual(firstReadOrder, [bluetoothDevice.id, unavailableDongle.id])
        XCTAssertEqual(secondReadOrder, [bluetoothDevice.id, unavailableDongle.id, bluetoothDevice.id])
    }

    func testSelectedUSBTelemetryUnavailableBacksOffAndDisconnectsDespitePassiveHID() async {
        let usbDevice = makeTestDevice(
            id: "usb-selected-telemetry-unavailable",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-SELECTED-TELEMETRY",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
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
        let telemetryUnavailable = "USB device telemetry unavailable. Feature-report interface did not return usable responses."

        await appState.deviceStore.refreshDevices()
        await MainActor.run {
            appState.deviceController.applyBackendDpiTransportStatusUpdate(
                deviceID: usbDevice.id,
                status: .streamActive,
                updatedAt: Date()
            )
        }
        let initialReadCount = await backend.readCount(for: usbDevice.id)
        await backend.setTransientReadFailures([telemetryUnavailable], for: usbDevice.id)

        let refreshed = await appState.deviceController.refreshState(for: usbDevice)
        let failedReadCount = await backend.readCount(for: usbDevice.id)
        let connectionState = await MainActor.run {
            appState.deviceStore.connectionState(for: usbDevice)
        }
        let warningAfterFailure = await MainActor.run { appState.deviceStore.warningMessage }
        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }

        XCTAssertFalse(refreshed)
        XCTAssertEqual(failedReadCount, initialReadCount + 1)
        XCTAssertEqual(connectionState, .disconnected)
        XCTAssertNil(warningAfterFailure)
        XCTAssertFalse(controlsEnabled)

        await appState.runtimeController.pollRuntimeOnce(now: Date(timeIntervalSince1970: 1_773_400_100))
        await appState.deviceStore.pollDevicePresence()

        let readCountAfterImmediatePolls = await backend.readCount(for: usbDevice.id)
        let presentedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }

        XCTAssertEqual(readCountAfterImmediatePolls, failedReadCount)
        XCTAssertEqual(presentedDpi, 800)
    }

    func testSelectedUSBTelemetryUnavailableWithCacheSurvivesDeviceListSync() async {
        let usbDevice = makeTestDevice(
            id: "usb-selected-telemetry-cached-sync",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-SELECTED-TELEMETRY-CACHED",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
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
        let telemetryUnavailable = "USB device telemetry unavailable. Feature-report interface did not return usable responses."

        await appState.deviceStore.refreshDevices()
        let initialReadCount = await backend.readCount(for: usbDevice.id)
        await backend.setTransientReadFailures([telemetryUnavailable], for: usbDevice.id)

        let refreshed = await appState.deviceController.refreshState(for: usbDevice)
        let failedReadCount = await backend.readCount(for: usbDevice.id)
        let stateAfterFailure = await MainActor.run { appState.deviceStore.state }
        let connectionAfterFailure = await MainActor.run {
            appState.deviceStore.connectionState(for: usbDevice)
        }
        await appState.deviceController.handleBackendDeviceListUpdate([usbDevice])
        let readCountAfterDeviceListUpdate = await backend.readCount(for: usbDevice.id)
        let stateAfterDeviceListUpdate = await MainActor.run { appState.deviceStore.state }
        let connectionAfterDeviceListUpdate = await MainActor.run {
            appState.deviceStore.connectionState(for: usbDevice)
        }
        let connectionAfterIdle = await MainActor.run {
            appState.deviceStore.connectionState(for: usbDevice)
        }
        let stateAfterIdle = await MainActor.run { appState.deviceStore.state }

        XCTAssertFalse(refreshed)
        XCTAssertEqual(failedReadCount, initialReadCount + 1)
        XCTAssertEqual(stateAfterFailure?.dpi?.x, 800)
        XCTAssertEqual(connectionAfterFailure, .disconnected)
        XCTAssertEqual(readCountAfterDeviceListUpdate, failedReadCount)
        XCTAssertEqual(stateAfterDeviceListUpdate?.dpi?.x, 800)
        XCTAssertEqual(connectionAfterDeviceListUpdate, .disconnected)
        XCTAssertEqual(stateAfterIdle?.dpi?.x, 800)
        XCTAssertEqual(connectionAfterIdle, .disconnected)
    }

    func testSelectedUSBCachedReceiverStaysConnectedWithoutExplicitUnavailable() async {
        let usbDevice = makeTestDevice(
            id: "usb-selected-cached-receiver-idle",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-SELECTED-CACHED-IDLE",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
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
        let readCountAfterHydration = await backend.readCount(for: usbDevice.id)
        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }
        let message = await MainActor.run { appState.deviceStore.selectedDeviceInteractionMessage }
        let warning = await MainActor.run { appState.deviceStore.warningMessage }
        let error = await MainActor.run { appState.deviceStore.errorMessage }
        let presentedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }

        XCTAssertEqual(readCountAfterHydration, 1)
        XCTAssertEqual(status, "Connected")
        XCTAssertTrue(controlsEnabled)
        XCTAssertNil(message)
        XCTAssertNil(warning)
        XCTAssertNil(error)
        XCTAssertEqual(presentedDpi, 800)
    }

    func testSelectedUSBTelemetryUnavailableWithoutCacheShowsDisconnectedWithoutError() async {
        let usbDevice = makeTestDevice(
            id: "usb-selected-telemetry-no-cache",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-SELECTED-NO-CACHE",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
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
        let telemetryUnavailable = "USB device telemetry unavailable. Feature-report interface did not return usable responses."
        await backend.setTransientReadFailures([telemetryUnavailable], for: usbDevice.id)

        await MainActor.run {
            appState.deviceStore.devices = [usbDevice]
            appState.deviceStore.selectedDeviceID = usbDevice.id
        }

        let refreshed = await appState.deviceController.refreshState(for: usbDevice)
        let errorMessage = await MainActor.run { appState.deviceStore.errorMessage }
        let presentedState = await MainActor.run { appState.deviceStore.state }
        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let message = await MainActor.run { appState.deviceStore.selectedDeviceInteractionMessage }
        let fastPollingDeviceIDs = await MainActor.run {
            appState.runtimeStore.activeFastPollingDeviceIDs(at: Date())
        }

        XCTAssertFalse(refreshed)
        XCTAssertNil(errorMessage)
        XCTAssertNil(presentedState)
        XCTAssertEqual(status, "Disconnected")
        XCTAssertTrue(fastPollingDeviceIDs.isEmpty)
        XCTAssertEqual(
            message,
            "The USB dongle is connected, but the mouse is not responding. Wake or power on the mouse to reconnect."
        )
    }

    func testSelectedUSBUnavailableThenReachableClearsBackoffAndRefreshes() async throws {
        let usbDevice = makeTestDevice(
            id: "usb-selected-telemetry-recovers",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-SELECTED-RECOVERS",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
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
        let telemetryUnavailable = "USB device telemetry unavailable. Feature-report interface did not return usable responses."

        await appState.deviceStore.refreshDevices()
        let initialReadCount = await backend.readCount(for: usbDevice.id)
        await backend.setTransientReadFailures([telemetryUnavailable], for: usbDevice.id)

        let failed = await appState.deviceController.refreshState(for: usbDevice)
        let failedReadCount = await backend.readCount(for: usbDevice.id)

        XCTAssertFalse(failed)
        XCTAssertEqual(failedReadCount, initialReadCount + 1)
        await MainActor.run {
            appState.deviceController.applyBackendUSBControlAvailabilityUpdate(
                deviceID: usbDevice.id,
                availability: .receiverPresentMouseReachable,
                updatedAt: Date()
            )
        }

        try await waitForAppStateCondition {
            await backend.readCount(for: usbDevice.id) >= failedReadCount + 1
        }

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }
        let errorMessage = await MainActor.run { appState.deviceStore.errorMessage }

        XCTAssertEqual(status, "Connected")
        XCTAssertTrue(controlsEnabled)
        XCTAssertNil(errorMessage)
    }

    func testUnavailableUSBReceiverProbeRecoversSleepingHyperSpeedWithoutPresenceEvent() async throws {
        let usbDevice = MouseDevice(
            id: "usb-v3x-hyperspeed-dongle-sleep",
            vendor_id: 0x1532,
            product_id: 0x00B9,
            product_name: "Basilisk V3 X HyperSpeed",
            transport: .usb,
            path_b64: "",
            serial: "V3X-HS-DONGLE-SLEEP",
            firmware: "1.0.0",
            location_id: 1,
            profile_id: .basiliskV3XHyperspeed,
            supports_advanced_lighting_effects: true,
            onboard_profile_count: 1
        )
        let initialState = makeTestState(
            device: usbDevice,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 1600, 3200],
            activeStage: 0
        )
        let recoveredState = makeTestState(
            device: usbDevice,
            connection: "usb",
            batteryPercent: 79,
            dpiValues: [800, 1600, 3200],
            activeStage: 1
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [usbDevice],
            stateByDeviceID: [usbDevice.id: initialState]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        let telemetryUnavailable = "USB device telemetry unavailable. Feature-report interface did not return usable responses."

        await appState.deviceStore.refreshDevices()
        let initialReadCount = await backend.readCount(for: usbDevice.id)
        await backend.setTransientReadFailures([telemetryUnavailable], for: usbDevice.id)

        let failed = await appState.deviceController.refreshState(for: usbDevice)
        let failedReadCount = await backend.readCount(for: usbDevice.id)
        let statusAfterFailure = await MainActor.run {
            appState.deviceStore.currentDeviceStatusIndicator.label
        }

        await backend.setState(recoveredState, for: usbDevice.id)
        await backend.setUSBControlAvailability(.receiverPresentMouseReachable, for: usbDevice.id)
        await appState.runtimeController.pollRuntimeOnce(now: Date(timeIntervalSince1970: 1_773_500_000))

        try await waitForAppStateCondition {
            await backend.readCount(for: usbDevice.id) >= failedReadCount + 1
        }

        let probeCount = await backend.usbControlAvailabilityProbeCount(for: usbDevice.id)
        let statusAfterRecovery = await MainActor.run {
            appState.deviceStore.currentDeviceStatusIndicator.label
        }
        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }
        let presentedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }

        XCTAssertFalse(failed)
        XCTAssertEqual(initialReadCount + 1, failedReadCount)
        XCTAssertEqual(statusAfterFailure, "Disconnected")
        XCTAssertEqual(probeCount, 1)
        XCTAssertEqual(statusAfterRecovery, "Connected")
        XCTAssertTrue(controlsEnabled)
        XCTAssertEqual(presentedDpi, 1600)
    }

    func testTransientBackendUSBUnavailableDoesNotFlickerConnectedMouse() async throws {
        let usbDevice = makeTestDevice(
            id: "usb-transient-unavailable",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-TRANSIENT-UNAVAILABLE",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
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
        await MainActor.run {
            let observedAt = Date()
            appState.deviceController.applyBackendDpiTransportStatusUpdate(
                deviceID: usbDevice.id,
                status: .streamActive,
                updatedAt: observedAt
            )
            appState.deviceController.applyBackendUSBControlAvailabilityUpdate(
                deviceID: usbDevice.id,
                availability: .receiverPresentMouseUnavailable,
                updatedAt: observedAt.addingTimeInterval(0.01)
            )
            appState.deviceController.applyBackendUSBControlAvailabilityUpdate(
                deviceID: usbDevice.id,
                availability: .receiverPresentMouseReachable,
                updatedAt: observedAt.addingTimeInterval(0.15)
            )
        }

        try await Task.sleep(
            nanoseconds: UInt64((AppStateDeviceController.usbControlUnavailableDebounceInterval + 0.15) * 1_000_000_000)
        )

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }
        let message = await MainActor.run { appState.deviceStore.selectedDeviceInteractionMessage }

        XCTAssertEqual(status, "Connected")
        XCTAssertTrue(controlsEnabled)
        XCTAssertNil(message)
    }

    func testBackendUSBUnavailableAppliesAfterDebounceWhenNotRecovered() async throws {
        let usbDevice = makeTestDevice(
            id: "usb-unavailable-debounced",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-UNAVAILABLE-DEBOUNCED",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
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
        await MainActor.run {
            let observedAt = Date()
            appState.deviceController.applyBackendDpiTransportStatusUpdate(
                deviceID: usbDevice.id,
                status: .streamActive,
                updatedAt: observedAt
            )
            appState.deviceController.applyBackendUSBControlAvailabilityUpdate(
                deviceID: usbDevice.id,
                availability: .receiverPresentMouseUnavailable,
                updatedAt: observedAt.addingTimeInterval(0.01)
            )
        }

        let immediateStatus = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        XCTAssertEqual(immediateStatus, "Connected")

        try await waitUntil(timeout: 1.0) {
            await MainActor.run {
                appState.deviceStore.currentDeviceStatusIndicator.label == "Disconnected"
            }
        }

        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }
        let message = await MainActor.run { appState.deviceStore.selectedDeviceInteractionMessage }

        XCTAssertFalse(controlsEnabled)
        XCTAssertEqual(
            message,
            "The USB dongle is connected, but the mouse is not responding. Wake or power on the mouse to reconnect."
        )
    }

    func testNewUSBInsertUnavailableReadStaysReconnectingDuringConnectGrace() async {
        let usbDevice = makeTestDevice(
            id: "usb-new-insert-connect-grace",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-NEW-INSERT-GRACE",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [],
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
        let telemetryUnavailable = "USB device telemetry unavailable. Feature-report interface did not return usable responses."

        await appState.deviceStore.refreshDevices()
        await backend.setTransientReadFailures([telemetryUnavailable], for: usbDevice.id)
        await appState.deviceController.handleBackendDeviceListUpdate([usbDevice], updatedAt: Date())

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }
        let errorMessage = await MainActor.run { appState.deviceStore.errorMessage }
        let warningMessage = await MainActor.run { appState.deviceStore.warningMessage }

        XCTAssertEqual(status, "Reconnecting")
        XCTAssertFalse(controlsEnabled)
        XCTAssertNil(errorMessage)
        XCTAssertNil(warningMessage)
    }

    func testSelectedUSBPartialTelemetryWithoutCacheShowsDisconnectedWithoutWarning() async {
        let usbDevice = makeTestDevice(
            id: "usb-selected-partial-telemetry-no-cache",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-SELECTED-PARTIAL-NO-CACHE",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let fullState = makeTestState(
            device: usbDevice,
            connection: "usb",
            batteryPercent: 81,
            dpiValues: [800, 1600, 3200],
            activeStage: 0
        )
        let partialState = MouseState(
            device: fullState.device,
            connection: fullState.connection,
            battery_percent: fullState.battery_percent,
            charging: fullState.charging,
            dpi: fullState.dpi,
            dpi_stages: DpiStages(active_stage: 0, values: nil),
            poll_rate: nil,
            sleep_timeout: fullState.sleep_timeout,
            device_mode: fullState.device_mode,
            low_battery_threshold_raw: fullState.low_battery_threshold_raw,
            scroll_mode: fullState.scroll_mode,
            scroll_acceleration: fullState.scroll_acceleration,
            scroll_smart_reel: fullState.scroll_smart_reel,
            active_onboard_profile: fullState.active_onboard_profile,
            onboard_profile_count: fullState.onboard_profile_count,
            led_value: nil,
            capabilities: fullState.capabilities
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [usbDevice],
            stateByDeviceID: [usbDevice.id: partialState]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await MainActor.run {
            appState.deviceStore.devices = [usbDevice]
            appState.deviceStore.selectedDeviceID = usbDevice.id
        }

        let refreshed = await appState.deviceController.refreshState(for: usbDevice)
        let errorMessage = await MainActor.run { appState.deviceStore.errorMessage }
        let warningMessage = await MainActor.run { appState.deviceStore.warningMessage }
        let presentedState = await MainActor.run { appState.deviceStore.state }
        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let readCount = await backend.readCount(for: usbDevice.id)

        XCTAssertFalse(refreshed)
        XCTAssertEqual(readCount, 1)
        XCTAssertNil(errorMessage)
        XCTAssertNil(warningMessage)
        XCTAssertNil(presentedState)
        XCTAssertEqual(status, "Disconnected")
    }

    func testSameDeviceListSubscriptionDoesNotClearUSBTelemetryUnavailableBackoff() async {
        let usbDevice = makeTestDevice(
            id: "usb-dongle-telemetry-backoff",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-DONGLE-BACKOFF",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
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
            ],
            dpiUpdateTransportStatus: .realTimeHID
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        let telemetryUnavailable = "USB device telemetry unavailable. Feature-report interface did not return usable responses."

        await appState.deviceStore.refreshDevices()
        let initialReadCount = await backend.readCount(for: usbDevice.id)
        await backend.setTransientReadFailures([telemetryUnavailable], for: usbDevice.id)

        let refreshed = await appState.deviceController.refreshState(for: usbDevice)
        let failedReadCount = await backend.readCount(for: usbDevice.id)
        let statusAfterFailure = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let statusAfterIdle = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        await appState.deviceController.handleBackendDeviceListUpdate([usbDevice])
        let readCountAfterStableSubscription = await backend.readCount(for: usbDevice.id)

        XCTAssertFalse(refreshed)
        XCTAssertEqual(failedReadCount, initialReadCount + 1)
        XCTAssertEqual(statusAfterFailure, "Disconnected")
        XCTAssertEqual(statusAfterIdle, "Disconnected")
        XCTAssertEqual(readCountAfterStableSubscription, failedReadCount)
    }

    func testNewlyVisibleUSBSubscriptionPreservesTelemetryUnavailableBackoff() async {
        let usbDevice = makeTestDevice(
            id: "usb-dongle-newly-visible-telemetry-backoff",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-DONGLE-NEW-BACKOFF",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
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
            ],
            dpiUpdateTransportStatus: .realTimeHID
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }
        let telemetryUnavailable = "USB device telemetry unavailable. Feature-report interface did not return usable responses."

        await appState.deviceStore.refreshDevices()
        let initialReadCount = await backend.readCount(for: usbDevice.id)
        await backend.setTransientReadFailures([telemetryUnavailable], for: usbDevice.id)

        let refreshed = await appState.deviceController.refreshState(for: usbDevice)
        let failedReadCount = await backend.readCount(for: usbDevice.id)
        await MainActor.run {
            appState.deviceStore.devices = []
        }
        await appState.deviceController.handleBackendDeviceListUpdate([usbDevice])
        let readCountAfterNewlyVisibleSubscription = await backend.readCount(for: usbDevice.id)

        XCTAssertFalse(refreshed)
        XCTAssertEqual(failedReadCount, initialReadCount + 1)
        XCTAssertEqual(readCountAfterNewlyVisibleSubscription, failedReadCount)
    }

    func testNewlyVisibleUSBSubscriptionPreservesAvailabilityBackoff() async {
        let usbDevice = makeTestDevice(
            id: "usb-dongle-newly-visible-availability-backoff",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-DONGLE-NEW-AVAILABILITY",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
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
            ],
            dpiUpdateTransportStatus: .realTimeHID
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        let initialReadCount = await backend.readCount(for: usbDevice.id)
        await backend.setTransientReadFailures(["Device not available"], for: usbDevice.id)

        let refreshed = await appState.deviceController.refreshState(for: usbDevice)
        let failedReadCount = await backend.readCount(for: usbDevice.id)
        await MainActor.run {
            appState.deviceStore.devices = []
        }
        await appState.deviceController.handleBackendDeviceListUpdate([usbDevice])
        let readCountAfterNewlyVisibleSubscription = await backend.readCount(for: usbDevice.id)

        XCTAssertFalse(refreshed)
        XCTAssertEqual(failedReadCount, initialReadCount + 1)
        XCTAssertEqual(readCountAfterNewlyVisibleSubscription, failedReadCount)
    }
}
