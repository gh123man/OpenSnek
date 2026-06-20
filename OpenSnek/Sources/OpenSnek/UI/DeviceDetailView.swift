import AppKit
import OpenSnekAppSupport
import SwiftUI
import OpenSnekCore

struct DeviceDetailView: View {
    let deviceStore: DeviceStore
    let editorStore: EditorStore
    let selected: MouseDevice
    let state: MouseState
    private let cardSpacing: CGFloat = 14
    private let detailTwoColumnMinWidth: CGFloat = 360
    private let twoColumnBreakpointPadding: CGFloat = 100
    private let detailCardMaxWidth: CGFloat = 560
    private let detailContentMaxWidth: CGFloat = 1400
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 18

    private let swatches: [LightingSwatch] = [
        LightingSwatch(hex: 0xFF0000), LightingSwatch(hex: 0x00FF00), LightingSwatch(hex: 0x0000FF), LightingSwatch(hex: 0xFFFF00),
        LightingSwatch(hex: 0x00FFFF), LightingSwatch(hex: 0xFF00FF), LightingSwatch(hex: 0xFFFFFF), LightingSwatch(hex: 0xFF8000),
    ]

    var body: some View {
        GeometryReader { proxy in
            let sections = detailSections
            let contentWidth = detailContentWidth(for: proxy.size.width)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    DeviceOverviewBar(deviceStore: deviceStore, editorStore: editorStore, selected: selected, state: state)
                    DetailColumnsLayout(
                        minTwoColumnCardWidth: detailTwoColumnMinWidth,
                        twoColumnBreakpointPadding: twoColumnBreakpointPadding,
                        spacing: cardSpacing,
                        maxCardWidth: detailCardMaxWidth
                    ) {
                        ForEach(sections, id: \.self) { section in
                            detailCard(for: section)
                                .layoutValue(key: PreferredDetailColumnLayoutKey.self, value: preferredColumn(for: section))
                                .layoutValue(key: DetailCardMaxWidthLayoutKey.self, value: section == .buttonRemap ? detailContentMaxWidth : detailCardMaxWidth)
                        }
                    }
                    DiagnosticsFooter(deviceStore: deviceStore, device: selected, state: state)
                }
                .frame(width: contentWidth, alignment: .leading)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .accessibilityIdentifier("device-detail-scroll-view")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(WindowDragBlocker())
            .loadingScrim(
                isPresented: editorStore.isButtonProfileOperationInFlight || editorStore.isOnboardProfileLoadInFlight,
                label: editorStore.buttonProfileOperationStatusText ?? editorStore.onboardProfileLoadStatusText
            )
            .task(id: selected.id) {
                await deviceStore.refreshConnectionDiagnostics(for: selected)
            }
        }
    }

    private var detailSections: [DetailSection] {
        var sections: [DetailSection] = []
        if state.capabilities.dpi_stages {
            sections.append(.dpiStages)
        }
        if editorStore.showsConnectBehaviorCard {
            sections.append(.onConnect)
        }
        if selected.showsLightingControls, state.capabilities.lighting {
            sections.append(.lighting)
        }
        if state.capabilities.power_management {
            sections.append(.powerManagement)
        }
        if selected.transport != .bluetooth, state.capabilities.poll_rate {
            sections.append(.pollRate)
        }
        if selected.transport != .bluetooth, state.low_battery_threshold_raw != nil {
            sections.append(.lowBatteryThreshold)
        }
        if selected.transport != .bluetooth,
           state.scroll_mode != nil || state.scroll_acceleration != nil || state.scroll_smart_reel != nil {
            sections.append(.scrollControls)
        }
        if state.capabilities.button_remap {
            sections.append(.buttonRemap)
        }
        return sections
    }

    @ViewBuilder
    private func detailCard(for section: DetailSection) -> some View {
        switch section {
        case .dpiStages:
            DpiStagesCard(editorStore: editorStore)
        case .onConnect:
            OnConnectBehaviorCard(editorStore: editorStore)
        case .lighting:
            LightingCard(editorStore: editorStore, selected: selected, swatches: swatches)
        case .pollRate:
            PollRateCard(editorStore: editorStore)
        case .powerManagement:
            SleepTimeoutCard(editorStore: editorStore)
        case .lowBatteryThreshold:
            LowBatteryThresholdCard(editorStore: editorStore)
        case .scrollControls:
            ScrollControlsCard(editorStore: editorStore, state: state)
        case .buttonRemap:
            ButtonMappingTableCard(deviceStore: deviceStore, editorStore: editorStore, title: "Buttons")
        }
    }

    private func detailContentWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max(availableWidth - (horizontalPadding * 2), 0), detailContentMaxWidth)
    }

    private func preferredColumn(for section: DetailSection) -> Int {
        switch section {
        case .lighting, .buttonRemap:
            return 1
        default:
            return 0
        }
    }
}

private enum DetailSection: Hashable {
    case dpiStages
    case onConnect
    case lighting
    case pollRate
    case powerManagement
    case lowBatteryThreshold
    case scrollControls
    case buttonRemap
}

struct LightingSwatch: Identifiable, Hashable {
    let hex: UInt32
    let color: Color
    let rgb: OpenSnekCore.RGBColor

    init(hex: UInt32) {
        self.hex = hex
        self.color = Color(hex: hex)
        self.rgb = OpenSnekCore.RGBColor(
            r: Int((hex >> 16) & 0xFF),
            g: Int((hex >> 8) & 0xFF),
            b: Int(hex & 0xFF)
        )
    }

    var id: UInt32 { hex }
}

private struct PreferredDetailColumnLayoutKey: LayoutValueKey {
    static let defaultValue = -1
}

private struct DetailCardMaxWidthLayoutKey: LayoutValueKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude
}

private struct DetailColumnsLayout: Layout {
    let minTwoColumnCardWidth: CGFloat
    let twoColumnBreakpointPadding: CGFloat
    let spacing: CGFloat
    let maxCardWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: proposal, subviews: subviews)
        let width = proposal.width ?? frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(for: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, frame) in frames.enumerated() {
            let placed = CGRect(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY, width: frame.width, height: frame.height)
            subviews[index].place(
                at: placed.origin,
                proposal: ProposedViewSize(width: placed.width, height: placed.height)
            )
        }
    }

    private func frames(for proposal: ProposedViewSize, subviews: Subviews) -> [CGRect] {
        let availableWidth = proposal.width ?? 0
        let useTwoColumns = availableWidth >= ((minTwoColumnCardWidth * 2) + spacing + twoColumnBreakpointPadding)

        if !useTwoColumns {
            return singleColumnFrames(for: availableWidth, subviews: subviews)
        }

        return twoColumnFrames(for: availableWidth, subviews: subviews)
    }

    private func singleColumnFrames(for width: CGFloat, subviews: Subviews) -> [CGRect] {
        let resolvedWidth = max(width, 0)
        var y: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let proposedWidth = resolvedWidth
            let size = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
            let x = (resolvedWidth - proposedWidth) / 2
            frames.append(CGRect(x: x, y: y, width: proposedWidth, height: size.height))
            y += size.height + spacing
        }

        return frames
    }

    private func twoColumnFrames(for width: CGFloat, subviews: Subviews) -> [CGRect] {
        let totalWidth = max(width, 0)
        let nominalColumnWidth = min(maxCardWidth, floor((totalWidth - spacing) / 2))
        let contentWidth = (nominalColumnWidth * 2) + spacing
        let originX = max((totalWidth - contentWidth) / 2, 0)
        var columnHeights: [CGFloat] = [0, 0]
        var balancedColumn = 0
        var frames: [CGRect] = Array(repeating: .zero, count: subviews.count)

        for (index, subview) in subviews.enumerated() {
            let preferredColumn = subview[PreferredDetailColumnLayoutKey.self]
            let column = preferredColumn == 0 || preferredColumn == 1 ? preferredColumn : balancedColumn
            if preferredColumn != 0 && preferredColumn != 1 {
                balancedColumn = (balancedColumn + 1) % 2
            }

            let cardMaxWidth = min(subview[DetailCardMaxWidthLayoutKey.self], nominalColumnWidth)
            let proposedWidth = min(nominalColumnWidth, cardMaxWidth)
            let size = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
            let x = originX + CGFloat(column) * (nominalColumnWidth + spacing) + ((nominalColumnWidth - proposedWidth) / 2)
            let y = columnHeights[column]
            frames[index] = CGRect(x: x, y: y, width: proposedWidth, height: size.height)
            columnHeights[column] += size.height + spacing
        }

        return frames
    }
}

