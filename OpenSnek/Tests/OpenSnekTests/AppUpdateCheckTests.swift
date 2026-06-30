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

    @MainActor func testDryRunInstallInvokesSparkleInstaller() async {
        let installer = MockSoftwareUpdateInstaller()
        let appState = AppState(launchRole: .app, backend: BootstrapPendingBackend.shared, softwareUpdateInstaller: installer, autoStart: false)
        appState.deviceStore.availableUpdate = ReleaseAvailability(latestVersion: "1.2.3", releaseURL: URL(string: "https://github.com/gh123man/OpenSnek/releases/tag/v1.2.3")!, checkMode: .latestReleaseDryRun)

        await appState.runtimeController.installAvailableUpdate()

        XCTAssertEqual(appState.deviceStore.updateInstallState, .checking)
        XCTAssertEqual(installer.installCallCount, 1)
    }

    @MainActor func testInstallAvailableUpdateInvokesInstallerForRealRelease() async {
        let installer = MockSoftwareUpdateInstaller(statuses: [.downloading(received: 10, expected: 100)])
        let appState = AppState(launchRole: .app, backend: BootstrapPendingBackend.shared, softwareUpdateInstaller: installer, autoStart: false)
        appState.deviceStore.availableUpdate = ReleaseAvailability(latestVersion: "1.2.3", releaseURL: URL(string: "https://github.com/gh123man/OpenSnek/releases/tag/v1.2.3")!, checkMode: .newerThanCurrent)

        await appState.runtimeController.installAvailableUpdate()

        XCTAssertEqual(appState.deviceStore.updateInstallState, .downloading(received: 10, expected: 100))
        XCTAssertEqual(installer.installCallCount, 1)
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

    func checkForUpdate(currentVersion: String, mode: ReleaseUpdateCheckMode) async throws -> ReleaseAvailability? {
        checks.append(RecordedReleaseCheck(version: currentVersion, mode: mode))
        return nil
    }

    func recordedChecks() -> [RecordedReleaseCheck] { checks }
}

/// Provides a mock software update installer test double.
@MainActor private final class MockSoftwareUpdateInstaller: SoftwareUpdateInstalling {
    private let statuses: [SoftwareUpdateInstallState]
    private(set) var installCallCount = 0

    init(statuses: [SoftwareUpdateInstallState] = []) { self.statuses = statuses }

    func installLatestRelease(statusHandler: @escaping @MainActor (SoftwareUpdateInstallState) -> Void) throws {
        installCallCount += 1
        for status in statuses { statusHandler(status) }
    }
}
