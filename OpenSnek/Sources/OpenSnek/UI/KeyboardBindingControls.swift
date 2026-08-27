import AppKit
import SwiftUI

/// Stores keyboard binding editor data.
struct KeyboardBindingEditor: View {
    let hidKey: Int
    let hidModifiers: Int
    let supportsModifierChords: Bool
    let isEditable: Bool
    let onSelect: (KeyboardBindingSelection) -> Void

    @State private var isShowingRecorder = false

    private var keyLabel: String { AppStateKeyboardSupport.keyboardDisplayLabel(forHidKey: hidKey, hidModifiers: hidModifiers) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) { HStack(spacing: 8) { KeyboardBindingCurrentKeyButton(label: keyLabel, isEditable: isEditable) { isShowingRecorder = true } } }.popover(isPresented: $isShowingRecorder) {
            KeyboardBindingRecorderPopover(currentHidKey: hidKey, currentHidModifiers: hidModifiers, supportsModifierChords: supportsModifierChords) { selection in
                onSelect(selection)
                isShowingRecorder = false
            }
        }
    }
}

/// Renders the keyboard binding current key button UI.
private struct KeyboardBindingCurrentKeyButton: View {
    let label: String
    let isEditable: Bool
    let action: () -> Void

    var body: some View { Button(action: action) { labelContent }.buttonStyle(.plain).controlSize(.small).disabled(!isEditable) }

    private var labelContent: some View {
        HStack(spacing: 6) {
            Text(label)
            Image(systemName: "keyboard").font(.system(size: 11, weight: .bold))
        }.font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.86)).padding(.horizontal, 10).padding(.vertical, 6).background(buttonBackground)
    }

    private var buttonBackground: some View { Capsule().fill(Color.white.opacity(0.06)).overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)) }
}

/// Stores keyboard binding selection data.
struct KeyboardBindingSelection: Equatable {
    let hidKey: Int
    let hidModifiers: Int
}

/// Renders the keyboard binding recorder popover UI.
private struct KeyboardBindingRecorderPopover: View {
    let currentHidKey: Int
    let currentHidModifiers: Int
    let supportsModifierChords: Bool
    let onCapture: (KeyboardBindingSelection) -> Void

    @Environment(\.dismiss) private var dismiss

    private var currentLabel: String { AppStateKeyboardSupport.keyboardDisplayLabel(forHidKey: currentHidKey, hidModifiers: currentHidModifiers) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            title

            Text("Current binding: \(currentLabel)").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.72))

            capturePanel

            KeyboardBindingSearchableKeyPicker(currentHidKey: currentHidKey, currentHidModifiers: currentHidModifiers, supportsModifierChords: supportsModifierChords) { selection in
                onCapture(selection)
                dismiss()
            }

            Text("Media and macro families are still hidden until the underlying protocol taxonomy is validated.").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.58)).frame(width: 328, alignment: .leading)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(14).frame(width: 360).background(Color(red: 0.09, green: 0.11, blue: 0.13))
    }

    private var title: some View { Text("Press A Key").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white) }

    private var capturePanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.10), lineWidth: 1))

            captureInstructions

            KeyboardBindingCaptureField(supportsModifierChords: supportsModifierChords) { selection in
                onCapture(selection)
                dismiss()
            }
        }.frame(width: 328, height: 108)
    }

    private var captureInstructions: some View {
        VStack(spacing: 6) {
            Text("Press one supported key").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.86))

            Text(supportsModifierChords ? "Shortcuts can include modifiers." : "Modifiers can be captured on their own.").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.58))
        }
    }

}

/// Renders the keyboard binding searchable key picker UI.
private struct KeyboardBindingSearchableKeyPicker: View {
    let currentHidKey: Int
    let currentHidModifiers: Int
    let supportsModifierChords: Bool
    let onCapture: (KeyboardBindingSelection) -> Void

    @State private var searchText = ""
    @State private var pendingModifier: KeyboardBindingOption?
    @State private var hoveredOptionHidKey: Int?

    private let pickerWidth: CGFloat = 328
    private let optionListHeight: CGFloat = 218

    private var isSelectingChordAction: Bool { pendingModifier != nil && supportsModifierChords }

    private var filteredOptions: [KeyboardBindingOption] { AppStateKeyboardSupport.filteredKeyOptions(matching: searchText, excludingModifiers: isSelectingChordAction) }

