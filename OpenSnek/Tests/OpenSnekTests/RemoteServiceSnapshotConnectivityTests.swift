import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

/// Exercises remote service snapshot connectivity behavior.
final class RemoteServiceSnapshotConnectivityTests: XCTestCase {
    func testApplyingLaterSnapshotKeepsExistingLocalSelection() async {
        let appState = await MainActor.run { AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false) }

        let bluetoothDevice = makeSnapshotDevice(id: "bluetooth-device", productName: "A Bluetooth Mouse", identity: SnapshotDeviceIdentity(transport: .bluetooth, serial: "BT", locationID: 2), profile: .basiliskV3XHyperspeed)
        let usbDevice = makeSnapshotDevice(id: "usb-device", productName: "Z USB Mouse", identity: SnapshotDeviceIdentity(transport: .usb, serial: "USB", locationID: 1), profile: .basiliskV3Pro)
        let initialSnapshot = SharedServiceSnapshot(
            devices: [bluetoothDevice, usbDevice],
            stateByDeviceID: [
                bluetoothDevice.id: makeSnapshotState(device: bluetoothDevice, connection: "bluetooth", batteryPercent: 74, dpiValues: [1200, 2400, 3200], activeStage: 2),
                usbDevice.id: makeSnapshotState(device: usbDevice, connection: "usb", batteryPercent: 81, dpiValues: [800, 2400, 6400], activeStage: 1)
            ], lastUpdatedByDeviceID: [bluetoothDevice.id: Date(timeIntervalSince1970: 1_773_320_010), usbDevice.id: Date(timeIntervalSince1970: 1_773_320_000)])
        let laterSnapshot = SharedServiceSnapshot(
            devices: [bluetoothDevice, usbDevice],
            stateByDeviceID: [
                bluetoothDevice.id: makeSnapshotState(device: bluetoothDevice, connection: "bluetooth", batteryPercent: 75, dpiValues: [1400, 2800, 4200], activeStage: 2),
                usbDevice.id: makeSnapshotState(device: usbDevice, connection: "usb", batteryPercent: 82, dpiValues: [900, 1800, 3600], activeStage: 0)
            ], lastUpdatedByDeviceID: [bluetoothDevice.id: Date(timeIntervalSince1970: 1_773_320_020), usbDevice.id: Date(timeIntervalSince1970: 1_773_320_021)])

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(initialSnapshot)
            appState.deviceStore.selectDevice(usbDevice.id)
            appState.deviceStore.applyRemoteServiceSnapshot(laterSnapshot)
        }

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let selectedBattery = await MainActor.run { appState.deviceStore.state?.battery_percent }
        let activeStage = await MainActor.run { appState.editorStore.editableActiveStage }

        XCTAssertEqual(selectedDeviceID, usbDevice.id)
        XCTAssertEqual(selectedDpi, 900)
        XCTAssertEqual(selectedBattery, 82)
        XCTAssertEqual(activeStage, 1)
    }

    func testCurrentDeviceStatusUsesSelectedDevicePresenceFromSnapshotCache() async {
        let appState = await MainActor.run { AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(shouldUseFastDPIPolling: true), autoStart: false) }

        let alphaDevice = makeSnapshotDevice(id: "alpha-device", productName: "Alpha Mouse", identity: SnapshotDeviceIdentity(transport: .usb, serial: "ALPHA", locationID: 1), profile: .basiliskV3Pro)
        let betaDevice = makeSnapshotDevice(id: "beta-device", productName: "Beta Mouse", identity: SnapshotDeviceIdentity(transport: .usb, serial: "BETA", locationID: 2), profile: .basiliskV3XHyperspeed)
        let snapshot = SharedServiceSnapshot(
            devices: [alphaDevice, betaDevice],
            stateByDeviceID: [
                alphaDevice.id: makeSnapshotState(device: alphaDevice, connection: "usb", batteryPercent: 70, dpiValues: [800, 1600, 2400], activeStage: 0), betaDevice.id: makeSnapshotState(device: betaDevice, connection: "usb", batteryPercent: 72, dpiValues: [1000, 2000, 3000], activeStage: 1)
            ], lastUpdatedByDeviceID: [alphaDevice.id: Date(timeIntervalSince1970: 1_700_000_000), betaDevice.id: Date()])

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
            appState.deviceStore.selectDevice(alphaDevice.id)
        }
        let staleLabel = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }

        await MainActor.run { appState.deviceStore.selectDevice(betaDevice.id) }
        let freshLabel = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }

        XCTAssertEqual(staleLabel, "Connected")
        XCTAssertEqual(freshLabel, "Connected")
    }

    func testRemoteSnapshotFreshUSBObservationKeepsStaleFullStateConnected() async {
        let appState = await MainActor.run { AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(shouldUseFastDPIPolling: true), autoStart: false) }

        let device = makeSnapshotDevice(id: "usb-fresh-observation", productName: "Snapshot USB Mouse", identity: SnapshotDeviceIdentity(transport: .usb, serial: "USB-FRESH", locationID: 4), profile: .basiliskV3Pro)
        let now = Date()
        let snapshot = SharedServiceSnapshot(
            devices: [device], stateByDeviceID: [device.id: makeSnapshotState(device: device, connection: "usb", batteryPercent: 80, dpiValues: [800, 1600, 3200], activeStage: 1)], lastUpdatedByDeviceID: [device.id: now.addingTimeInterval(-30)], observedAtByDeviceID: [device.id: now])

        await MainActor.run { appState.deviceStore.applyRemoteServiceSnapshot(snapshot) }

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        XCTAssertEqual(status, "Connected")
    }

    func testRemoteSnapshotFreshFullStateOverridesStaleUSBObservation() async {
        let appState = await MainActor.run { AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(shouldUseFastDPIPolling: true), autoStart: false) }

        let device = makeSnapshotDevice(id: "usb-stale-observation", productName: "Snapshot USB Mouse", identity: SnapshotDeviceIdentity(transport: .usb, serial: "USB-STALE", locationID: 5), profile: .basiliskV3Pro)
        let now = Date()
        let snapshot = SharedServiceSnapshot(
            devices: [device], stateByDeviceID: [device.id: makeSnapshotState(device: device, connection: "usb", batteryPercent: 80, dpiValues: [800, 1600, 3200], activeStage: 1)], lastUpdatedByDeviceID: [device.id: now], observedAtByDeviceID: [device.id: now.addingTimeInterval(-5)])

        await MainActor.run { appState.deviceStore.applyRemoteServiceSnapshot(snapshot) }

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let message = await MainActor.run { appState.deviceStore.selectedDeviceInteractionMessage }
        XCTAssertEqual(status, "Connected")
        XCTAssertNil(message)
    }

    func testRemoteSnapshotUSBUnavailableOverridesFreshCachedState() async {
        let appState = await MainActor.run { AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(shouldUseFastDPIPolling: true), autoStart: false) }

        let device = makeSnapshotDevice(id: "usb-explicit-unavailable", productName: "Snapshot USB Mouse", identity: SnapshotDeviceIdentity(transport: .usb, serial: "USB-EXPLICIT-UNAVAILABLE", locationID: 4), profile: .basiliskV3Pro)
        let now = Date()
        let connectedSnapshot = SharedServiceSnapshot(
            devices: [device], stateByDeviceID: [device.id: makeSnapshotState(device: device, connection: "usb", batteryPercent: 80, dpiValues: [800, 1600, 3200], activeStage: 1)], lastUpdatedByDeviceID: [device.id: now.addingTimeInterval(-1)],
            observedAtByDeviceID: [device.id: now.addingTimeInterval(-1)])
        let snapshot = SharedServiceSnapshot(
            devices: [device], stateByDeviceID: [device.id: makeSnapshotState(device: device, connection: "usb", batteryPercent: 80, dpiValues: [800, 1600, 3200], activeStage: 1)], lastUpdatedByDeviceID: [device.id: now], observedAtByDeviceID: [device.id: now],
            usbControlAvailabilityByDeviceID: [device.id: .receiverPresentMouseUnavailable])

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(connectedSnapshot)
            appState.deviceStore.applyRemoteServiceSnapshot(snapshot)
        }

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }
        let message = await MainActor.run { appState.deviceStore.selectedDeviceInteractionMessage }
        let presentedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }

        XCTAssertEqual(status, "Disconnected")
        XCTAssertFalse(controlsEnabled)
        XCTAssertEqual(presentedDpi, 1600)
        XCTAssertEqual(message, "The USB dongle is connected, but the mouse is not responding. Wake or power on the mouse to reconnect.")
    }

    func testStaleRemoteSnapshotUSBUnavailableDoesNotOverrideNewerUSBActivity() async {
        let appState = await MainActor.run { AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(shouldUseFastDPIPolling: true), autoStart: false) }

        let device = makeSnapshotDevice(id: "usb-stale-unavailable", productName: "Snapshot USB Mouse", identity: SnapshotDeviceIdentity(transport: .usb, serial: "USB-STALE-UNAVAILABLE", locationID: 4), profile: .basiliskV3Pro)
        let newerAt = Date()
        let newerSnapshot = SharedServiceSnapshot(
            devices: [device], stateByDeviceID: [device.id: makeSnapshotState(device: device, connection: "usb", batteryPercent: 80, dpiValues: [800, 1600, 3200], activeStage: 1)], lastUpdatedByDeviceID: [device.id: newerAt], observedAtByDeviceID: [device.id: newerAt])
        let olderSnapshot = SharedServiceSnapshot(
            devices: [device], stateByDeviceID: [device.id: makeSnapshotState(device: device, connection: "usb", batteryPercent: 80, dpiValues: [800, 1600, 3200], activeStage: 1)], lastUpdatedByDeviceID: [device.id: newerAt.addingTimeInterval(-1)],
            observedAtByDeviceID: [device.id: newerAt.addingTimeInterval(-1)], usbControlAvailabilityByDeviceID: [device.id: .receiverPresentMouseUnavailable])

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(newerSnapshot)
            appState.deviceStore.applyRemoteServiceSnapshot(olderSnapshot)
        }

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }
        let message = await MainActor.run { appState.deviceStore.selectedDeviceInteractionMessage }
        let presentedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }

        XCTAssertEqual(status, "Connected")
        XCTAssertTrue(controlsEnabled)
        XCTAssertNil(message)
        XCTAssertEqual(presentedDpi, 1600)
    }

    func testRemoteSnapshotNewUSBInsertUnavailableStaysReconnectingDuringConnectGrace() async {
        let appState = await MainActor.run { AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(shouldUseFastDPIPolling: true), autoStart: false) }

        let device = makeSnapshotDevice(id: "usb-explicit-unavailable-new-insert", productName: "Snapshot USB Mouse", identity: SnapshotDeviceIdentity(transport: .usb, serial: "USB-EXPLICIT-UNAVAILABLE-NEW", locationID: 4), profile: .basiliskV3Pro)
        let now = Date()
        let snapshot = SharedServiceSnapshot(devices: [device], stateByDeviceID: [:], lastUpdatedByDeviceID: [:], observedAtByDeviceID: [device.id: now], usbControlAvailabilityByDeviceID: [device.id: .receiverPresentMouseUnavailable])

        await MainActor.run { appState.deviceStore.applyRemoteServiceSnapshot(snapshot) }

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }
        let message = await MainActor.run { appState.deviceStore.selectedDeviceInteractionMessage }

        XCTAssertEqual(status, "Reconnecting")
        XCTAssertFalse(controlsEnabled)
        XCTAssertEqual(message, "Reconnecting to live telemetry. Controls will unlock automatically.")
    }

    func testRemoteSnapshotNormalUSBServiceCadenceDoesNotDisconnectHealthyMouse() async {
        let appState = await MainActor.run { AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(shouldUseFastDPIPolling: true), autoStart: false) }

        let device = makeSnapshotDevice(id: "usb-healthy-cadence", productName: "Snapshot USB Mouse", identity: SnapshotDeviceIdentity(transport: .usb, serial: "USB-HEALTHY", locationID: 6), profile: .basiliskV3Pro)
        let now = Date()
        let snapshot = SharedServiceSnapshot(
            devices: [device], stateByDeviceID: [device.id: makeSnapshotState(device: device, connection: "usb", batteryPercent: 80, dpiValues: [800, 1600, 3200], activeStage: 1)], lastUpdatedByDeviceID: [device.id: now], observedAtByDeviceID: [device.id: now.addingTimeInterval(-3)])

        await MainActor.run { appState.deviceStore.applyRemoteServiceSnapshot(snapshot) }

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        XCTAssertEqual(status, "Connected")
    }

    func testRemoteSnapshotIdleUSBObservationDoesNotDisconnectHealthyMouse() async {
        let appState = await MainActor.run { AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(shouldUseFastDPIPolling: true), autoStart: false) }

        let device = makeSnapshotDevice(id: "usb-service-idle-cadence", productName: "Snapshot USB Mouse", identity: SnapshotDeviceIdentity(transport: .usb, serial: "USB-SERVICE-IDLE", locationID: 7), profile: .basiliskV3Pro)
        let now = Date()
        let observedAt = now.addingTimeInterval(-7)
        let snapshot = SharedServiceSnapshot(
            devices: [device], stateByDeviceID: [device.id: makeSnapshotState(device: device, connection: "usb", batteryPercent: 80, dpiValues: [800, 1600, 3200], activeStage: 1)], lastUpdatedByDeviceID: [device.id: observedAt], observedAtByDeviceID: [device.id: observedAt])

        await MainActor.run { appState.deviceStore.applyRemoteServiceSnapshot(snapshot) }

        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }
        let controlsEnabled = await MainActor.run { appState.deviceStore.selectedDeviceControlsEnabled }
        let message = await MainActor.run { appState.deviceStore.selectedDeviceInteractionMessage }

        XCTAssertEqual(status, "Connected")
        XCTAssertTrue(controlsEnabled)
        XCTAssertNil(message)
    }

    func testOlderRemoteSnapshotDoesNotOverwriteNewerPerDeviceState() async {
        let appState = await MainActor.run { AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false) }

        let device = makeSnapshotDevice(id: "bt-snapshot-stale", productName: "Snapshot BT Mouse", identity: SnapshotDeviceIdentity(transport: .bluetooth, serial: "BT-SNAPSHOT", locationID: 3), profile: .basiliskV3XHyperspeed)
        let newerSnapshot = SharedServiceSnapshot(
            devices: [device], stateByDeviceID: [device.id: makeSnapshotState(device: device, connection: "bluetooth", batteryPercent: 75, dpiValues: [800, 900, 1000, 1100, 1500], activeStage: 3)], lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_520_020)])
        let olderSnapshot = SharedServiceSnapshot(
            devices: [device], stateByDeviceID: [device.id: makeSnapshotState(device: device, connection: "bluetooth", batteryPercent: 74, dpiValues: [800, 900, 1000, 1100, 1500], activeStage: 1)], lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_520_010)])

        await MainActor.run {
            appState.deviceStore.applyRemoteServiceSnapshot(newerSnapshot)
            appState.deviceStore.applyRemoteServiceSnapshot(olderSnapshot)
        }

        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let selectedBattery = await MainActor.run { appState.deviceStore.state?.battery_percent }
        let activeStage = await MainActor.run { appState.editorStore.editableActiveStage }

        XCTAssertEqual(selectedDpi, 1100)
        XCTAssertEqual(selectedBattery, 75)
        XCTAssertEqual(activeStage, 4)
    }

}
