import Foundation
import XCTest
import OpenSnekCore
import OpenSnekProtocols
@testable import OpenSnekHardware
@testable import OpenSnek

/// Exercises USB passive DPI bridge behavior behavior.
final class USBPassiveDPIBridgeBehaviorTests: XCTestCase {
    func testPassiveUSBMonitorReplaceTargetsReturnsForEmptyList() async throws {
        let monitor = PassiveDPIEventMonitor()

        let active = try await withAsyncTimeout(seconds: 1.0) { await monitor.replaceTargets([]) }

        XCTAssertTrue(active.isEmpty)
    }

    func testPassiveMonitorReusesRegistrationForStableDeviceIdentity() {
        let descriptor = PassiveDPIInputDescriptor(usagePage: 0x01, usage: 0x02, reportID: 0x05, subtype: 0x02, heartbeatSubtype: 0x10, minInputReportSize: 7, maxFeatureReportSize: 1)

        XCTAssertTrue(PassiveDPIEventMonitor.shouldReuseRegistration(existingDescriptor: descriptor, existingDeviceIdentityToken: "registry:42", targetDescriptor: descriptor, targetDeviceIdentityToken: "registry:42"))
        XCTAssertFalse(PassiveDPIEventMonitor.shouldReuseRegistration(existingDescriptor: descriptor, existingDeviceIdentityToken: "registry:42", targetDescriptor: descriptor, targetDeviceIdentityToken: "registry:99"))
    }

    func testPassiveDpiFastPollingFallsBackUntilRealEventIsObserved() {
        let usbDevice = makePassiveTestDevice(id: "usb-passive-gating", transport: .usb)
        let bluetoothDevice = makePassiveTestDevice(id: "bt-passive-gating", transport: .bluetooth)

        XCTAssertTrue(BridgeClient.shouldUseFastDPIPolling(device: usbDevice, armedPassiveDpiDeviceIDs: [], observedPassiveDpiDeviceIDs: []))
        XCTAssertTrue(BridgeClient.shouldUseFastDPIPolling(device: usbDevice, armedPassiveDpiDeviceIDs: [usbDevice.id], observedPassiveDpiDeviceIDs: []))
        XCTAssertFalse(BridgeClient.shouldUseFastDPIPolling(device: usbDevice, armedPassiveDpiDeviceIDs: [usbDevice.id], observedPassiveDpiDeviceIDs: [usbDevice.id]))
        XCTAssertFalse(BridgeClient.shouldUseFastDPIPolling(device: bluetoothDevice, armedPassiveDpiDeviceIDs: [bluetoothDevice.id], observedPassiveDpiDeviceIDs: [bluetoothDevice.id]))
    }

    func testPassiveDpiUpgradeRetriesOnlyForHealthyUnobservedUSBTargets() {
        let now = Date(timeIntervalSince1970: 1_773_500_000)
        let usbDevice = makePassiveTestDevice(id: "usb-passive-upgrade", transport: .usb)
        let bluetoothDevice = makePassiveTestDevice(id: "bt-passive-upgrade", transport: .bluetooth)

        XCTAssertTrue(BridgeClient.shouldAttemptPassiveDpiUpgrade(device: usbDevice, targetAvailable: true, observedPassiveDpiDeviceIDs: [], retryNotBefore: nil, now: now))
        XCTAssertFalse(BridgeClient.shouldAttemptPassiveDpiUpgrade(device: usbDevice, targetAvailable: false, observedPassiveDpiDeviceIDs: [], retryNotBefore: nil, now: now))
        XCTAssertFalse(BridgeClient.shouldAttemptPassiveDpiUpgrade(device: usbDevice, targetAvailable: true, observedPassiveDpiDeviceIDs: [usbDevice.id], retryNotBefore: nil, now: now))
        XCTAssertFalse(BridgeClient.shouldAttemptPassiveDpiUpgrade(device: usbDevice, targetAvailable: true, observedPassiveDpiDeviceIDs: [], retryNotBefore: now.addingTimeInterval(1.0), now: now))
        XCTAssertFalse(BridgeClient.shouldAttemptPassiveDpiUpgrade(device: bluetoothDevice, targetAvailable: true, observedPassiveDpiDeviceIDs: [], retryNotBefore: nil, now: now))
    }

