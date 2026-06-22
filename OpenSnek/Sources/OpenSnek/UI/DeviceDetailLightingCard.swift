import AppKit
import OpenSnekAppSupport
import SwiftUI
import OpenSnekCore

struct LightingSwatch: Identifiable, Hashable {
    let hex: UInt32
    let rgb: OpenSnekCore.RGBColor

    init(hex: UInt32) {
        self.hex = hex
        self.rgb = OpenSnekCore.RGBColor(
            r: Int((hex >> 16) & 0xFF),
            g: Int((hex >> 8) & 0xFF),
            b: Int(hex & 0xFF)
        )
    }

    var id: UInt32 { hex }
}

struct LightingCard: View {
    let editorStore: EditorStore
    let selected: MouseDevice
    let swatches: [LightingSwatch]

    @State private var selectedTab: LightingCardTab = .onboard
    @State private var onboardZoneMode: LightingZoneEditMode = .allZones
    @State private var isExpanded = false

    private var accentBase: Color {
        Color(rgb: editorStore.editableColor)
    }

    private var actionAccent: Color {
        Color(hex: 0x0A84FF)
    }

    private var preferredLightingTab: LightingCardTab {
        editorStore.editableSoftwareLightingApplyOnConnect && selected.supportsSoftwareLightingEffects
            ? .advanced
            : .onboard
    }

    private var accentOpacity: Double {
        let brightness = Double(max(0, min(255, editorStore.editableLedBrightness))) / 255.0
        return 0.10 + (brightness * 0.22)
    }

    private var showsStaticLightingZoneControls: Bool {
        editorStore.editableLightingEffect == .staticColor &&
            editorStore.visibleUSBLightingZones.count > 1
    }

    private var singleColorGradientColors: [Color] {
        [
            accentBase.opacity(accentOpacity),
            Color.white.opacity(0.05)
        ]
    }

    private var lightingCardGradientColors: [Color] {
        if usesSoftwareLightingPaletteForCard {
            return softwareLightingGradientColors
        }

        return onboardLightingGradientColors
    }

    private var usesSoftwareLightingPaletteForCard: Bool {
        selected.supportsSoftwareLightingEffects &&
            (softwareLightingIsRunning || (isExpanded && selectedTab == .advanced))
    }

    private var onboardLightingGradientColors: [Color] {
        gradientColors(
            from: editorStore.lightingGradientDisplayColors,
            fallback: editorStore.editableColor
        )
    }

    private var softwareLightingGradientColors: [Color] {
        if activeSoftwareLightingPreset == .batteryMeter {
            let color = batteryMeterSummaryColor
            return gradientColors(from: [color], fallback: color)
        }

        let defaultPalette = activeSoftwareLightingPreset.defaultPalette
        let fallbackColor = defaultPalette.first.map {
            RGBColor(r: $0.r, g: $0.g, b: $0.b)
        } ?? editorStore.editableColor

        return gradientColors(
            from: activeSoftwareLightingPalette,
            fallback: fallbackColor
        )
    }

    private var activeSoftwareLightingRequest: SoftwareLightingEffectRequest? {
        softwareLightingIsRunning ? softwareLightingStatus?.request : nil
    }

    private var activeSoftwareLightingPreset: SoftwareLightingPresetID {
        activeSoftwareLightingRequest?.presetID ?? editorStore.editableSoftwareLightingPreset
    }

    private var activeSoftwareLightingPalette: [RGBColor] {
        if let request = activeSoftwareLightingRequest {
            return request.palette.map { RGBColor(r: $0.r, g: $0.g, b: $0.b) }
        }
        return editorStore.editableSoftwareLightingPalette(for: editorStore.editableSoftwareLightingPreset)
    }

    private var batteryMeterSummaryColor: RGBColor {
        guard let percent = editorStore.deviceStore.state?.battery_percent else {
            return RGBColor(r: 255, g: 255, b: 255)
        }
        if percent < 15 {
            return RGBColor(r: 255, g: 0, b: 0)
        }
        if percent < 30 {
            return RGBColor(r: 255, g: 255, b: 0)
        }
        return RGBColor(r: 255, g: 255, b: 255)
    }

    private func gradientColors(from displayColors: [RGBColor], fallback: RGBColor) -> [Color] {
        let colors = displayColors.isEmpty ? [fallback] : displayColors
        guard let firstColor = colors.first else {
            return singleColorGradientColors
        }
        guard colors.dropFirst().contains(where: { $0 != firstColor }) else {
            return [
                Color(rgb: firstColor).opacity(accentOpacity),
                Color.white.opacity(0.05)
            ]
        }

        let overlayOpacity = max(0.10, accentOpacity * 0.9)
        return colors.map {
            Color(rgb: $0).opacity(overlayOpacity)
        }
    }

