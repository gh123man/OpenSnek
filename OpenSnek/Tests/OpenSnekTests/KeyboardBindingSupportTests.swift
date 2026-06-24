import XCTest
@testable import OpenSnek

/// Exercises keyboard binding support behavior.
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

    func testDisplayLabelFallsBackForUnknownHidKey() { XCTAssertEqual(AppStateKeyboardSupport.keyboardDisplayLabel(forHidKey: 200), "HID 0xC8") }

    func testDisplayLabelIncludesKeyboardModifiers() { XCTAssertEqual(AppStateKeyboardSupport.keyboardDisplayLabel(forHidKey: 47, hidModifiers: 0x08), "Command + [") }

    func testFuzzySearchMatchesAliasesAndSubsequences() {
        XCTAssertEqual(AppStateKeyboardSupport.filteredKeyOptions(matching: "pgdn").first?.label, "Page Down")
        XCTAssertEqual(AppStateKeyboardSupport.filteredKeyOptions(matching: "cmd").first?.label, "Left Command")
    }

    func testFuzzySearchCanExcludeModifiersForChordActionKey() {
        let tabResults = AppStateKeyboardSupport.filteredKeyOptions(matching: "tab", excludingModifiers: true)
        XCTAssertEqual(tabResults.first?.label, "Tab")

        let commandResults = AppStateKeyboardSupport.filteredKeyOptions(matching: "cmd", excludingModifiers: true)
        XCTAssertTrue(commandResults.allSatisfy { $0.group != .modifiers })
    }

    func testModifierKeysResolveToHIDModifierBits() {
        XCTAssertEqual(AppStateKeyboardSupport.hidModifierBit(forHidKey: 227), 0x08)
        XCTAssertEqual(AppStateKeyboardSupport.hidModifierBit(forHidKey: 231), 0x80)
        XCTAssertNil(AppStateKeyboardSupport.hidModifierBit(forHidKey: 43))
    }
}