    func testPassiveDpiObservedStateResetsWhenRegistrationChanges() {
        let unchanged = BridgeClient.reconciledObservedPassiveDpiDeviceIDs(
            observedDeviceIDs: ["bt-device:bluetooth", "usb-device"], previousTargetIDsByDeviceID: ["bt-device:bluetooth": ["bt-a"], "usb-device": ["usb-a", "usb-b"]], nextTargetIDsByDeviceID: ["bt-device:bluetooth": ["bt-b"], "usb-device": ["usb-c", "usb-d"]])
        let removed = BridgeClient.reconciledObservedPassiveDpiDeviceIDs(observedDeviceIDs: ["bt-device:bluetooth"], previousTargetIDsByDeviceID: ["bt-device:bluetooth": ["bt-a"]], nextTargetIDsByDeviceID: [:])

        XCTAssertEqual(unchanged, ["bt-device:bluetooth"])
        XCTAssertTrue(removed.isEmpty)
    }

    func testBluetoothReadStateBypassesRecentCacheWhenPassiveRealtimeDpiIsActive() {
        let device = makePassiveTestDevice(id: "bt-passive-cache", transport: .bluetooth)
        let now = Date(timeIntervalSince1970: 1_773_600_000)

        let shouldReuse = LocalBridgeBackend.shouldReuseCachedStateForRead(device: device, cachedAt: now.addingTimeInterval(-0.2), now: now, shouldUseFastDPIPolling: false)

        XCTAssertFalse(shouldReuse)
    }

    func testBluetoothReadStateStillUsesRecentCacheBeforePassiveRealtimeDpiIsObserved() {
        let device = makePassiveTestDevice(id: "bt-fast-cache", transport: .bluetooth)
        let now = Date(timeIntervalSince1970: 1_773_600_010)

        let shouldReuse = LocalBridgeBackend.shouldReuseCachedStateForRead(device: device, cachedAt: now.addingTimeInterval(-0.2), now: now, shouldUseFastDPIPolling: true)

        XCTAssertTrue(shouldReuse)
    }

    func testBluetoothRealtimeFastReadReusesRecentPassiveSnapshot() {
        let device = makePassiveTestDevice(id: "bt-fast-snapshot-cache", transport: .bluetooth)
        let now = Date(timeIntervalSince1970: 1_773_600_010)

        let shouldReuse = LocalBridgeBackend.shouldReuseCachedFastSnapshot(device: device, cachedAt: now.addingTimeInterval(-0.5), now: now, shouldUseFastDPIPolling: false)

        XCTAssertTrue(shouldReuse)
    }

    func testBluetoothRealtimeFastReadReusesPassiveSnapshotWithoutAgeLimit() {
        let device = makePassiveTestDevice(id: "bt-fast-snapshot-cache-old", transport: .bluetooth)
        let now = Date(timeIntervalSince1970: 1_773_600_010)

        let shouldReuse = LocalBridgeBackend.shouldReuseCachedFastSnapshot(device: device, cachedAt: now.addingTimeInterval(-30.0), now: now, shouldUseFastDPIPolling: false)

        XCTAssertTrue(shouldReuse)
    }

    func testBluetoothPollingFallbackFastReadKeepsShortCacheWindow() {
        let device = makePassiveTestDevice(id: "bt-fast-fallback-cache", transport: .bluetooth)
        let now = Date(timeIntervalSince1970: 1_773_600_010)

        let shouldReuse = LocalBridgeBackend.shouldReuseCachedFastSnapshot(device: device, cachedAt: now.addingTimeInterval(-0.5), now: now, shouldUseFastDPIPolling: true)

        XCTAssertFalse(shouldReuse)
    }

