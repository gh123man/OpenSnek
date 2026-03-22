import AppKit
import SwiftUI

struct KeyboardBindingEditor: View {
    let hidKey: Int
    let isEditable: Bool
    let onSelect: (Int) -> Void

    @State private var isShowingRecorder = false

    private var keyLabel: String {
        AppStateKeyboardSupport.keyboardDisplayLabel(forHidKey: hidKey)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 8) {
                Text("Key")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))

                Text(keyLabel)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )

                Button("Record") {
                    isShowingRecorder = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!isEditable)

                Menu("Browse") {
                    ForEach(AppStateKeyboardSupport.groupedKeyOptions, id: \.group.id) { entry in
                        Section(entry.group.label) {
                            ForEach(entry.options) { option in
                                Button(option.label) {
                                    onSelect(option.hidKey)
                                }
                            }
                        }
                    }
                }
                .controlSize(.small)
                .disabled(!isEditable)
            }

            Text("Use Record to press a key directly, or Browse for modifiers, arrows, function keys, navigation, and keypad bindings.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .frame(maxWidth: 360, alignment: .trailing)
        }
        .popover(isPresented: $isShowingRecorder) {
            KeyboardBindingRecorderPopover(currentLabel: keyLabel) { hidKey in
                onSelect(hidKey)
                isShowingRecorder = false
            }
        }
    }
}

private struct KeyboardBindingRecorderPopover: View {
    let currentLabel: String
    let onCapture: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Press A Key")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Current binding: \(currentLabel)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                VStack(spacing: 6) {
                    Text("Press any supported key")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.86))

                    Text("Modifiers can be captured on their own.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }

                KeyboardBindingCaptureField { hidKey in
                    onCapture(hidKey)
                    dismiss()
                }
            }
            .frame(width: 300, height: 108)

            Text("Media and macro families are still hidden until the underlying protocol taxonomy is validated.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 300, alignment: .leading)

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 332)
        .background(Color(red: 0.09, green: 0.11, blue: 0.13))
    }
}

private struct KeyboardBindingCaptureField: NSViewRepresentable {
    let onCapture: (Int) -> Void

    func makeNSView(context: Context) -> KeyboardBindingCaptureView {
        let view = KeyboardBindingCaptureView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: KeyboardBindingCaptureView, context: Context) {
        nsView.onCapture = onCapture
        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

private final class KeyboardBindingCaptureView: NSView {
    var onCapture: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard let hidKey = KeyboardBindingCaptureSupport.hidKey(from: event) else {
            NSSound.beep()
            return
        }
        onCapture?(hidKey)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let hidKey = KeyboardBindingCaptureSupport.hidKey(from: event) else { return }
        onCapture?(hidKey)
    }
}

private enum KeyboardBindingCaptureSupport {
    // macOS keyCode values are hardware key positions, so special/modifier keys need an explicit translation table.
    private static let hidKeyByModifierKeyCode: [UInt16: Int] = [
        54: 231, // Right Command
        55: 227, // Left Command
        56: 225, // Left Shift
        57: 57, // Caps Lock
        58: 226, // Left Option
        59: 224, // Left Control
        60: 229, // Right Shift
        61: 230, // Right Option
        62: 228, // Right Control
    ]

    private static let hidKeyByKeypadKeyCode: [UInt16: Int] = [
        65: 99, // Keypad .
        67: 85, // Keypad *
        69: 87, // Keypad +
        75: 84, // Keypad /
        76: 88, // Keypad Enter
        78: 86, // Keypad -
        81: 103, // Keypad =
        82: 98, // Keypad 0
        83: 89, // Keypad 1
        84: 90, // Keypad 2
        85: 91, // Keypad 3
        86: 92, // Keypad 4
        87: 93, // Keypad 5
        88: 94, // Keypad 6
        89: 95, // Keypad 7
        91: 96, // Keypad 8
        92: 97, // Keypad 9
    ]

    private static let hidKeyBySpecialKeyCode: [UInt16: Int] = [
        36: 40, // Return
        48: 43, // Tab
        49: 44, // Space
        51: 42, // Delete / Backspace
        53: 41, // Escape
        64: 108, // F17
        79: 109, // F18
        80: 110, // F19
        90: 111, // F20
        96: 62, // F5
        97: 63, // F6
        98: 64, // F7
        99: 60, // F3
        100: 65, // F8
        101: 66, // F9
        103: 68, // F11
        105: 104, // F13
        106: 107, // F16
        107: 105, // F14
        109: 67, // F10
        111: 69, // F12
        113: 106, // F15
        114: 73, // Insert
        115: 74, // Home
        116: 75, // Page Up
        117: 76, // Forward Delete
        118: 61, // F4
        119: 77, // End
        120: 59, // F2
        121: 78, // Page Down
        122: 58, // F1
        123: 80, // Left Arrow
        124: 79, // Right Arrow
        125: 81, // Down Arrow
        126: 82, // Up Arrow
    ]

    static func hidKey(from event: NSEvent) -> Int? {
        if event.type == .flagsChanged {
            return hidKeyByModifierKeyCode[event.keyCode]
        }
        if let keypadHidKey = hidKeyByKeypadKeyCode[event.keyCode] {
            return keypadHidKey
        }
        if let specialHidKey = hidKeyBySpecialKeyCode[event.keyCode] {
            return specialHidKey
        }
        guard let characters = event.charactersIgnoringModifiers else { return nil }
        return AppStateKeyboardSupport.hidKey(fromKeyboardText: characters)
    }
}
