import Foundation

/// A development-launch acknowledgment emitted only after a foreground main window is visible.
struct AppLaunchReceipt: Codable {
    let schemaVersion: Int
    let pid: Int32
    let bundlePath: String
    let role: String
    let visibleWindowCount: Int

    static func write(to url: URL, role: OpenSnekProcessRole, visibleWindowCount: Int) throws -> Bool {
        guard role == .app, visibleWindowCount > 0 else { return false }
        let receipt = Self(schemaVersion: 1, pid: ProcessInfo.processInfo.processIdentifier, bundlePath: Bundle.main.bundleURL.path, role: role.rawValue, visibleWindowCount: visibleWindowCount)
        try JSONEncoder().encode(receipt).write(to: url, options: .atomic)
        return true
    }
}