    func testBluetoothRealtimeCorrectionDefersWhileHeartbeatIsFresh() {
        let now = Date(timeIntervalSince1970: 1_773_600_012)

        XCTAssertTrue(AppStateDeviceController.shouldDelayBluetoothRealtimeCorrection(lastHeartbeatAt: now.addingTimeInterval(-0.2), now: now))
        XCTAssertFalse(AppStateDeviceController.shouldDelayBluetoothRealtimeCorrection(lastHeartbeatAt: now.addingTimeInterval(-0.5), now: now))
        XCTAssertFalse(AppStateDeviceController.shouldDelayBluetoothRealtimeCorrection(lastHeartbeatAt: nil, now: now))
    }

    func testBluetoothRealtimeStateRefreshDefersWhileHeartbeatIsFresh() {
        let now = Date(timeIntervalSince1970: 1_773_600_013)

        XCTAssertTrue(
            AppStateDeviceController.shouldDelayBluetoothRealtimeStateRefresh(
                AppStateDeviceController.BluetoothRealtimeRefreshDelayContext(
                    transport: .bluetooth, transportStatus: .realTimeHID, lastHeartbeatAt: now.addingTimeInterval(-0.2), lastFullStateRefreshStartedAt: now.addingTimeInterval(-1.9), minimumRefreshInterval: PollingProfile.serviceInteractive.refreshStateInterval, now: now)))
        XCTAssertTrue(
            AppStateDeviceController.shouldDelayBluetoothRealtimeStateRefresh(
                AppStateDeviceController.BluetoothRealtimeRefreshDelayContext(
                    transport: .bluetooth, transportStatus: .streamActive, lastHeartbeatAt: now.addingTimeInterval(-0.2), lastFullStateRefreshStartedAt: now.addingTimeInterval(-1.9), minimumRefreshInterval: PollingProfile.serviceInteractive.refreshStateInterval, now: now)))
        XCTAssertFalse(
            AppStateDeviceController.shouldDelayBluetoothRealtimeStateRefresh(
                AppStateDeviceController.BluetoothRealtimeRefreshDelayContext(
                    transport: .bluetooth, transportStatus: .realTimeHID, lastHeartbeatAt: now.addingTimeInterval(-1.0), lastFullStateRefreshStartedAt: now.addingTimeInterval(-1.9), minimumRefreshInterval: PollingProfile.serviceInteractive.refreshStateInterval, now: now)))
        XCTAssertFalse(
            AppStateDeviceController.shouldDelayBluetoothRealtimeStateRefresh(
                AppStateDeviceController.BluetoothRealtimeRefreshDelayContext(
                    transport: .bluetooth, transportStatus: .realTimeHID, lastHeartbeatAt: now.addingTimeInterval(-0.2), lastFullStateRefreshStartedAt: now.addingTimeInterval(-2.0), minimumRefreshInterval: PollingProfile.serviceInteractive.refreshStateInterval, now: now)))
        XCTAssertFalse(
            AppStateDeviceController.shouldDelayBluetoothRealtimeStateRefresh(
                AppStateDeviceController.BluetoothRealtimeRefreshDelayContext(
                    transport: .bluetooth, transportStatus: .pollingFallback, lastHeartbeatAt: now.addingTimeInterval(-0.2), lastFullStateRefreshStartedAt: now.addingTimeInterval(-1.9), minimumRefreshInterval: PollingProfile.serviceInteractive.refreshStateInterval, now: now)))
        XCTAssertFalse(
            AppStateDeviceController.shouldDelayBluetoothRealtimeStateRefresh(
                AppStateDeviceController.BluetoothRealtimeRefreshDelayContext(
                    transport: .usb, transportStatus: .realTimeHID, lastHeartbeatAt: now.addingTimeInterval(-0.2), lastFullStateRefreshStartedAt: now.addingTimeInterval(-1.9), minimumRefreshInterval: PollingProfile.serviceInteractive.refreshStateInterval, now: now)))
    }

    func testRealtimeCorrectionMinimumIntervalIsLowerInServiceMode() {
        XCTAssertEqual(AppStateDeviceController.realtimeCorrectionMinimumInterval(isService: true), 0.45, accuracy: 0.001)
        XCTAssertEqual(AppStateDeviceController.realtimeCorrectionMinimumInterval(isService: false), 1.0, accuracy: 0.001)
    }

