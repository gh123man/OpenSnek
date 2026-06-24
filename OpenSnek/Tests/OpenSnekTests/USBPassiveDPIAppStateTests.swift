import Foundation
import XCTest
import OpenSnekCore
import OpenSnekProtocols
@testable import OpenSnekHardware
@testable import OpenSnek

/// Exercises USB passive DPI app state behavior.
final class USBPassiveDPIAppStateTests: XCTestCase {
    func testAppStateAppliesBackendStateUpdatesWithoutWaitingForPolling() async {
        let device = makePassiveTestDevice(id: "usb-passive-live", transport: .usb)
        let backend = PassiveUpdateStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makePassiveTestState(
                    device: device,
                    dpiValues: [800, 1600, 3200],
                    activeStage: 0,
                    dpiValue: 800
                )
            ],
            shouldUseFastPolling: false
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await Task.yield()
        await appState.deviceStore.refreshDevices()
        await backend.emitStateUpdate(
            deviceID: device.id,
            state: makePassiveTestState(
                device: device,
                dpiValues: [800, 1600, 3200],
                activeStage: 2,
                dpiValue: 3200
            )
        )
        try? await Task.sleep(nanoseconds: 50_000_000)

        let liveDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let activeStage = await MainActor.run { appState.editorStore.editableActiveStage }

