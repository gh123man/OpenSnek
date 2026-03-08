import XCTest
@testable import OpenSnekMac

final class DevicePatchMergeTests: XCTestCase {
    func testMergedUsesNewestFieldValues() {
        let older = DevicePatch(
            pollRate: 500,
            dpiStages: [800, 1600],
            activeStage: 0,
            ledBrightness: 120,
            ledRGB: RGBPatch(r: 10, g: 20, b: 30),
            buttonBinding: ButtonBindingPatch(slot: 2, kind: .rightClick, hidKey: nil)
        )
        let newer = DevicePatch(
            pollRate: 1000,
            dpiStages: [1200, 6400],
            activeStage: 1,
            ledBrightness: 200,
            ledRGB: RGBPatch(r: 1, g: 2, b: 3),
            buttonBinding: ButtonBindingPatch(slot: 3, kind: .keyboardSimple, hidKey: 40)
        )

        let merged = older.merged(with: newer)
        XCTAssertEqual(merged.pollRate, 1000)
        XCTAssertEqual(merged.dpiStages ?? [], [1200, 6400])
        XCTAssertEqual(merged.activeStage, 1)
        XCTAssertEqual(merged.ledBrightness, 200)
        XCTAssertEqual(merged.ledRGB?.r, 1)
        XCTAssertEqual(merged.buttonBinding?.slot, 3)
        XCTAssertEqual(merged.buttonBinding?.kind, .keyboardSimple)
    }

    func testMergedKeepsExistingFieldsWhenNewestPatchPartial() {
        let older = DevicePatch(
            pollRate: 1000,
            dpiStages: [800, 6400],
            activeStage: 1,
            ledBrightness: 150,
            ledRGB: RGBPatch(r: 100, g: 120, b: 140),
            buttonBinding: ButtonBindingPatch(slot: 4, kind: .mouseBack, hidKey: nil)
        )
        let newer = DevicePatch(activeStage: 0)

        let merged = older.merged(with: newer)
        XCTAssertEqual(merged.pollRate, 1000)
        XCTAssertEqual(merged.dpiStages ?? [], [800, 6400])
        XCTAssertEqual(merged.activeStage, 0)
        XCTAssertEqual(merged.ledBrightness, 150)
        XCTAssertEqual(merged.ledRGB?.g, 120)
        XCTAssertEqual(merged.buttonBinding?.kind, .mouseBack)
    }
}
