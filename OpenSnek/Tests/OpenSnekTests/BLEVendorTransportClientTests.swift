import Foundation
import XCTest
@testable import OpenSnekHardware

/// Exercises BLE vendor transport routing and completion timing.
final class BLEVendorTransportClientTests: XCTestCase {
    func testReadyConnectionSwitchesBetweenBasiliskModelsInBothDirections() {
        let pro = BLEVendorTransportClient.ConnectedPeripheralSummary(name: "BSK V3 PRO", identifier: UUID())
        let pro35K = BLEVendorTransportClient.ConnectedPeripheralSummary(name: "BSKV3P 35K", identifier: UUID())
        for devices in [[pro, pro35K], [pro35K, pro]] {
            XCTAssertEqual(BLEVendorTransportClient.connectionSelection(from: devices, preferredName: pro35K.name, currentIdentifier: pro.identifier, isReady: true), .connect(pro35K.identifier))
            XCTAssertEqual(BLEVendorTransportClient.connectionSelection(from: devices, preferredName: pro.name, currentIdentifier: pro35K.identifier, isReady: true), .connect(pro.identifier))
            XCTAssertEqual(BLEVendorTransportClient.connectionSelection(from: devices, preferredName: pro35K.name, currentIdentifier: pro35K.identifier, isReady: true), .reuse)
        }
    }

    func testMissingSelectedBasiliskWaitsAndReconnectsWithoutUsingOtherMouse() {
        let pro = BLEVendorTransportClient.ConnectedPeripheralSummary(name: "BSK V3 PRO", identifier: UUID())
        let pro35K = BLEVendorTransportClient.ConnectedPeripheralSummary(name: "BSKV3P 35K", identifier: UUID())
        for (selected, other) in [(pro, pro35K), (pro35K, pro)] {
            XCTAssertEqual(BLEVendorTransportClient.connectionSelection(from: [other], preferredName: selected.name, currentIdentifier: other.identifier, isReady: true), .wait)
            XCTAssertEqual(BLEVendorTransportClient.connectionSelection(from: [], preferredName: selected.name, currentIdentifier: selected.identifier, isReady: true), .wait)
            XCTAssertEqual(BLEVendorTransportClient.connectionSelection(from: [other, selected], preferredName: selected.name, currentIdentifier: other.identifier, isReady: true), .connect(selected.identifier))
            XCTAssertEqual(BLEVendorTransportClient.connectionSelection(from: [selected], preferredName: selected.name, currentIdentifier: selected.identifier, isReady: false), .connect(selected.identifier))
        }
    }

    func testPeripheralSelectionSupportsMarketingNamesAndUnnamedRequests() {
        let pro35K = BLEVendorTransportClient.ConnectedPeripheralSummary(name: "BSKV3P 35K", identifier: UUID())
        let pro = BLEVendorTransportClient.ConnectedPeripheralSummary(name: "BSK V3 PRO", identifier: UUID())
        let devices = [pro, pro35K]
        XCTAssertEqual(BLEVendorTransportClient.connectionSelection(from: devices, preferredName: "Razer Basilisk V3 Pro 35K Phantom Green Edition", currentIdentifier: pro.identifier, isReady: true), .connect(pro35K.identifier))
        XCTAssertEqual(BLEVendorTransportClient.connectionSelection(from: devices, preferredName: "Orochi V2", currentIdentifier: pro.identifier, isReady: true), .wait)
        XCTAssertEqual(BLEVendorTransportClient.connectionSelection(from: devices, preferredName: nil, currentIdentifier: pro35K.identifier, isReady: true), .reuse)
        XCTAssertEqual(BLEVendorTransportClient.connectionSelection(from: devices, preferredName: nil, currentIdentifier: nil, isReady: false), .connect(pro.identifier))
    }

    func testConnectionOnlyWarmupCompletesWithoutACommandResponse() throws {
        let scheduler = WorkItemRecorder()
        let completions = LockedCounter()
        let timer = BLEVendorResponseIdleTimer(scheduler: scheduler.record, onIdle: completions.increment)
        timer.restart(responseExpected: false, hasResponse: false)
        try scheduler.item(at: 0).perform()
        XCTAssertEqual(completions.value, 1)
        timer.restart(responseExpected: true, hasResponse: false)
        XCTAssertEqual(scheduler.count, 1, "The following command must wait for its own response")
        timer.restart(responseExpected: true, hasResponse: true)
        try scheduler.item(at: 1).perform()
        XCTAssertEqual(completions.value, 2)
    }

    func testWriteAcknowledgementWaitsForDelayedFirstVendorNotification() throws {
        let scheduler = WorkItemRecorder()
        let completions = LockedCounter()
        let timer = BLEVendorResponseIdleTimer(scheduler: scheduler.record, onIdle: completions.increment)
        // The device acknowledged ATT but has not sent its vendor response yet.
        timer.restart(responseExpected: true, hasResponse: false)
        XCTAssertEqual(scheduler.count, 0)
        XCTAssertEqual(completions.value, 0)
        // A response arriving after the old 120 ms empty-success window still completes normally.
        timer.restart(responseExpected: true, hasResponse: true)
        XCTAssertEqual(scheduler.count, 1)
        try scheduler.item(at: 0).perform()
        XCTAssertEqual(completions.value, 1)
    }

    func testResponseIdleTimerCompletesOnlyAfterLatestActivityDeadline() throws {
        let scheduler = WorkItemRecorder()
        let completions = LockedCounter()
        let timer = BLEVendorResponseIdleTimer(scheduler: scheduler.record, onIdle: completions.increment)

        timer.restart(responseExpected: true, hasResponse: true)
        timer.restart(responseExpected: true, hasResponse: true)
        timer.restart(responseExpected: true, hasResponse: true)

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