        XCTAssertEqual(liveDpi, 3200)
        XCTAssertEqual(activeStage, 3)
    }

    func testServiceAppStateShowsTransientStatusItemDpiAfterLiveUpdate() async {
        let device = makePassiveTestDevice(id: "usb-passive-service-badge", transport: .usb)
        let backend = PassiveUpdateStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makePassiveTestState(
                    device: device,
                    dpiValues: [800, 1600, 3200],
                    activeStage: 0,
                    dpiValue: 800
                )
            ],
            shouldUseFastPolling: false
        )
        let appState = await MainActor.run {
            AppState(
                launchRole: .service,
                backend: backend,
                autoStart: false,
                statusItemDpiDisplayDuration: 0.05
            )
        }

        await Task.yield()
        await appState.deviceStore.refreshDevices()
        let initialTransientDpi = await MainActor.run { appState.runtimeStore.statusItemTransientDpi }
        XCTAssertNil(initialTransientDpi)

        await backend.emitStateUpdate(
            deviceID: device.id,
            state: makePassiveTestState(
                device: device,
                dpiValues: [800, 1600, 3200],
                activeStage: 2,
                dpiValue: 3200
            )
        )
        let transientDpi = try? await withAsyncTimeout(seconds: 1.0) {
            while true {
                let transientDpi = await MainActor.run { appState.runtimeStore.statusItemTransientDpi }
                if transientDpi == 3200 {
                    return transientDpi
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        XCTAssertEqual(transientDpi, 3200)

        let clearedTransientDpi = try? await withAsyncTimeout(seconds: 1.0) {
            while true {
                let transientDpi = await MainActor.run { appState.runtimeStore.statusItemTransientDpi }
                if transientDpi == nil {
                    return transientDpi
                }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
        }
        XCTAssertNil(clearedTransientDpi)
    }

    func testAppStateKeepsLowRateCorrectionPollingWhenPassiveUSBUpdatesAreAvailable() async {
        let device = makePassiveTestDevice(id: "usb-passive-correct", transport: .usb)
        let backend = PassiveUpdateStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makePassiveTestState(
                    device: device,
                    dpiValues: [800, 1600, 3200],
                    activeStage: 1,
                    dpiValue: 1600
                )
            ],
            shouldUseFastPolling: false
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await Task.yield()
        await appState.deviceStore.refreshDevices()
        await appState.deviceStore.refreshDpiFast()

        let fastReadCount = await backend.fastReadCount()
        XCTAssertEqual(fastReadCount, 1)
    }

    func testAppStateDefersBluetoothFullStateRefreshWhileRealtimeHeartbeatIsFresh() async {
        let device = makePassiveTestDevice(id: "bt-passive-defer-state", transport: .bluetooth)
        let backend = PassiveUpdateStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makePassiveTestState(
                    device: device,
                    dpiValues: [800, 900, 1000, 1100, 1200],
                    activeStage: 1,
                    dpiValue: 900
                )
            ],
            shouldUseFastPolling: false
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await Task.yield()
        await appState.deviceStore.refreshDevices()
        let baselineReadCount = await backend.readStateCount()

        await backend.emitTransportStatusUpdate(deviceID: device.id, status: .realTimeHID)
        await backend.emitTransportStatusUpdate(deviceID: device.id, status: .streamActive, updatedAt: Date())
        try? await Task.sleep(nanoseconds: 50_000_000)
        await appState.deviceStore.refreshState()

        let readCountAfterDeferredRefresh = await backend.readStateCount()
        XCTAssertEqual(readCountAfterDeferredRefresh, baselineReadCount)
    }

    func testAppStateFallsBackToFastPollingWhenPassiveUSBUpdatesAreUnavailable() async {
        let device = makePassiveTestDevice(id: "usb-passive-fallback", transport: .usb)
        let backend = PassiveUpdateStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makePassiveTestState(
                    device: device,
                    dpiValues: [800, 1600, 3200],
                    activeStage: 1,
                    dpiValue: 1600
                )
            ],
            shouldUseFastPolling: true
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await Task.yield()
        await appState.deviceStore.refreshDevices()
        await appState.deviceStore.refreshDpiFast()

        let fastReadCount = await backend.fastReadCount()
        XCTAssertEqual(fastReadCount, 1)
    }

    func testRefreshDpiFastPreservesLastStableUpdateTimestamp() async {
        let device = makePassiveTestDevice(id: "usb-fast-last-updated", transport: .usb)
        let backend = PassiveUpdateStubBackend(
            devices: [device],
            stateByDeviceID: [
                device.id: makePassiveTestState(
                    device: device,
                    dpiValues: [800, 1600, 3200],
                    activeStage: 1,
                    dpiValue: 1600
                )
            ],
            shouldUseFastPolling: true
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await Task.yield()
        await appState.deviceStore.refreshDevices()
        let initialLastUpdated = await MainActor.run { appState.deviceStore.lastUpdated }
        XCTAssertNotNil(initialLastUpdated)

        try? await Task.sleep(nanoseconds: 50_000_000)
        await appState.deviceStore.refreshDpiFast()

        let refreshedLastUpdated = await MainActor.run { appState.deviceStore.lastUpdated }
        let fastReadCount = await backend.fastReadCount()
        guard let initialLastUpdated else {
            XCTFail("Expected initial selected-state timestamp")
            return
        }
        guard let refreshedLastUpdated else {
            XCTFail("Expected selected-state timestamp after fast refresh")
            return
        }
        let initialTimestamp = initialLastUpdated.timeIntervalSince1970
        let refreshedTimestamp = refreshedLastUpdated.timeIntervalSince1970

        XCTAssertEqual(fastReadCount, 1)
        XCTAssertEqual(refreshedTimestamp, initialTimestamp, accuracy: 0.001)
    }

    func testRefreshStateDoesNotOverwriteNewerPassiveBluetoothUpdateWithStaleRead() async {
        let device = makePassiveTestDevice(id: "bt-passive-race", transport: .bluetooth)
        let staleState = makePassiveTestState(
            device: device,
            dpiValues: [800, 900, 1000, 1100, 1200],
            activeStage: 1,
            dpiValue: 900
        )
        let passiveState = makePassiveTestState(
            device: device,
            dpiValues: [800, 900, 1000, 1100, 1200],
            activeStage: 4,
            dpiValue: 1200
        )
        let backend = RacingPassiveUpdateStubBackend(
            devices: [device],
            staleStateByDeviceID: [device.id: staleState]
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        let refreshTask = Task {
            await appState.deviceStore.refreshDevices()
        }

        await backend.waitForReadStateStart()
        let passiveObservedAt = Date()
        await backend.emitStateUpdate(
            deviceID: device.id,
            state: passiveState,
            updatedAt: passiveObservedAt
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        await backend.resumeReadState()
        await refreshTask.value

        let liveDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let activeStage = await MainActor.run { appState.editorStore.editableActiveStage }
        let lastUpdated = await MainActor.run { appState.deviceStore.lastUpdated }

        XCTAssertEqual(liveDpi, 1200)
        XCTAssertEqual(activeStage, 5)
        XCTAssertNotNil(lastUpdated)
        XCTAssertEqual(lastUpdated!.timeIntervalSince1970, passiveObservedAt.timeIntervalSince1970, accuracy: 0.2)
    }

    func testRefreshStateDoesNotOverwriteNewerFastDpiUpdateWithStaleRead() async {
        let device = makePassiveTestDevice(id: "usb-fast-race", transport: .usb)
        let staleState = makePassiveTestState(
            device: device,
            dpiValues: [800, 900, 1000, 1100, 1200],
            activeStage: 4,
            dpiValue: 1200
        )
        let backend = RacingPassiveUpdateStubBackend(
            devices: [device],
            staleStateByDeviceID: [device.id: staleState],
            fastSnapshotByDeviceID: [device.id: DpiFastSnapshot(active: 4, values: [800, 900, 1000, 1100, 1200])],
            shouldUseFastPolling: true,
            blockReadState: false
        )
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: backend, autoStart: false)
        }

        await appState.deviceStore.refreshDevices()
        await backend.setFastSnapshot(
            DpiFastSnapshot(active: 2, values: [800, 900, 1000, 1100, 1200]),
            for: device.id
        )
        await appState.deviceStore.refreshDpiFast()
        await appState.deviceStore.refreshState()

        let liveDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let activeStage = await MainActor.run { appState.editorStore.editableActiveStage }

        XCTAssertEqual(liveDpi, 1000)
        XCTAssertEqual(activeStage, 3)
    }
}
