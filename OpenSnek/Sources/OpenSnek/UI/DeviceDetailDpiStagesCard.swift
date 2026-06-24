import AppKit
import OpenSnekAppSupport
import SwiftUI
import OpenSnekCore

private let maximumEditableDpiStageCount = DeviceProfiles.maximumDpiStageCount

/// Renders the DPI stages card UI.
struct DpiStagesCard: View {
    let editorStore: EditorStore

    var body: some View {
        _ = editorStore.onboardProfilesRevision
        let profileID = editorStore.selectedDeviceProfileID
        let supportsIndependentXYDPI = editorStore.selectedDeviceSupportsIndependentXYDPI
        let stageCount = editorStore.editableStageCount
        return Card(title: "DPI Stages", accessibilityIdentifier: "dpi-stages-card") {
            DpiStageCountHeader(editorStore: editorStore)

            ForEach(0..<stageCount, id: \.self) { idx in
                DpiStageRow(
                    editorStore: editorStore,
                    index: idx,
                    stageCount: stageCount,
                    profileID: profileID,
                    supportsIndependentXYDPI: supportsIndependentXYDPI
                )
            }
        }
    }
}

/// Renders the DPI stage count header UI.
private struct DpiStageCountHeader: View {
    let editorStore: EditorStore

    var body: some View {
        HStack {
            Text("Enabled stages: \(editorStore.editableStageCount) / \(maximumEditableDpiStageCount)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
            Spacer()
            HStack(spacing: 8) {
                stageCountButton(
                    systemName: "minus.circle.fill",
                    isEnabled: editorStore.editableStageCount > 1,
                    accessibilityIdentifier: "dpi-stage-count-decrease-button",
                    action: decreaseStageCount
                )
                stageCountButton(
                    systemName: "plus.circle.fill",
                    isEnabled: editorStore.editableStageCount < maximumEditableDpiStageCount,
                    accessibilityIdentifier: "dpi-stage-count-increase-button",
                    action: increaseStageCount
                )
            }
        }
    }

    private func stageCountButton(
        systemName: String,
        isEnabled: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .bold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? .white : .white.opacity(0.35))
        .disabled(!isEnabled)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func decreaseStageCount() {
        let next = max(1, editorStore.editableStageCount - 1)
        guard next != editorStore.editableStageCount else { return }
        editorStore.editableStageCount = next
        editorStore.setEditableActiveStage(
            min(editorStore.editableActiveStage, editorStore.editableStageCount),
            source: "ui.detail.stageCount.decrease"
        )
        editorStore.normalizeExpandedXYStages()
        editorStore.scheduleAutoApplyDpi()
    }

    private func increaseStageCount() {
        let next = min(maximumEditableDpiStageCount, editorStore.editableStageCount + 1)
        guard next != editorStore.editableStageCount else { return }
        // Hidden stage values can be stale duplicates after single-slot profile restores.
        // Seed before the auto-apply so hardware can verify the active stage unambiguously.
        editorStore.seedNewlyEnabledDPIStage(at: next - 1)
        editorStore.editableStageCount = next
        editorStore.normalizeExpandedXYStages()
        editorStore.scheduleAutoApplyDpi()
    }
}

/// Renders the DPI stage row UI.
private struct DpiStageRow: View {
    let editorStore: EditorStore
    let index: Int
    let stageCount: Int
    let profileID: DeviceProfileID?
    let supportsIndependentXYDPI: Bool

    private var isSelectedStage: Bool {
        stageCount == 1 || editorStore.editableActiveStage == index + 1
    }

    private var stageColor: Color {
        dpiStageAccent(for: index, isSelected: isSelectedStage)
    }

    private var stagePair: DpiPair {
        editorStore.stagePair(index)
    }

    private var isXYExpanded: Bool {
        supportsIndependentXYDPI && editorStore.isStageXYExpanded(index)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            splitSummary
            sliderControls
        }
        .padding(8)
        .background(rowBackground)
        .shadow(color: isSelectedStage ? stageColor.opacity(0.30) : .clear, radius: 12, y: 0)
    }