    func testBluetoothPassiveObservationDoesNotResetOnStaleVendorRead() {
        let device = makePassiveTestDevice(id: "bt-watchdog", transport: .bluetooth)
        let now = Date(timeIntervalSince1970: 1_773_600_011)

        let staleReadAfterSilence = BridgeClient.shouldResetBluetoothPassiveObservation(
            BridgeClient.BluetoothPassiveObservationResetContext(
                previousState: makePassiveTestState(device: device, dpiValues: [800, 900, 1000, 1100, 1200], activeStage: 1, dpiValue: 900), active: 3, values: [800, 900, 1000, 1100, 1200], lastHeartbeatAt: now.addingTimeInterval(-1.6), lastObservedAt: now.addingTimeInterval(-1.2), now: now))
        let staleReadWithRecentEvent = BridgeClient.shouldResetBluetoothPassiveObservation(
            BridgeClient.BluetoothPassiveObservationResetContext(
                previousState: makePassiveTestState(device: device, dpiValues: [800, 900, 1000, 1100, 1200], activeStage: 1, dpiValue: 900), active: 3, values: [800, 900, 1000, 1100, 1200], lastHeartbeatAt: now.addingTimeInterval(-0.1), lastObservedAt: now.addingTimeInterval(-0.1), now: now))
        let staleReadWithHeartbeat = BridgeClient.shouldResetBluetoothPassiveObservation(
            BridgeClient.BluetoothPassiveObservationResetContext(
                previousState: makePassiveTestState(device: device, dpiValues: [800, 900, 1000, 1100, 1200], activeStage: 1, dpiValue: 900), active: 3, values: [800, 900, 1000, 1100, 1200], lastHeartbeatAt: now.addingTimeInterval(-0.1), lastObservedAt: now.addingTimeInterval(-0.6), now: now))
        let staleReadDuringRecentSilence = BridgeClient.shouldResetBluetoothPassiveObservation(
            BridgeClient.BluetoothPassiveObservationResetContext(
                previousState: makePassiveTestState(device: device, dpiValues: [800, 900, 1000, 1100, 1200], activeStage: 1, dpiValue: 900), active: 3, values: [800, 900, 1000, 1100, 1200], lastHeartbeatAt: nil, lastObservedAt: now.addingTimeInterval(-0.6), now: now))

        XCTAssertFalse(staleReadAfterSilence)
        XCTAssertFalse(staleReadWithRecentEvent)
        XCTAssertFalse(staleReadWithHeartbeat)
        XCTAssertFalse(staleReadDuringRecentSilence)
    }

    func testBluetoothHeartbeatHealthReportsFreshHeartbeatWithoutResettingPassiveObservation() {
        let device = makePassiveTestDevice(id: "bt-watchdog-heartbeat-healthy", transport: .bluetooth)
        let now = Date(timeIntervalSince1970: 1_773_600_014)

        XCTAssertTrue(BridgeClient.isBluetoothPassiveHeartbeatHealthy(lastHeartbeatAt: now.addingTimeInterval(-1.4), now: now))
        XCTAssertFalse(
            BridgeClient.shouldResetBluetoothPassiveObservation(
                BridgeClient.BluetoothPassiveObservationResetContext(
                    previousState: makePassiveTestState(device: device, dpiValues: [800, 900, 1000, 1100, 1200], activeStage: 1, dpiValue: 900), active: 4, values: [800, 900, 1000, 1100, 1200], lastHeartbeatAt: now.addingTimeInterval(-1.4), lastObservedAt: now.addingTimeInterval(-1.4), now: now)))
        XCTAssertFalse(BridgeClient.isBluetoothPassiveHeartbeatHealthy(lastHeartbeatAt: now.addingTimeInterval(-1.6), now: now))
    }

