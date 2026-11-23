import Foundation
import XCTest
@testable import OpenSnek

/// Exercises app update check behavior.
final class AppUpdateCheckTests: XCTestCase {
    func testPeriodicUpdateCheckIsDueAfterFullDay() {
        let start = Date(timeIntervalSince1970: 1_774_000_000)

        XCTAssertTrue(ReleaseUpdateChecker.isPeriodicCheckDue(lastCheckedAt: nil, now: start))
        XCTAssertFalse(ReleaseUpdateChecker.isPeriodicCheckDue(lastCheckedAt: start, now: start.addingTimeInterval(ReleaseUpdateChecker.periodicCheckInterval - 1)))
        XCTAssertTrue(ReleaseUpdateChecker.isPeriodicCheckDue(lastCheckedAt: start, now: start.addingTimeInterval(ReleaseUpdateChecker.periodicCheckInterval)))
    }

    @MainActor func testForegroundRuntimeChecksForUpdatesAtMostOncePerDayWithoutRestart() async {
        let checker = MockReleaseUpdateChecker()
        let appState = AppState(launchRole: .app, backend: BootstrapPendingBackend.shared, releaseUpdateChecker: checker, currentAppVersion: "1.0.0", shouldCheckForReleaseUpdates: true, autoStart: false)
        let start = Date(timeIntervalSince1970: 1_774_000_000)

        await appState.runtimeController.pollRuntimeOnce(now: start)
        var recordedChecks = await checker.recordedChecks()
        XCTAssertEqual(recordedChecks, [RecordedReleaseCheck(version: "1.0.0", mode: .newerThanCurrent)])

        await appState.runtimeController.pollRuntimeOnce(now: start.addingTimeInterval(ReleaseUpdateChecker.periodicCheckInterval - 1))
        recordedChecks = await checker.recordedChecks()
        XCTAssertEqual(recordedChecks, [RecordedReleaseCheck(version: "1.0.0", mode: .newerThanCurrent)])

        await appState.runtimeController.pollRuntimeOnce(now: start.addingTimeInterval(ReleaseUpdateChecker.periodicCheckInterval))
        recordedChecks = await checker.recordedChecks()
        XCTAssertEqual(recordedChecks, [RecordedReleaseCheck(version: "1.0.0", mode: .newerThanCurrent), RecordedReleaseCheck(version: "1.0.0", mode: .newerThanCurrent)])
    }

    @MainActor func testForegroundRuntimeSkipsNetworkChecksWhenReleaseChecksAreDisabled() async {
        let checker = MockReleaseUpdateChecker()
        let appState = AppState(launchRole: .app, backend: BootstrapPendingBackend.shared, releaseUpdateChecker: checker, currentAppVersion: "1.0.0", shouldCheckForReleaseUpdates: false, autoStart: false)

        await appState.runtimeController.pollRuntimeOnce(now: Date(timeIntervalSince1970: 1_774_000_000))

        let recordedChecks = await checker.recordedChecks()
        XCTAssertEqual(recordedChecks, [])
        XCTAssertNil(appState.deviceStore.availableUpdate)
    }

    @MainActor func testRCBuildChecksForNewerReleaseCandidates() async {
        let checker = MockReleaseUpdateChecker()
        let appState = AppState(launchRole: .app, backend: BootstrapPendingBackend.shared, releaseUpdateChecker: checker, currentAppVersion: "1.4.1-rc.1", shouldCheckForReleaseUpdates: true, autoStart: false)
        await appState.runtimeController.pollRuntimeOnce()
        let checks = await checker.recordedChecks()
        XCTAssertEqual(checks, [RecordedReleaseCheck(version: "1.4.1-rc.1", mode: .includingReleaseCandidates)])
    }

    @MainActor func testSettingsCheckBypassesDailyIntervalAndInstallsSelectedRelease() async {
        let checker = MockReleaseUpdateChecker()
        let installer = MockSoftwareUpdateInstaller()
        let app = AppState(launchRole: .app, backend: BootstrapPendingBackend.shared, releaseUpdateChecker: checker, currentAppVersion: "1.5.1-rc.1", shouldCheckForReleaseUpdates: true, softwareUpdateInstaller: installer, autoStart: false)
        await app.runtimeController.pollRuntimeOnce()
        XCTAssertEqual(app.deviceStore.updateCheckState, .upToDate)

        let release = ReleaseAvailability(latestVersion: "1.5.1-rc.2", releaseURL: ReleaseUpdateChecker.releasesPageURL, checkMode: .includingReleaseCandidates)
        await checker.setResult(.success(release))
        await app.deviceStore.checkForUpdates()
        let checks = await checker.recordedChecks()
        XCTAssertEqual(checks.map(\.mode), [.includingReleaseCandidates, .includingReleaseCandidates])
        XCTAssertEqual(app.deviceStore.availableUpdate, release)

        await app.runtimeController.installAvailableUpdate()
        XCTAssertEqual(installer.installedRelease, release)
    }

