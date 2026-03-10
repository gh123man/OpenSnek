import XCTest
@testable import OpenSnek
import OpenSnekCore

final class AdaptiveRefreshPolicyTests: XCTestCase {
    func testActiveIntervalsUseResponsiveDefaults() {
        XCTAssertEqual(AdaptiveRefreshPolicy.interval(for: .presence, isSceneActive: true, backoffStep: 0), 15.0)
        XCTAssertEqual(AdaptiveRefreshPolicy.interval(for: .selectedCore, isSceneActive: true, backoffStep: 0), 3.0)
        XCTAssertEqual(AdaptiveRefreshPolicy.interval(for: .selectedSlow, isSceneActive: true, backoffStep: 0), 20.0)
    }

    func testInactiveIntervalsBackOffAggressively() {
        XCTAssertEqual(AdaptiveRefreshPolicy.interval(for: .presence, isSceneActive: false, backoffStep: 0), 60.0)
        XCTAssertEqual(AdaptiveRefreshPolicy.interval(for: .selectedCore, isSceneActive: false, backoffStep: 0), 10.0)
        XCTAssertEqual(AdaptiveRefreshPolicy.interval(for: .selectedSlow, isSceneActive: false, backoffStep: 0), 60.0)
    }

    func testBackoffCapsAtFourTimesBaseInterval() {
        XCTAssertEqual(AdaptiveRefreshPolicy.interval(for: .selectedCore, isSceneActive: true, backoffStep: 1), 6.0)
        XCTAssertEqual(AdaptiveRefreshPolicy.interval(for: .selectedCore, isSceneActive: true, backoffStep: 2), 12.0)
        XCTAssertEqual(AdaptiveRefreshPolicy.interval(for: .selectedCore, isSceneActive: true, backoffStep: 99), 12.0)
    }

    func testFastDpiIntervalsDifferByTransport() {
        XCTAssertEqual(AdaptiveRefreshPolicy.fastDpiInterval(for: .usb), 0.55)
        XCTAssertEqual(AdaptiveRefreshPolicy.fastDpiInterval(for: .bluetooth), 0.25)
    }
}
