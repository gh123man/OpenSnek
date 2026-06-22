import AppKit
import OpenSnekAppSupport
import SwiftUI
import OpenSnekCore

struct LightingColorOrbRow: View {
    let title: String
    let identifierPrefix: String
    @Binding var color: RGBColor
    let swatches: [LightingSwatch]

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 12)

            LightingColorOrbPicker(
                title: title,
                identifierPrefix: identifierPrefix,
                color: $color,
                swatches: swatches
            )
        }
        .frame(minHeight: 44)
    }
}

struct LightingColorOrbPicker: View {
    let title: String
    let identifierPrefix: String
    @Binding var color: RGBColor
    let swatches: [LightingSwatch]

    @State private var showsEditor = false
    @State private var colorAtEditorOpen: RGBColor?
    @State private var recentColors: [RGBColor] = []

    var body: some View {
        Button {
            colorAtEditorOpen = color
            showsEditor = true
        } label: {
            Circle()
                .fill(Color(rgb: color))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.82), lineWidth: 1.5)
                )
                .shadow(color: Color(rgb: color).opacity(0.38), radius: 6, y: 0)
                .padding(8)
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("\(identifierPrefix)-orb-button")
        .onChange(of: showsEditor) { _, isPresented in
            guard !isPresented else { return }
            if colorAtEditorOpen != color {
                remember(color)
            }
            colorAtEditorOpen = nil
        }
        .popover(isPresented: $showsEditor, arrowEdge: .trailing) {
            LightingColorPopoverEditor(
                title: title,
                identifierPrefix: identifierPrefix,
                color: $color,
                swatches: swatches,
                recentColors: $recentColors
            )
            .frame(width: 300)
            .padding(12)
        }
    }

    private func remember(_ next: RGBColor) {
        recentColors.removeAll { $0 == next }
        recentColors.insert(next, at: 0)
        if recentColors.count > 8 {
            recentColors = Array(recentColors.prefix(8))
        }
    }
}

struct LightingColorPopoverEditor: View {
    let title: String
    let identifierPrefix: String
    @Binding var color: RGBColor
    let swatches: [LightingSwatch]
    @Binding var recentColors: [RGBColor]

    private var colorPickerBinding: Binding<Color> {
        Binding(
            get: { Color(rgb: color) },
            set: {
                color = RGBColor.fromColor($0)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))

            colorRow(title: "Presets", colors: swatches.map(\.rgb), identifier: "preset")

            if !recentColors.isEmpty {
                colorRow(title: "Recent", colors: recentColors, identifier: "recent")
            }

            ColorPicker("Picker", selection: colorPickerBinding, supportsOpacity: false)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.76))
                .accessibilityIdentifier("\(identifierPrefix)-system-color-picker")

            RGBSliderRow(
                label: "R",
                accessibilityIdentifier: "\(identifierPrefix)-red-slider",
                tint: Color.red,
                value: Binding(
                    get: { color.r },
                    set: { color.r = max(0, min(255, $0)) }
                )
            )

            RGBSliderRow(
                label: "G",
                accessibilityIdentifier: "\(identifierPrefix)-green-slider",
                tint: Color.green,
                value: Binding(
                    get: { color.g },
                    set: { color.g = max(0, min(255, $0)) }
                )
            )

            RGBSliderRow(
                label: "B",
                accessibilityIdentifier: "\(identifierPrefix)-blue-slider",
                tint: Color.blue,
                value: Binding(
                    get: { color.b },
                    set: { color.b = max(0, min(255, $0)) }
                )
            )

            Text(String(format: "#%02X%02X%02X", color.r, color.g, color.b))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    @ViewBuilder
    private func colorRow(title: String, colors: [RGBColor], identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))

            HStack(spacing: 8) {
                ForEach(Array(colors.enumerated()), id: \.offset) { index, rgb in
                    ColorSwatchButton(
                        color: Color(rgb: rgb),
                        isSelected: rgb == color,
                        action: { color = rgb }
                    )
                    .accessibilityIdentifier("\(identifierPrefix)-\(identifier)-swatch-\(index)")
                }
            }
        }
    }

}

