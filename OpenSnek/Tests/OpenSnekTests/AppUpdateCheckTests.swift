import Foundation
import XCTest
@testable import OpenSnek

final class AppUpdateCheckTests: XCTestCase {
    func testPeriodicUpdateCheckIsDueAfterFullDay() {
        let start = Date(timeIntervalSince1970: 1_774_000_000)

        XCTAssertTrue(ReleaseUpdateChecker.isPeriodicCheckDue(lastCheckedAt: nil, now: start))
        XCTAssertFalse(
            ReleaseUpdateChecker.isPeriodicCheckDue(
                lastCheckedAt: start,
                now: start.addingTimeInterval(ReleaseUpdateChecker.periodicCheckInterval - 1)
            )
        )
        XCTAssertTrue(
            ReleaseUpdateChecker.isPeriodicCheckDue(
                lastCheckedAt: start,
                now: start.addingTimeInterval(ReleaseUpdateChecker.periodicCheckInterval)
            )
        )
    }

    @MainActor
    func testForegroundRuntimeChecksForUpdatesAtMostOncePerDayWithoutRestart() async {
        let checker = MockReleaseUpdateChecker()
        let appState = AppState(
            launchRole: .app,
            backend: BootstrapPendingBackend.shared,
            releaseUpdateChecker: checker,
            currentAppVersion: "1.0.0",
            shouldCheckForReleaseUpdates: true,
            autoStart: false
        )
        let start = Date(timeIntervalSince1970: 1_774_000_000)

        await appState.runtimeController.pollRuntimeOnce(now: start)
        var recordedVersions = await checker.recordedVersions()
        XCTAssertEqual(recordedVersions, ["1.0.0"])

        await appState.runtimeController.pollRuntimeOnce(
            now: start.addingTimeInterval(ReleaseUpdateChecker.periodicCheckInterval - 1)
        )
        recordedVersions = await checker.recordedVersions()
        XCTAssertEqual(recordedVersions, ["1.0.0"])

        await appState.runtimeController.pollRuntimeOnce(
            now: start.addingTimeInterval(ReleaseUpdateChecker.periodicCheckInterval)
        )
        recordedVersions = await checker.recordedVersions()
        XCTAssertEqual(recordedVersions, ["1.0.0", "1.0.0"])
    }

    @MainActor
    func testForegroundRuntimeSkipsNetworkChecksWhenReleaseChecksAreDisabled() async {
        let checker = MockReleaseUpdateChecker()
        let appState = AppState(
            launchRole: .app,
            backend: BootstrapPendingBackend.shared,
            releaseUpdateChecker: checker,
            currentAppVersion: "1.0.0",
            shouldCheckForReleaseUpdates: false,
            autoStart: false
        )

        await appState.runtimeController.pollRuntimeOnce(now: Date(timeIntervalSince1970: 1_774_000_000))

        let recordedVersions = await checker.recordedVersions()
        XCTAssertEqual(recordedVersions, [])
        XCTAssertNil(appState.deviceStore.availableUpdate)
    }
}

private actor MockReleaseUpdateChecker: ReleaseUpdateChecking {
    private var versions: [String] = []

    func checkForUpdate(currentVersion: String) async throws -> ReleaseAvailability? {
        versions.append(currentVersion)
        return nil
    }

    func recordedVersions() -> [String] {
        versions
    }
}