struct DeviceOverviewBar: View {
    let deviceStore: DeviceStore
    let editorStore: EditorStore
    let selected: MouseDevice
    let state: MouseState
    @State private var isOnboardProfileManagerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selected.product_name)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("selected-device-name")
                        .accessibilityLabel(selected.product_name)
                    if showsUnsupportedUSBMarker {
                        UnsupportedUSBInlineBanner()
                    }
                    if let serial = state.device.serial {
                        Text("Serial \(serial)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    if let dpi = state.dpi {
                        Text("DPI \(dpi.x)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.76))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if let battery = state.battery_percent {
                        let batteryIcon = BatteryPresentation.icon(
                            percent: battery,
                            charging: state.charging,
                            thresholdRaw: state.low_battery_threshold_raw
                        )
                        HStack(spacing: 8) {
                            Image(
                                systemName: batteryIcon.symbolName,
                                variableValue: batteryIcon.variableValue
                            )
                            Text("\(battery)%")
                        }
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(batteryIcon.accent == .low ? BatteryPresentation.lowBatteryColor : .white)
                    }
                }
            }

            HStack(spacing: 10) {
                Pill(
                    text: state.connection,
                    color: selected.transport == .bluetooth ? Color(hex: 0x66D9FF) : Color(hex: 0xA8F46A)
                )
                .accessibilityIdentifier("selected-device-connection")
                DeviceStatusBadge(
                    indicator: deviceStore.currentDeviceStatusIndicator,
                    helpText: deviceStore.currentDeviceConnectionTooltip
                )

                if editorStore.supportsOnboardProfileCRUD {
                    Spacer(minLength: 12)
                    Text("Profile")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.50))
                    OnboardProfilePillButton(editorStore: editorStore) {
                        isOnboardProfileManagerPresented.toggle()
                    }
                    .popover(
                        isPresented: $isOnboardProfileManagerPresented,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .top
                    ) {
                        OnboardProfileManagerPopover(editorStore: editorStore)
                    }
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
        }
        .task(id: selected.id) {
            guard editorStore.supportsOnboardProfileCRUD else { return }
            await editorStore.refreshOnboardProfiles()
        }
        .onChange(of: selected.id) { _, _ in
            isOnboardProfileManagerPresented = false
        }
        .zIndex(6)
    }

    private var showsUnsupportedUSBMarker: Bool {
        deviceStore.selectedDeviceIsUnsupportedUSB && deviceStore.selectedDeviceID == selected.id
    }
}

struct GenericDeviceDetailView: View {
    let deviceStore: DeviceStore
    let selected: MouseDevice

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                GenericDeviceOverviewBar(deviceStore: deviceStore, selected: selected)

                if resolvedProfile == nil {
                    Card(title: "Limited Support") {
                        Text(primaryMessage)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(secondaryMessage)
                            .hintTextStyle()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 6) {
                            diagnosticRow(label: "Vendor ID", value: String(format: "0x%04X", selected.vendor_id))
                            diagnosticRow(label: "Product ID", value: String(format: "0x%04X", selected.product_id))
                            diagnosticRow(label: "Location ID", value: String(format: "0x%08X", selected.location_id))
                            diagnosticRow(label: "Transport", value: selected.transport.connectionLabel)
                            diagnosticRow(label: "Resolved profile", value: "None")
                        }
                        .padding(.top, 2)
                    }
                }

                DiagnosticsFooter(deviceStore: deviceStore, device: selected, state: nil)
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WindowDragBlocker())
    }

    private var resolvedProfile: DeviceProfile? {
        DeviceProfiles.resolve(
            vendorID: selected.vendor_id,
            productID: selected.product_id,
            transport: selected.transport
        )
    }

    private var primaryMessage: String {
        "This mouse is not fully supported yet."
    }

    private var secondaryMessage: String {
        "OpenSnek will show the controls it can verify safely. Use Diagnostics in bug reports so unsupported devices are easier to map."
    }

    @ViewBuilder
    private func diagnosticRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DeviceUnavailableDetailView: View {
    let deviceStore: DeviceStore
    let selected: MouseDevice

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                GenericDeviceOverviewBar(deviceStore: deviceStore, selected: selected)

                Card(title: deviceStore.currentDeviceStatusIndicator.label) {
                    Text(deviceStore.selectedDeviceInteractionMessage ?? "Live telemetry is unavailable for this device right now.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("The controls stay locked until the device reconnects and OpenSnek is receiving live updates again.")
                        .hintTextStyle()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(deviceStore.diagnosticsConnectionLines(for: selected), id: \.self) { line in
                            Text(line)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                    }
                    .padding(.top, 2)
                }

                DiagnosticsFooter(deviceStore: deviceStore, device: selected, state: nil)
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WindowDragBlocker())
        .task(id: selected.id) {
            await deviceStore.refreshConnectionDiagnostics(for: selected)
        }
    }
}

struct DeviceConnectingDetailView: View {
    let deviceStore: DeviceStore
    let selected: MouseDevice

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 18) {
                GenericDeviceOverviewBar(deviceStore: deviceStore, selected: selected)

                VStack(spacing: 18) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white.opacity(0.92))

                    VStack(spacing: 8) {
                        Text(headline)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text(subtitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 42)
                .background(
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )

                DiagnosticsFooter(deviceStore: deviceStore, device: selected, state: nil)
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WindowDragBlocker())
        .task(id: selected.id) {
            await deviceStore.refreshConnectionDiagnostics(for: selected)
        }
    }

    private var headline: String {
        switch selected.transport {
        case .bluetooth:
            "Connecting to \(selected.product_name)"
        case .usb:
            "Loading \(selected.product_name)"
        }
    }

    private var subtitle: String {
        switch selected.transport {
        case .bluetooth:
            "Establishing the Bluetooth control link and reading your settings."
        case .usb:
            "Reading device settings and preparing controls."
        }
    }
}

struct GenericDeviceOverviewBar: View {
    let deviceStore: DeviceStore
    let selected: MouseDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selected.product_name)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    if showsUnsupportedUSBMarker {
                        UnsupportedUSBInlineBanner()
                    }
                    if let serial = selected.serial {
                        Text("Serial \(serial)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Pill(
                    text: selected.connectionLabel,
                    color: selected.transport == .bluetooth ? Color(hex: 0x66D9FF) : Color(hex: 0xA8F46A)
                )
                DeviceStatusBadge(
                    indicator: deviceStore.currentDeviceStatusIndicator,
                    helpText: deviceStore.currentDeviceConnectionTooltip
                )
            }

            Rectangle()
                .fill(Color.white.opacity(0.14))
                .frame(height: 1)
        }
        .zIndex(6)
    }

    private var showsUnsupportedUSBMarker: Bool {
        deviceStore.selectedDeviceIsUnsupportedUSB && deviceStore.selectedDeviceID == selected.id
    }
}