    @MainActor func testSettingsCheckReportsFailureAndCanRetryWithoutAutomaticChecks() async {
        let checker = MockReleaseUpdateChecker()
        let app = AppState(launchRole: .app, backend: BootstrapPendingBackend.shared, releaseUpdateChecker: checker, currentAppVersion: "1.0.0", shouldCheckForReleaseUpdates: false, autoStart: false)
        await checker.setResult(.failure(URLError(.notConnectedToInternet)))
        await app.deviceStore.checkForUpdates()
        XCTAssertEqual(app.deviceStore.updateCheckState, .failed(URLError(.notConnectedToInternet).localizedDescription))
        XCTAssertNil(app.deviceStore.availableUpdate)

        await checker.setResult(.success(nil))
        await app.deviceStore.checkForUpdates()
        XCTAssertEqual(app.deviceStore.updateCheckState, .upToDate)
    }

    @MainActor func testDryRunInstallInvokesSparkleInstaller() async {
        let installer = MockSoftwareUpdateInstaller()
        let appState = AppState(launchRole: .app, backend: BootstrapPendingBackend.shared, softwareUpdateInstaller: installer, autoStart: false)
        appState.deviceStore.availableUpdate = ReleaseAvailability(latestVersion: "1.2.3", releaseURL: URL(string: "https://github.com/gh123man/OpenSnek/releases/tag/v1.2.3")!, checkMode: .latestReleaseDryRun)

        await appState.runtimeController.installAvailableUpdate()

        XCTAssertEqual(appState.deviceStore.updateInstallState, .idle)
        XCTAssertEqual(installer.installCallCount, 1)
        XCTAssertEqual(installer.installedRelease, appState.deviceStore.availableUpdate)
    }

    @MainActor func testInstallAvailableUpdateInvokesInstallerForRealRelease() async {
        let installer = MockSoftwareUpdateInstaller(statuses: [.downloading(received: 10, expected: 100)])
        let appState = AppState(launchRole: .app, backend: BootstrapPendingBackend.shared, softwareUpdateInstaller: installer, autoStart: false)
        appState.deviceStore.availableUpdate = ReleaseAvailability(latestVersion: "1.2.3", releaseURL: URL(string: "https://github.com/gh123man/OpenSnek/releases/tag/v1.2.3")!, checkMode: .newerThanCurrent)

        installer.operation = {
            XCTAssertEqual(appState.deviceStore.updateInstallState, .downloading(received: 10, expected: 100))
            XCTAssertTrue(appState.runtimeController.isInstallingUpdate)
            await appState.runtimeController.installAvailableUpdate()
            XCTAssertEqual(installer.installCallCount, 1, "Repeated clicks must not start another update")
        }
        await appState.runtimeController.installAvailableUpdate()

        XCTAssertEqual(appState.deviceStore.updateInstallState, .idle)
        XCTAssertFalse(appState.runtimeController.isInstallingUpdate)
        XCTAssertEqual(installer.installCallCount, 1)
        XCTAssertEqual(installer.installedRelease, appState.deviceStore.availableUpdate)
    }
}

/// Stores a recorded release update check request.
private struct RecordedReleaseCheck: Equatable {
    let version: String
    let mode: ReleaseUpdateCheckMode
}

/// Provides a mock release update checker test double.
private actor MockReleaseUpdateChecker: ReleaseUpdateChecking {
    private var checks: [RecordedReleaseCheck] = []
    private var result: Result<ReleaseAvailability?, URLError> = .success(nil)

    func setResult(_ result: Result<ReleaseAvailability?, URLError>) { self.result = result }

    func checkForUpdate(currentVersion: String, mode: ReleaseUpdateCheckMode) async throws -> ReleaseAvailability? {
        checks.append(RecordedReleaseCheck(version: currentVersion, mode: mode))
        return try result.get()
    }

    func recordedChecks() -> [RecordedReleaseCheck] { checks }
}

/// Provides a mock software update installer test double.
@MainActor private final class MockSoftwareUpdateInstaller: SoftwareUpdateInstalling {
    private let statuses: [SoftwareUpdateInstallState]
    private(set) var installCallCount = 0
    private(set) var installedRelease: ReleaseAvailability?
    var operation: @MainActor () async -> Void = {}

    init(statuses: [SoftwareUpdateInstallState] = []) { self.statuses = statuses }

    func installLatestRelease(_ release: ReleaseAvailability, statusHandler: @escaping @MainActor (SoftwareUpdateInstallState) -> Void) async throws {
        installCallCount += 1
        installedRelease = release
        for status in statuses { statusHandler(status) }
        await operation()
    }
}
