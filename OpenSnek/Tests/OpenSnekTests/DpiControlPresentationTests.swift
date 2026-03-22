import XCTest
@testable import OpenSnek

final class DpiControlPresentationTests: XCTestCase {
    func testStageLabelUsesOneBasedIndex() {
        XCTAssertEqual(DpiControlPresentation.stageLabel(for: 0), "Stage 1")
        XCTAssertEqual(DpiControlPresentation.stageLabel(for: 4), "Stage 5")
    }

    func testStageCountSummaryReflectsSingleAndMultiStageModes() {
        XCTAssertEqual(DpiControlPresentation.stageCountSummary(for: 1), "Single-stage DPI")
        XCTAssertEqual(DpiControlPresentation.stageCountSummary(for: 3), "Enabled stages: 3 / 5")
    }

    func testQuantizedDpiRoundsToNearestHundred() {
        XCTAssertEqual(DpiControlPresentation.quantizedDpi(from: 1049), 1000)
        XCTAssertEqual(DpiControlPresentation.quantizedDpi(from: 1050), 1100)
    }

    func testSliderValueClampsToUpperBound() {
        XCTAssertEqual(DpiControlPresentation.sliderValue(for: 1600, upperBound: 6000), 1600)
        XCTAssertEqual(DpiControlPresentation.sliderValue(for: 18_000, upperBound: 6000), 6000)
    }
}
