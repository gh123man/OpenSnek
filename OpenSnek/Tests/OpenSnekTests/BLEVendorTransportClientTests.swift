import Foundation
import XCTest
@testable import OpenSnekHardware

/// Exercises BLE vendor transport completion timing.
final class BLEVendorTransportClientTests: XCTestCase {
    func testResponseIdleTimerCompletesOnlyAfterLatestActivityDeadline() throws {
        let scheduler = WorkItemRecorder()
        let completions = LockedCounter()
        let timer = BLEVendorResponseIdleTimer(scheduler: scheduler.record, onIdle: completions.increment)

        timer.restart()
        timer.restart()
        timer.restart()

        XCTAssertEqual(scheduler.count, 3)
        try scheduler.item(at: 0).perform()
        try scheduler.item(at: 1).perform()
        XCTAssertEqual(completions.value, 0)

        try scheduler.item(at: 2).perform()
        XCTAssertEqual(completions.value, 1)
    }
}

/// Records scheduled work so idle deadlines can be advanced deterministically.
private final class WorkItemRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DispatchWorkItem] = []

    var count: Int { lock.withLock { items.count } }

    func record(_ item: DispatchWorkItem) { lock.withLock { items.append(item) } }

    func item(at index: Int) throws -> DispatchWorkItem { try XCTUnwrap(lock.withLock { items.indices.contains(index) ? items[index] : nil }) }
}

/// Stores completion counts across dispatch work-item callbacks.
private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int { lock.withLock { count } }

    func increment() { lock.withLock { count += 1 } }
}
