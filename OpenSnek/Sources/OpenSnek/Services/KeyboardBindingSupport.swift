import Foundation

/// Defines keyboard binding group values.
enum KeyboardBindingGroup: String, CaseIterable, Identifiable {
    case letters
    case numbers
    case punctuation
    case editing
    case navigation
    case function
    case keypad
    case modifiers
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .letters: return "Letters"
        case .numbers: return "Numbers"
        case .punctuation: return "Punctuation"
        case .editing: return "Editing"
        case .navigation: return "Navigation"
        case .function: return "Function Keys"
        case .keypad: return "Keypad"
        case .modifiers: return "Modifiers"
        case .system: return "System"
        }
    }
}

/// Stores keyboard binding option data.
struct KeyboardBindingOption: Identifiable, Hashable {
    let hidKey: Int
    let label: String
    let aliases: [String]
    let group: KeyboardBindingGroup

    var id: Int { hidKey }
}

/// Groups app state keyboard support helpers.
enum AppStateKeyboardSupport {
    static let keyOptions: [KeyboardBindingOption] = {
        var options: [KeyboardBindingOption] = []

        options += (0..<26).map { index in
            let hidKey = 4 + index
            let letter = String(UnicodeScalar(65 + index)!)
            return KeyboardBindingOption(
                hidKey: hidKey,
                label: letter,
                aliases: [letter.lowercased()],
                group: .letters
            )
        }

        let numberAliases = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        options += numberAliases.enumerated().map { index, value in
            KeyboardBindingOption(
                hidKey: index == 9 ? 39 : 30 + index,
                label: value,
                aliases: [value],
                group: .numbers
            )
        }

        options += [
            option(45, "-", aliases: ["minus", "dash"], group: .punctuation),
            option(46, "=", aliases: ["equals", "equal"], group: .punctuation),
            option(47, "[", aliases: ["leftbracket", "openbracket"], group: .punctuation),
            option(48, "]", aliases: ["rightbracket", "closebracket"], group: .punctuation),
            option(49, "\\", aliases: ["backslash"], group: .punctuation),
            option(50, "Non-US #", aliases: ["nonus#", "hashnonus", "poundsign"], group: .punctuation),
            option(51, ";", aliases: ["semicolon"], group: .punctuation),
            option(52, "'", aliases: ["apostrophe", "quote"], group: .punctuation),
            option(53, "`", aliases: ["grave", "backtick", "tilde"], group: .punctuation),
            option(54, ",", aliases: ["comma"], group: .punctuation),
            option(55, ".", aliases: ["period", "dot"], group: .punctuation),
            option(56, "/", aliases: ["slash", "forwardslash"], group: .punctuation),
            option(100, "Non-US \\", aliases: ["nonusbackslash"], group: .punctuation)
        ]

        options += [
            option(40, "Return", aliases: ["enter"], group: .editing),
            option(41, "Escape", aliases: ["esc"], group: .editing),
            option(42, "Delete", aliases: ["backspace"], group: .editing),
            option(43, "Tab", aliases: [], group: .editing),
            option(44, "Space", aliases: ["spacebar"], group: .editing),
            option(57, "Caps Lock", aliases: ["caps"], group: .editing)
        ]

        options += [
            option(70, "Print Screen", aliases: ["prtscr", "print"], group: .navigation),
            option(71, "Scroll Lock", aliases: ["scroll"], group: .navigation),
            option(72, "Pause", aliases: [], group: .navigation),
            option(73, "Insert", aliases: ["help"], group: .navigation),
            option(74, "Home", aliases: [], group: .navigation),
            option(75, "Page Up", aliases: ["pgup"], group: .navigation),
            option(76, "Forward Delete", aliases: ["forwarddelete", "del"], group: .navigation),
            option(77, "End", aliases: [], group: .navigation),
            option(78, "Page Down", aliases: ["pgdown"], group: .navigation),
            option(79, "Right Arrow", aliases: ["rightarrow", "right"], group: .navigation),
            option(80, "Left Arrow", aliases: ["leftarrow", "left"], group: .navigation),
            option(81, "Down Arrow", aliases: ["downarrow", "down"], group: .navigation),
            option(82, "Up Arrow", aliases: ["uparrow", "up"], group: .navigation)
        ]

        options += (1...12).map { number in
            option(57 + number, "F\(number)", aliases: [], group: .function)
        }
        options += (13...24).map { number in
            option(91 + number, "F\(number)", aliases: [], group: .function)
        }

        options += [
            option(83, "Num Lock", aliases: ["numlock"], group: .keypad),
            option(84, "Keypad /", aliases: ["keypadslash", "numpadslash"], group: .keypad),
            option(85, "Keypad *", aliases: ["keypadasterisk", "numpadasterisk"], group: .keypad),
            option(86, "Keypad -", aliases: ["keypadminus", "numpadminus"], group: .keypad),
            option(87, "Keypad +", aliases: ["keypadplus", "numpadplus"], group: .keypad),
            option(88, "Keypad Enter", aliases: ["keypadreturn", "numpadenter"], group: .keypad),
            option(89, "Keypad 1", aliases: ["numpad1"], group: .keypad),
            option(90, "Keypad 2", aliases: ["numpad2"], group: .keypad),
            option(91, "Keypad 3", aliases: ["numpad3"], group: .keypad),
            option(92, "Keypad 4", aliases: ["numpad4"], group: .keypad),
            option(93, "Keypad 5", aliases: ["numpad5"], group: .keypad),
            option(94, "Keypad 6", aliases: ["numpad6"], group: .keypad),
            option(95, "Keypad 7", aliases: ["numpad7"], group: .keypad),
            option(96, "Keypad 8", aliases: ["numpad8"], group: .keypad),
            option(97, "Keypad 9", aliases: ["numpad9"], group: .keypad),
            option(98, "Keypad 0", aliases: ["numpad0"], group: .keypad),
            option(99, "Keypad .", aliases: ["keypadperiod", "numpadperiod"], group: .keypad),
            option(103, "Keypad =", aliases: ["keypadequals", "numpadequals"], group: .keypad)
        ]

        options += [
            option(224, "Left Control", aliases: ["control", "ctrl", "leftctrl", "leftcontrol"], group: .modifiers),
            option(225, "Left Shift", aliases: ["shift", "leftshift"], group: .modifiers),
            option(226, "Left Option", aliases: ["alt", "option", "leftalt", "leftoption"], group: .modifiers),
            option(227, "Left Command", aliases: ["cmd", "command", "leftcmd", "leftcommand", "leftgui"], group: .modifiers),
            option(228, "Right Control", aliases: ["rightctrl", "rightcontrol"], group: .modifiers),
            option(229, "Right Shift", aliases: ["rightshift"], group: .modifiers),
            option(230, "Right Option", aliases: ["rightalt", "rightoption"], group: .modifiers),
            option(231, "Right Command", aliases: ["rightcmd", "rightcommand", "rightgui"], group: .modifiers)
        ]

        options += [
            option(101, "Menu", aliases: ["application", "contextmenu"], group: .system)
        ]

        return options
    }()