private struct UnsupportedUSBInlineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("⚠️")
                .font(.system(size: 12))
            Text("Unsupported USB device. Only verified controls are shown.")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color(hex: 0xFF9F0A).opacity(0.18))
                .overlay(
                    Capsule()
                        .stroke(Color(hex: 0xFF9F0A).opacity(0.42), lineWidth: 1)
                )
        )
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DiagnosticsFooter: View {
    let deviceStore: DeviceStore
    let device: MouseDevice
    let state: MouseState?

    var body: some View {
        HStack {
            Spacer()
            DeviceDiagnosticsButton(deviceStore: deviceStore, device: device, state: state)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }
}

struct DeviceStatusBadge: View {
    let indicator: DeviceStatusIndicator
    var helpText: String?

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicator.color)
                .frame(width: 9, height: 9)
                .shadow(color: indicator.color.opacity(0.45), radius: 6, y: 0)

            Text(indicator.label)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .accessibilityIdentifier("device-status-label")
                .accessibilityLabel(indicator.label)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .contentShape(Capsule())
        .hoverTooltip(helpText, xOffset: 6, yOffset: 34, maxWidth: 360)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(indicator.label)
        .accessibilityIdentifier("device-status-badge")
    }
}

struct DeviceDiagnosticsButton: View {
    let deviceStore: DeviceStore
    let device: MouseDevice
    let state: MouseState?
    @State private var showsDiagnostics = false

    var body: some View {
        Button {
            showsDiagnostics = true
        } label: {
            Label("Diagnostics", systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 11, weight: .black, design: .rounded))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(.white.opacity(0.2))
        .sheet(isPresented: $showsDiagnostics) {
            DeviceDiagnosticsSheet(deviceStore: deviceStore, device: device, state: state)
        }
    }
}

struct DeviceDiagnosticsSheet: View {
    let deviceStore: DeviceStore
    let device: MouseDevice
    let state: MouseState?
    @Environment(\.dismiss) private var dismiss

    private var diagnosticsText: String {
        deviceStore.diagnosticsDump(for: device, state: state)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Device Diagnostics")
                        .font(.system(size: 21, weight: .black, design: .rounded))
                    Text(device.product_name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Copy") {
                    copyDiagnostics()
                }
                .buttonStyle(.borderedProminent)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

            Text("Use this dump in bug reports when a device is unsupported, partially supported, or behaving unexpectedly.")
                .hintTextStyle()

            VStack(alignment: .leading, spacing: 6) {
                Text("Connection Paths")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                ForEach(deviceStore.diagnosticsConnectionLines(for: device), id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )

            ScrollView {
                Text(diagnosticsText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 540, alignment: .topLeading)
        .task(id: device.id) {
            await deviceStore.refreshConnectionDiagnostics(for: device)
        }
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText, forType: .string)
    }
}

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
            Color.white.opacity(0.05),
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
                Color.white.opacity(0.05),
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