    func testBluetoothExpectedReadMasksOnlyMatchingPreviousState() {
        let expected = BridgeClient.BluetoothExpectedDpiState(
            active: 3, values: [800, 900, 1000, 1100, 1200], pairs: [800, 900, 1000, 1100, 1200].map { DpiPair(x: $0, y: $0) }, previousActive: 1, previousValues: [800, 900, 1000, 1100, 1200], previousPairs: [800, 900, 1000, 1100, 1200].map { DpiPair(x: $0, y: $0) },
            expiresAt: Date(timeIntervalSince1970: 1_773_600_020), remainingMasks: 4)

        XCTAssertTrue(BridgeClient.shouldMaskBluetoothExpectedRead(parsedActive: 1, parsedValues: [800, 900, 1000, 1100, 1200], parsedPairs: [800, 900, 1000, 1100, 1200].map { DpiPair(x: $0, y: $0) }, expected: expected))
        XCTAssertFalse(BridgeClient.shouldMaskBluetoothExpectedRead(parsedActive: 4, parsedValues: [800, 900, 1000, 1100, 1200], parsedPairs: [800, 900, 1000, 1100, 1200].map { DpiPair(x: $0, y: $0) }, expected: expected))
    }

    func testBluetoothExpectedReadMasksPreviousActiveEvenWhenPreviousPairsDiffer() {
        let expected = BridgeClient.BluetoothExpectedDpiState(
            active: 3, values: [800, 900, 1000, 1100, 1200], pairs: [800, 900, 1000, 1100, 1200].map { DpiPair(x: $0, y: $0) }, previousActive: 1, previousValues: [800, 900, 1000, 1100, 1200],
            previousPairs: [DpiPair(x: 800, y: 800), DpiPair(x: 1100, y: 1100), DpiPair(x: 1000, y: 1000), DpiPair(x: 1100, y: 1100), DpiPair(x: 1200, y: 1200)], expiresAt: Date(timeIntervalSince1970: 1_773_600_020), remainingMasks: 4)

        XCTAssertTrue(BridgeClient.shouldMaskBluetoothExpectedRead(parsedActive: 1, parsedValues: [800, 900, 1000, 1100, 1200], parsedPairs: [800, 900, 1000, 1100, 1200].map { DpiPair(x: $0, y: $0) }, expected: expected))
    }

    func testBluetoothExpectedReadDoesNotMaskWhenPreviousStateIsUnknown() {
        let expected = BridgeClient.BluetoothExpectedDpiState(
            active: 2, values: [800, 900, 1000, 1100, 1200], pairs: [800, 900, 1000, 1100, 1200].map { DpiPair(x: $0, y: $0) }, previousActive: nil, previousValues: nil, previousPairs: nil, expiresAt: Date(timeIntervalSince1970: 1_773_600_021), remainingMasks: 4)

        XCTAssertFalse(BridgeClient.shouldMaskBluetoothExpectedRead(parsedActive: 1, parsedValues: [800, 900, 1000, 1100, 1200], parsedPairs: [800, 900, 1000, 1100, 1200].map { DpiPair(x: $0, y: $0) }, expected: expected))
    }

    func testCompletedPollingReadIsMaskedWhenNewerCachedStateLandsDuringRead() {
        let start = Date(timeIntervalSince1970: 1_773_600_020)

        XCTAssertTrue(LocalBridgeBackend.completedReadWasSuperseded(startedAt: start, latestCachedAt: start.addingTimeInterval(0.05)))
        XCTAssertFalse(LocalBridgeBackend.completedReadWasSuperseded(startedAt: start, latestCachedAt: start.addingTimeInterval(-0.05)))
    }

    func testBluetoothHIDDiscoveryRequiresMatchingConnectedPeripheralWhenKnown() {
        XCTAssertTrue(BridgeClient.shouldIncludeBluetoothHIDDevice(hidDeviceName: "Basilisk V3 X HyperSpeed", connectedPeripheralNames: nil))
        XCTAssertFalse(BridgeClient.shouldIncludeBluetoothHIDDevice(hidDeviceName: "Basilisk V3 X HyperSpeed", connectedPeripheralNames: []))
        XCTAssertTrue(BridgeClient.shouldIncludeBluetoothHIDDevice(hidDeviceName: "Basilisk V3 X HyperSpeed", connectedPeripheralNames: ["Razer Basilisk V3 X HyperSpeed"]))
        XCTAssertFalse(BridgeClient.shouldIncludeBluetoothHIDDevice(hidDeviceName: "Basilisk V3 X HyperSpeed", connectedPeripheralNames: ["DeathAdder V2 X HyperSpeed"]))
    }

}
