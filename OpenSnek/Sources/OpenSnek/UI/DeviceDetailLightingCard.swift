import AppKit
import OpenSnekAppSupport
import SwiftUI
import OpenSnekCore

/// Stores lighting swatch data.
struct LightingSwatch: Identifiable, Hashable {
    let hex: UInt32
    let rgb: OpenSnekCore.RGBColor

    init(hex: UInt32) {
        self.hex = hex
        self.rgb = OpenSnekCore.RGBColor(r: Int((hex >> 16) & 0xFF), g: Int((hex >> 8) & 0xFF), b: Int(hex & 0xFF))
    }

    var id: UInt32 { hex }
}

/// Renders the lighting card UI.
struct LightingCard: View {
    let editorStore: EditorStore
    let selected: MouseDevice
    let swatches: [LightingSwatch]
    let isLightingOnly: Bool

    @State private var selectedTab: LightingCardTab = .onboard
    @State private var onboardZoneMode: LightingZoneEditMode = .allZones
    @State private var isExpanded = false

    /// Defines the single-picker modes shown for lighting-only devices.
    private enum LightingMode: Hashable {
        case onboard(LightingEffectKind)
        case software(SoftwareLightingPresetID)
    }

    private var accentBase: Color { Color(rgb: editorStore.editableColor) }

    private var actionAccent: Color { Color(hex: 0x0A84FF) }

    private var preferredLightingTab: LightingCardTab { editorStore.editableSoftwareLightingApplyOnConnect && selected.supportsSoftwareLightingEffects ? .advanced : .onboard }

    private var availableTabs: [LightingCardTab] { selected.supportsSoftwareLightingEffects ? LightingCardTab.allCases : [.onboard] }

    private var activeTab: LightingCardTab { availableTabs.contains(selectedTab) ? selectedTab : .onboard }

    private var accentOpacity: Double {
        let brightness = Double(max(0, min(255, editorStore.editableLedBrightness))) / 255.0
        return 0.10 + (brightness * 0.22)
    }

    private var showsStaticLightingZoneControls: Bool { editorStore.editableLightingEffect == .staticColor && editorStore.visibleUSBLightingZones.count > 1 }

    private var singleColorGradientColors: [Color] { [accentBase.opacity(accentOpacity), Color.white.opacity(0.05)] }

    private var lightingCardGradientColors: [Color] {
        if usesSoftwareLightingPaletteForCard { return softwareLightingGradientColors }

        return onboardLightingGradientColors
    }

    private var usesSoftwareLightingPaletteForCard: Bool {
        if isLightingOnly {
            if case .software = selectedLightingMode { return true }
            return false
        }
        return selected.supportsSoftwareLightingEffects && (softwareLightingIsRunning || (isExpanded && activeTab == .advanced))
    }

    private var onboardLightingGradientColors: [Color] { gradientColors(from: editorStore.lightingGradientDisplayColors, fallback: editorStore.editableColor) }

    private var softwareLightingGradientColors: [Color] {
        if activeSoftwareLightingPreset == .batteryMeter {
            let color = batteryMeterSummaryColor
            return gradientColors(from: [color], fallback: color)
        }

        let defaultPalette = activeSoftwareLightingPreset.defaultPalette
        let fallbackColor = defaultPalette.first.map { RGBColor(r: $0.r, g: $0.g, b: $0.b) } ?? editorStore.editableColor

        return gradientColors(from: activeSoftwareLightingPalette, fallback: fallbackColor)
    }

    private var activeSoftwareLightingRequest: SoftwareLightingEffectRequest? { softwareLightingIsRunning ? softwareLightingStatus?.request : nil }

    private var activeSoftwareLightingPreset: SoftwareLightingPresetID { activeSoftwareLightingRequest?.presetID ?? editorStore.editableSoftwareLightingPreset }

    private var activeSoftwareLightingPalette: [RGBColor] {
        if let request = activeSoftwareLightingRequest { return request.palette.map { RGBColor(r: $0.r, g: $0.g, b: $0.b) } }
        return editorStore.editableSoftwareLightingPalette(for: editorStore.editableSoftwareLightingPreset)
    }