    private var summarizesSoftwareLighting: Bool {
        selected.supportsSoftwareLightingEffects && softwareLightingIsRunning
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

    static func make(
        supportsSoftwareLightingEffects: Bool,
        softwareLightingStatus: SoftwareLightingEngineStatus?,
        editableSoftwareLightingPreset: SoftwareLightingPresetID,
        editableSoftwareLightingPalette: [RGBColor],
        onboardEffectLabel: String,
        onboardColors: [RGBColor],
        fallbackColor: RGBColor,
        batteryState: MouseState?
    ) -> LightingSummaryPresentation {
        if supportsSoftwareLightingEffects,
           softwareLightingStatus?.state == .running {
            let preset = softwareLightingStatus?.request?.presetID ?? editableSoftwareLightingPreset
            if preset == .batteryMeter {
                return LightingSummaryPresentation(
                    title: preset.label,
                    swatches: [],
                    batteryIcon: batteryIcon(for: batteryState)
                )
            }

            let palette = softwareLightingStatus?.request?.palette.map { color in
                RGBColor(r: color.r, g: color.g, b: color.b)
            } ?? editableSoftwareLightingPalette
            return LightingSummaryPresentation(
                title: preset.label,
                swatches: condensedSwatches(from: palette, fallback: fallbackColor),
                batteryIcon: nil
            )
        }

        return LightingSummaryPresentation(
            title: "Onboard \(onboardEffectLabel)",
            swatches: condensedSwatches(from: onboardColors, fallback: fallbackColor),
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(palette.indices), id: \.self) { index in
                        VStack(spacing: 5) {
                            LightingColorOrbPicker(
                                title: "\(preset.label) palette color \(index + 1)",
                                identifierPrefix: "software-lighting-palette-\(index)",
                                color: paletteBinding(index),
                                swatches: swatches
                            )

                            if maximumPaletteColorCount > 1 {
                                Button {
                                    onRemove(index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(palette.count > 1 ? Color.white.opacity(0.62) : Color.white.opacity(0.24))
                                .disabled(palette.count <= 1)
                                .help("Remove color")
                                .accessibilityLabel("Remove palette color \(index + 1)")
                                .accessibilityIdentifier("software-lighting-palette-\(index)-remove-button")
                            } else {
                                Color.clear
                                    .frame(width: 13, height: 13)
                            }
                        }
                        .frame(width: 44)
                    }

                    if maximumPaletteColorCount > 1 {
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
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
            }
            .accessibilityIdentifier("software-lighting-palette-list")
        }
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

struct LightingColorEditor: View {
    let title: String
    var identifierPrefix: String? = nil
    @Binding var color: OpenSnekCore.RGBColor
    let swatches: [LightingSwatch]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))

            HStack(spacing: 8) {
                ForEach(swatches) { swatch in
                    ColorSwatchButton(
                        color: swatch.color,
                        isSelected: swatch.rgb == color,
                        action: { color = swatch.rgb }
                    )
                }
            }

            RGBSliderRow(
                label: "R",
                accessibilityIdentifier: identifierPrefix.map { "\($0)-red-slider" },
                tint: Color.red,
                value: Binding(
                    get: { color.r },
                    set: { color.r = max(0, min(255, $0)) }
                )
            )

            RGBSliderRow(
                label: "G",
                accessibilityIdentifier: identifierPrefix.map { "\($0)-green-slider" },
                tint: Color.green,
                value: Binding(
                    get: { color.g },
                    set: { color.g = max(0, min(255, $0)) }
                )
            )

            RGBSliderRow(
                label: "B",
                accessibilityIdentifier: identifierPrefix.map { "\($0)-blue-slider" },
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
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .optionalAccessibilityIdentifier(identifierPrefix.map { "\($0)-editor" })
    }
}

struct RGBSliderRow: View {
    let label: String
    var accessibilityIdentifier: String? = nil
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

struct DpiStagesCard: View {
    let editorStore: EditorStore

    var body: some View {
        _ = editorStore.onboardProfilesRevision
        let profileID = editorStore.selectedDeviceProfileID
        let supportsIndependentXYDPI = editorStore.selectedDeviceSupportsIndependentXYDPI
        let supportsMultiStage = true
        let stageCount = supportsMultiStage ? editorStore.editableStageCount : 1
        return Card(title: "DPI Stages", accessibilityIdentifier: "dpi-stages-card") {
            HStack {
                Text(
                    supportsMultiStage
                        ? "Enabled stages: \(editorStore.editableStageCount) / 5"
                        : "Single-stage DPI"
                )
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        guard supportsMultiStage else { return }
                        let next = max(1, editorStore.editableStageCount - 1)
                        guard next != editorStore.editableStageCount else { return }
                        editorStore.editableStageCount = next
                        editorStore.setEditableActiveStage(
                            min(editorStore.editableActiveStage, editorStore.editableStageCount),
                            source: "ui.detail.stageCount.decrease"
                        )
                        editorStore.normalizeExpandedXYStages()
                        editorStore.scheduleAutoApplyDpi()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(supportsMultiStage && editorStore.editableStageCount > 1 ? .white : .white.opacity(0.35))
                    .disabled(!supportsMultiStage || editorStore.editableStageCount <= 1)
                    .accessibilityIdentifier("dpi-stage-count-decrease-button")

                    Button {
                        guard supportsMultiStage else { return }
                        let next = min(5, editorStore.editableStageCount + 1)
                        guard next != editorStore.editableStageCount else { return }
                        editorStore.editableStageCount = next
                        editorStore.normalizeExpandedXYStages()
                        editorStore.scheduleAutoApplyDpi()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(supportsMultiStage && editorStore.editableStageCount < 5 ? .white : .white.opacity(0.35))
                    .disabled(!supportsMultiStage || editorStore.editableStageCount >= 5)
                    .accessibilityIdentifier("dpi-stage-count-increase-button")
                }
            }

            ForEach(0..<stageCount, id: \.self) { idx in
                let isSelectedStage = stageCount == 1 || editorStore.editableActiveStage == (idx + 1)
                let stageColor = stageAccent(for: idx, isSelected: isSelectedStage)
                let stagePair = editorStore.stagePair(idx)
                let isXYExpanded = supportsIndependentXYDPI && editorStore.isStageXYExpanded(idx)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        stageHeader(for: idx, stageCount: stageCount, stageColor: stageColor, isSelectedStage: isSelectedStage)

                        Spacer()

                        if isXYExpanded {
                            HStack(spacing: 8) {
                                axisTextField(label: "X", value: stagePair.x, stageIndex: idx) { parsed in
                                    editorStore.updateStageX(idx, value: parsed)
                                    editorStore.scheduleAutoApplyDpi()
                                }
                                axisTextField(label: "Y", value: stagePair.y, stageIndex: idx) { parsed in
                                    editorStore.updateStageY(idx, value: parsed)
                                    editorStore.scheduleAutoApplyDpi()
                                }
                            }
                        } else {
                            DpiValueField(
                                placeholder: "DPI",
                                value: editorStore.stageValue(idx),
                                width: 100,
                                accessibilityIdentifier: "dpi-stage-\(idx + 1)-value-field"
                            ) { parsed in
                                editorStore.updateStage(idx, value: parsed)
                                editorStore.scheduleAutoApplyDpi()
                            }
                        }

                        if supportsIndependentXYDPI {
                            xyToggleButton(isExpanded: isXYExpanded, tint: stageColor) {
                                if editorStore.toggleStageXYExpansion(idx) {
                                    editorStore.scheduleAutoApplyDpi()
                                }
                            }
                        }
                    }

                    if supportsIndependentXYDPI && !isXYExpanded && stagePair.x != stagePair.y {
                        Text("Current split: X \(stagePair.x) / Y \(stagePair.y)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.62))
                    }

                    if isXYExpanded {
                        axisSlider(
                            label: "X",
                            value: stagePair.x,
                            stageIndex: idx,
                            profileID: profileID,
                            tint: isSelectedStage ? stageColor : Color.white.opacity(0.80)
                        ) { quantized in
                            editorStore.updateStageX(idx, value: quantized)
                            editorStore.scheduleAutoApplyDpi()
                        }
                        axisSlider(
                            label: "Y",
                            value: stagePair.y,
                            stageIndex: idx,
                            profileID: profileID,
                            tint: isSelectedStage ? stageColor.opacity(0.8) : Color.white.opacity(0.65)
                        ) { quantized in
                            editorStore.updateStageY(idx, value: quantized)
                            editorStore.scheduleAutoApplyDpi()
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: {
                                        DeviceProfiles.dpiSliderPosition(
                                            for: editorStore.stageValue(idx),
                                            profileID: profileID
                                        )
                                    },
                                    set: { newPosition in
                                        editorStore.updateStage(
                                            idx,
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
                            .tint(isSelectedStage ? stageColor : Color.white.opacity(0.80))
                            .accessibilityIdentifier("dpi-stage-\(idx + 1)-slider")

                            DpiSliderScaleMarkers(
                                profileID: profileID,
                                markerColor: isSelectedStage ? stageColor : Color.white.opacity(0.72)
                            )
                        }
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelectedStage ? stageColor.opacity(0.24) : stageColor.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isSelectedStage ? stageColor.opacity(0.95) : stageColor.opacity(0.35), lineWidth: isSelectedStage ? 2 : 1)
                        )
                )
                .shadow(color: isSelectedStage ? stageColor.opacity(0.30) : .clear, radius: 12, y: 0)
            }
        }
    }

    private func axisTextField(label: String, value: Int, stageIndex: Int, onCommit: @escaping (Int) -> Void) -> some View {
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

    private func xyToggleButton(isExpanded: Bool, tint: Color, action: @escaping () -> Void) -> some View {
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

    private func axisSlider(
        label: String,
        value: Int,
        stageIndex: Int,
        profileID: DeviceProfileID?,
        tint: Color,
        onChange: @escaping (Int) -> Void
    ) -> some View {
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

    @ViewBuilder
    private func stageHeader(for index: Int, stageCount: Int, stageColor: Color, isSelectedStage: Bool) -> some View {
        if stageCount == 1 {
            Text("DPI")
                .foregroundStyle(stageColor)
        } else {
            Button {
                let selected = index + 1
                if editorStore.editableActiveStage != selected {
                    editorStore.setEditableActiveStage(selected, source: "ui.detail.stageHeader")
                    editorStore.scheduleAutoApplyActiveStage()
                }
            } label: {
                Label(
                    "Stage \(index + 1)",
                    systemImage: editorStore.editableActiveStage == (index + 1) ? "checkmark.square.fill" : "square"
                )
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isSelectedStage ? stageColor.opacity(0.18) : Color.white.opacity(0.05))
                )
                .overlay(
                    Capsule()
                        .stroke(isSelectedStage ? stageColor.opacity(0.95) : Color.white.opacity(0.16), lineWidth: 1)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(isSelectedStage ? stageColor : .white)
            .accessibilityIdentifier("dpi-stage-\(index + 1)-select-button")
        }
    }

    private func stageAccent(for index: Int, isSelected: Bool) -> Color {
        switch index {
        case 0: return Color(hex: isSelected ? 0xFF6B61 : 0xFF3B30) // Red
        case 1: return Color(hex: isSelected ? 0x5BEB7E : 0x34C759) // Green
        case 2: return Color(hex: isSelected ? 0x4FA7FF : 0x0A84FF) // Blue
        case 3: return Color(hex: isSelected ? 0x36F0E8 : 0x00C7BE) // Teal
        default: return Color(hex: isSelected ? 0xFFE35A : 0xFFD60A) // Yellow
        }
    }
}

private struct DpiValueField: View {
    let placeholder: String
    let value: Int
    let width: CGFloat
    var alignment: TextAlignment = .leading
    var isDisabled: Bool = false
    var accessibilityIdentifier: String? = nil
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

struct PollRateCard: View {
    let editorStore: EditorStore
    private let pollRates = [125, 500, 1000]

    var body: some View {
        Card(title: "Polling Rate", accessibilityIdentifier: "poll-rate-card") {
            LabeledControlRow(title: "Rate") {
                HStack(spacing: 0) {
                    ForEach(Array(pollRates.enumerated()), id: \.element) { index, rate in
                        pollRateButton(rate)
                        if index < pollRates.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 1, height: 18)
                        }
                    }
                }
                .frame(width: 220, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Polling Rate")
                .accessibilityIdentifier("poll-rate-picker")
            }
        }
        .onChange(of: editorStore.editablePollRate) { _, _ in
            editorStore.scheduleAutoApplyPollRate()
        }
    }

    private func pollRateButton(_ rate: Int) -> some View {
        let isSelected = editorStore.editablePollRate == rate
        return Button {
            editorStore.editablePollRate = rate
        } label: {
            Text("\(rate) Hz")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.72))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white.opacity(0.20) : Color.clear)
        .accessibilityIdentifier("poll-rate-option-\(rate)")
        .accessibilityLabel("\(rate) Hz")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
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

struct ButtonMappingTableCard: View {
    let deviceStore: DeviceStore
    let editorStore: EditorStore
    let title: String

    private var isBusy: Bool {
        editorStore.isButtonProfileOperationInFlight || editorStore.isOnboardProfileLoadInFlight
    }

    private var rows: [ButtonBindingRowModel] {
        _ = editorStore.usbButtonProfilesRevision
        return deviceStore.visibleButtonSlots.map { slot in
            let kind = editorStore.buttonBindingKind(for: slot.slot)
            let turboEnabled = editorStore.buttonBindingTurboEnabled(for: slot.slot)
            let turboRate = editorStore.buttonBindingTurboRatePressesPerSecond(for: slot.slot)
            return ButtonBindingRowModel(
                slot: slot.slot,
                friendlyName: slot.friendlyName,
                isEditable: deviceStore.isButtonSlotEditable(slot.slot) && !isBusy,
                selectedKind: kind,
                turboEligible: kind != .default && kind.supportsTurbo,
                clutchDPI: editorStore.buttonBindingClutchDPI(for: slot.slot),
                keyboardHidKey: editorStore.buttonBindingHidKey(for: slot.slot),
                keyboardHidModifiers: editorStore.buttonBindingHidModifiers(for: slot.slot),
                supportsKeyboardModifierChords: deviceStore.selectedDevice.map { device in
                    device.transport == .usb || device.transport == .bluetooth
                } ?? false,
                turboEnabled: turboEnabled,
                turboRatePressesPerSecond: turboRate,
                notice: deviceStore.buttonSlotNotice(slot.slot)
            )
        }
    }

    var body: some View {
        Card(title: title, accessibilityIdentifier: "button-mapping-card") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        ButtonBindingRow(editorStore: editorStore, row: row)
                    }
                }

                if !deviceStore.hiddenUnsupportedButtonSlots.isEmpty {
                    UnsupportedButtonsFootnote(entries: deviceStore.hiddenUnsupportedButtonSlots)
                }
            }
        }
    }
}

private struct OnboardProfilePillButton: View {
    let editorStore: EditorStore
    let action: () -> Void

    private var activeProfileID: Int {
        editorStore.activeOnboardProfile
    }

    private var activeSummary: OnboardProfileSummary? {
        editorStore.onboardProfileSummaries.first { $0.profileID == activeProfileID }
    }

    private var profileName: String {
        if let activeSummary {
            return activeSummary.displayName
        }
        if activeProfileID == 1 {
            return "Base Profile"
        }
        return "Profile \(activeProfileID)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(onboardProfileSlotColor(activeProfileID))
                    .frame(width: 9, height: 9)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.38), lineWidth: 1)
                    )
                    .shadow(color: onboardProfileSlotColor(activeProfileID).opacity(0.45), radius: 6, y: 0)
                    .accessibilityHidden(true)