    private var brightnessPercent: Int {
        Int(round((Double(max(0, min(255, editorStore.editableLedBrightness))) / 255.0) * 100.0))
    }

    private var softwareLightingStatus: SoftwareLightingEngineStatus? {
        editorStore.deviceStore.softwareLightingStatusByDeviceID[selected.id]
    }

    private var softwareLightingIsRunning: Bool {
        softwareLightingStatus?.state == .running
    }

    private var lightingSummaryTitle: String {
        lightingSummaryPresentation.title
    }

    private var lightingSummarySwatches: [RGBColor] {
        lightingSummaryPresentation.swatches
    }

    private var lightingSummaryBatteryIcon: BatteryIconPresentation? {
        lightingSummaryPresentation.batteryIcon
    }

    private var lightingSummaryPresentation: LightingSummaryPresentation {
        LightingSummaryPresentation.make(
            LightingSummaryInput(
                supportsSoftwareLightingEffects: selected.supportsSoftwareLightingEffects,
                softwareLightingStatus: softwareLightingStatus,
                editableSoftwareLightingPreset: editorStore.editableSoftwareLightingPreset,
                editableSoftwareLightingPalette: editorStore.editableSoftwareLightingPalette(
                    for: editorStore.editableSoftwareLightingPreset
                ),
                onboardEffectLabel: editorStore.editableLightingEffect.label,
                onboardColors: editorStore.lightingGradientDisplayColors,
                fallbackColor: editorStore.editableColor,
                batteryState: editorStore.deviceStore.state
            ),
        )
    }

    private var advancedStatusText: String? {
        guard let status = softwareLightingStatus else { return nil }
        switch status.state {
        case .running:
            return "Running \(status.request?.presetID.label ?? "effect")"
        case .suspended, .failed:
            return status.message
        case .stopped:
            return nil
        }
    }

    private var tabSelection: Binding<LightingCardTab> {
        Binding(
            get: { selectedTab },
            set: { selectedTab = $0 }
        )
    }