    private var batteryMeterSummaryColor: RGBColor {
        guard let percent = editorStore.deviceStore.state?.battery_percent else { return RGBColor(r: 255, g: 255, b: 255) }
        if percent < 15 { return RGBColor(r: 255, g: 0, b: 0) }
        if percent < 30 { return RGBColor(r: 255, g: 255, b: 0) }
        return RGBColor(r: 255, g: 255, b: 255)
    }

    private func gradientColors(from displayColors: [RGBColor], fallback: RGBColor) -> [Color] {
        let colors = displayColors.isEmpty ? [fallback] : displayColors
        guard let firstColor = colors.first else { return singleColorGradientColors }
        guard colors.dropFirst().contains(where: { $0 != firstColor }) else { return [Color(rgb: firstColor).opacity(accentOpacity), Color.white.opacity(0.05)] }

        let overlayOpacity = max(0.10, accentOpacity * 0.9)
        return colors.map { Color(rgb: $0).opacity(overlayOpacity) }
    }

    private var brightnessPercent: Int { Int(round((Double(max(0, min(255, editorStore.editableLedBrightness))) / 255.0) * 100.0)) }

    private var softwareLightingStatus: SoftwareLightingEngineStatus? { editorStore.deviceStore.softwareLightingStatusByDeviceID[selected.id] }

    private var softwareLightingIsRunning: Bool { softwareLightingStatus?.state == .running }

    private var lightingSummaryTitle: String { lightingSummaryPresentation.title }

    private var lightingSummarySwatches: [RGBColor] { lightingSummaryPresentation.swatches }

    private var lightingSummaryPresentation: LightingSummaryPresentation {
        LightingSummaryPresentation.make(
            LightingSummaryInput(
                supportsSoftwareLightingEffects: selected.supportsSoftwareLightingEffects, softwareLightingStatus: softwareLightingStatus, editableSoftwareLightingPreset: editorStore.editableSoftwareLightingPreset,
                editableSoftwareLightingPalette: editorStore.editableSoftwareLightingPalette(for: editorStore.editableSoftwareLightingPreset), onboardEffectLabel: editorStore.editableLightingEffect.label, onboardColors: editorStore.lightingGradientDisplayColors,
                fallbackColor: editorStore.editableColor, batteryState: batteryMeterSourceState), )
    }

    private var advancedStatusText: String? {
        guard let status = softwareLightingStatus else { return nil }
        switch status.state {
        case .running: return "Running \(status.request?.presetID.label ?? "effect")"
        case .suspended, .failed: return status.message
        case .stopped: return nil
        }
    }

    private var tabSelection: Binding<LightingCardTab> { Binding(get: { selectedTab }, set: { selectedTab = availableTabs.contains($0) ? $0 : .onboard }) }

    private var effectiveExpanded: Bool { isLightingOnly || isExpanded }

    private var availableLightingModes: [LightingMode] {
        var modes = editorStore.visibleLightingEffects.map(LightingMode.onboard)
        if selected.supportsSoftwareLightingEffects { modes.append(contentsOf: editorStore.visibleSoftwareLightingPresets.map(LightingMode.software)) }
        return modes
    }

    private var selectedLightingMode: LightingMode {
        if let status = softwareLightingStatus, status.state == .running || status.state == .suspended || status.state == .failed { return .software(status.request?.presetID ?? editorStore.editableSoftwareLightingPreset) }
        return .onboard(editorStore.editableLightingEffect)
    }

    private var lightingModeBinding: Binding<LightingMode> {
        Binding(
            get: { selectedLightingMode },
            set: { mode in
                switch mode {
                case .onboard(let kind):
                    Task {
                        await editorStore.stopSoftwareLighting()
                        editorStore.updateLightingEffect(kind)
                        editorStore.scheduleAutoApplyLightingEffect()
                    }
                case .software(let preset):
                    editorStore.updateEditableSoftwareLightingPreset(preset)
                    Task { await editorStore.startSoftwareLighting() }
                }
            })
    }

