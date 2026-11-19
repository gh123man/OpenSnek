import Foundation
import OpenSnekCore

/// Learns seconds per percentage point from consecutive battery readings on the same connection.
struct BatteryRuntimeEstimator {
    /// Keep the start of the discharge interval and the last reading to detect gaps or a refill.
    private struct Window {
        let start: Date
        let startPercent: Int
        var last: Date
        var lastPercent: Int

        init(at date: Date, percent: Int) {
            start = date
            startPercent = percent
            last = date
            lastPercent = percent
        }
    }

    private var windows: [String: Window] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    mutating func interrupt(deviceID: String) { windows.removeValue(forKey: deviceID) }

    mutating func observe(_ device: MouseDevice, percent: Int?, charging: Bool?, at date: Date) {
        guard device.hasRechargeableBattery else { return }
        if let last = windows[device.id]?.last, date <= last { return }
        guard let percent, (0...100).contains(percent), charging != true else {
            interrupt(deviceID: device.id)
            return
        }
        guard var window = windows[device.id], date.timeIntervalSince(window.last) <= 10 * 60, percent <= window.lastPercent else {
            windows[device.id] = Window(at: date, percent: percent)
            return
        }
        let elapsed = date.timeIntervalSince(window.start)
        let drop = window.startPercent - percent
        // Commit only on a falling edge. Repeated reads of the same percentage aren't evidence of a slower discharge.
        if percent < window.lastPercent, drop >= 3, elapsed >= 15 * 60 {
            let key = Self.rateKey(device)
            let previous = defaults.double(forKey: key)
            let measured = elapsed / Double(drop)
            defaults.set(previous > 0 ? 0.7 * previous + 0.3 * measured : measured, forKey: key)
            windows[device.id] = Window(at: date, percent: percent)
        } else {
            window.last = date
            window.lastPercent = percent
            windows[device.id] = window
        }
    }

    static func remaining(for device: MouseDevice, percent: Int, defaults: UserDefaults = .standard) -> TimeInterval? {
        guard device.hasRechargeableBattery, (0...100).contains(percent) else { return nil }
        let rate = defaults.double(forKey: rateKey(device))
        guard rate > 0, rate.isFinite else { return nil }
        return Double(percent) * rate
    }

    private static func rateKey(_ device: MouseDevice) -> String {
        // Wireless transports can drain at different rates. Avoid sharing history between
        // identical models without a serial when macOS supplies distinct device IDs.
        let identity = DevicePersistenceKeys.normalizedStableSerial(device.serial) ?? device.id
        return "batterySecondsPerPercent.\(device.transport.rawValue).\(identity)"
    }
}