    private static let optionsByHidKey = Dictionary(uniqueKeysWithValues: keyOptions.map { ($0.hidKey, $0) })
    private static let hidKeyByAlias = keyOptions.reduce(into: [String: Int]()) { partialResult, option in
        for value in [option.label] + option.aliases {
            partialResult[normalizedToken(value)] = option.hidKey
        }
    }

    static var groupedKeyOptions: [(group: KeyboardBindingGroup, options: [KeyboardBindingOption])] {
        KeyboardBindingGroup.allCases.compactMap { group in
            let options = keyOptions.filter { $0.group == group }
            guard !options.isEmpty else { return nil }
            return (group, options)
        }
    }

    static func filteredKeyOptions(matching query: String, excludingModifiers: Bool = false) -> [KeyboardBindingOption] {
        let baseOptions = keyOptions.enumerated().filter { _, option in
            !excludingModifiers || !isModifierKey(option.hidKey)
        }
        let normalizedQuery = normalizedToken(query)
        guard !normalizedQuery.isEmpty else { return baseOptions.map(\.element) }

        return baseOptions.compactMap { entry -> SearchMatch? in
            let index = entry.offset
            let option = entry.element
            guard let score = fuzzyScore(option: option, normalizedQuery: normalizedQuery) else { return nil }
            return SearchMatch(option: option, score: score, index: index)
        }
        .sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            return lhs.index < rhs.index
        }
        .map(\.option)
    }

    static func hidKey(fromKeyboardText text: String) -> Int? {
        if text == " " {
            return 44
        }
        let normalized = normalizedToken(text)
        guard !normalized.isEmpty else { return nil }
        return hidKeyByAlias[normalized]
    }

    static func isModifierKey(_ hidKey: Int) -> Bool {
        hidModifierBit(forHidKey: hidKey) != nil
    }

    static func hidModifierBit(forHidKey hidKey: Int) -> Int? {
        switch hidKey {
        case 224: return 0x01
        case 225: return 0x02
        case 226: return 0x04
        case 227: return 0x08
        case 228: return 0x10
        case 229: return 0x20
        case 230: return 0x40
        case 231: return 0x80
        default: return nil
        }
    }

    static func keyboardDisplayLabel(forHidKey hidKey: Int) -> String {
        optionsByHidKey[hidKey]?.label ?? String(format: "HID 0x%02X", hidKey)
    }

    static func keyboardDisplayLabel(forHidKey hidKey: Int, hidModifiers: Int) -> String {
        let keyLabel = keyboardDisplayLabel(forHidKey: hidKey)
        let modifierLabels = keyboardModifierLabels(forHidModifiers: hidModifiers)
        guard !modifierLabels.isEmpty else { return keyLabel }
        return (modifierLabels + [keyLabel]).joined(separator: " + ")
    }

    static func keyboardModifierLabels(forHidModifiers hidModifiers: Int) -> [String] {
        let bits = max(0, min(255, hidModifiers))
        let ordered: [(Int, String)] = [
            (0x01, "Control"),
            (0x02, "Shift"),
            (0x04, "Option"),
            (0x08, "Command"),
            (0x10, "Right Control"),
            (0x20, "Right Shift"),
            (0x40, "Right Option"),
            (0x80, "Right Command")
        ]
        return ordered.compactMap { bit, label in
            bits & bit == bit ? label : nil
        }
    }

    private static func option(_ hidKey: Int, _ label: String, aliases: [String], group: KeyboardBindingGroup) -> KeyboardBindingOption {
        KeyboardBindingOption(hidKey: hidKey, label: label, aliases: aliases, group: group)
    }

    /// Stores search match data.
    private struct SearchMatch {
        let option: KeyboardBindingOption
        let score: Int
        let index: Int
    }

    private static func fuzzyScore(option: KeyboardBindingOption, normalizedQuery: String) -> Int? {
        let searchableValues = [option.label, option.group.label, String(format: "hid%02x", option.hidKey)] + option.aliases
        let scores = searchableValues.compactMap { value -> Int? in
            let target = normalizedToken(value)
            guard !target.isEmpty else { return nil }
            if target == normalizedQuery {
                return 10_000 - target.count
            }
            if target.hasPrefix(normalizedQuery) {
                return 9_000 - target.count
            }
            if target.contains(normalizedQuery) {
                return 8_000 - target.count
            }
            guard let penalty = fuzzySubsequencePenalty(query: normalizedQuery, target: target) else {
                return nil
            }
            return 7_000 - penalty - target.count
        }
        return scores.max()
    }

    private static func fuzzySubsequencePenalty(query: String, target: String) -> Int? {
        var targetIndex = target.startIndex
        var previousMatch: String.Index?
        var penalty = 0

        for character in query {
            var matchedIndex: String.Index?
            while targetIndex < target.endIndex {
                if target[targetIndex] == character {
                    matchedIndex = targetIndex
                    break
                }
                target.formIndex(after: &targetIndex)
            }
            guard let matchedIndex else { return nil }

            if let previousMatch {
                penalty += target.distance(from: target.index(after: previousMatch), to: matchedIndex)
            } else {
                penalty += target.distance(from: target.startIndex, to: matchedIndex)
            }
            targetIndex = target.index(after: matchedIndex)
            previousMatch = matchedIndex
        }

        return penalty
    }

    private static func normalizedToken(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
    }
}