    private var groupedOptions: [(group: KeyboardBindingGroup, options: [KeyboardBindingOption])] {
        KeyboardBindingGroup.allCases.compactMap { group in
            let options = filteredOptions.filter { $0.group == group }
            guard !options.isEmpty else { return nil }
            return (group, options)
        }
    }

    private var searchPrompt: String { isSelectingChordAction ? "Search action key" : "Search keys" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            KeyboardBindingSearchField(searchText: $searchText, prompt: searchPrompt, width: pickerWidth)

            if let pendingModifier, supportsModifierChords { pendingModifierRow(pendingModifier) }

            optionList
        }
    }

    private func pendingModifierRow(_ option: KeyboardBindingOption) -> some View {
        KeyboardBindingPendingModifierRow(
            option: option, width: pickerWidth, onUseAlone: { onCapture(KeyboardBindingSelection(hidKey: option.hidKey, hidModifiers: 0)) },
            onClear: {
                pendingModifier = nil
                searchText = ""
            })
    }

    private var optionList: some View { ScrollView { optionListContent }.frame(width: pickerWidth, height: optionListHeight).background(optionListBackground) }

    private var optionListContent: some View { LazyVStack(alignment: .leading, spacing: 10) { if groupedOptions.isEmpty { emptySearchResult } else { ForEach(groupedOptions, id: \.group.id) { entry in optionSection(entry) } } }.padding(8).frame(maxWidth: .infinity, alignment: .leading) }

    private var optionListBackground: some View { RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.09), lineWidth: 1)) }

    private var emptySearchResult: some View { Text("No supported keys").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.52)).frame(maxWidth: .infinity, minHeight: optionListHeight - 16) }

    private func optionSection(_ entry: (group: KeyboardBindingGroup, options: [KeyboardBindingOption])) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.group.label).font(.system(size: 10, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.42)).textCase(.uppercase)

            ForEach(entry.options) { option in optionButton(option) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionButton(_ option: KeyboardBindingOption) -> some View {
        Button {
            select(option)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: optionSystemImageName(for: option)).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.48)).frame(width: 18).accessibilityHidden(true)

                Text(option.label).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.84)).lineLimit(1).truncationMode(.tail)

                Spacer(minLength: 8)

                optionTrailingIcon(option)
            }.padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 28, alignment: .leading).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(optionBackgroundOpacity(for: option)))).contentShape(Rectangle())
        }.buttonStyle(.plain).frame(maxWidth: .infinity).onHover { isHovering in updateHoveredOption(option, isHovering: isHovering) }.accessibilityIdentifier("keyboard-binding-key-option-\(option.hidKey)")
    }

    @ViewBuilder private func optionTrailingIcon(_ option: KeyboardBindingOption) -> some View {
        if optionIsSelected(option) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(.white.opacity(0.76)).accessibilityHidden(true)
        } else if supportsModifierChords && !isSelectingChordAction && AppStateKeyboardSupport.isModifierKey(option.hidKey) {
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .black)).foregroundStyle(.white.opacity(0.36)).accessibilityHidden(true)
        }
    }

    private func select(_ option: KeyboardBindingOption) {
        if isSelectingChordAction, let hidModifiers = pendingModifierBit {
            onCapture(KeyboardBindingSelection(hidKey: option.hidKey, hidModifiers: hidModifiers))
            return
        }

        if supportsModifierChords, AppStateKeyboardSupport.isModifierKey(option.hidKey) {
            pendingModifier = option
            searchText = ""
            return
        }

        onCapture(KeyboardBindingSelection(hidKey: option.hidKey, hidModifiers: 0))
    }

    private var pendingModifierBit: Int? { pendingModifier.flatMap { AppStateKeyboardSupport.hidModifierBit(forHidKey: $0.hidKey) } }

    private func optionIsSelected(_ option: KeyboardBindingOption) -> Bool {
        if isSelectingChordAction, let pendingModifierBit { return currentHidKey == option.hidKey && currentHidModifiers == pendingModifierBit }
        return currentHidKey == option.hidKey && currentHidModifiers == 0
    }

    private func optionBackgroundOpacity(for option: KeyboardBindingOption) -> Double {
        if optionIsSelected(option) { return hoveredOptionHidKey == option.hidKey ? 0.14 : 0.10 }
        return hoveredOptionHidKey == option.hidKey ? 0.07 : 0.0
    }

    private func updateHoveredOption(_ option: KeyboardBindingOption, isHovering: Bool) { if isHovering { hoveredOptionHidKey = option.hidKey } else if hoveredOptionHidKey == option.hidKey { hoveredOptionHidKey = nil } }

    private func optionSystemImageName(for option: KeyboardBindingOption) -> String {
        if AppStateKeyboardSupport.isModifierKey(option.hidKey) { return modifierSystemImageName(for: option.hidKey) }
        switch option.group {
        case .letters: return "textformat"
        case .numbers: return "number"
        case .punctuation: return "textformat.abc.dottedunderline"
        case .editing: return "keyboard"
        case .navigation: return "arrow.up.and.down.and.arrow.left.and.right"
        case .function: return "function"
        case .keypad: return "rectangle.grid.3x2"
        case .modifiers: return "keyboard"
        case .system: return "gearshape"
        }
    }

    private func modifierSystemImageName(for hidKey: Int) -> String { KeyboardBindingPickerIcons.modifierSystemImageName(for: hidKey) }
}

