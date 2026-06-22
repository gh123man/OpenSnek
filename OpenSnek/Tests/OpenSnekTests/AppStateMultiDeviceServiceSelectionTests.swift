import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

final class AppStateMultiDeviceServiceSelectionTests: XCTestCase {
    func testBackendDeviceListUpdateRecoversSelectionToMatchingBluetoothTransportWhenUSBHasNoTelemetry() async throws {
        let usbDevice = makeTestDevice(
            id: "usb-recovery",
            productName: "Shared Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "MATCHED-DEVICE",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let bluetoothDevice = makeTestDevice(
            id: "bt-recovery",
            productName: "Shared Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "MATCHED-DEVICE",
                locationID: 2
            ),
            profile: .basiliskV3XHyperspeed
        )
        let bluetoothState = makeTestState(
            device: bluetoothDevice,
            connection: "bluetooth",
            batteryPercent: 74,
            dpiValues: [1200, 2400, 3600],
            activeStage: 1
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [usbDevice],
            stateByDeviceID: [bluetoothDevice.id: bluetoothState]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await backend.emitDeviceListUpdate([usbDevice, bluetoothDevice])

        try await waitForAppStateCondition(timeout: 2.0) {
            await MainActor.run {
                appState.deviceStore.selectedDeviceID == bluetoothDevice.id &&
                    appState.deviceStore.state?.device.id == bluetoothDevice.id
            }
        }

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let status = await MainActor.run { appState.deviceStore.currentDeviceStatusIndicator.label }

        XCTAssertEqual(selectedDeviceID, bluetoothDevice.id)
        XCTAssertEqual(selectedDpi, 2400)
        XCTAssertEqual(status, "Connected")
    }

    func testBackendDeviceListUpdateDoesNotSwitchToUnrelatedBluetoothDeviceDuringUSBRecovery() async throws {
        let usbDevice = makeTestDevice(
            id: "usb-unrelated",
            productName: "Alpha Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "USB-ONLY",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let bluetoothDevice = makeTestDevice(
            id: "bt-unrelated",
            productName: "Beta Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "BT-ONLY",
                locationID: 2
            ),
            profile: .basiliskV3XHyperspeed
        )
        let bluetoothState = makeTestState(
            device: bluetoothDevice,
            connection: "bluetooth",
            batteryPercent: 74,
            dpiValues: [1200, 2400, 3600],
            activeStage: 1
        )
        let backend = DeviceListUpdatingStubBackend(
            devices: [usbDevice],
            stateByDeviceID: [bluetoothDevice.id: bluetoothState]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await backend.emitDeviceListUpdate([usbDevice, bluetoothDevice])

        try await waitForAppStateCondition(timeout: 1.0) {
            await MainActor.run {
                appState.deviceStore.devices.count == 2
            }
        }

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }

