import AppKit
import Darwin
import Foundation
import OpenSnekCore

/// Isolates manual BLE probes from OpenSnek and other probe processes.
/// The lock intentionally covers all BLE probes for this user, before a peripheral is selected.
/// It is advisory, released by the kernel on process exit, and never unlinked while in use.
public final class BLEProbeSession {
    private let descriptor: Int32
    private let activeAppProcessIDs: () -> [Int32]

    public init(lockURL: URL? = nil, activeAppProcessIDs: @escaping () -> [Int32] = BLEProbeSession.runningAppProcessIDs) throws {
        self.activeAppProcessIDs = activeAppProcessIDs
        try Self.requireStopped(activeAppProcessIDs())
        let url = lockURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("open-snek-ble-probe-\(getuid()).lock")
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw BridgeError.commandFailed("Cannot open BLE probe lock: errno \(errno)") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(descriptor)
            throw BridgeError.commandFailed("Another BLE probe session owns the lock (errno \(failure)). Stop it before probing; no commands were sent.")
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }

    public func checkAppIsStopped(activeAppProcessIDs: [Int32]? = nil) throws { try Self.requireStopped(activeAppProcessIDs ?? self.activeAppProcessIDs()) }

    public static func runningAppProcessIDs() -> [Int32] { NSRunningApplication.runningApplications(withBundleIdentifier: "io.opensnek.OpenSnek").map(\.processIdentifier) }

    private static func requireStopped(_ processIDs: [Int32]) throws { guard processIDs.isEmpty else { throw BridgeError.commandFailed("Stop both OpenSnek app and background service before BLE probing (PIDs \(processIDs.map(String.init).joined(separator: ","))). No commands were sent.") } }
}
