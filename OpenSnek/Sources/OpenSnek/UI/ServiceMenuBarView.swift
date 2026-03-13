import AppKit
import SwiftUI

enum ServiceMenuBarPresentation {
    static func batterySymbolName(percent: Int, charging: Bool?) -> String {
        if charging == true {
            return "battery.100percent.bolt"
        }

        switch percent {
        case ..<13:
            return "battery.0"
        case ..<38:
            return "battery.25"
        case ..<63:
            return "battery.50"
        case ..<88:
            return "battery.75"
        default:
            return "battery.100percent"
        }
    }

    static func compactDpiText(for dpi: Int?) -> String? {
        guard let dpi, dpi > 0 else { return nil }
        guard dpi >= 1000 else { return "\(dpi)" }

        let thousands = Double(dpi) / 1000.0
        if dpi < 10_000 {
            let rounded = (thousands * 10).rounded() / 10
            if rounded == rounded.rounded() {
                return "\(Int(rounded))k"
            }
            return String(format: "%.1fk", rounded)
        }

        return "\(Int(thousands.rounded()))k"
    }
}

struct ServiceMenuBarView: View {
    let deviceStore: DeviceStore
    let editorStore: EditorStore
    let runtimeStore: RuntimeStore

    private var showsDeviceControls: Bool {
        deviceStore.selectedDevice != nil && deviceStore.state != nil
    }

    private var controlsEnabled: Bool {
        deviceStore.selectedDeviceControlsEnabled
    }

    private var showsDevicePicker: Bool {
        deviceStore.devices.count > 1
    }

    private var selectedDeviceIDBinding: Binding<String> {
        Binding(
            get: { deviceStore.selectedDeviceID ?? deviceStore.devices.first?.id ?? "" },
            set: { deviceID in
                guard deviceStore.devices.contains(where: { $0.id == deviceID }) else { return }
                deviceStore.selectDevice(deviceID)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statusRow
            if showsDeviceControls {
                VStack(alignment: .leading, spacing: 10) {
                    if !controlsEnabled, let message = deviceStore.selectedDeviceInteractionMessage {
                        Text(message)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        stagePicker
                        dpiSlider
                    }
                    .disabled(!controlsEnabled)
                    .opacity(controlsEnabled ? 1.0 : 0.45)

                    if let message = runtimeStore.compactStatusMessage {
                        Text(message)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            } else if let message = deviceStore.selectedDeviceInteractionMessage {
                Text(message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("Connect a supported mouse to edit DPI from the menu bar.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Divider()
            actionRow("Show Open Snek", systemImage: "rectangle.on.rectangle") {
                runtimeStore.openFullAppFromService()
            }
            actionRow("Settings…", systemImage: "gearshape") {
                runtimeStore.openSettingsFromService()
            }
            actionRow("Quit", systemImage: "power") {
                runtimeStore.terminateServiceProcess()
            }
        }
        .padding(16)
        .frame(width: 320)
        .task {
            await runtimeStore.start()
        }
        .task(id: deviceStore.selectedDeviceID) {
            guard let device = deviceStore.selectedDevice else { return }
            await deviceStore.refreshConnectionDiagnostics(for: device)
        }
        .onAppear {
            runtimeStore.setCompactMenuPresented(true)
        }
        .onDisappear {
            runtimeStore.setCompactMenuPresented(false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: showsDevicePicker ? 8 : 3) {
            if showsDevicePicker {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Picker("Device", selection: selectedDeviceIDBinding) {
                        ForEach(deviceStore.devices) { device in
                            Text("\(device.product_name) (\(device.transport.shortLabel))")
                                .tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(deviceStore.selectedDevice?.product_name ?? "No device connected")
                    .font(.system(size: 15, weight: .black, design: .rounded))
            }
            Text(deviceStore.selectedDevice?.connectionLabel ?? "Waiting for a supported mouse")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Label(deviceStore.currentDeviceStatusIndicator.label, systemImage: "circle.fill")
                .foregroundStyle(deviceStore.currentDeviceStatusIndicator.color)
                .font(.system(size: 11, weight: .bold, design: .rounded))

            Spacer()

            if let battery = deviceStore.state?.battery_percent {
                HStack(spacing: 4) {
                    Image(
                        systemName: ServiceMenuBarPresentation.batterySymbolName(
                            percent: battery,
                            charging: deviceStore.state?.charging
                        )
                    )
                    Text("\(battery)%")
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var stagePicker: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(1, editorStore.editableStageCount), id: \.self) { index in
                let stage = index + 1
                let isSelected = editorStore.editableActiveStage == stage
                Button {
                    if !isSelected {
                        editorStore.editableActiveStage = stage
                        editorStore.scheduleAutoApplyActiveStage()
                    }
                } label: {
                    Text("\(stage)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: 1)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dpiSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stage \(editorStore.editableActiveStage) DPI")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Text("\(editorStore.compactActiveStageValue)")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(editorStore.compactActiveStageValue) },
                    set: { newValue in
                        let quantized = Int(round(newValue / 100.0) * 100.0)
                        editorStore.updateStage(editorStore.compactActiveStageIndex, value: quantized)
                        editorStore.scheduleAutoApplyDpi()
                    }
                ),
                in: 100...30000,
                onEditingChanged: { editing in
                    editorStore.isEditingDpiControl = editing
                }
            )
        }
    }

    private func actionRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct ServiceMenuBarStatusItemLabel: View {
    let deviceStore: DeviceStore
    let editorStore: EditorStore

    private var currentDpi: Int? {
        guard deviceStore.state != nil else { return nil }

        if let liveDpi = deviceStore.state?.dpi?.x, liveDpi > 0 {
            return liveDpi
        }

        let fallback = editorStore.compactActiveStageValue
        return fallback > 0 ? fallback : nil
    }

    var body: some View {
        ServiceMenuBarStatusGlyph(isConnected: deviceStore.selectedDevice != nil)
            .frame(width: OpenSnekBranding.menuBarIconSide, height: OpenSnekBranding.menuBarIconSide)
            .fixedSize()
            .help(helpText)
            .accessibilityLabel(helpText)
    }

    private var helpText: String {
        if let device = deviceStore.selectedDevice, let currentDpi {
            return "\(device.product_name), \(currentDpi) DPI"
        }
        if let device = deviceStore.selectedDevice {
            return device.product_name
        }
        return "Open Snek"
    }
}

private struct ServiceMenuBarStatusGlyph: View {
    let isConnected: Bool

    private var iconOpacity: Double {
        isConnected ? 0.88 : 0.46
    }

    var body: some View {
        Group {
            if let menuIcon = OpenSnekBranding.menuIcon {
                Image(nsImage: menuIcon)
                    .renderingMode(.original)
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(iconOpacity), lineWidth: 1.2)

                    Rectangle()
                        .fill(Color.primary.opacity(iconOpacity))
                        .frame(width: 1, height: 11)

                    Rectangle()
                        .fill(Color.primary.opacity(iconOpacity))
                        .frame(width: 11, height: 1)

                    Circle()
                        .fill(Color.primary.opacity(iconOpacity))
                        .frame(width: 3.5, height: 3.5)
                }
            }
        }
        .opacity(iconOpacity)
        .frame(width: OpenSnekBranding.menuBarIconSide, height: OpenSnekBranding.menuBarIconSide)
    }
}