    private func lightingModeLabel(_ mode: LightingMode) -> String {
        switch mode {
        case .onboard(let kind): return kind.label
        case .software(let preset): return preset.label
        }
    }

    @ViewBuilder private func unifiedLightingControls() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Mode").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))

                Spacer(minLength: 12)

                Picker("", selection: lightingModeBinding) { ForEach(availableLightingModes, id: \.self) { mode in Text(lightingModeLabel(mode)).tag(mode) } }.labelsHidden().pickerStyle(.menu).frame(width: 220, alignment: .trailing).accessibilityIdentifier("lighting-mode-picker")
            }

            switch selectedLightingMode {
            case .onboard: onboardControls(includePresetPicker: false)
            case .software: softwareLightingControls(includePresetPicker: false)
            }
        }
    }

    @ViewBuilder private func tabPicker() -> some View { if availableTabs.count > 1 { Picker("", selection: tabSelection) { ForEach(availableTabs) { tab in Text(tab.label).tag(tab) } }.labelsHidden().pickerStyle(.segmented).accessibilityIdentifier("lighting-card-tab-picker") } }

    @ViewBuilder private func brightnessControls() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Brightness").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text("\(brightnessPercent)%").font(.system(size: 13, weight: .black, design: .monospaced)).foregroundStyle(.white)
            }

            Slider(
                value: Binding(
                    get: { (Double(max(0, min(255, editorStore.editableLedBrightness))) / 255.0) * 100.0 },
                    set: { newValue in
                        let percent = max(0.0, min(100.0, newValue))
                        editorStore.editableLedBrightness = Int(round((percent / 100.0) * 255.0))
                        editorStore.scheduleAutoApplyLedBrightness()
                    }), in: 0...100
            ).tint(accentBase).accessibilityIdentifier("lighting-brightness-slider")
        }
    }

    @ViewBuilder private func onboardPresetPicker() -> some View {
        if selected.supports_advanced_lighting_effects {
            HStack {
                Text("Preset").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))
                Spacer()
                Picker(
                    "",
                    selection: Binding(
                        get: { editorStore.editableLightingEffect },
                        set: {
                            editorStore.updateLightingEffect($0)
                            editorStore.scheduleAutoApplyLightingEffect()
                        })
                ) { ForEach(editorStore.visibleLightingEffects) { kind in Text(kind.label).tag(kind) } }.labelsHidden().pickerStyle(.menu).frame(width: 220, alignment: .trailing).accessibilityIdentifier("lighting-effect-picker")
            }
        }
    }

    @ViewBuilder private func onboardEffectOptions() -> some View {
        if editorStore.editableLightingEffect.usesWaveDirection {
            HStack {
                Text("Direction").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))
                Spacer()
                Picker(
                    "Direction",
                    selection: Binding(
                        get: { editorStore.editableLightingWaveDirection },
                        set: {
                            editorStore.updateLightingWaveDirection($0)
                            editorStore.scheduleAutoApplyLightingEffect()
                        })
                ) {
                    Text("Left").tag(LightingWaveDirection.left)
                    Text("Right").tag(LightingWaveDirection.right)
                }.pickerStyle(.segmented).frame(width: 220).accessibilityIdentifier("lighting-direction-picker")
            }
        }

        if editorStore.editableLightingEffect.usesReactiveSpeed {
            HStack {
                Text("Speed").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))
                Spacer()
                Picker(
                    "Speed",
                    selection: Binding(
                        get: { editorStore.editableLightingReactiveSpeed },
                        set: {
                            editorStore.updateLightingReactiveSpeed($0)
                            editorStore.scheduleAutoApplyLightingEffect()
                        })
                ) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                }.pickerStyle(.segmented).frame(width: 220).accessibilityIdentifier("lighting-speed-picker")
            }
        }
    }

    private func colorForZone(_ zone: USBLightingZoneDescriptor) -> RGBColor {
        let colors = editorStore.lightingGradientDisplayColors
        guard let index = editorStore.visibleUSBLightingZones.firstIndex(where: { $0.id == zone.id }), colors.indices.contains(index) else { return editorStore.editableColor }
        return colors[index]
    }

    private func scheduleStaticColorApply(allZones: Bool) { if allZones { editorStore.scheduleAutoApplyCurrentStaticColorToAllZones() } else if selected.supports_advanced_lighting_effects { editorStore.scheduleAutoApplyLightingEffect() } else { editorStore.scheduleAutoApplyLedColor() } }

    private func allZonesColorBinding() -> Binding<RGBColor> {
        Binding(
            get: { editorStore.editableColor },
            set: { color in
                editorStore.editableUSBLightingZoneID = "all"
                editorStore.editableColor = color
                scheduleStaticColorApply(allZones: true)
            })
    }

    private func zoneColorBinding(_ zone: USBLightingZoneDescriptor) -> Binding<RGBColor> {
        Binding(
            get: { colorForZone(zone) },
            set: { color in
                editorStore.editableUSBLightingZoneID = zone.id
                editorStore.editableColor = color
                scheduleStaticColorApply(allZones: false)
            })
    }

    private func primaryColorBinding(title _: String = "Primary Color") -> Binding<RGBColor> {
        Binding(
            get: { editorStore.editableColor },
            set: { color in
                editorStore.editableColor = color
                editorStore.scheduleAutoApplyLightingEffect()
            })
    }

    private func secondaryColorBinding() -> Binding<RGBColor> {
        Binding(
            get: { editorStore.editableSecondaryColor },
            set: { color in
                editorStore.editableSecondaryColor = color
                editorStore.scheduleAutoApplyLightingEffect()
            })
    }

    @ViewBuilder private func onboardColorControls() -> some View {
        if editorStore.editableLightingEffect == .staticColor || !selected.supports_advanced_lighting_effects {
            VStack(alignment: .leading, spacing: 10) {
                if showsStaticLightingZoneControls {
                    HStack(spacing: 12) {
                        Text("Zones").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))
                        Spacer(minLength: 8)
                        Picker("", selection: Binding(get: { onboardZoneMode }, set: { onboardZoneMode = $0 })) { ForEach(LightingZoneEditMode.allCases) { mode in Text(mode.label).tag(mode) } }.labelsHidden().pickerStyle(.segmented).frame(width: 220).accessibilityIdentifier(
                            "lighting-zone-mode-picker")
                    }
                }

                if showsStaticLightingZoneControls && onboardZoneMode == .individualZones {
                    VStack(alignment: .leading, spacing: 8) { ForEach(editorStore.visibleUSBLightingZones) { zone in LightingColorOrbRow(title: zone.label, identifierPrefix: "lighting-zone-\(zone.id)", color: zoneColorBinding(zone), swatches: swatches) } }
                } else {
                    LightingColorOrbRow(title: showsStaticLightingZoneControls ? "All Zones" : "Color", identifierPrefix: "lighting-all-zones", color: allZonesColorBinding(), swatches: swatches)
                }
            }
        } else {
            if editorStore.editableLightingEffect.usesPrimaryColor { LightingColorOrbRow(title: "Primary Color", identifierPrefix: "lighting-primary-color", color: primaryColorBinding(), swatches: swatches) }

            if editorStore.editableLightingEffect.usesSecondaryColor { LightingColorOrbRow(title: "Secondary Color", identifierPrefix: "lighting-secondary-color", color: secondaryColorBinding(), swatches: swatches) }
        }
    }

    @ViewBuilder private func onboardControls(includePresetPicker: Bool = true) -> some View {
        lightingNotice(systemImage: "memorychip.fill", iconColor: actionAccent, text: "Onboard lighting is stored on the device and survives restart and reconnect.")

        if selected.supportsLightingBrightnessControls { brightnessControls().padding(.vertical, 2) }

        if includePresetPicker { onboardPresetPicker() }
        onboardEffectOptions()
        onboardColorControls()
    }

    var body: some View {
        Card(title: "Lighting", accessibilityIdentifier: "lighting-card") {
            lightingSummaryRow()

            if effectiveExpanded {
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.vertical, 2)

                if isLightingOnly {
                    unifiedLightingControls()
                } else {
                    tabPicker()

                    if activeTab == .advanced { advancedLightingControls() } else { onboardControls() }
                }
            }
        }.background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: lightingCardGradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))).onAppear { selectedTab = preferredLightingTab }.onChange(of: selected.id) {
            selectedTab = preferredLightingTab
            isExpanded = false
        }.onChange(of: editorStore.editableSoftwareLightingApplyOnConnect) { _, enabled in if enabled && selected.supportsSoftwareLightingEffects { selectedTab = .advanced } }
    }

    private func lightingSummaryRow() -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) { Text(lightingSummaryTitle).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.88)).lineLimit(1).accessibilityIdentifier("lighting-card-summary-text") }

            Spacer(minLength: 10)

            lightingSummaryBatteryIndicator()

            if !isLightingOnly {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() }
                } label: {
                    Label(isExpanded ? "Collapse" : "Expand", systemImage: isExpanded ? "chevron.up" : "chevron.down")
                }.buttonStyle(.bordered).controlSize(.small).accessibilityIdentifier("lighting-card-expand-button")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func lightingSummaryBatteryIndicator() -> some View {
        switch lightingSummaryPresentation.batteryIndicator {
        case .hidden:
            HStack(spacing: -3) { ForEach(Array(lightingSummarySwatches.enumerated()), id: \.offset) { _, color in Circle().fill(Color(rgb: color)).frame(width: 15, height: 15).overlay(Circle().stroke(Color.white.opacity(0.62), lineWidth: 1)) } }.padding(.horizontal, 3).accessibilityHidden(true)
        case let .level(batteryIcon, percent):
            HStack(spacing: 6) {
                Image(systemName: batteryIcon.symbolName, variableValue: batteryIcon.variableValue)
                Text("\(percent)%").font(.system(size: 13, weight: .black, design: .monospaced)).foregroundStyle(.white.opacity(0.82))
            }.font(.system(size: 17, weight: .bold)).foregroundStyle(batteryIcon.accent == .low ? BatteryPresentation.lowBatteryColor : .white.opacity(0.82)).frame(height: 18).accessibilityLabel("Battery Meter").accessibilityIdentifier("lighting-card-summary-battery-icon")
        case .unavailable:
            HStack(spacing: 6) {
                Image(systemName: "battery.0percent")
                Text("Battery unavailable")
            }.font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.58)).frame(height: 18).accessibilityLabel("Battery unavailable").accessibilityIdentifier("lighting-card-summary-battery-unavailable")
        }
    }

    @ViewBuilder private func advancedLightingControls() -> some View { softwareLightingControls(includePresetPicker: true) }

    @ViewBuilder private func softwareLightingControls(includePresetPicker: Bool) -> some View {
        if selected.supportsSoftwareLightingEffects {
            VStack(alignment: .leading, spacing: 10) {
                lightingNotice(systemImage: "bolt.horizontal.circle.fill", iconColor: actionAccent, text: "Advanced effects run only while OpenSnek is running.")

                if includePresetPicker {
                    HStack(spacing: 12) {
                        Text("Preset").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))

                        Spacer(minLength: 12)

                        Picker("", selection: Binding(get: { editorStore.editableSoftwareLightingPreset }, set: { editorStore.updateEditableSoftwareLightingPreset($0) })) { ForEach(editorStore.visibleSoftwareLightingPresets) { preset in Text(preset.label).tag(preset) } }.labelsHidden().pickerStyle(
                            .menu
                        ).frame(width: 190, alignment: .trailing).accessibilityIdentifier("software-lighting-preset-picker")
                    }
                }

                if editorStore.editableSoftwareLightingPreset.usesSpeedControl { softwareLightingSpeedControl() }
                softwareLightingBrightnessControl()

                if editorStore.editableSoftwareLightingPreset == .batteryMeter { softwareLightingBatteryThresholdControl() }

                if editorStore.editableSoftwareLightingPreset.usesPaletteControls {
                    SoftwareLightingPaletteEditor(
                        preset: editorStore.editableSoftwareLightingPreset,
                        palette: Binding(get: { editorStore.editableSoftwareLightingPalette(for: editorStore.editableSoftwareLightingPreset) }, set: { editorStore.setEditableSoftwareLightingPalette($0, for: editorStore.editableSoftwareLightingPreset) }), swatches: swatches,
                        onAdd: { editorStore.addEditableSoftwareLightingPaletteColor(for: editorStore.editableSoftwareLightingPreset) }, onRemove: { index in editorStore.removeEditableSoftwareLightingPaletteColor(at: index, for: editorStore.editableSoftwareLightingPreset) },
                        onReset: { editorStore.resetEditableSoftwareLightingPalette(for: editorStore.editableSoftwareLightingPreset) })
                }

                if let advancedStatusText { Text(advancedStatusText).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.58)).lineLimit(2).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("software-lighting-status-text") }

                softwareLightingActionRow()
            }
        }
    }

    private func softwareLightingActionRow() -> some View {
        HStack(spacing: 12) {
            softwareLightingApplyOnConnectToggle().frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                if softwareLightingIsRunning {
                    Button {
                        Task { await editorStore.stopSoftwareLighting() }
                    } label: {
                        Label("Stop", systemImage: "stop.fill").frame(minWidth: 106)
                    }.buttonStyle(.borderedProminent).controlSize(.large).tint(Color(hex: 0xFF453A)).accessibilityIdentifier("software-lighting-stop-button")
                }

                Button {
                    Task { await editorStore.startSoftwareLighting() }
                } label: {
                    Label("Apply", systemImage: "checkmark.circle.fill").frame(minWidth: softwareLightingIsRunning ? 106 : 148)
                }.buttonStyle(.borderedProminent).controlSize(.large).tint(actionAccent).accessibilityIdentifier("software-lighting-apply-button")
            }
        }
    }

    private func softwareLightingApplyOnConnectToggle() -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: Binding(get: { editorStore.editableSoftwareLightingApplyOnConnect }, set: { editorStore.updateSoftwareLightingApplyOnConnect($0) })) { Text("Apply on connect").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82)) }.toggleStyle(
                .checkbox
            ).accessibilityIdentifier("software-lighting-apply-on-connect-checkbox")

            Text("Starts the last applied effect automatically when this device connects.").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.58)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func lightingNotice(systemImage: String, iconColor: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)).foregroundStyle(iconColor)

            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.68)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func softwareLightingSpeedControl() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Speed").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text(editorStore.editableSoftwareLightingSpeed <= 0.001 ? "Static" : "\(Int(round(editorStore.editableSoftwareLightingSpeed * 100)))%").font(.system(size: 13, weight: .black, design: .monospaced)).foregroundStyle(.white)
            }

            Slider(value: Binding(get: { editorStore.editableSoftwareLightingSpeed * 100.0 }, set: { editorStore.editableSoftwareLightingSpeed = max(0.0, min(2.0, $0 / 100.0)) }), in: 0...200).tint(.white).accessibilityIdentifier("software-lighting-speed-slider")
        }
    }

    private func softwareLightingBrightnessControl() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Brightness").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text("\(Int(round(editorStore.editableSoftwareLightingBrightness * 100)))%").font(.system(size: 13, weight: .black, design: .monospaced)).foregroundStyle(.white)
            }

            Slider(value: Binding(get: { editorStore.editableSoftwareLightingBrightness * 100.0 }, set: { editorStore.editableSoftwareLightingBrightness = max(0.0, min(1.0, $0 / 100.0)) }), in: 0...100).tint(.white).accessibilityIdentifier("software-lighting-brightness-slider")
        }
    }

    private var batterySourceCandidates: [MouseDevice] { editorStore.deviceStore.devices.filter { $0.id != selected.id }.sorted { $0.product_name < $1.product_name } }

    private var showsBatterySourcePicker: Bool {
        guard editorStore.editableSoftwareLightingPreset == .batteryMeter, !batterySourceCandidates.isEmpty else { return false }
        return DeviceProfiles.resolve(vendorID: selected.vendor_id, productID: selected.product_id, transport: selected.transport)?.formFactor == .accessory
    }

    private var batteryMeterSourceState: MouseState? {
        BatteryMeterSourceSelection.state(
            BatteryMeterSourceSelectionInput(
                deviceID: selected.id, ownState: editorStore.deviceStore.state, explicitSourceDeviceID: editorStore.editableSoftwareLightingBatterySourceDeviceID, candidateDeviceIDs: editorStore.deviceStore.devices.map(\.id),
                unavailableSourceDeviceIDs: editorStore.deviceStore.usbUnavailableDeviceIDs, stateByDeviceID: editorStore.deviceStore.stateByDeviceID))
    }

    private func batterySourceLabel(_ device: MouseDevice) -> String {
        guard let percent = editorStore.deviceStore.stateByDeviceID[device.id]?.battery_percent else { return device.product_name }
        return "\(device.product_name) — \(percent)%"
    }

    private var batterySourceBinding: Binding<String?> {
        Binding(
            get: { editorStore.editableSoftwareLightingBatterySourceDeviceID },
            set: { deviceID in
                editorStore.updateSoftwareLightingBatterySourceDeviceID(deviceID)
                if case .software = selectedLightingMode { Task { await editorStore.startSoftwareLighting() } }
            })
    }

    private func softwareLightingBatteryThresholdControl() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsBatterySourcePicker {
                HStack(spacing: 12) {
                    Text("Battery source").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))

                    Spacer(minLength: 12)

                    Picker("", selection: batterySourceBinding) {
                        Text("Automatic").tag(String?.none)
                        ForEach(batterySourceCandidates) { device in Text(batterySourceLabel(device)).tag(String?.some(device.id)) }
                    }.labelsHidden().pickerStyle(.menu).frame(width: 220, alignment: .trailing).accessibilityIdentifier("software-lighting-battery-source-picker")
                }
            }

            HStack {
                Text("Low battery below").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text("\(editorStore.editableSoftwareLightingBatteryLowThreshold)%").font(.system(size: 13, weight: .black, design: .monospaced)).foregroundStyle(.white)
            }

            Slider(value: Binding(get: { Double(editorStore.editableSoftwareLightingBatteryLowThreshold) }, set: { editorStore.updateSoftwareLightingBatteryLowThreshold(Int($0.rounded())) }), in: 1...98).tint(.white).accessibilityIdentifier("software-lighting-battery-low-slider")

            HStack {
                Text("Medium battery below").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text("\(editorStore.editableSoftwareLightingBatteryMediumThreshold)%").font(.system(size: 13, weight: .black, design: .monospaced)).foregroundStyle(.white)
            }

            Slider(value: Binding(get: { Double(editorStore.editableSoftwareLightingBatteryMediumThreshold) }, set: { editorStore.updateSoftwareLightingBatteryMediumThreshold(Int($0.rounded())) }), in: 2...99).tint(.white).accessibilityIdentifier("software-lighting-battery-medium-slider")

            Text("Palette order sets the low, medium, and high battery colors. The low color flashes below its threshold.").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.58)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Defines lighting card tab values.