        XCTAssertEqual(selectedDeviceID, usbDevice.id)
    }

    func testRemotePresenceSelectedDeviceDrivesServiceInteractivePollingUntilExpiry() async {
        let suiteName = "AppStateMultiDeviceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = await MainActor.run {
            BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!)
        }
        let appState = await MainActor.run {
            AppState(launchRole: .service, serviceCoordinator: coordinator, autoStart: false)
        }
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
                transport: .usb,
                serial: "BETA",
                locationID: 2
            ),
            profile: .basiliskV3XHyperspeed
        )
        let now = Date(timeIntervalSince1970: 1_773_400_000)

        await MainActor.run {
            appState.deviceStore.devices = [alphaDevice, betaDevice]
            appState.deviceStore.selectedDeviceID = betaDevice.id
            appState.runtimeStore.recordRemoteClientPresence(
                CrossProcessClientPresence(sourceProcessID: 41, selectedDeviceID: alphaDevice.id),
                now: now
            )
        }

        let activeProfile = await MainActor.run { appState.runtimeStore.pollingProfile(at: now) }
        let activeDeviceIDs = await MainActor.run { appState.runtimeStore.activeFastPollingDeviceIDs(at: now) }
        let expiredProfile = await MainActor.run { appState.runtimeStore.pollingProfile(at: now.addingTimeInterval(3.0)) }
        let expiredDeviceIDs = await MainActor.run { appState.runtimeStore.activeFastPollingDeviceIDs(at: now.addingTimeInterval(3.0)) }
        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }

        XCTAssertEqual(selectedDeviceID, betaDevice.id)
        XCTAssertEqual(activeProfile, .serviceInteractive)
        XCTAssertEqual(activeDeviceIDs, [alphaDevice.id])
        XCTAssertEqual(expiredProfile, .serviceIdle)
        XCTAssertTrue(expiredDeviceIDs.isEmpty)
    }

    func testRemotePresenceWithoutSelectedDeviceFallsBackToServiceSelectionForFastPolling() async {
        let suiteName = "AppStateMultiDeviceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = await MainActor.run {
            BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!)
        }
        let appState = await MainActor.run {
            AppState(launchRole: .service, serviceCoordinator: coordinator, autoStart: false)
        }
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
                transport: .usb,
                serial: "BETA",
                locationID: 2
            ),
            profile: .basiliskV3XHyperspeed
        )
        let now = Date(timeIntervalSince1970: 1_773_400_050)

        await MainActor.run {
            appState.deviceStore.devices = [alphaDevice, betaDevice]
            appState.deviceStore.selectedDeviceID = betaDevice.id
            appState.runtimeStore.recordRemoteClientPresence(
                CrossProcessClientPresence(sourceProcessID: 41, selectedDeviceID: nil),
                now: now
            )
        }

        let activeProfile = await MainActor.run { appState.runtimeStore.pollingProfile(at: now) }
        let activeDeviceIDs = await MainActor.run { appState.runtimeStore.activeFastPollingDeviceIDs(at: now) }

        XCTAssertEqual(activeProfile, .serviceInteractive)
        XCTAssertEqual(activeDeviceIDs, [betaDevice.id])
    }

    func testServiceFastPollingPrefersRemoteSelectionOverLocalSelection() async {
        let suiteName = "AppStateMultiDeviceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let coordinator = await MainActor.run {
            BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!)
        }
        let appState = await MainActor.run {
            AppState(launchRole: .service, serviceCoordinator: coordinator, autoStart: false)
        }
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
                transport: .usb,
                serial: "BETA",
                locationID: 2
            ),
            profile: .basiliskV3XHyperspeed
        )
        let now = Date(timeIntervalSince1970: 1_773_400_100)

        await MainActor.run {
            appState.deviceStore.devices = [alphaDevice, betaDevice]
            appState.deviceStore.selectedDeviceID = betaDevice.id
            appState.runtimeStore.setCompactMenuPresented(true)
            appState.runtimeStore.recordRemoteClientPresence(
                CrossProcessClientPresence(sourceProcessID: 42, selectedDeviceID: alphaDevice.id),
                now: now
            )
        }

        let profile = await MainActor.run { appState.runtimeStore.pollingProfile(at: now) }
        let activeDeviceIDs = await MainActor.run { appState.runtimeStore.activeFastPollingDeviceIDs(at: now) }

        XCTAssertEqual(profile, .serviceInteractive)
        XCTAssertEqual(activeDeviceIDs, [alphaDevice.id])
    }

    func testWindowedAppFastPollingTracksOnlySelectedDevice() async {
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
            devices: [alphaDevice, betaDevice],
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

        let activeDeviceIDs = await MainActor.run {
            appState.deviceStore.devices = [alphaDevice, betaDevice]
            appState.deviceStore.selectedDeviceID = betaDevice.id
            return appState.runtimeStore.activeFastPollingDeviceIDs(at: Date())
        }

        XCTAssertEqual(activeDeviceIDs, [betaDevice.id])
    }

    func testWindowedAppRuntimeFullRefreshTracksOnlySelectedDevice() async {
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
            devices: [alphaDevice, betaDevice],
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
        await backend.resetReadOrder()

        await MainActor.run {
            appState.deviceStore.selectDevice(betaDevice.id)
        }

        await appState.runtimeController.pollRuntimeOnce(now: Date(timeIntervalSince1970: 1_773_400_100))

        let readOrder = await backend.recordedReadOrder()
        XCTAssertEqual(readOrder, [betaDevice.id])
    }

    func testServiceRuntimeFullRefreshTracksOnlyRemoteSelectedDevice() async {
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
            devices: [alphaDevice, betaDevice],
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
            AppState(launchRole: .service, backend: backend, autoStart: false)
        }
        let now = Date(timeIntervalSince1970: 1_773_400_150)

        await appState.deviceStore.refreshDevices()
        await backend.resetReadOrder()

        await MainActor.run {
            appState.runtimeStore.recordRemoteClientPresence(
                CrossProcessClientPresence(sourceProcessID: 77, selectedDeviceID: betaDevice.id),
                now: now
            )
        }

        await appState.runtimeController.pollRuntimeOnce(now: now)

        let readOrder = await backend.recordedReadOrder()
        XCTAssertEqual(readOrder, [betaDevice.id])
    }

    func testServiceRemoteSelectionBlocksActivityFocusOverride() async {
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
            devices: [alphaDevice, betaDevice],
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
            AppState(launchRole: .service, backend: backend, autoStart: false)
        }
        await MainActor.run {
            appState.deviceStore.devices = [alphaDevice, betaDevice]
            appState.deviceStore.selectedDeviceID = betaDevice.id
            appState.runtimeStore.recordRemoteClientPresence(
                CrossProcessClientPresence(sourceProcessID: 78, selectedDeviceID: betaDevice.id),
                now: Date()
            )
            appState.deviceController.focusServiceSelectionOnActivity(deviceID: alphaDevice.id)
        }

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        XCTAssertEqual(selectedDeviceID, betaDevice.id)
    }

    func testServiceApplyDeviceListPreservesRemoteSelectedBluetoothIdentityWhenOnlyTwinUSBRemains() async {
        let usbDevice = makeTestDevice(
            id: "usb-shared",
            productName: "Shared Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "MATCHED-DEVICE",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let bluetoothDevice = makeTestDevice(
            id: "bt-shared",
            productName: "Shared Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "MATCHED-DEVICE",
                locationID: 2
            ),
            profile: .basiliskV3XHyperspeed
        )
        let backend = MultiDeviceStubBackend(
            devices: [usbDevice, bluetoothDevice],
            stateByDeviceID: [
                bluetoothDevice.id: makeTestState(
                    device: bluetoothDevice,
                    connection: "bluetooth",
                    batteryPercent: 74,
                    dpiValues: [1200, 2400, 3600],
                    activeStage: 1
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .service, backend: backend, autoStart: false)
        }
        await MainActor.run {
            appState.deviceStore.devices = [usbDevice, bluetoothDevice]
            appState.deviceStore.selectedDeviceID = usbDevice.id
            appState.runtimeStore.recordRemoteClientPresence(
                CrossProcessClientPresence(sourceProcessID: 79, selectedDeviceID: bluetoothDevice.id),
                now: Date()
            )
            _ = appState.deviceController.applyDeviceList([usbDevice], source: "subscription")
        }

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        XCTAssertEqual(selectedDeviceID, bluetoothDevice.id)
    }

    func testBackendDeviceListUpdatePreservesSelectedBluetoothIdentityWhenOnlyTwinUSBRemains() async {
        let usbDevice = makeTestDevice(
            id: "usb-shared",
            productName: "Shared Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .usb,
                serial: "MATCHED-DEVICE",
                locationID: 1
            ),
            profile: .basiliskV3Pro
        )
        let bluetoothDevice = makeTestDevice(
            id: "bt-shared",
            productName: "Shared Mouse",
            identity: MultiDeviceTestIdentity(
                transport: .bluetooth,
                serial: "MATCHED-DEVICE",
                locationID: 2
            ),
            profile: .basiliskV3XHyperspeed
        )
        let backend = MultiDeviceStubBackend(
            devices: [usbDevice, bluetoothDevice],
            stateByDeviceID: [
                bluetoothDevice.id: makeTestState(
                    device: bluetoothDevice,
                    connection: "bluetooth",
                    batteryPercent: 74,
                    dpiValues: [1200, 2400, 3600],
                    activeStage: 1
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await MainActor.run {
            appState.deviceStore.devices = [usbDevice, bluetoothDevice]
            appState.deviceStore.selectedDeviceID = bluetoothDevice.id
        }

        await MainActor.run {
            _ = appState.deviceController.applyDeviceList([usbDevice], source: "subscription")
        }

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        XCTAssertEqual(selectedDeviceID, bluetoothDevice.id)
    }

    func testServiceSelectionFollowsDeviceWithMeaningfulRefreshChange() async {
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
                transport: .usb,
                serial: "BETA",
                locationID: 2
            ),
            profile: .basiliskV3XHyperspeed
        )
        let backend = MultiDeviceStubBackend(
            devices: [alphaDevice, betaDevice],
            stateByDeviceID: [
                alphaDevice.id: makeTestState(
                    device: alphaDevice,
                    connection: "usb",
                    batteryPercent: 81,
                    dpiValues: [800, 1600, 2400],
                    activeStage: 0
                ),
                betaDevice.id: makeTestState(
                    device: betaDevice,
                    connection: "usb",
                    batteryPercent: 77,
                    dpiValues: [1000, 2000, 3000],
                    activeStage: 0
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .service, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        await MainActor.run {
            appState.deviceStore.selectDevice(alphaDevice.id)
        }
        await backend.setState(
            makeTestState(
                device: betaDevice,
                connection: "usb",
                batteryPercent: 77,
                dpiValues: [1800, 3600, 5400],
                activeStage: 1
            ),
            for: betaDevice.id
        )

        await appState.deviceStore.refreshDevices()

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let activeStage = await MainActor.run { appState.editorStore.editableActiveStage }

        XCTAssertEqual(selectedDeviceID, betaDevice.id)
        XCTAssertEqual(selectedDpi, 3600)
        XCTAssertEqual(activeStage, 2)
    }

    func testServiceSelectionFollowsDeviceWithFastDpiActivity() async {
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
                transport: .usb,
                serial: "BETA",
                locationID: 2
            ),
            profile: .basiliskV3XHyperspeed
        )
        let backend = MultiDeviceStubBackend(
            devices: [alphaDevice, betaDevice],
            stateByDeviceID: [
                alphaDevice.id: makeTestState(
                    device: alphaDevice,
                    connection: "usb",
                    batteryPercent: 81,
                    dpiValues: [800, 1600, 2400],
                    activeStage: 0
                ),
                betaDevice.id: makeTestState(
                    device: betaDevice,
                    connection: "usb",
                    batteryPercent: 77,
                    dpiValues: [1000, 2000, 3000],
                    activeStage: 0
                )
            ]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .service, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()

        await MainActor.run {
            appState.deviceStore.selectDevice(betaDevice.id)
            appState.runtimeStore.setCompactMenuPresented(true)
            appState.runtimeStore.recordRemoteClientPresence(
                CrossProcessClientPresence(sourceProcessID: 99, selectedDeviceID: alphaDevice.id),
                now: Date()
            )
        }
        await backend.setFastSnapshot(DpiFastSnapshot(active: 2, values: [800, 1600, 5200]), for: alphaDevice.id)

        await appState.deviceStore.refreshDpiFast()

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let activeStage = await MainActor.run { appState.editorStore.editableActiveStage }

        XCTAssertEqual(selectedDeviceID, alphaDevice.id)
        XCTAssertEqual(selectedDpi, 5200)
        XCTAssertEqual(activeStage, 3)
    }
}
