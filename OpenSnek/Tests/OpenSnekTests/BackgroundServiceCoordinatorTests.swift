import AppKit
import XCTest
@testable import OpenSnek

final class BackgroundServiceCoordinatorTests: XCTestCase {
    func testFreshInstallDefaultsEnableMenuBarIcon() async {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let coordinator = await MainActor.run {
            BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!)
        }

        let backgroundServiceEnabled = await MainActor.run { coordinator.backgroundServiceEnabled }
        let launchAtStartupEnabled = await MainActor.run { coordinator.launchAtStartupEnabled }

        XCTAssertTrue(backgroundServiceEnabled)
        XCTAssertFalse(launchAtStartupEnabled)
    }

    func testVersionedMigrationTurnsMenuBarIconOnForPreviouslyMigratedInstall() async {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: BackgroundServiceCoordinator.backgroundServiceEnabledDefaultsKey)
        defaults.set(true, forKey: BackgroundServiceCoordinator.menuBarDefaultMigrationDefaultsKey)

        let coordinator = await MainActor.run {
            BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!)
        }

        let backgroundServiceEnabled = await MainActor.run { coordinator.backgroundServiceEnabled }
        XCTAssertTrue(backgroundServiceEnabled)
        XCTAssertTrue(defaults.bool(forKey: BackgroundServiceCoordinator.menuBarDefaultMigrationV2DefaultsKey))
    }

    func testVersionedMigrationDoesNotOverrideLaterUserOptOut() async {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: BackgroundServiceCoordinator.backgroundServiceEnabledDefaultsKey)
        defaults.set(true, forKey: BackgroundServiceCoordinator.menuBarDefaultMigrationDefaultsKey)
        defaults.set(true, forKey: BackgroundServiceCoordinator.menuBarDefaultMigrationV2DefaultsKey)

        let coordinator = await MainActor.run {
            BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!)
        }

        let backgroundServiceEnabled = await MainActor.run { coordinator.backgroundServiceEnabled }
        XCTAssertFalse(backgroundServiceEnabled)
    }

    func testPreferredReusableApplicationPrefersActiveRegularApp() {
        let selected = BackgroundServiceCoordinator.preferredReusableApplication(
            in: [
                .init(processIdentifier: 101, activationPolicy: .accessory, isActive: true, isTerminated: false),
                .init(processIdentifier: 102, activationPolicy: .regular, isActive: false, isTerminated: false),
                .init(processIdentifier: 103, activationPolicy: .regular, isActive: true, isTerminated: false),
            ],
            excluding: 101
        )

        XCTAssertEqual(selected?.processIdentifier, 103)
    }

    func testPreferredReusableApplicationExcludesCurrentAndTerminatedProcesses() {
        let selected = BackgroundServiceCoordinator.preferredReusableApplication(
            in: [
                .init(processIdentifier: 201, activationPolicy: .regular, isActive: true, isTerminated: false),
                .init(processIdentifier: 202, activationPolicy: .regular, isActive: false, isTerminated: true),
                .init(processIdentifier: 203, activationPolicy: .accessory, isActive: false, isTerminated: false),
            ],
            excluding: 201
        )

        XCTAssertNil(selected)
    }
}