    @ViewBuilder
    private func tabPicker() -> some View {
        Picker("", selection: tabSelection) {
            ForEach(LightingCardTab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .accessibilityIdentifier("lighting-card-tab-picker")
    }

    @ViewBuilder
    private func brightnessControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Brightness")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text("\(brightnessPercent)%")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
            }

            Slider(
                value: Binding(
                    get: { (Double(max(0, min(255, editorStore.editableLedBrightness))) / 255.0) * 100.0 },
                    set: { newValue in
                        let percent = max(0.0, min(100.0, newValue))
                        editorStore.editableLedBrightness = Int(round((percent / 100.0) * 255.0))
                        editorStore.scheduleAutoApplyLedBrightness()
                    }
                ),
                in: 0...100
            )
            .tint(accentBase)
            .accessibilityIdentifier("lighting-brightness-slider")
        }
    }

    @ViewBuilder
    private func onboardPresetPicker() -> some View {
        if selected.supports_advanced_lighting_effects {
            HStack {
                Text("Preset")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Picker(
                    "",
                    selection: Binding(
                        get: { editorStore.editableLightingEffect },
                        set: {
                            editorStore.updateLightingEffect($0)
                            editorStore.scheduleAutoApplyLightingEffect()
                        }
                    )
                ) {
                    ForEach(editorStore.visibleLightingEffects) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 220, alignment: .trailing)
                .accessibilityIdentifier("lighting-effect-picker")
            }
        }
    }

    @ViewBuilder
    private func onboardEffectOptions() -> some View {
        if editorStore.editableLightingEffect.usesWaveDirection {
            HStack {
                Text("Direction")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Picker(
                    "Direction",
                    selection: Binding(
                        get: { editorStore.editableLightingWaveDirection },
                        set: {
                            editorStore.updateLightingWaveDirection($0)
                            editorStore.scheduleAutoApplyLightingEffect()
                        }
                    )
                ) {
                    Text("Left").tag(LightingWaveDirection.left)
                    Text("Right").tag(LightingWaveDirection.right)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .accessibilityIdentifier("lighting-direction-picker")
            }
        }

        if editorStore.editableLightingEffect.usesReactiveSpeed {
            HStack {
                Text("Speed")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Picker(
                    "Speed",
                    selection: Binding(
                        get: { editorStore.editableLightingReactiveSpeed },
                        set: {
                            editorStore.updateLightingReactiveSpeed($0)
                            editorStore.scheduleAutoApplyLightingEffect()
                        }
                    )
                ) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .accessibilityIdentifier("lighting-speed-picker")
            }
        }
    }

    private func colorForZone(_ zone: USBLightingZoneDescriptor) -> RGBColor {
        let colors = editorStore.lightingGradientDisplayColors
        guard let index = editorStore.visibleUSBLightingZones.firstIndex(where: { $0.id == zone.id }),
              colors.indices.contains(index) else {
            return editorStore.editableColor
        }
        return colors[index]
    }

    private func scheduleStaticColorApply(allZones: Bool) {
        if allZones {
            editorStore.scheduleAutoApplyCurrentStaticColorToAllZones()
        } else if selected.supports_advanced_lighting_effects {
            editorStore.scheduleAutoApplyLightingEffect()
        } else {
            editorStore.scheduleAutoApplyLedColor()
        }
    }

    private func allZonesColorBinding() -> Binding<RGBColor> {
        Binding(
            get: { editorStore.editableColor },
            set: { color in
                editorStore.editableUSBLightingZoneID = "all"
                editorStore.editableColor = color
                scheduleStaticColorApply(allZones: true)
            }
        )
    }

    private func zoneColorBinding(_ zone: USBLightingZoneDescriptor) -> Binding<RGBColor> {
        Binding(
            get: { colorForZone(zone) },
            set: { color in
                editorStore.editableUSBLightingZoneID = zone.id
                editorStore.editableColor = color
                scheduleStaticColorApply(allZones: false)
            }
        )
    }

    private func primaryColorBinding(title _: String = "Primary Color") -> Binding<RGBColor> {
        Binding(
            get: { editorStore.editableColor },
            set: { color in
                editorStore.editableColor = color
                editorStore.scheduleAutoApplyLightingEffect()
            }
        )
    }

    private func secondaryColorBinding() -> Binding<RGBColor> {
        Binding(
            get: { editorStore.editableSecondaryColor },
            set: { color in
                editorStore.editableSecondaryColor = color
                editorStore.scheduleAutoApplyLightingEffect()
            }
        )
    }

    @ViewBuilder
    private func onboardColorControls() -> some View {
        if editorStore.editableLightingEffect == .staticColor || !selected.supports_advanced_lighting_effects {
            VStack(alignment: .leading, spacing: 10) {
                if showsStaticLightingZoneControls {
                    HStack(spacing: 12) {
                        Text("Zones")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer(minLength: 8)
                        Picker(
                            "",
                            selection: Binding(
                                get: { onboardZoneMode },
                                set: { onboardZoneMode = $0 }
                            )
                        ) {
                            ForEach(LightingZoneEditMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        .accessibilityIdentifier("lighting-zone-mode-picker")
                    }
                }

                if showsStaticLightingZoneControls && onboardZoneMode == .individualZones {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(editorStore.visibleUSBLightingZones) { zone in
                            LightingColorOrbRow(
                                title: zone.label,
                                identifierPrefix: "lighting-zone-\(zone.id)",
                                color: zoneColorBinding(zone),
                                swatches: swatches
                            )
                        }
                    }
                } else {
                    LightingColorOrbRow(
                        title: showsStaticLightingZoneControls ? "All Zones" : "Color",
                        identifierPrefix: "lighting-all-zones",
                        color: allZonesColorBinding(),
                        swatches: swatches
                    )
                }
            }
        } else {
            if editorStore.editableLightingEffect.usesPrimaryColor {
                LightingColorOrbRow(
                    title: "Primary Color",
                    identifierPrefix: "lighting-primary-color",
                    color: primaryColorBinding(),
                    swatches: swatches
                )
            }

            if editorStore.editableLightingEffect.usesSecondaryColor {
                LightingColorOrbRow(
                    title: "Secondary Color",
                    identifierPrefix: "lighting-secondary-color",
                    color: secondaryColorBinding(),
                    swatches: swatches
                )
            }
        }
    }

    @ViewBuilder
    private func onboardControls() -> some View {
        lightingNotice(
            systemImage: "memorychip.fill",
            iconColor: actionAccent,
            text: "Onboard lighting is stored on the device and survives restart and reconnect."
        )

        brightnessControls()
            .padding(.vertical, 2)

        onboardPresetPicker()
        onboardEffectOptions()
        onboardColorControls()
    }

    var body: some View {
        Card(title: "Lighting", accessibilityIdentifier: "lighting-card") {
            lightingSummaryRow()

            if isExpanded {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1)
                    .padding(.vertical, 2)

                tabPicker()

                if selectedTab == .onboard {
                    onboardControls()
                } else {
                    advancedLightingControls()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: lightingCardGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .onAppear {
            selectedTab = preferredLightingTab
        }
        .onChange(of: selected.id) {
            selectedTab = preferredLightingTab
            isExpanded = false
        }
        .onChange(of: editorStore.editableSoftwareLightingApplyOnConnect) { _, enabled in
            if enabled && selected.supportsSoftwareLightingEffects {
                selectedTab = .advanced
            }
        }
    }

    private func lightingSummaryRow() -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(lightingSummaryTitle)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .accessibilityIdentifier("lighting-card-summary-text")
            }

            Spacer(minLength: 10)

            if let batteryIcon = lightingSummaryBatteryIcon {
                Image(
                    systemName: batteryIcon.symbolName,
                    variableValue: batteryIcon.variableValue
                )
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(batteryIcon.accent == .low ? BatteryPresentation.lowBatteryColor : .white.opacity(0.82))
                .frame(width: 28, height: 18)
                .accessibilityLabel("Battery Meter")
                .accessibilityIdentifier("lighting-card-summary-battery-icon")
            } else {
                HStack(spacing: -3) {
                    ForEach(Array(lightingSummarySwatches.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(Color(rgb: color))
                            .frame(width: 15, height: 15)
                            .overlay(Circle().stroke(Color.white.opacity(0.62), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 3)
                .accessibilityHidden(true)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                Label(isExpanded ? "Collapse" : "Expand", systemImage: isExpanded ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("lighting-card-expand-button")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func advancedLightingControls() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            lightingNotice(
                systemImage: "bolt.horizontal.circle.fill",
                iconColor: actionAccent,
                text: "Advanced effects run only while OpenSnek is running."
            )

            if selected.supportsSoftwareLightingEffects {
                HStack(spacing: 12) {
                    Text("Preset")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))

                    Spacer(minLength: 12)

                    Picker(
                        "",
                        selection: Binding(
                            get: { editorStore.editableSoftwareLightingPreset },
                            set: { editorStore.updateEditableSoftwareLightingPreset($0) }
                        )
                    ) {
                        ForEach(editorStore.visibleSoftwareLightingPresets) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 190, alignment: .trailing)
                    .accessibilityIdentifier("software-lighting-preset-picker")
                }

                if editorStore.editableSoftwareLightingPreset.usesSpeedControl {
                    softwareLightingSpeedControl()
                }
                softwareLightingBrightnessControl()

                if editorStore.editableSoftwareLightingPreset.usesPaletteControls {
                    SoftwareLightingPaletteEditor(
                        preset: editorStore.editableSoftwareLightingPreset,
                        palette: Binding(
                            get: {
                                editorStore.editableSoftwareLightingPalette(
                                    for: editorStore.editableSoftwareLightingPreset
                                )
                            },
                            set: {
                                editorStore.setEditableSoftwareLightingPalette(
                                    $0,
                                    for: editorStore.editableSoftwareLightingPreset
                                )
                            }
                        ),
                        swatches: swatches,
                        onAdd: {
                            editorStore.addEditableSoftwareLightingPaletteColor(
                                for: editorStore.editableSoftwareLightingPreset
                            )
                        },
                        onRemove: { index in
                            editorStore.removeEditableSoftwareLightingPaletteColor(
                                at: index,
                                for: editorStore.editableSoftwareLightingPreset
                            )
                        },
                        onReset: {
                            editorStore.resetEditableSoftwareLightingPalette(
                                for: editorStore.editableSoftwareLightingPreset
                            )
                        }
                    )
                }

                if let advancedStatusText {
                    Text(advancedStatusText)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("software-lighting-status-text")
                }

                softwareLightingActionRow()
            } else {
                Text("Advanced software effects are available on Basilisk V3 USB devices with underglow.")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func softwareLightingActionRow() -> some View {
        HStack(spacing: 12) {
            softwareLightingApplyOnConnectToggle()
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if softwareLightingIsRunning {
                    Button {
                        Task {
                            await editorStore.stopSoftwareLighting()
                        }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .frame(minWidth: 106)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Color(hex: 0xFF453A))
                    .accessibilityIdentifier("software-lighting-stop-button")
                }

                Button {
                    Task {
                        await editorStore.startSoftwareLighting()
                    }
                } label: {
                    Label("Apply", systemImage: "checkmark.circle.fill")
                        .frame(minWidth: softwareLightingIsRunning ? 106 : 148)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(actionAccent)
                .accessibilityIdentifier("software-lighting-apply-button")
            }
        }
    }

    private func softwareLightingApplyOnConnectToggle() -> some View {
        Toggle(
            isOn: Binding(
                get: { editorStore.editableSoftwareLightingApplyOnConnect },
                set: { editorStore.updateSoftwareLightingApplyOnConnect($0) }
            )
        ) {
            Text("Apply on connect")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
        }
        .toggleStyle(.checkbox)
        .accessibilityIdentifier("software-lighting-apply-on-connect-checkbox")
    }

    private func lightingNotice(systemImage: String, iconColor: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func softwareLightingSpeedControl() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Speed")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text(editorStore.editableSoftwareLightingSpeed <= 0.001
                    ? "Static"
                    : "\(Int(round(editorStore.editableSoftwareLightingSpeed * 100)))%")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
            }

            Slider(
                value: Binding(
                    get: { editorStore.editableSoftwareLightingSpeed * 100.0 },
                    set: { editorStore.editableSoftwareLightingSpeed = max(0.0, min(2.0, $0 / 100.0)) }
                ),
                in: 0...200
            )
            .tint(.white)
            .accessibilityIdentifier("software-lighting-speed-slider")
        }
    }

    private func softwareLightingBrightnessControl() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Brightness")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text("\(Int(round(editorStore.editableSoftwareLightingBrightness * 100)))%")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
            }

            Slider(
                value: Binding(
                    get: { editorStore.editableSoftwareLightingBrightness * 100.0 },
                    set: {
                        editorStore.editableSoftwareLightingBrightness = max(0.0, min(1.0, $0 / 100.0))
                    }
                ),
                in: 0...100
            )
            .tint(.white)
            .accessibilityIdentifier("software-lighting-brightness-slider")
        }
    }
}

private enum LightingCardTab: String, CaseIterable, Identifiable {
    case onboard
    case advanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onboard:
            return "Onboard"
        case .advanced:
            return "Advanced"
        }
    }
}

