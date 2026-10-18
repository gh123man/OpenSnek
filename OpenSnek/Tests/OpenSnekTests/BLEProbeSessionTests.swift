import XCTest
import OpenSnekHardware

/// Verifies fail-fast isolation without connecting to Bluetooth hardware.
final class BLEProbeSessionTests: XCTestCase {
    func testRunningAppPreventsProbeAcquisition() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try BLEProbeSession(lockURL: directory.appendingPathComponent("probe.lock"), activeAppProcessIDs: { [123] }))
    }

    func testContentionFailsAndReleaseAllowsAnotherSession() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("probe.lock")
        var first: BLEProbeSession? = try BLEProbeSession(lockURL: url, activeAppProcessIDs: { [] })
        XCTAssertNotNil(first)
        XCTAssertThrowsError(try BLEProbeSession(lockURL: url, activeAppProcessIDs: { [] }))
        first = nil
        let recovered = try BLEProbeSession(lockURL: url, activeAppProcessIDs: { [] })
        try recovered.checkAppIsStopped()
    }

    func testAppStartingAfterAcquisitionIsRejectedBeforeAnotherExchange() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try BLEProbeSession(lockURL: directory.appendingPathComponent("probe.lock"), activeAppProcessIDs: { [] })
        XCTAssertThrowsError(try session.checkAppIsStopped(activeAppProcessIDs: [456]))
        try session.checkAppIsStopped(activeAppProcessIDs: [])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