    private var headerRow: some View {
        HStack {
            DpiStageHeader(
                editorStore: editorStore,
                index: index,
                stageCount: stageCount,
                stageColor: stageColor,
                isSelectedStage: isSelectedStage
            )

            Spacer()

            stageValueControls

            if supportsIndependentXYDPI {
                DpiStageXYToggleButton(isExpanded: isXYExpanded, tint: stageColor) {
                    if editorStore.toggleStageXYExpansion(index) {
                        editorStore.scheduleAutoApplyDpi()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stageValueControls: some View {
        if isXYExpanded {
            HStack(spacing: 8) {
                DpiStageAxisTextField(label: "X", value: stagePair.x, stageIndex: index) { parsed in
                    editorStore.updateStageX(index, value: parsed)
                    editorStore.scheduleAutoApplyDpi()
                }
                DpiStageAxisTextField(label: "Y", value: stagePair.y, stageIndex: index) { parsed in
                    editorStore.updateStageY(index, value: parsed)
                    editorStore.scheduleAutoApplyDpi()
                }
            }
        } else {
            DpiValueField(
                placeholder: "DPI",
                value: editorStore.stageValue(index),
                width: 100,
                accessibilityIdentifier: "dpi-stage-\(index + 1)-value-field"
            ) { parsed in
                editorStore.updateStage(index, value: parsed)
                editorStore.scheduleAutoApplyDpi()
            }
        }
    }

    @ViewBuilder
    private var splitSummary: some View {
        if supportsIndependentXYDPI && !isXYExpanded && stagePair.x != stagePair.y {
            Text("Current split: X \(stagePair.x) / Y \(stagePair.y)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    @ViewBuilder
    private var sliderControls: some View {
        if isXYExpanded {
            DpiStageAxisSlider(
                editorStore: editorStore,
                label: "X",
                value: stagePair.x,
                stageIndex: index,
                profileID: profileID,
                tint: isSelectedStage ? stageColor : Color.white.opacity(0.80)
            ) { quantized in
                editorStore.updateStageX(index, value: quantized)
                editorStore.scheduleAutoApplyDpi()
            }
            DpiStageAxisSlider(
                editorStore: editorStore,
                label: "Y",
                value: stagePair.y,
                stageIndex: index,
                profileID: profileID,
                tint: isSelectedStage ? stageColor.opacity(0.8) : Color.white.opacity(0.65)
            ) { quantized in
                editorStore.updateStageY(index, value: quantized)
                editorStore.scheduleAutoApplyDpi()
            }
        } else {
            DpiStageSingleSlider(
                editorStore: editorStore,
                index: index,
                profileID: profileID,
                tint: isSelectedStage ? stageColor : Color.white.opacity(0.80),
                markerColor: isSelectedStage ? stageColor : Color.white.opacity(0.72)
            )
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(isSelectedStage ? stageColor.opacity(0.24) : stageColor.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelectedStage ? stageColor.opacity(0.95) : stageColor.opacity(0.35),
                        lineWidth: isSelectedStage ? 2 : 1
                    )
            )
    }
}

/// Renders the DPI stage axis text field UI.
private struct DpiStageAxisTextField: View {
    let label: String
    let value: Int
    let stageIndex: Int
    let onCommit: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            DpiValueField(
                placeholder: label,
                value: value,
                width: 88,
                accessibilityIdentifier: "dpi-stage-\(stageIndex + 1)-\(label.lowercased())-field"
            ) { parsed in
                onCommit(parsed)
            }
        }
    }
}

/// Renders the DPI stage xy toggle button UI.
private struct DpiStageXYToggleButton: View {
    let isExpanded: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("X/Y")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(isExpanded ? tint : .white.opacity(0.78))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isExpanded ? tint.opacity(0.18) : Color.white.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(isExpanded ? tint.opacity(0.95) : Color.white.opacity(0.14), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Stores DPI stage axis slider data.
private struct DpiStageAxisSlider: View {
    let editorStore: EditorStore
    let label: String
    let value: Int
    let stageIndex: Int
    let profileID: DeviceProfileID?
    let tint: Color
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(label)-Axis")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 4) {
                Slider(
                    value: Binding(
                        get: { DeviceProfiles.dpiSliderPosition(for: value, profileID: profileID) },
                        set: { newPosition in
                            onChange(DeviceProfiles.dpi(forSliderPosition: newPosition, profileID: profileID))
                        }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        editorStore.isEditingDpiControl = editing
                    }
                )
                .tint(tint)
                .accessibilityIdentifier("dpi-stage-\(stageIndex + 1)-\(label.lowercased())-axis-slider")

                DpiSliderScaleMarkers(
                    profileID: profileID,
                    markerColor: tint
                )
            }
        }
    }
}

/// Stores DPI stage single slider data.
private struct DpiStageSingleSlider: View {
    let editorStore: EditorStore
    let index: Int
    let profileID: DeviceProfileID?
    let tint: Color
    let markerColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(
                value: Binding(
                    get: {
                        DeviceProfiles.dpiSliderPosition(
                            for: editorStore.stageValue(index),
                            profileID: profileID
                        )
                    },
                    set: { newPosition in
                        editorStore.updateStage(
                            index,
                            value: DeviceProfiles.dpi(forSliderPosition: newPosition, profileID: profileID)
                        )
                        editorStore.scheduleAutoApplyDpi()
                    }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    editorStore.isEditingDpiControl = editing
                }
            )
            .tint(tint)
            .accessibilityIdentifier("dpi-stage-\(index + 1)-slider")

            DpiSliderScaleMarkers(profileID: profileID, markerColor: markerColor)
        }
    }
}

/// Renders the DPI stage header UI.
private struct DpiStageHeader: View {
    let editorStore: EditorStore
    let index: Int
    let stageCount: Int
    let stageColor: Color
    let isSelectedStage: Bool

    var body: some View {
        if stageCount == 1 {
            DpiSingleStageHeader(stageColor: stageColor)
        } else {
            DpiSelectableStageHeader(
                editorStore: editorStore,
                index: index,
                stageColor: stageColor,
                isSelectedStage: isSelectedStage
            )
        }
    }
}

/// Renders the DPI single stage header UI.
private struct DpiSingleStageHeader: View {
    let stageColor: Color

    var body: some View {
        Text("DPI")
            .foregroundStyle(stageColor)
    }
}

/// Renders the DPI selectable stage header UI.
private struct DpiSelectableStageHeader: View {
    let editorStore: EditorStore
    let index: Int
    let stageColor: Color
    let isSelectedStage: Bool

    private var stageNumber: Int { index + 1 }

    var body: some View {
        Button(action: selectStage) {
            DpiSelectableStageHeaderLabel(
                stageNumber: stageNumber,
                systemImage: editorStore.editableActiveStage == stageNumber ? "checkmark.square.fill" : "square",
                stageColor: stageColor,
                isSelectedStage: isSelectedStage
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelectedStage ? stageColor : .white)
        .accessibilityIdentifier("dpi-stage-\(stageNumber)-select-button")
    }

    private func selectStage() {
        guard editorStore.editableActiveStage != stageNumber else { return }
        editorStore.setEditableActiveStage(stageNumber, source: "ui.detail.stageHeader")
        editorStore.scheduleAutoApplyActiveStage()
    }
}

/// Stores DPI selectable stage header label data.
private struct DpiSelectableStageHeaderLabel: View {
    let stageNumber: Int
    let systemImage: String
    let stageColor: Color
    let isSelectedStage: Bool

    var body: some View {
        label
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(backgroundShape)
            .overlay(borderShape)
            .contentShape(Capsule())
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
    }

    private var title: String {
        "Stage \(stageNumber)"
    }

    private var backgroundShape: some View {
        Capsule().fill(backgroundColor)
    }

    private var borderShape: some View {
        Capsule().stroke(borderColor, lineWidth: 1)
    }

    private var backgroundColor: Color {
        isSelectedStage ? stageColor.opacity(0.18) : Color.white.opacity(0.05)
    }

    private var borderColor: Color {
        isSelectedStage ? stageColor.opacity(0.95) : Color.white.opacity(0.16)
    }
}

private func dpiStageAccent(for index: Int, isSelected: Bool) -> Color {
    switch index {
    case 0: return Color(hex: isSelected ? 0xFF6B61 : 0xFF3B30) // Red
    case 1: return Color(hex: isSelected ? 0x5BEB7E : 0x34C759) // Green
    case 2: return Color(hex: isSelected ? 0x4FA7FF : 0x0A84FF) // Blue
    case 3: return Color(hex: isSelected ? 0x36F0E8 : 0x00C7BE) // Teal
    default: return Color(hex: isSelected ? 0xFFE35A : 0xFFD60A) // Yellow
    }
}

/// Renders the DPI value field UI.
struct DpiValueField: View {
    let placeholder: String
    let value: Int
    let width: CGFloat
    var alignment: TextAlignment = .leading
    var isDisabled: Bool = false
    var accessibilityIdentifier: String?
    let onCommit: (Int) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        placeholder: String,
        value: Int,
        width: CGFloat,
        alignment: TextAlignment = .leading,
        isDisabled: Bool = false,
        accessibilityIdentifier: String? = nil,
        onCommit: @escaping (Int) -> Void
    ) {
        self.placeholder = placeholder
        self.value = value
        self.width = width
        self.alignment = alignment
        self.isDisabled = isDisabled
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onCommit = onCommit
        _draft = State(initialValue: String(value))
    }

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.roundedBorder)
            .frame(width: width)
            .multilineTextAlignment(alignment)
            .disabled(isDisabled)
            .optionalAccessibilityIdentifier(accessibilityIdentifier)
            .focused($isFocused)
            .onSubmit {
                commitDraft()
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commitDraft()
                }
            }
            .onChange(of: value) { _, newValue in
                let resolved = String(newValue)
                if !isFocused && draft != resolved {
                    draft = resolved
                }
            }
    }

    private func commitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draft = String(value)
            return
        }
        guard let parsed = Int(trimmed) else {
            draft = String(value)
            return
        }
        onCommit(parsed)
        draft = String(parsed)
    }
}