/// Renders the keyboard binding search field UI.
private struct KeyboardBindingSearchField: View {
    @Binding var searchText: String
    let prompt: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            searchIcon
            searchTextField
            if !searchText.isEmpty { clearButton }
        }.padding(.horizontal, 10).padding(.vertical, 8).frame(width: width).background(searchBackground)
    }

    private var searchIcon: some View { Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.52)).accessibilityHidden(true) }

    private var searchTextField: some View { TextField(prompt, text: $searchText).textFieldStyle(.plain).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.88)).accessibilityIdentifier("keyboard-binding-key-search") }

    private var clearButton: some View {
        Button {
            searchText = ""
        } label: {
            Image(systemName: "xmark.circle.fill").font(.system(size: 12, weight: .bold))
        }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.48)).help("Clear search")
    }

    private var searchBackground: some View { RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10), lineWidth: 1)) }
}

/// Renders the keyboard binding pending modifier row UI.
private struct KeyboardBindingPendingModifierRow: View {
    let option: KeyboardBindingOption
    let width: CGFloat
    let onUseAlone: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            modifierIcon
            modifierLabel
            Spacer(minLength: 8)
            useAloneButton
            clearButton
        }.padding(.horizontal, 10).padding(.vertical, 7).frame(width: width).background(rowBackground)
    }

    private var modifierIcon: some View { Image(systemName: KeyboardBindingPickerIcons.modifierSystemImageName(for: option.hidKey)).font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.70)).frame(width: 16).accessibilityHidden(true) }

    private var modifierLabel: some View { Text("\(option.label) +").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.86)).lineLimit(1) }

    private var useAloneButton: some View { Button("Use Alone", action: onUseAlone).buttonStyle(.plain).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.72)) }

    private var clearButton: some View { Button(action: onClear) { Image(systemName: "xmark").font(.system(size: 10, weight: .black)).frame(width: 20, height: 20) }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.52)).help("Clear modifier") }

    private var rowBackground: some View { RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1)) }
}

/// Defines keyboard binding picker icons values.
private enum KeyboardBindingPickerIcons {
    static func modifierSystemImageName(for hidKey: Int) -> String {
        switch hidKey {
        case 224, 228: return "control"
        case 225, 229: return "shift"
        case 226, 230: return "option"
        case 227, 231: return "command"
        default: return "keyboard"
        }
    }
}

/// Renders the keyboard binding capture field UI.
private struct KeyboardBindingCaptureField: NSViewRepresentable {
    let supportsModifierChords: Bool
    let onCapture: (KeyboardBindingSelection) -> Void

    func makeNSView(context: Context) -> KeyboardBindingCaptureView {
        let view = KeyboardBindingCaptureView()
        view.supportsModifierChords = supportsModifierChords
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: KeyboardBindingCaptureView, context: Context) {
        nsView.supportsModifierChords = supportsModifierChords
        nsView.onCapture = onCapture
    }
}

/// Coordinates keyboard binding capture view behavior.
private final class KeyboardBindingCaptureView: NSView {
    var supportsModifierChords = false
    var onCapture: ((KeyboardBindingSelection) -> Void)?
    private var pendingModifierCapture: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        pendingModifierCapture?.cancel()
        pendingModifierCapture = nil

        let hidModifiers = KeyboardBindingCaptureSupport.hidModifiers(from: event)
        guard supportsModifierChords || hidModifiers == 0 else {
            NSSound.beep()
            return
        }

