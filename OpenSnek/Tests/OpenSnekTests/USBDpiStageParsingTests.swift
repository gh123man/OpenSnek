import XCTest
import OpenSnekCore
@testable import OpenSnek

/// Exercises USB DPI stage parsing behavior.
final class USBDpiStageParsingTests: XCTestCase {
    func testUSBStageSnapshotParsingUsesCorrectResponseOffsets() async {
        let client = BridgeClient(startHIDMonitoring: false)

        var response = [UInt8](repeating: 0, count: 11 + (2 * 7))
        response[0] = 0x02
        response[8] = 0x01
        response[9] = 0x02
        response[10] = 0x02

        response[11] = 0x01
        response[12] = 0x03
        response[13] = 0x20
        response[14] = 0x03
        response[15] = 0x20

        response[18] = 0x02
        response[19] = 0x06
        response[20] = 0x40
        response[21] = 0x06
        response[22] = 0x40

        let snapshot = await client.parseUSBDpiStageSnapshotResponse(response)

        XCTAssertEqual(snapshot?.active, 1)
        XCTAssertEqual(snapshot?.values, [800, 1600])
        XCTAssertEqual(snapshot?.pairs, [DpiPair(x: 800, y: 800), DpiPair(x: 1600, y: 1600)])
        XCTAssertEqual(snapshot?.stageIDs, [0x01, 0x02])
    }

    func testUSBStageSnapshotParsingPreservesIndependentXYPairs() async {
        let client = BridgeClient(startHIDMonitoring: false)

        var response = [UInt8](repeating: 0, count: 11 + 7)
        response[0] = 0x02
        response[8] = 0x01
        response[9] = 0x05
        response[10] = 0x01

        response[11] = 0x05
        response[12] = 0x06
        response[13] = 0x40
        response[14] = 0x07
        response[15] = 0x08

        let snapshot = await client.parseUSBDpiStageSnapshotResponse(response)

        XCTAssertEqual(snapshot?.active, 0)
        XCTAssertEqual(snapshot?.values, [1600])
        XCTAssertEqual(snapshot?.pairs, [DpiPair(x: 1600, y: 1800)])
        XCTAssertEqual(snapshot?.stageIDs, [0x05])
    }

    func testUSBFastDpiActiveResolutionUsesLiveValueOnlyWhenUnique() {
        let uniqueStages = BridgeClient.USBDpiStageSnapshot(
            active: 0,
            values: [800, 1600, 3200],
            pairs: [800, 1600, 3200].map { DpiPair(x: $0, y: $0) },
            stageIDs: [0x01, 0x02, 0x03]
        )
        let duplicateStages = BridgeClient.USBDpiStageSnapshot(
            active: 2,
            values: [800, 1600, 1600],
            pairs: [800, 1600, 1600].map { DpiPair(x: $0, y: $0) },
            stageIDs: [0x01, 0x02, 0x03]
        )

        XCTAssertEqual(BridgeClient.resolvedUSBFastDpiActiveStage(stages: uniqueStages, liveDpi: 1600), 1)
        XCTAssertEqual(BridgeClient.resolvedUSBFastDpiActiveStage(stages: duplicateStages, liveDpi: 1600), 2)
        XCTAssertEqual(BridgeClient.resolvedUSBFastDpiActiveStage(stages: duplicateStages, liveDpi: nil), 2)
    }

    func testUSBActiveResolutionUsesLiveDpiPairWhenStageTokenIsStale() {
        let staleTokenStages = BridgeClient.USBDpiStageSnapshot(
            active: 0,
            values: [800, 1600, 3200],
            pairs: [800, 1600, 3200].map { DpiPair(x: $0, y: $0) },
            stageIDs: [0x01, 0x02, 0x03]
        )
        let independentPairs = BridgeClient.USBDpiStageSnapshot(
            active: 0,
            values: [1200, 1200, 2400],
            pairs: [
                DpiPair(x: 1200, y: 1200),
                DpiPair(x: 1200, y: 1600),
                DpiPair(x: 2400, y: 2400)
            ],
            stageIDs: [0x01, 0x02, 0x03]
        )
        let duplicatePairs = BridgeClient.USBDpiStageSnapshot(
            active: 0,
            values: [800, 3200, 3200],
            pairs: [800, 3200, 3200].map { DpiPair(x: $0, y: $0) },
            stageIDs: [0x01, 0x02, 0x03]
        )

        XCTAssertEqual(
            BridgeClient.resolvedUSBActiveStage(
                stages: staleTokenStages,
                liveDpi: DpiPair(x: 3200, y: 3200)
            ),
            2
        )
        XCTAssertEqual(
            BridgeClient.resolvedUSBActiveStage(
                stages: independentPairs,
                liveDpi: DpiPair(x: 1200, y: 1600)
            ),
            1
        )
        XCTAssertEqual(
            BridgeClient.resolvedUSBActiveStage(
                stages: duplicatePairs,
                liveDpi: DpiPair(x: 3200, y: 3200)
            ),
            0
        )
    }
}
