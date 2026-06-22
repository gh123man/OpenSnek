import AppKit
import OpenSnekAppSupport
import SwiftUI
import OpenSnekCore

struct OnConnectBehaviorCard: View {
    let editorStore: EditorStore
    @State private var showsExpandedInfo = false

    private var connectBehaviorBinding: Binding<DeviceConnectBehavior> {
        Binding(
            get: { editorStore.connectBehavior },
            set: { editorStore.updateConnectBehavior($0) }
        )
    }

    private var selectedDescription: String {
        switch editorStore.connectBehavior {
        case .useMouseSettings:
            return "OpenSnek reads the current settings from the mouse when it connects and does not rewrite them automatically."
        case .restoreOpenSnekSettings:
            return "OpenSnek reapplies the last settings you changed here when this mouse connects."
        }
    }

    var body: some View {
        Card(title: "On Connect", accessibilityIdentifier: "on-connect-card") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("On Connect Behavior", selection: connectBehaviorBinding) {
                    Text("Use Mouse Settings").tag(DeviceConnectBehavior.useMouseSettings)
                    Text("Restore OpenSnek Settings").tag(DeviceConnectBehavior.restoreOpenSnekSettings)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityIdentifier("on-connect-picker")

                HStack(alignment: .top, spacing: 10) {
                    Text(selectedDescription)
                        .hintTextStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        showsExpandedInfo.toggle()
                    } label: {
                        Image(systemName: showsExpandedInfo ? "info.circle.fill" : "info.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showsExpandedInfo ? "Hide on connect details" : "Show on connect details")
                    .accessibilityIdentifier("on-connect-details-button")
                }

                if showsExpandedInfo {
                    Text("Choose Use OpenSnek Settings if you use this mouse with another computer or with Synapse. Vendor software can overwrite the live settings on reconnect, and this restores your OpenSnek setup.")
                        .hintTextStyle()
                }
            }
        }
    }
}

struct PollRateCard: View {
    let editorStore: EditorStore
    private let pollRates = [125, 500, 1000]

    var body: some View {
        Card(title: "Polling Rate", accessibilityIdentifier: "poll-rate-card") {
            LabeledControlRow(title: "Rate") {
                Picker(
                    "Rate",
                    selection: Binding(
                        get: { editorStore.editablePollRate },
                        set: { editorStore.editablePollRate = $0 }
                    )
                ) {
                    ForEach(pollRates, id: \.self) { rate in
                        Text("\(rate) Hz")
                            .tag(rate)
                            .accessibilityIdentifier("poll-rate-option-\(rate)")
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220, alignment: .trailing)
                .accessibilityLabel("Polling Rate")
                .accessibilityIdentifier("poll-rate-picker")
            }
        }
        .onChange(of: editorStore.editablePollRate) { _, _ in
            editorStore.scheduleAutoApplyPollRate()
        }
    }
}

struct SleepTimeoutCard: View {
    let editorStore: EditorStore

    var body: some View {
        Card(title: "Power Management", accessibilityIdentifier: "power-management-card") {
            HStack {
                Text("Sleep timeout")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(formatTimeout(editorStore.editableSleepTimeout))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            Slider(
                value: Binding(
                    get: { Double(editorStore.editableSleepTimeout) },
                    set: { newValue in
                        let quantized = Int(round(newValue / 15.0) * 15.0)
                        editorStore.editableSleepTimeout = max(60, min(900, quantized))
                        editorStore.scheduleAutoApplySleepTimeout()
                    }
                ),
                in: 60...900
            )
            .accessibilityIdentifier("sleep-timeout-slider")
        }
    }

    private func formatTimeout(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        let mins = clamped / 60
        let secs = clamped % 60
        return "\(mins)m \(String(format: "%02d", secs))s"
    }
}

struct LowBatteryThresholdCard: View {
    let editorStore: EditorStore

    var body: some View {
        Card(title: "Low Battery Threshold", accessibilityIdentifier: "low-battery-threshold-card") {
            HStack {
                Text("Threshold")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                let raw = max(0x0C, min(0x3F, editorStore.editableLowBatteryThresholdRaw))
                Text("~\(approxPercent(raw))%")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            Slider(
                value: Binding(
                    get: { Double(max(0x0C, min(0x3F, editorStore.editableLowBatteryThresholdRaw)) ) },
                    set: { newValue in
                        editorStore.editableLowBatteryThresholdRaw = max(0x0C, min(0x3F, Int(round(newValue))))
                        editorStore.scheduleAutoApplyLowBatteryThreshold()
                    }
                ),
                in: Double(0x0C)...Double(0x3F)
            )
            .accessibilityIdentifier("low-battery-threshold-slider")

            Text("Approximate warning level")
                .hintTextStyle()
        }
    }

    private func approxPercent(_ raw: Int) -> Int {
        BatteryPresentation.approximateThresholdPercent(raw: raw) ?? 5
    }
}

struct ScrollControlsCard: View {
    let editorStore: EditorStore
    let state: MouseState

    var body: some View {
        Card(title: "Scroll Controls", accessibilityIdentifier: "scroll-controls-card") {
            VStack(alignment: .leading, spacing: 12) {
                if state.scroll_mode != nil {
                    LabeledControlRow(title: "Wheel") {
                        Picker(
                            "Wheel",
                            selection: Binding(
                                get: { editorStore.editableScrollMode },
                                set: {
                                    editorStore.editableScrollMode = ($0 == 1 ? 1 : 0)
                                    editorStore.scheduleAutoApplyScrollMode()
                                }
                            )
                        ) {
                            Text("Tactile").tag(0)
                            Text("Free Spin").tag(1)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220, alignment: .trailing)
                        .accessibilityIdentifier("scroll-mode-picker")
                    }
                }

                if state.scroll_acceleration != nil {
                    LabeledControlRow(title: "Acceleration") {
                        Toggle(
                            "Acceleration",
                            isOn: Binding(
                                get: { editorStore.editableScrollAcceleration },
                                set: {
                                    editorStore.editableScrollAcceleration = $0
                                    editorStore.scheduleAutoApplyScrollAcceleration()
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                        .accessibilityIdentifier("scroll-acceleration-toggle")
                    }
                }

                if state.scroll_smart_reel != nil {
                    LabeledControlRow(title: "Smart Reel") {
                        Toggle(
                            "Smart Reel",
                            isOn: Binding(
                                get: { editorStore.editableScrollSmartReel },
                                set: {
                                    editorStore.editableScrollSmartReel = $0
                                    editorStore.scheduleAutoApplyScrollSmartReel()
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                        .accessibilityIdentifier("scroll-smart-reel-toggle")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