                Text(profileName)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 128, alignment: .leading)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white.opacity(0.54))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboard-profile-pill-button")
        .accessibilityLabel("Onboard profile \(profileName)")
        .help("Manage onboard profiles")
    }
}

private func onboardProfileSlotColor(_ profileID: Int) -> Color {
    switch profileID {
    case 1: Color.white
    case 2: Color(hex: 0xFF3B30)
    case 3: Color(hex: 0x30D158)
    case 4: Color(hex: 0x0A84FF)
    case 5: Color(hex: 0x64D2FF)
    default: Color.white.opacity(0.65)
    }
}

private struct OnboardProfileManagerPopover: View {
    let editorStore: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Onboard Profiles")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityIdentifier("onboard-profiles-card")

            OnboardProfileManagerPanel(editorStore: editorStore)
        }
        .padding(14)
        .frame(width: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: 0x111820))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        )
        .task {
            await editorStore.refreshOnboardProfiles()
        }
    }
}

private struct OnboardProfileManagerPanel: View {
    let editorStore: EditorStore

    @State private var renameName = ""
    @State private var copyFromProfileID = 1
    @State private var hoveredProfileID: Int?
    private let slotColumnWidth: CGFloat = 188
    private let connectorWidth: CGFloat = 14
    private let slotRowHeight: CGFloat = 48
    private let slotRowSpacing: CGFloat = 8
    private let columnSpacing: CGFloat = 10
    private let actionPanelCornerRadius: CGFloat = 8

    private var isBusy: Bool {
        editorStore.isButtonProfileOperationInFlight || editorStore.isOnboardProfileLoadInFlight
    }

    private var isRefreshing: Bool {
        editorStore.isOnboardProfileRefreshInFlight
    }

    private var statusLabel: String? {
        editorStore.buttonProfileOperationStatusText ?? editorStore.onboardProfileLoadStatusText
    }

    private var selectedProfileID: Int? {
        editorStore.selectedOnboardProfileID
    }

    private var selectedSummary: OnboardProfileSummary? {
        guard let selectedProfileID else { return nil }
        return editorStore.onboardProfileSummaries.first(where: { $0.profileID == selectedProfileID })
    }

