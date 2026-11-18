import XCTest
import OpenSnekAppSupport
import OpenSnekCore
@testable import OpenSnek

/// Exercises the service-to-window handoff before the foreground runtime performs any reads.
final class ServiceLaunchPresentationTests: XCTestCase {
    @MainActor func testFirstFrameUsesSelectedDeviceActiveProfileAndButtonBindings() throws {
        let domain = "ServiceLaunchPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        for transport in [DeviceTransportKind.usb, .bluetooth] {
            let device = makeRefactorTestDevice(id: "launch-\(transport)", transport: transport, serial: "launch-selected", onboardProfileCount: 5, profileID: .basiliskV3Pro)
            let other = makeRefactorTestDevice(id: "launch-other", transport: .bluetooth, serial: "launch-other", onboardProfileCount: 1)
            let service = AppState(launchRole: .service, backend: SnapshotTestRemoteBackend(), autoStart: false)
            let state = makeRefactorTestState(device: device, telemetry: .init(connection: transport.rawValue, batteryPercent: 81, dpiValues: [700, 1400], activeStage: 1), options: .init(activeOnboardProfile: 3, onboardProfileCount: 5))
            service.deviceStore.devices = [other, device]
            service.deviceStore.selectedDeviceID = device.id
            service.deviceController.stateCacheByDeviceID[device.id] = state
            service.deviceController.lastUpdatedByDeviceID[device.id] = Date()
            let profile = makeRefactorOnboardProfileSnapshot(profileID: 3, name: "Studio", dpiValues: [700, 1400], activeStage: 1)
            let inventory = OnboardProfileInventory(activeProfileID: 3, maxProfileID: 5, assignedProfileIDs: [1, 3], profiles: [makeRefactorOnboardProfileSummary(profileID: 3, name: "Studio", isActive: true)])
            var prepared = ServiceProfilePreparation()
            let token = try XCTUnwrap(prepared.begin(device: device, profileID: 3, retryFailed: false))
            prepared.finish(token: token, inventory: inventory, profile: profile)
            prepared.end(token: token)
            let launch = service.deviceController.makeLaunchPresentation(prepared: prepared, hidAccess: .unknown())
            let window = AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false, preferenceStore: DevicePreferenceStore(defaults: defaults))
            let decoded = try XCTUnwrap(ServiceLaunchPresentation.decode(launch.encoded, servicePID: launch.processID))
            window.deviceController.applyLaunchPresentation(decoded)

            XCTAssertEqual(window.deviceStore.selectedDeviceID, device.id)
            XCTAssertEqual(window.deviceStore.connectionState(for: device), .connected)
            XCTAssertEqual(window.editorStore.selectedOnboardProfileName, "Studio")
            XCTAssertEqual(window.editorStore.editableStageValues.prefix(2), [700, 1400])
            XCTAssertEqual(window.editorStore.editableButtonBindings, profile.buttonBindings)
            XCTAssertFalse(window.editorStore.isOnboardProfileLoadInFlight)
            window.editorStore.isOnboardProfileRefreshInFlight = true
            XCTAssertFalse(window.editorStore.isOnboardProfilePillLoading)
            XCTAssertNil(ServiceLaunchPresentation.decode(launch.encoded, servicePID: launch.processID + 1))
            XCTAssertNil(ServiceLaunchPresentation.decode(launch.encoded, servicePID: launch.processID, now: launch.createdAt.addingTimeInterval(60)))
        }
    }

    @MainActor func testDeviceWithoutPreparedOnboardProfilesOpensWithLiveDPI() {
        for transport in [DeviceTransportKind.usb, .bluetooth] {
            let device = makeRefactorTestDevice(id: "single-slot-\(transport)", transport: transport, serial: "single-slot", onboardProfileCount: 1, profileID: .basiliskV3XHyperspeed)
            let state = makeSnapshotState(device: device, connection: transport.rawValue, batteryPercent: 65, dpiValues: [800, 1800], activeStage: 1)
            let service = AppState(launchRole: .service, backend: SnapshotTestRemoteBackend(), autoStart: false)
            service.deviceStore.devices = [device]
            service.deviceStore.selectedDeviceID = device.id
            service.deviceController.stateCacheByDeviceID[device.id] = state
            service.deviceController.lastUpdatedByDeviceID[device.id] = Date()
            let launch = service.deviceController.makeLaunchPresentation(prepared: ServiceProfilePreparation(), hidAccess: .unknown())
            XCTAssertNil(launch.activeProfile)
            let window = AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false)
            window.deviceController.applyLaunchPresentation(launch)
            XCTAssertEqual(window.deviceStore.connectionState(for: device), .connected)
            XCTAssertEqual(window.editorStore.editableStageValues.prefix(2), [800, 1800])
            XCTAssertFalse(window.editorStore.isOnboardProfileLoadInFlight)
        }
    }

    @MainActor func testOfflineHandoffDropsCachedSettingsAndAcceptsLiveRecovery() {
        let device = makeRefactorTestDevice(id: "offline-launch", transport: .usb, serial: "offline-launch", onboardProfileCount: 1)
        let state = makeSnapshotState(device: device, connection: "usb", batteryPercent: 61, dpiValues: [800, 1600], activeStage: 0)
        let service = AppState(launchRole: .service, backend: SnapshotTestRemoteBackend(), autoStart: false)
        service.deviceStore.devices = [device]
        service.deviceStore.selectedDeviceID = device.id
        service.deviceController.stateCacheByDeviceID[device.id] = state
        service.deviceController.setUSBControlAvailability(.receiverPresentMouseUnavailable, for: device.id, observedAt: Date())
        let launch = service.deviceController.makeLaunchPresentation(prepared: ServiceProfilePreparation(), hidAccess: .unknown())
        let window = AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false)
        window.deviceController.applyLaunchPresentation(launch)
        XCTAssertNil(window.deviceStore.state)
        XCTAssertEqual(window.deviceStore.connectionState(for: device), .disconnected)
        window.deviceStore.applyRemoteServiceSnapshot(SharedServiceSnapshot(devices: [device], stateByDeviceID: [device.id: state], lastUpdatedByDeviceID: [device.id: Date()], usbControlAvailabilityByDeviceID: [device.id: .receiverPresentMouseReachable]))
        XCTAssertEqual(window.deviceStore.connectionState(for: device), .connected)
        XCTAssertEqual(window.deviceStore.state, state)
    }

    func testLateReadCannotRepopulateInvalidatedProfile() throws {
        let device = makeRefactorTestDevice(id: "profile-generation", transport: .bluetooth, serial: "generation", onboardProfileCount: 5)
        var prepared = ServiceProfilePreparation()
        let oldToken = try XCTUnwrap(prepared.begin(device: device, profileID: 1, retryFailed: false))
        XCTAssertNil(prepared.begin(device: device, profileID: 1, retryFailed: true))
        prepared.invalidate(deviceID: device.id)
        let newToken = try XCTUnwrap(prepared.begin(device: device, profileID: 1, retryFailed: false))
        prepared.finish(token: oldToken, inventory: OnboardProfileInventory(activeProfileID: 1, maxProfileID: 5, assignedProfileIDs: [1], profiles: []), profile: makeRefactorOnboardProfileSnapshot(profileID: 1, name: "Obsolete"))
        prepared.end(token: oldToken)
        XCTAssertNil(prepared.profile)
        XCTAssertEqual(prepared.token, newToken)
    }
}
