import SwiftUI

enum DpiControlPresentation {
    static func stageLabel(for index: Int) -> String {
        "Stage \(index + 1)"
    }

    static func stageCountSummary(for stageCount: Int) -> String {
        stageCount == 1 ? "Single-stage DPI" : "Enabled stages: \(stageCount) / 5"
    }

    static func quantizedDpi(from rawValue: Double) -> Int {
        Int(round(rawValue / 100.0) * 100.0)
    }

    static func sliderValue(for dpi: Int, upperBound: Int) -> Double {
        Double(min(dpi, upperBound))
    }
}

struct DpiStageChipButton: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    var selectedForegroundStyle: Color? = nil
    var unselectedForegroundStyle: Color = .primary
    var font: Font = .system(size: 11, weight: .black, design: .rounded)
    var minHeight: CGFloat = 34
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 9
    var expandHorizontally: Bool = false
    var selectedBackgroundOpacity: Double = 0.18
    var unselectedBackgroundOpacity: Double = 0.06
    var selectedStrokeOpacity: Double = 0.95
    var unselectedStrokeOpacity: Double = 0.10

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                        .labelStyle(.titleAndIcon)
                } else {
                    Text(title)
                }
            }
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isSelected ? (selectedForegroundStyle ?? accentColor) : unselectedForegroundStyle)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: expandHorizontally ? .infinity : nil, minHeight: minHeight)
            .background(
                Capsule()
                    .fill(isSelected ? accentColor.opacity(selectedBackgroundOpacity) : Color.primary.opacity(unselectedBackgroundOpacity))
            )
            .overlay(
                Capsule()
                    .stroke(
                        isSelected ? (selectedForegroundStyle ?? accentColor).opacity(selectedStrokeOpacity) : Color.primary.opacity(unselectedStrokeOpacity),
                        lineWidth: 1
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct DpiQuantizedSlider: View {
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let tint: Color
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        Slider(value: value, in: range, onEditingChanged: onEditingChanged)
            .tint(tint)
    }
}
