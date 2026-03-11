import AppKit
import SwiftUI

struct ServiceMenuBarView: View {
    @Bindable var appState: AppState

    private var showsDeviceControls: Bool {
        appState.selectedDevice != nil && appState.state != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            statusRow
            if showsDeviceControls {
                stagePicker
                dpiSlider
                if let message = appState.compactStatusMessage {
                    Text(message)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Connect a supported mouse to edit DPI from the menu bar.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Divider()
            actionRow("Refresh") {
                Task { await appState.refreshNow() }
            }
            actionRow("Open Open Snek") {
                appState.openFullAppFromService()
            }
            actionRow("Settings…") {
                appState.openSettingsFromService()
            }
            actionRow("Quit Service") {
                appState.terminateServiceProcess()
            }
        }
        .padding(16)
        .frame(width: 320)
        .task {
            await appState.start()
        }
        .onAppear {
            appState.setCompactMenuPresented(true)
        }
        .onDisappear {
            appState.setCompactMenuPresented(false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(appState.selectedDevice?.product_name ?? "No device connected")
                .font(.system(size: 15, weight: .black, design: .rounded))
            Text(appState.selectedDevice?.connectionLabel ?? "Waiting for a supported mouse")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            Label(appState.currentDeviceStatusIndicator.label, systemImage: "circle.fill")
                .foregroundStyle(appState.currentDeviceStatusIndicator.color)
                .font(.system(size: 11, weight: .bold, design: .rounded))

            Spacer()

            if let battery = appState.state?.battery_percent {
                Text("\(battery)%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stagePicker: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(1, appState.editableStageCount), id: \.self) { index in
                let stage = index + 1
                Button {
                    if appState.editableActiveStage != stage {
                        appState.editableActiveStage = stage
                        appState.scheduleAutoApplyActiveStage()
                    }
                } label: {
                    Text("\(stage)")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(
                    Capsule()
                        .fill(appState.editableActiveStage == stage ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .overlay(
                    Capsule()
                        .stroke(appState.editableActiveStage == stage ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: 1)
                )
            }
        }
    }

    private var dpiSlider: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stage \(appState.editableActiveStage) DPI")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Text("\(appState.compactActiveStageValue)")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(appState.compactActiveStageValue) },
                    set: { newValue in
                        let quantized = Int(round(newValue / 100.0) * 100.0)
                        appState.updateStage(appState.compactActiveStageIndex, value: quantized)
                        appState.scheduleAutoApplyDpi()
                    }
                ),
                in: 100...30000,
                onEditingChanged: { editing in
                    appState.isEditingDpiControl = editing
                }
            )
        }
    }

    private func actionRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
