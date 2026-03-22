import XCTest
@testable import OpenSnek

final class KeyboardBindingSupportTests: XCTestCase {
    func testCatalogIncludesModifiersNavigationAndFunctionKeys() {
        let labelsByHidKey = Dictionary(uniqueKeysWithValues: AppStateKeyboardSupport.keyOptions.map { ($0.hidKey, $0.label) })

        XCTAssertEqual(labelsByHidKey[224], "Left Control")
        XCTAssertEqual(labelsByHidKey[79], "Right Arrow")
        XCTAssertEqual(labelsByHidKey[104], "F13")
        XCTAssertEqual(labelsByHidKey[88], "Keypad Enter")
    }

    func testParsesNamedNonTextBindings() {
        XCTAssertEqual(AppStateKeyboardSupport.hidKey(fromKeyboardText: "ctrl"), 224)
        XCTAssertEqual(AppStateKeyboardSupport.hidKey(fromKeyboardText: "right control"), 228)
        XCTAssertEqual(AppStateKeyboardSupport.hidKey(fromKeyboardText: "left arrow"), 80)
        XCTAssertEqual(AppStateKeyboardSupport.hidKey(fromKeyboardText: "page down"), 78)
        XCTAssertEqual(AppStateKeyboardSupport.hidKey(fromKeyboardText: "command"), 227)
        XCTAssertEqual(AppStateKeyboardSupport.hidKey(fromKeyboardText: "f13"), 104)
        XCTAssertEqual(AppStateKeyboardSupport.hidKey(fromKeyboardText: "numpad enter"), 88)
    }

    func testDisplayLabelFallsBackForUnknownHidKey() {
        XCTAssertEqual(AppStateKeyboardSupport.keyboardDisplayLabel(forHidKey: 200), "HID 0xC8")
    }
}