    private var selectedNameIsEmpty: Bool {
        renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var profileListHeight: CGFloat {
        let count = max(1, editorStore.onboardProfileSummaries.count)
        return CGFloat(count) * slotRowHeight + CGFloat(max(0, count - 1)) * slotRowSpacing
    }

    private var selectedProfileIndex: Int {
        guard let selectedProfileID,
              let index = editorStore.onboardProfileSummaries.firstIndex(where: { $0.profileID == selectedProfileID }) else {
            return 0
        }
        return index
    }

    private var selectedArrowCenterY: CGFloat {
        CGFloat(selectedProfileIndex) * (slotRowHeight + slotRowSpacing) + (slotRowHeight / 2)
    }

    private var copySourceSummaries: [OnboardProfileSummary] {
        editorStore.onboardProfileSummaries.filter(\.isAssigned)
    }

    private var resolvedCopyFromProfileID: Int {
        let sourceIDs = Set(copySourceSummaries.map(\.profileID))
        if sourceIDs.contains(copyFromProfileID) {
            return copyFromProfileID
        }
        if let active = copySourceSummaries.first(where: \.isActive)?.profileID {
            return active
        }
        return copySourceSummaries.first?.profileID ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if editorStore.onboardProfileSummaries.isEmpty {
                if isRefreshing {
                    loadingRow
                } else {
                    emptyRefreshState
                }
            } else {
                profileLayout
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Reading onboard profiles")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var emptyRefreshState: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profiles unavailable")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                Text(editorStore.onboardProfileRefreshErrorMessage ?? "Profile inventory has not loaded yet.")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                Task { await editorStore.refreshOnboardProfiles() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Refresh profiles")
            .accessibilityIdentifier("onboard-profiles-refresh-button")
        }
    }

    private var profileLayout: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            VStack(alignment: .leading, spacing: slotRowSpacing) {
                ForEach(editorStore.onboardProfileSummaries) { profile in
                    profileSlotRow(profile)
                        .frame(width: slotColumnWidth, height: slotRowHeight)
                }
            }

            actionPanel
                .frame(maxWidth: .infinity, minHeight: profileListHeight, alignment: .topLeading)
        }
    }

    private func profileSlotRow(_ profile: OnboardProfileSummary) -> some View {
        let isSelected = profile.profileID == selectedProfileID
        let isEmptySlot = !profile.isAssigned
        let isHovered = hoveredProfileID == profile.profileID
        let titleOpacity = profileTitleOpacity(profile: profile, isSelected: isSelected, isHovered: isHovered)
        let subtitleOpacity = profileSubtitleOpacity(profile: profile, isSelected: isSelected, isHovered: isHovered)
        let fillOpacity = profileFillOpacity(profile: profile, isSelected: isSelected, isHovered: isHovered)
        let strokeOpacity = profileStrokeOpacity(profile: profile, isSelected: isSelected, isHovered: isHovered)
        let plusOpacity = isEmptySlot && isHovered ? 0.82 : 0.0
        let slotColor = onboardProfileSlotColor(profile.profileID)

        return Button {
            Task { await editorStore.selectOnboardProfile(profile.profileID) }
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(slotColor.opacity(profile.isAssigned || isSelected ? 0.95 : 0.45))
                        .frame(width: 4, height: 30)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.isAssigned ? profile.displayName : "None")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(titleOpacity))
                            .lineLimit(1)
                        Text(profile.profileID == 1 ? "Base" : "Slot \(profile.profileID)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(subtitleOpacity))
                    }
                    Spacer(minLength: 0)
                    if isEmptySlot {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.white.opacity(plusOpacity))
                            .frame(width: 22, height: 22)
                            .accessibilityLabel("Create profile")
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .padding(.vertical, 7)

                if profile.isActive {
                    Text("active")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(hex: 0x30D158))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(hex: 0x30D158).opacity(0.14))
                        )
                        .offset(x: -6, y: 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        profile.isActive
                            ? Color(hex: 0x30D158).opacity(0.95)
                            : Color.white.opacity(strokeOpacity),
                        lineWidth: profile.isActive ? 2 : 1
                    )
            )
            .shadow(
                color: profile.isActive ? Color(hex: 0x30D158).opacity(0.35) : .clear,
                radius: profile.isActive ? 8 : 0,
                x: 0,
                y: 0
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityIdentifier("onboard-profile-row-\(profile.profileID)")
        .accessibilityLabel(profileAccessibilityLabel(profile))
        .onHover { isHovered in
            if isHovered {
                hoveredProfileID = profile.profileID
            } else if hoveredProfileID == profile.profileID {
                hoveredProfileID = nil
            }
        }
    }

    private func profileAccessibilityLabel(_ profile: OnboardProfileSummary) -> String {
        var parts = [
            profile.isAssigned ? profile.displayName : "None",
            profile.profileID == 1 ? "Base" : "Slot \(profile.profileID)",
        ]
        if profile.isActive {
            parts.append("active")
        }
        if !profile.isAssigned {
            parts.append("Create profile")
        }
        return parts.joined(separator: ", ")
    }

    private func profileTitleOpacity(profile: OnboardProfileSummary, isSelected: Bool, isHovered: Bool) -> Double {
        if profile.isActive || isSelected { return 1.0 }
        if profile.isAssigned { return isHovered ? 0.88 : 0.72 }
        return isHovered ? 0.54 : 0.22
    }

    private func profileSubtitleOpacity(profile: OnboardProfileSummary, isSelected: Bool, isHovered: Bool) -> Double {
        if profile.isActive || isSelected { return 0.56 }
        if profile.isAssigned { return isHovered ? 0.54 : 0.42 }
        return isHovered ? 0.34 : 0.18
    }

    private func profileFillOpacity(profile: OnboardProfileSummary, isSelected: Bool, isHovered: Bool) -> Double {
        if isSelected { return 0.12 }
        if profile.isAssigned { return isHovered ? 0.065 : 0.040 }
        return isHovered ? 0.034 : 0.010
    }

    private func profileStrokeOpacity(profile: OnboardProfileSummary, isSelected: Bool, isHovered: Bool) -> Double {
        if isSelected { return 0.18 }
        if profile.isAssigned { return isHovered ? 0.14 : 0.085 }
        return isHovered ? 0.10 : 0.025
    }

    @ViewBuilder
    private var actionPanel: some View {
        if let selectedProfileID, let selectedSummary {
            VStack(alignment: .leading, spacing: 12) {
                TextField(selectedSummary.isAssigned ? "Profile name" : "Name this profile", text: $renameName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("onboard-profile-name-field")
                    .onAppear {
                        resetNameField(forProfileID: selectedProfileID)
                    }
                    .onChange(of: selectedProfileID) { _, newValue in
                        resetNameField(forProfileID: newValue)
                    }
                    .onChange(of: editorStore.selectedOnboardProfileName) { _, newValue in
                        resetNameFieldFromSelectedProfileName(newValue)
                    }

                if selectedSummary.isAssigned {
                    assignedActions(selectedProfileID: selectedProfileID)
                } else {
                    copyFromPicker
                    createAction(selectedProfileID: selectedProfileID)
                }

                if let statusLabel {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(statusLabel)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.64))
                    }
                }

                if selectedSummary.profileID == 1 {
                    Spacer(minLength: 4)
                    baseProfileWarning
                }
            }
            .frame(maxWidth: .infinity, minHeight: max(0, profileListHeight - 24), alignment: .topLeading)
            .padding(.leading, connectorWidth + 10)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: profileListHeight, alignment: .topLeading)
            .background(
                ProfileActionPanelShape(
                    arrowCenterY: selectedArrowCenterY,
                    arrowWidth: connectorWidth,
                    arrowHeight: 20,
                    cornerRadius: actionPanelCornerRadius
                )
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        ProfileActionPanelShape(
                            arrowCenterY: selectedArrowCenterY,
                            arrowWidth: connectorWidth,
                            arrowHeight: 20,
                            cornerRadius: actionPanelCornerRadius
                        )
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        } else {
            Color.clear
                .frame(height: slotRowHeight)
        }
    }

    private var baseProfileWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0xFFD166))
                .frame(width: 14, height: 14)
            Text("Synapse will overwrite this profile. Save settings to a stored slot if you want to keep them.")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(hex: 0xFFD166).opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: 0xFFD166).opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(hex: 0xFFD166).opacity(0.22), lineWidth: 1)
        )
    }

    private func assignedActions(selectedProfileID: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await editorStore.renameSelectedOnboardProfile(name: renameName) }
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || selectedNameIsEmpty)
            .accessibilityIdentifier("onboard-profile-rename-button")

            Button {
                Task { await editorStore.deleteSelectedOnboardProfile() }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(isBusy || selectedProfileID <= 1)
            .accessibilityIdentifier("onboard-profile-delete-button")
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var copyFromPicker: some View {
        if !copySourceSummaries.isEmpty {
            HStack(spacing: 12) {
                Text("Copy From")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer(minLength: 8)
                Picker(
                    "",
                    selection: Binding(
                        get: { resolvedCopyFromProfileID },
                        set: { copyFromProfileID = $0 }
                    )
                ) {
                    ForEach(copySourceSummaries) { profile in
                        Text(profile.displayName).tag(profile.profileID)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 180, alignment: .trailing)
                .accessibilityIdentifier("onboard-profile-copy-from-picker")
            }
        }
    }

    private func createAction(selectedProfileID: Int) -> some View {
        Button {
            let name = renameName
            let copyFrom = copySourceSummaries.isEmpty ? nil : resolvedCopyFromProfileID
            Task {
                await editorStore.createOnboardProfile(
                    name: name,
                    targetProfileID: selectedProfileID,
                    copyFromProfileID: copyFrom
                )
            }
        } label: {
            Label("Create", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(isBusy || selectedNameIsEmpty)
        .accessibilityIdentifier("onboard-profile-create-button")
    }

    private func resetNameField(forProfileID profileID: Int?) {
        guard let profileID,
              let summary = editorStore.onboardProfileSummaries.first(where: { $0.profileID == profileID }) else {
            return
        }
        renameName = summary.isAssigned ? summary.displayName : ""
        if !summary.isAssigned {
            copyFromProfileID = resolvedCopyFromProfileID
        }
    }

    private func resetNameFieldFromSelectedProfileName(_ name: String) {
        guard let selectedProfileID,
              let summary = editorStore.onboardProfileSummaries.first(where: { $0.profileID == selectedProfileID }) else {
            return
        }
        renameName = summary.isAssigned ? name : ""
        if !summary.isAssigned {
            copyFromProfileID = resolvedCopyFromProfileID
        }
    }
}

private struct ProfileActionPanelShape: Shape {
    let arrowCenterY: CGFloat
    let arrowWidth: CGFloat
    let arrowHeight: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let bodyMinX = rect.minX + max(0, arrowWidth)
        let radius = min(max(0, cornerRadius), min((rect.maxX - bodyMinX) / 2, rect.height / 2))
        let halfArrowHeight = max(0, arrowHeight / 2)
        let minArrowCenterY = rect.minY + radius + halfArrowHeight
        let maxArrowCenterY = rect.maxY - radius - halfArrowHeight
        let resolvedArrowCenterY = min(max(rect.minY + arrowCenterY, minArrowCenterY), maxArrowCenterY)

        var path = Path()
        path.move(to: CGPoint(x: bodyMinX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bodyMinX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: bodyMinX, y: rect.maxY - radius),
            control: CGPoint(x: bodyMinX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: bodyMinX, y: resolvedArrowCenterY + halfArrowHeight))
        path.addLine(to: CGPoint(x: rect.minX, y: resolvedArrowCenterY))
        path.addLine(to: CGPoint(x: bodyMinX, y: resolvedArrowCenterY - halfArrowHeight))
        path.addLine(to: CGPoint(x: bodyMinX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: bodyMinX + radius, y: rect.minY),
            control: CGPoint(x: bodyMinX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct LoadButtonProfilePopover: View {
    let editorStore: EditorStore
    let pickerLabel: (ButtonProfileSource) -> String
    let onSelect: (ButtonProfileSource) -> Void
    @State private var showsSavedProfiles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsSavedProfiles {
                savedProfilesView
            } else {
                rootView
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private var rootView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Saved in OpenSnek")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))

                if editorStore.savedButtonProfiles.isEmpty {
                    Text("No saved local profiles yet.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                } else {
                    loadActionButton(
                        "Saved Profiles",
                        trailingDetail: "\(editorStore.savedButtonProfiles.count)",
                        trailingSystemImage: "chevron.right"
                    ) {
                        showsSavedProfiles = true
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 6) {
                Text("On This Mouse")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))

                ForEach(editorStore.loadableMouseButtonSources, id: \.id) { source in
                    loadActionButton(
                        pickerLabel(source),
                        isDisabled: source == .mouseSlot(1)
                    ) {
                        onSelect(source)
                    }
                }
            }
        }
    }

    private var savedProfilesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showsSavedProfiles = false
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Saved Profiles")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.72))
            }
            .buttonStyle(.plain)

            ForEach(editorStore.savedButtonProfiles) { profile in
                let source = ButtonProfileSource.openSnekProfile(profile.id)
                loadActionButton(pickerLabel(source)) {
                    onSelect(source)
                }
            }
        }
    }

    private func loadActionButton(
        _ title: String,
        isDisabled: Bool = false,
        trailingDetail: String? = nil,
        trailingSystemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            popoverRowLabel(
                title,
                trailingDetail: trailingDetail,
                trailingSystemImage: trailingSystemImage
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1.0)
    }

    private func popoverRowLabel(
        _ title: String,
        trailingDetail: String? = nil,
        trailingSystemImage: String? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            if let trailingDetail {
                Text(trailingDetail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }
            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
    }
}

private struct StoreButtonProfilePopover: View {
    let editorStore: EditorStore
    let currentMouseSlot: Int?
    let pickerLabel: (ButtonProfileSource) -> String
    let onSave: () -> Void
    let onWriteStoredSlot: (Int) -> Void
    let onReplaceCurrentSlot: () -> Void
    let onRevertToSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Saved in OpenSnek")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))

                storeActionButton("Save", action: onSave)
            }

            if editorStore.supportsMultipleOnboardProfiles {
                Divider().overlay(Color.white.opacity(0.08))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Stored Slots")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))

                    ForEach(editorStore.writableMouseButtonSources, id: \.id) { source in
                        if case .mouseSlot(let slot) = source {
                            storeActionButton(pickerLabel(source)) {
                                onWriteStoredSlot(slot)
                            }
                        }
                    }

                    if let currentMouseSlot, currentMouseSlot > 1, editorStore.canReplaceCurrentMouseSlot {
                        storeActionButton("Replace Current Stored Slot", action: onReplaceCurrentSlot)
                    }
                }
            }

            if editorStore.buttonWorkspaceHasUnsavedSourceChanges {
                Divider().overlay(Color.white.opacity(0.08))
                storeActionButton("Revert to Source", action: onRevertToSource)
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
    }

    private func storeActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SaveButtonProfileSheet: View {
    let initialName: String
    let existingProfiles: [OpenSnekButtonProfile]
    let onSaveNew: (String) -> Void
    let onOverwrite: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: SaveButtonProfileMode = .newProfile
    @State private var name = ""
    @State private var selectedProfileID: UUID?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        switch mode {
        case .newProfile:
            return !trimmedName.isEmpty
        case .overwriteExisting:
            return selectedProfileID != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save Button Profile")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("Saved profiles live in OpenSnek and can be reused across devices.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            Picker("Save Mode", selection: $mode) {
                Text("New").tag(SaveButtonProfileMode.newProfile)
                Text("Overwrite").tag(SaveButtonProfileMode.overwriteExisting)
            }
            .pickerStyle(.segmented)

            if mode == .newProfile {
                TextField("Profile Name", text: $name)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker(
                    "Existing Profile",
                    selection: Binding(
                        get: { selectedProfileID ?? existingProfiles.first?.id },
                        set: { selectedProfileID = $0 }
                    )
                ) {
                    ForEach(existingProfiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }

                Button("Save") {
                    switch mode {
                    case .newProfile:
                        onSaveNew(trimmedName)
                    case .overwriteExisting:
                        if let selectedProfileID {
                            onOverwrite(selectedProfileID)
                        }
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if name.isEmpty {
                name = initialName
            }
            if selectedProfileID == nil {
                selectedProfileID = existingProfiles.first?.id
            }
            if existingProfiles.isEmpty {
                mode = .newProfile
            }
        }
    }
}

private enum SaveButtonProfileMode: Hashable {
    case newProfile
    case overwriteExisting
}

private struct ManageButtonProfilesSheet: View {
    let profiles: [OpenSnekButtonProfile]
    let onRename: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftNames: [UUID: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Button Profiles")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Manage your OpenSnek profile library.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            if profiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No saved profiles yet.")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Use Store to save the current button layout into OpenSnek.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.04))
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(profiles) { profile in
                            HStack(spacing: 10) {
                                TextField(
                                    "Profile Name",
                                    text: Binding(
                                        get: { draftNames[profile.id] ?? profile.name },
                                        set: { draftNames[profile.id] = $0 }
                                    )
                                )
                                .textFieldStyle(.roundedBorder)

                                Button("Rename") {
                                    onRename(profile.id, draftNames[profile.id] ?? profile.name)
                                }
                                .disabled((draftNames[profile.id] ?? profile.name).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Button("Delete", role: .destructive) {
                                    onDelete(profile.id)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 300)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            draftNames = profiles.reduce(into: [:]) { partialResult, profile in
                partialResult[profile.id] = profile.name
            }
        }
        .onChange(of: profiles) { _, newValue in
            draftNames = newValue.reduce(into: [:]) { partialResult, profile in
                partialResult[profile.id] = draftNames[profile.id] ?? profile.name
            }
        }
    }
}

private struct UnsupportedButtonsFootnote: View {
    let entries: [DocumentedButtonSlot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.72))
                Text("Some buttons can't be changed yet")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Text("OpenSnek can still use the rest of the device normally.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.60))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(entries) { entry in
                    Text("\(entry.descriptor.friendlyName): \(entry.note ?? entry.access.defaultNotice ?? "Unsupported")")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

private struct LabeledControlRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            Spacer(minLength: 12)

            control()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ButtonBindingRowModel: Identifiable, Equatable {
    let slot: Int
    let friendlyName: String
    let isEditable: Bool
    let selectedKind: ButtonBindingKind
    let turboEligible: Bool
    let clutchDPI: Int
    let keyboardHidKey: Int
    let keyboardHidModifiers: Int
    let supportsKeyboardModifierChords: Bool
    let turboEnabled: Bool
    let turboRatePressesPerSecond: Int
    let notice: String?

    var id: Int { slot }
}

private struct ButtonBindingRow: View {
    let editorStore: EditorStore
    let row: ButtonBindingRowModel

    var body: some View {
        _ = editorStore.usbButtonProfilesRevision
        let profileID = editorStore.selectedDeviceProfileID
        let dpiRange = DeviceProfiles.dpiRange(for: profileID)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(row.friendlyName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("button-binding-row-\(row.slot)")

                Spacer(minLength: 12)

                Picker(
                    "",
                    selection: Binding(
                        get: { editorStore.buttonBindingKind(for: row.slot) },
                        set: { editorStore.updateButtonBindingKind(slot: row.slot, kind: $0) }
                    )
                ) {
                    ForEach(ButtonBindingSupport.availableButtonBindingKinds(profileID: editorStore.selectedDeviceProfileID)) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 220, alignment: .trailing)
                .disabled(!row.isEditable)
                .accessibilityIdentifier("button-binding-kind-picker-\(row.slot)")
            }

            if row.selectedKind == .keyboardSimple {
                HStack(alignment: .center, spacing: 12) {
                    Spacer()
                    KeyboardBindingEditor(
                        hidKey: row.keyboardHidKey,
                        hidModifiers: row.keyboardHidModifiers,
                        supportsModifierChords: row.supportsKeyboardModifierChords,
                        isEditable: row.isEditable,
                        onSelect: {
                            editorStore.updateButtonBindingKeyboardShortcut(
                                slot: row.slot,
                                hidKey: $0.hidKey,
                                hidModifiers: $0.hidModifiers
                            )
                        }
                    )
                }
            }

            if row.selectedKind == .dpiClutch {
                HStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Text("Clutch DPI")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                        DpiValueField(
                            placeholder: "400",
                            value: editorStore.buttonBindingClutchDPI(for: row.slot),
                            width: 120,
                            alignment: .center,
                            isDisabled: !row.isEditable,
                            accessibilityIdentifier: "button-binding-clutch-dpi-field-\(row.slot)"
                        ) { parsed in
                            editorStore.updateButtonBindingClutchDPI(slot: row.slot, dpi: parsed)
                        }
                    }
                    .frame(width: 300, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Spacer()
                    Text("100")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))

                    VStack(alignment: .leading, spacing: 4) {
                        Slider(
                            value: Binding(
                                get: {
                                    DeviceProfiles.dpiSliderPosition(
                                        for: editorStore.buttonBindingClutchDPI(for: row.slot),
                                        profileID: profileID
                                    )
                                },
                                set: { newPosition in
                                    editorStore.updateButtonBindingClutchDPI(
                                        slot: row.slot,
                                        dpi: DeviceProfiles.dpi(forSliderPosition: newPosition, profileID: profileID)
                                    )
                                }
                            ),
                            in: 0...1
                        )
                        .frame(width: 140)
                        .disabled(!row.isEditable)
                        .accessibilityIdentifier("button-binding-clutch-dpi-slider-\(row.slot)")

                        DpiSliderScaleMarkers(
                            profileID: profileID,
                            markerColor: Color.white.opacity(0.84),
                            compact: true
                        )
                        .frame(width: 140)
                    }
                    .frame(width: 140)

                    Text("\(dpiRange.upperBound)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))

                    Text("\(row.clutchDPI)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.76))
                        .frame(width: 56, alignment: .trailing)
                }
            }

            if row.turboEligible {
                HStack(spacing: 8) {
                    Spacer()
                    turboToggle
                }

                if row.turboEnabled {
                    HStack(spacing: 8) {
                        Spacer()
                        Text("Slow")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))

                        Slider(
                            value: Binding(
                                get: { Double(editorStore.buttonBindingTurboRatePressesPerSecond(for: row.slot)) },
                                set: { editorStore.updateButtonBindingTurboPressesPerSecond(slot: row.slot, pressesPerSecond: Int(round($0))) }
                            ),
                            in: 1...20
                        )
                        .frame(width: 140)
                        .disabled(!row.isEditable)
                        .accessibilityIdentifier("button-binding-turbo-rate-slider-\(row.slot)")

                        Text("Fast")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.62))

                        Text("\(row.turboRatePressesPerSecond)/s")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.78))
                            .frame(width: 54, alignment: .trailing)
                    }

                    HStack {
                        Spacer()
                        Text("Turbo rate: 1..20 presses per second")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
            }

            if let notice = row.notice {
                HStack {
                    Spacer()
                    Text(notice)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }
        }
        .padding(8)
        .opacity(row.isEditable ? 1.0 : 0.75)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var turboToggle: some View {
        Toggle(
            "Turbo",
            isOn: Binding(
                get: { editorStore.buttonBindingTurboEnabled(for: row.slot) },
                set: { editorStore.updateButtonBindingTurboEnabled(slot: row.slot, enabled: $0) }
            )
        )
        .toggleStyle(.switch)
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(.white.opacity(0.76))
        .disabled(!row.isEditable)
        .accessibilityIdentifier("button-binding-turbo-toggle-\(row.slot)")
    }
}
