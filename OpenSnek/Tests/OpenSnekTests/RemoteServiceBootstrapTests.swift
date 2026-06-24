import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

/// Exercises remote service bootstrap behavior.
final class RemoteServiceBootstrapTests: XCTestCase {
    func testRemoteServiceStartBootstrapsSelectedStateBeforeFirstSnapshot() async throws {
        let suiteName = "RemoteServiceSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backend = RemoteBootstrapServiceBackend()
        let host = try BackgroundServiceHost(backend: backend, defaults: defaults)
        try await host.start()
        defer { host.stop() }

        let coordinator = await MainActor.run { BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!) }
        let appState = await MainActor.run { AppState(launchRole: .app, serviceCoordinator: coordinator, autoStart: false) }

        await MainActor.run { appState.environment.lastReleaseUpdateCheckAt = Date() }
        await appState.runtimeStore.start()

        let selectedDeviceID = await MainActor.run { appState.deviceStore.selectedDeviceID }
        let selectedBattery = await MainActor.run { appState.deviceStore.state?.battery_percent }
        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }

        XCTAssertEqual(selectedDeviceID, RemoteBootstrapServiceBackend.device.id)
        XCTAssertEqual(selectedBattery, 83)
        XCTAssertEqual(selectedDpi, 1600)
    }

    func testRemoteServiceAppliesPushedSnapshotUpdatesOverTCPAfterBootstrap() async throws {
        let suiteName = "RemoteServiceSnapshotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backend = RemoteBootstrapServiceBackend()
        let host = try BackgroundServiceHost(backend: backend, defaults: defaults)
        try await host.start()
        defer { host.stop() }

        let coordinator = await MainActor.run { BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!) }
        let appState = await MainActor.run { AppState(launchRole: .app, serviceCoordinator: coordinator, autoStart: false) }

        await MainActor.run { appState.environment.lastReleaseUpdateCheckAt = Date() }
        await appState.runtimeStore.start()

        let snapshotUpdatedAt = Date().addingTimeInterval(1)
        let updatedState = makeSnapshotState(device: RemoteBootstrapServiceBackend.device, connection: "bluetooth", batteryPercent: 79, dpiValues: [1000, 2000, 3000], activeStage: 2)
        await backend.emit(.snapshot(SharedServiceSnapshot(devices: [RemoteBootstrapServiceBackend.device], stateByDeviceID: [RemoteBootstrapServiceBackend.device.id: updatedState], lastUpdatedByDeviceID: [RemoteBootstrapServiceBackend.device.id: snapshotUpdatedAt])))

        try await waitUntil { await MainActor.run { appState.deviceStore.state?.dpi?.x == 3000 && appState.deviceStore.state?.battery_percent == 79 } }

        let selectedDpi = await MainActor.run { appState.deviceStore.state?.dpi?.x }
        let selectedBattery = await MainActor.run { appState.deviceStore.state?.battery_percent }
        XCTAssertEqual(selectedDpi, 3000)
        XCTAssertEqual(selectedBattery, 79)
    }

    private func waitUntil(timeout: TimeInterval = 2.0, pollInterval: UInt64 = 20_000_000, condition: @escaping @Sendable () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: pollInterval)
        }
        XCTFail("Timed out waiting for condition")
    }
}
