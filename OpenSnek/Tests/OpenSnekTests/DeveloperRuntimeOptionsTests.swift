import Foundation
import XCTest
import OpenSnekAppSupport

/// Exercises developer runtime options behavior.
final class DeveloperRuntimeOptionsTests: XCTestCase {
    func testDeveloperRuntimeOptionsDefaultToEnabled() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        XCTAssertTrue(DeveloperRuntimeOptions.pollingEnabled(defaults: defaults))
        XCTAssertTrue(DeveloperRuntimeOptions.passiveHIDUpdatesEnabled(defaults: defaults))
        XCTAssertTrue(DeveloperRuntimeOptions.rememberWindowSizeEnabled(defaults: defaults))
        XCTAssertFalse(DeveloperRuntimeOptions.releaseUpdateDryRunEnabled(defaults: defaults))
    }

    func testDeveloperRuntimeOptionsReadPersistedFalseValues() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: DeveloperRuntimeOptions.pollingEnabledDefaultsKey)
        defaults.set(false, forKey: DeveloperRuntimeOptions.passiveHIDUpdatesEnabledDefaultsKey)
        defaults.set(false, forKey: DeveloperRuntimeOptions.rememberWindowSizeEnabledDefaultsKey)
        defaults.set(true, forKey: DeveloperRuntimeOptions.releaseUpdateDryRunEnabledDefaultsKey)

        XCTAssertFalse(DeveloperRuntimeOptions.pollingEnabled(defaults: defaults))
        XCTAssertFalse(DeveloperRuntimeOptions.passiveHIDUpdatesEnabled(defaults: defaults))
        XCTAssertFalse(DeveloperRuntimeOptions.rememberWindowSizeEnabled(defaults: defaults))
        XCTAssertTrue(DeveloperRuntimeOptions.releaseUpdateDryRunEnabled(defaults: defaults))
    }
}
