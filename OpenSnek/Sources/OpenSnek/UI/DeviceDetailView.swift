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
        LightingSwatch(hex: 0x00FFFF), LightingSwatch(hex: 0xFF00FF), LightingSwatch(hex: 0xFFFFFF), LightingSwatch(hex: 0xFF8000)
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

                DeviceConnectionLoadingCard(headline: headline, subtitle: subtitle)

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

private struct DeviceConnectionLoadingCard: View {
    let headline: String
    let subtitle: String

    var body: some View {
        DeviceConnectionLoadingContent(headline: headline, subtitle: subtitle)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 42)
        .background(DeviceConnectionLoadingBackground())
    }
}

private struct DeviceConnectionLoadingContent: View {
    let headline: String
    let subtitle: String

    var body: some View {
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
    }
}

private struct DeviceConnectionLoadingBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
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
        DeviceStatusBadgeContent(indicator: indicator)
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

private struct DeviceStatusBadgeContent: View {
    let indicator: DeviceStatusIndicator

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
            DeviceDiagnosticsSheetHeader(deviceName: device.product_name, copy: copyDiagnostics, done: { dismiss() })

            Text("Use this dump in bug reports when a device is unsupported, partially supported, or behaving unexpectedly.")
                .hintTextStyle()

            DeviceDiagnosticsConnectionPanel(lines: deviceStore.diagnosticsConnectionLines(for: device))

            DeviceDiagnosticsTextPanel(text: diagnosticsText)
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

private struct DeviceDiagnosticsSheetHeader: View {
    let deviceName: String
    let copy: () -> Void
    let done: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Device Diagnostics")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                Text(deviceName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Copy", action: copy)
                .buttonStyle(.borderedProminent)

            Button("Done", action: done)
                .buttonStyle(.bordered)
        }
    }
}

private struct DeviceDiagnosticsConnectionPanel: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connection Paths")
                .font(.system(size: 12, weight: .black, design: .rounded))
            ForEach(lines, id: \.self) { line in
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
    }
}

private struct DeviceDiagnosticsTextPanel: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
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
}