private enum LightingCardTab: String, CaseIterable, Identifiable {
    case onboard
    case advanced

    var id: String { rawValue }

    var label: String {
        switch self {
        case .onboard: return "Onboard"
        case .advanced: return "Advanced"
        }
    }
}

/// Inputs for selecting the battery state shown by the Battery Meter card summary.
struct BatteryMeterSourceSelectionInput {
    let deviceID: String
    var ownState: MouseState?
    var explicitSourceDeviceID: String?
    let candidateDeviceIDs: [String]
    var unavailableSourceDeviceIDs: Set<String> = []
    let stateByDeviceID: [String: MouseState]
}

/// Selects the battery state shown by the Battery Meter card summary.
enum BatteryMeterSourceSelection {
    /// The meter device's own battery wins. An explicitly selected source is honored even while it
    /// is unavailable and is never replaced by another device's battery; a source that is no longer
    /// connected or reachable reports unavailable rather than its last value. Automatic selection
    /// (no explicit source) uses the first currently connected candidate that reports a battery.
    static func state(_ input: BatteryMeterSourceSelectionInput) -> MouseState? {
        if let ownState = input.ownState, ownState.battery_percent != nil, !input.unavailableSourceDeviceIDs.contains(input.deviceID) { return ownState }
        if let explicitSourceDeviceID = input.explicitSourceDeviceID {
            guard input.candidateDeviceIDs.contains(explicitSourceDeviceID), !input.unavailableSourceDeviceIDs.contains(explicitSourceDeviceID) else { return nil }
            return input.stateByDeviceID[explicitSourceDeviceID]
        }
        return input.candidateDeviceIDs.first { !input.unavailableSourceDeviceIDs.contains($0) && input.stateByDeviceID[$0]?.battery_percent != nil }.flatMap { input.stateByDeviceID[$0] }
    }
}