struct SoftwareLightingPaletteEditor: View {
    let preset: SoftwareLightingPresetID
    @Binding var palette: [RGBColor]
    let swatches: [LightingSwatch]
    let onAdd: () -> Void
    let onRemove: (Int) -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            paletteHeader
            paletteList
        }
    }

    private var paletteHeader: some View {
        HStack(spacing: 12) {
            Text("Palette")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            Spacer(minLength: 12)

            Button(action: onReset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("software-lighting-palette-reset-button")
        }
    }

    private var paletteList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(palette.indices), id: \.self) { index in
                    paletteColorItem(index)
                }

                if maximumPaletteColorCount > 1 {
                    addColorButton
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
        .accessibilityIdentifier("software-lighting-palette-list")
    }

    private func paletteColorItem(_ index: Int) -> some View {
        VStack(spacing: 5) {
            LightingColorOrbPicker(
                title: "\(preset.label) palette color \(index + 1)",
                identifierPrefix: "software-lighting-palette-\(index)",
                color: paletteBinding(index),
                swatches: swatches
            )

            if maximumPaletteColorCount > 1 {
                PaletteRemoveColorButton(
                    index: index,
                    canRemove: palette.count > 1,
                    remove: { onRemove(index) }
                )
            } else {
                PaletteRemoveColorPlaceholder()
            }
        }
        .frame(width: 44)
    }

    private var addColorButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            palette.count < maximumPaletteColorCount
                ? Color.white.opacity(0.86)
                : Color.white.opacity(0.34)
        )
        .disabled(palette.count >= maximumPaletteColorCount)
        .help("Add color")
        .accessibilityLabel("Add palette color")
        .accessibilityIdentifier("software-lighting-palette-add-button")
        .frame(width: 44)
        .padding(.top, 0)
        .padding(.bottom, 18)
        .opacity(palette.count < maximumPaletteColorCount ? 1 : 0.55)
    }

    private func paletteBinding(_ index: Int) -> Binding<RGBColor> {
        Binding(
            get: {
                guard palette.indices.contains(index) else {
                    return RGBColor(r: 255, g: 255, b: 255)
                }
                return palette[index]
            },
            set: { color in
                guard palette.indices.contains(index) else { return }
                var next = palette
                next[index] = color
                palette = next
            }
        )
    }

    private var maximumPaletteColorCount: Int {
        preset.maximumPaletteColorCount
    }
}

private struct PaletteRemoveColorButton: View {
    let index: Int
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            PaletteRemoveColorIcon()
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .disabled(!canRemove)
        .help("Remove color")
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityIdentifier(accessibilityID)
    }

    private var foregroundColor: Color {
        canRemove ? Color.white.opacity(0.62) : Color.white.opacity(0.24)
    }

    private var accessibilityLabelText: String {
        "Remove palette color \(index + 1)"
    }

    private var accessibilityID: String {
        "software-lighting-palette-\(index)-remove-button"
    }
}

private struct PaletteRemoveColorIcon: View {
    var body: some View {
        Image(systemName: "xmark.circle.fill")
            .font(.system(size: 13, weight: .semibold))
    }
}

private struct PaletteRemoveColorPlaceholder: View {
    var body: some View {
        Color.clear
            .frame(width: 13, height: 13)
    }
}

struct RGBSliderRow: View {
    let label: String
    var accessibilityIdentifier: String?
    let tint: Color
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 16, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { value = Int(round($0)) }
                ),
                in: 0...255
            )
            .tint(tint)
            .optionalAccessibilityIdentifier(accessibilityIdentifier)
            Text("\(value)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 34, alignment: .trailing)
        }
    }
}
