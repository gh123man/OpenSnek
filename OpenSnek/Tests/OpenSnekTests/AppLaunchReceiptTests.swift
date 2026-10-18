import XCTest
@testable import OpenSnek

/// Verifies that only a visible foreground app can acknowledge a development launch.
final class AppLaunchReceiptTests: XCTestCase {
    func testServiceOrMissingWindowCannotWriteSuccessReceipt() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertFalse(try AppLaunchReceipt.write(to: url, role: .service, visibleWindowCount: 1))
        XCTAssertFalse(try AppLaunchReceipt.write(to: url, role: .app, visibleWindowCount: 0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testVisibleAppReceiptIncludesIdentityAndWindowCount() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(try AppLaunchReceipt.write(to: url, role: .app, visibleWindowCount: 1))
        let receipt = try JSONDecoder().decode(AppLaunchReceipt.self, from: Data(contentsOf: url))
        XCTAssertEqual(receipt.role, "app")
        XCTAssertEqual(receipt.visibleWindowCount, 1)
        XCTAssertEqual(receipt.pid, ProcessInfo.processInfo.processIdentifier)
        XCTAssertEqual(receipt.bundlePath, Bundle.main.bundleURL.path)
    }

    private func temporaryURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("launch-\(UUID().uuidString).json") }
}