        guard let hidKey = KeyboardBindingCaptureSupport.hidKey(from: event) else {
            NSSound.beep()
            return
        }
        onCapture?(KeyboardBindingSelection(hidKey: hidKey, hidModifiers: hidModifiers))
    }

    override func flagsChanged(with event: NSEvent) {
        guard let hidKey = KeyboardBindingCaptureSupport.hidKey(from: event) else { return }
        pendingModifierCapture?.cancel()
        guard KeyboardBindingCaptureSupport.isModifierPressed(in: event) else {
            pendingModifierCapture = nil
            return
        }

        var workItem: DispatchWorkItem?
        workItem = DispatchWorkItem { [weak self, weak workItem] in
            guard workItem?.isCancelled == false else { return }
            self?.onCapture?(KeyboardBindingSelection(hidKey: hidKey, hidModifiers: 0))
            self?.pendingModifierCapture = nil
        }
        guard let workItem else { return }
        pendingModifierCapture = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }
}

/// Groups keyboard binding capture support helpers.
private enum KeyboardBindingCaptureSupport {
    // macOS keyCode values are hardware key positions, so special/modifier keys need an explicit translation table.
    private static let hidKeyByModifierKeyCode: [UInt16: Int] = [
        54: 231,  // Right Command
        55: 227,  // Left Command
        56: 225,  // Left Shift
        57: 57,  // Caps Lock
        58: 226,  // Left Option
        59: 224,  // Left Control
        60: 229,  // Right Shift
        61: 230,  // Right Option
        62: 228  // Right Control
    ]

    private static let hidKeyByKeypadKeyCode: [UInt16: Int] = [
        65: 99,  // Keypad .
        67: 85,  // Keypad *
        69: 87,  // Keypad +
        75: 84,  // Keypad /
        76: 88,  // Keypad Enter
        78: 86,  // Keypad -
        81: 103,  // Keypad =
        82: 98,  // Keypad 0
        83: 89,  // Keypad 1
        84: 90,  // Keypad 2
        85: 91,  // Keypad 3
        86: 92,  // Keypad 4
        87: 93,  // Keypad 5
        88: 94,  // Keypad 6
        89: 95,  // Keypad 7
        91: 96,  // Keypad 8
        92: 97  // Keypad 9
    ]

    private static let hidKeyBySpecialKeyCode: [UInt16: Int] = [
        36: 40,  // Return
        48: 43,  // Tab
        49: 44,  // Space
        51: 42,  // Delete / Backspace
        53: 41,  // Escape
        64: 108,  // F17
        79: 109,  // F18
        80: 110,  // F19
        90: 111,  // F20
        96: 62,  // F5
        97: 63,  // F6
        98: 64,  // F7
        99: 60,  // F3
        100: 65,  // F8
        101: 66,  // F9
        103: 68,  // F11
        105: 104,  // F13
        106: 107,  // F16
        107: 105,  // F14
        109: 67,  // F10
        111: 69,  // F12
        113: 106,  // F15
        114: 73,  // Insert
        115: 74,  // Home
        116: 75,  // Page Up
        117: 76,  // Forward Delete
        118: 61,  // F4
        119: 77,  // End
        120: 59,  // F2
        121: 78,  // Page Down
        122: 58,  // F1
        123: 80,  // Left Arrow
        124: 79,  // Right Arrow
        125: 81,  // Down Arrow
        126: 82  // Up Arrow
    ]

    static func hidKey(from event: NSEvent) -> Int? {
        if event.type == .flagsChanged { return hidKeyByModifierKeyCode[event.keyCode] }
        if let keypadHidKey = hidKeyByKeypadKeyCode[event.keyCode] { return keypadHidKey }
        if let specialHidKey = hidKeyBySpecialKeyCode[event.keyCode] { return specialHidKey }
        guard let characters = event.charactersIgnoringModifiers else { return nil }
        return AppStateKeyboardSupport.hidKey(fromKeyboardText: characters)
    }

    static func isModifierPressed(in event: NSEvent) -> Bool {
        switch event.keyCode {
        case 54, 55: return event.modifierFlags.contains(.command)
        case 56, 60: return event.modifierFlags.contains(.shift)
        case 57: return event.modifierFlags.contains(.capsLock)
        case 58, 61: return event.modifierFlags.contains(.option)
        case 59, 62: return event.modifierFlags.contains(.control)
        default: return false
        }
    }

    static func hidModifiers(from event: NSEvent) -> Int {
        var modifiers = 0
        if event.modifierFlags.contains(.control) { modifiers |= 0x01 }
        if event.modifierFlags.contains(.shift) { modifiers |= 0x02 }
        if event.modifierFlags.contains(.option) { modifiers |= 0x04 }
        if event.modifierFlags.contains(.command) { modifiers |= 0x08 }
        return modifiers
    }
}