/// Stores lighting summary presentation data.
struct LightingSummaryPresentation: Equatable {
    /// Battery indicator shown in the summary row.
    enum BatteryIndicator: Equatable {
        case hidden
        case level(BatteryIconPresentation, percent: Int)
        case unavailable
    }

    let title: String
    let swatches: [RGBColor]
    let batteryIndicator: BatteryIndicator

    static func make(_ input: LightingSummaryInput) -> LightingSummaryPresentation {
        if input.supportsSoftwareLightingEffects, let status = input.softwareLightingStatus, status.state != .stopped {
            let preset = status.request?.presetID ?? input.editableSoftwareLightingPreset
            if preset == .batteryMeter {
                // Battery-less accessories (for example the Mouse Dock) follow another device's
                // battery, so call out an unavailable source instead of showing a fake level or
                // silently substituting another device's battery.
                guard let batteryState = input.batteryState, let batteryPercent = batteryState.battery_percent else { return LightingSummaryPresentation(title: preset.label, swatches: [], batteryIndicator: .unavailable) }
                return LightingSummaryPresentation(title: preset.label, swatches: [], batteryIndicator: .level(batteryIcon(for: batteryState, percent: batteryPercent), percent: batteryPercent))
            }

            let palette = status.request?.palette.map { color in RGBColor(r: color.r, g: color.g, b: color.b) } ?? input.editableSoftwareLightingPalette
            return LightingSummaryPresentation(title: preset.label, swatches: condensedSwatches(from: palette, fallback: input.fallbackColor), batteryIndicator: .hidden)
        }

        return LightingSummaryPresentation(title: "Onboard \(input.onboardEffectLabel)", swatches: condensedSwatches(from: input.onboardColors, fallback: input.fallbackColor), batteryIndicator: .hidden)
    }

    private static func batteryIcon(for state: MouseState, percent: Int) -> BatteryIconPresentation { ServiceMenuBarPresentation.batteryIcon(percent: percent, charging: state.charging, thresholdRaw: state.low_battery_threshold_raw) }

    private static func condensedSwatches(from colors: [RGBColor], fallback: RGBColor) -> [RGBColor] {
        let source = colors.isEmpty ? [fallback] : colors
        var uniqueColors: [RGBColor] = []
        for color in source {
            if !uniqueColors.contains(color) { uniqueColors.append(color) }
            if uniqueColors.count == 6 { break }
        }
        return uniqueColors.isEmpty ? [fallback] : uniqueColors
    }
}

/// Stores lighting summary input data.
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

/// Defines lighting zone edit mode values.
private enum LightingZoneEditMode: String, CaseIterable, Identifiable {
    case allZones
    case individualZones

    var id: String { rawValue }

    var label: String {
        switch self {
        case .allZones: return "All Zones"
        case .individualZones: return "Individual Zones"
        }
    }
}