struct LightingSummaryPresentation: Equatable {
    let title: String
    let swatches: [RGBColor]
    let batteryIcon: BatteryIconPresentation?

    static func make(_ input: LightingSummaryInput) -> LightingSummaryPresentation {
        if input.supportsSoftwareLightingEffects,
           input.softwareLightingStatus?.state == .running {
            let preset = input.softwareLightingStatus?.request?.presetID ?? input.editableSoftwareLightingPreset
            if preset == .batteryMeter {
                return LightingSummaryPresentation(
                    title: preset.label,
                    swatches: [],
                    batteryIcon: batteryIcon(for: input.batteryState)
                )
            }

            let palette = input.softwareLightingStatus?.request?.palette.map { color in
                RGBColor(r: color.r, g: color.g, b: color.b)
            } ?? input.editableSoftwareLightingPalette
            return LightingSummaryPresentation(
                title: preset.label,
                swatches: condensedSwatches(from: palette, fallback: input.fallbackColor),
                batteryIcon: nil
            )
        }

        return LightingSummaryPresentation(
            title: "Onboard \(input.onboardEffectLabel)",
            swatches: condensedSwatches(from: input.onboardColors, fallback: input.fallbackColor),
            batteryIcon: nil
        )
    }

    private static func batteryIcon(for state: MouseState?) -> BatteryIconPresentation {
        guard let state,
              let percent = state.battery_percent else {
            return BatteryIconPresentation(
                symbolName: "battery.100percent",
                variableValue: 1.0,
                accent: .normal
            )
        }
        return ServiceMenuBarPresentation.batteryIcon(
            percent: percent,
            charging: state.charging,
            thresholdRaw: state.low_battery_threshold_raw
        )
    }

    private static func condensedSwatches(from colors: [RGBColor], fallback: RGBColor) -> [RGBColor] {
        let source = colors.isEmpty ? [fallback] : colors
        var uniqueColors: [RGBColor] = []
        for color in source {
            if !uniqueColors.contains(color) {
                uniqueColors.append(color)
            }
            if uniqueColors.count == 6 {
                break
            }
        }
        return uniqueColors.isEmpty ? [fallback] : uniqueColors
    }
}

struct LightingSummaryInput {
    let supportsSoftwareLightingEffects: Bool
    let softwareLightingStatus: SoftwareLightingEngineStatus?
    let editableSoftwareLightingPreset: SoftwareLightingPresetID
    let editableSoftwareLightingPalette: [RGBColor]
    let onboardEffectLabel: String
    let onboardColors: [RGBColor]
    let fallbackColor: RGBColor
    let batteryState: MouseState?
}

private enum LightingZoneEditMode: String, CaseIterable, Identifiable {
    case allZones
    case individualZones

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allZones:
            return "All Zones"
        case .individualZones:
            return "Individual Zones"
        }
    }
}
