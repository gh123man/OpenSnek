import Foundation
import OpenSnekCore
import XCTest
@testable import OpenSnek

/// Exercises learning across observations, interruptions, and different batteries.
final class BatteryRuntimeEstimatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let suite = "BatteryRuntimeTests." + UUID().uuidString
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func device(_ profile: DeviceProfile = DeviceProfiles.basiliskV3ProUSB, id: String = "receiver") -> MouseDevice {
        MouseDevice(id: id, vendor_id: profile.transport == .usb ? 0x1532 : 0x068E, product_id: profile.supportedProducts.min()!, product_name: profile.productName, transport: profile.transport, path_b64: "", serial: nil, firmware: nil, profile_id: profile.id)
    }

    func testLearnsFromSustainedDropAndSmoothsNextInterval() throws {
        let device = device()
        var estimator = BatteryRuntimeEstimator(defaults: defaults)
        func sample(_ minute: Int, _ percent: Int) { estimator.observe(device, percent: percent, charging: false, at: start.addingTimeInterval(Double(minute * 60))) }
        func estimate(_ level: Int) -> TimeInterval? { BatteryRuntimeEstimator.remaining(for: device, percent: level, defaults: defaults) }
        sample(0, 90)
        sample(8, 89)
        sample(10, 88)
        XCTAssertNil(estimate(88))
        sample(15, 87)
        XCTAssertEqual(estimate(87), 87 * 300)
        sample(20, 87)
        sample(30, 87)
        XCTAssertEqual(estimate(87), 87 * 300)
        sample(35, 86)
        sample(40, 85)
        sample(45, 84)
        XCTAssertEqual(try XCTUnwrap(estimate(84)), 84 * (0.7 * 300 + 0.3 * 600), accuracy: 0.001)
        estimator.interrupt(deviceID: device.id)
        XCTAssertNotNil(estimate(80))
    }

    func testDiscontinuitiesCannotCompleteASamplingWindow() {
        let device = device()
        for interruption in ["charging", "refill", "disconnect", "missing", "sleep"] {
            var estimator = BatteryRuntimeEstimator(defaults: defaults)
            estimator.observe(device, percent: 80, charging: false, at: start)
            estimator.observe(device, percent: 78, charging: false, at: start.addingTimeInterval(500))
            let at = start.addingTimeInterval(510)
            switch interruption {
            case "charging": estimator.observe(device, percent: 78, charging: true, at: at)
            case "refill": estimator.observe(device, percent: 79, charging: nil, at: at)
            case "missing": estimator.observe(device, percent: nil, charging: nil, at: at)
            case "disconnect": estimator.interrupt(deviceID: device.id)
            default: break
            }
            estimator.observe(device, percent: 76, charging: false, at: start.addingTimeInterval(interruption == "sleep" ? 3600 : 1000))
            XCTAssertNil(BatteryRuntimeEstimator.remaining(for: device, percent: 76, defaults: defaults), interruption)
        }
    }

    private func train(_ device: MouseDevice, estimator: inout BatteryRuntimeEstimator) { for (index, level) in [70, 69, 67].enumerated() { estimator.observe(device, percent: level, charging: false, at: start.addingTimeInterval(Double(index * 450))) } }

    func testEveryRegisteredProfileUsesItsBatteryCapability() {
        let rechargeable: Set<DeviceProfileID> = [.basiliskV3Pro, .basiliskV3Pro35K, .basiliskV4Hyperspeed, .basiliskMobile, .nagaPro, .nagaV2Pro, .nagaV3Pro]
        var estimator = BatteryRuntimeEstimator(defaults: defaults)
        for profile in DeviceProfiles.all {
            let device = device(profile, id: "\(profile.id.rawValue)-\(profile.transport.rawValue)")
            train(device, estimator: &estimator)
            let estimate = BatteryRuntimeEstimator.remaining(for: device, percent: 67, defaults: defaults)
            XCTAssertEqual(estimate, rechargeable.contains(profile.id) ? 67 * 300 : nil, device.id)
        }
    }

    func testDeviceAndTransportHistoriesAreIndependent() {
        var estimator = BatteryRuntimeEstimator(defaults: defaults)
        train(device(), estimator: &estimator)
        for other in [device(id: "other"), device(DeviceProfiles.basiliskV3ProBluetooth)] { XCTAssertNil(BatteryRuntimeEstimator.remaining(for: other, percent: 67, defaults: defaults)) }
    }
}
