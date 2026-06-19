import SwiftUI
import AppKit
import OpenSnekCore

struct ContentView: View {
    let deviceStore: DeviceStore
    let editorStore: EditorStore
    let runtimeStore: RuntimeStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var dismissedPermissionNoticeKey: String?

    var body: some View {
        NavigationSplitView {
            DeviceSidebarView(deviceStore: deviceStore)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.automatic)
        .task {
            await runtimeStore.start()
            await runtimeStore.refreshHIDAccessStatus(forceRefresh: false)
        }
        .onChange(of: deviceStore.selectedDeviceID) { _, _ in
            guard !deviceStore.usesRemoteServiceTransport || deviceStore.state == nil else { return }
            Task { await deviceStore.refreshState() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await runtimeStore.refreshHIDAccessStatus(forceRefresh: false)
                    if deviceStore.usesRemoteServiceTransport {
                        runtimeStore.sendRemoteClientPresence()
                    } else {
                        await deviceStore.refreshDevices()
                    }
                }
            }
        }
        .onChange(of: runtimeStore.hidAccessStatus.authorization) { _, authorization in
            if authorization != .denied {
                dismissedPermissionNoticeKey = nil
            }
        }
    }

    private var detail: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0E1218), Color(hex: 0x121D15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let selected = deviceStore.selectedDevice {
                if deviceStore.selectedDeviceIsStrictlyUnsupported || deviceStore.selectedDeviceIsUnsupportedUSB {
                    GenericDeviceDetailView(deviceStore: deviceStore, selected: selected)
                } else if let state = deviceStore.state,
                          state.device.id == nil || state.device.id == selected.id {
                    DeviceDetailView(
                        deviceStore: deviceStore,
                        editorStore: editorStore,
                        selected: selected,
                        state: state
                    )
                } else if shouldShowLoadingDetail(for: selected) {
                    DeviceConnectingDetailView(deviceStore: deviceStore, selected: selected)
                } else {
                    DeviceUnavailableDetailView(deviceStore: deviceStore, selected: selected)
                }
            } else {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .overlay(alignment: .topLeading) {
            if !noticeItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(noticeItems.enumerated()), id: \.offset) { _, notice in
                        StatusNoticeCard(
                            title: notice.title,
                            message: notice.message,
                            detailLines: notice.detailLines,
                            tone: notice.tone,
                            actions: notice.actions
                        )
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 12)
                .frame(maxWidth: 520, alignment: .leading)
            }
        }
    }

    private func shouldShowLoadingDetail(for selected: MouseDevice) -> Bool {
        guard deviceStore.selectedDeviceID == selected.id else { return false }
        if deviceStore.isRefreshingState {
            return true
        }

        switch deviceStore.connectionState(for: selected) {
        case .connected, .reconnecting:
            return true
        case .disconnected, .unsupported, .error:
            return false
        }
    }

    private func isInputMonitoringError(_ message: String?) -> Bool {
        guard let message else { return false }
        let lowered = message.lowercased()
        return lowered.contains("input monitoring") ||
            lowered.contains("usb hid access denied") ||
            lowered.contains("usb hid feature reports are blocked") ||
            lowered.contains("kioreturnnotpermitted")
    }

    private var permissionGuidanceDetailLines: [String] {
        [
            "Open Input Monitoring settings and turn on OpenSnek.",
            "If it still looks stuck, use Reset Permissions and try again.",
            "After changing the permission, quit and reopen OpenSnek.",
            "Current app host: \(runtimeStore.hidAccessStatus.hostLabel)"
        ]
    }

    private var activePermissionNoticeKey: String? {
        guard runtimeStore.hidAccessStatus.isDenied,
              let selectedDevice = deviceStore.selectedDevice else {
            return nil
        }
        if selectedDevice.transport == .bluetooth, deviceStore.selectedDeviceSupportsPassiveDPIInput {
            return "bt:\(selectedDevice.id):\(runtimeStore.hidAccessStatus.authorization.rawValue)"
        }
        if selectedDevice.transport == .usb, isInputMonitoringError(deviceStore.errorMessage) {
            return "usb:\(selectedDevice.id):\(runtimeStore.hidAccessStatus.authorization.rawValue)"
        }
        return nil
    }

    private var shouldShowPermissionNotice: Bool {
        guard let activePermissionNoticeKey else { return false }
        return dismissedPermissionNoticeKey != activePermissionNoticeKey
    }

    private var showsBluetoothHIDAccessCallout: Bool {
        guard runtimeStore.hidAccessStatus.isDenied else { return false }
        guard let selectedDevice = deviceStore.selectedDevice, selectedDevice.transport == .bluetooth else { return false }
        return deviceStore.selectedDeviceSupportsPassiveDPIInput && shouldShowPermissionNotice
    }

    private var showsUSBAccessCallout: Bool {
        guard deviceStore.selectedDevice?.transport == .usb else { return false }
        if isInputMonitoringError(deviceStore.errorMessage) {
            return shouldShowPermissionNotice
        }
        if deviceStore.warningMessage != nil {
            return true
        }
        guard let state = deviceStore.state else { return false }
        return state.dpi_stages.values == nil || state.poll_rate == nil || state.led_value == nil
    }

    private var usbCalloutTitle: String {
        if isInputMonitoringError(deviceStore.errorMessage) {
            return "USB Access Blocked"
        }
        return "USB Telemetry Limited"
    }

    private var usbCalloutMessage: String {
        if let warning = deviceStore.warningMessage {
            return warning
        }
        return "DPI, polling, or lighting readback is unavailable for this device session."
    }

    private var noticeItems: [NoticeItem] {
        var notices: [NoticeItem] = []

        if showsBluetoothHIDAccessCallout, let selectedDevice = deviceStore.selectedDevice {
            notices.append(
                NoticeItem(
                    title: "Allow Input Monitoring",
                    message: "OpenSnek can talk to \(selectedDevice.product_name), but macOS is still blocking the permission that lets instant on-device DPI changes show up right away.",
                    detailLines: permissionGuidanceDetailLines,
                    tone: .permission,
                    actions: [
                        NoticeAction(title: "Open Settings", isProminent: true) {
                            PermissionSupport.openInputMonitoringSettings()
                        },
                        NoticeAction(title: "Reset Permissions") {
                            Task { await runtimeStore.resetAllPermissions() }
                        },
                        NoticeAction(title: "Refresh") {
                            Task {
                                await runtimeStore.refreshHIDAccessStatus(forceRefresh: true)
                                await deviceStore.refreshDevices()
                            }
                        },
                        NoticeAction(title: "Dismiss") {
                            dismissedPermissionNoticeKey = activePermissionNoticeKey
                        }
                    ]
                )
            )
        }

        if showsUSBAccessCallout {
            var detailLines: [String] = []
            var actions: [NoticeAction] = [
                NoticeAction(title: "Refresh") {
                    Task {
                        await runtimeStore.refreshHIDAccessStatus(forceRefresh: true)
                        await deviceStore.refreshDevices()
                    }
                }
            ]

            if isInputMonitoringError(deviceStore.errorMessage) {
                detailLines = permissionGuidanceDetailLines
                actions.insert(
                    NoticeAction(title: "Open Settings", isProminent: true) {
                        PermissionSupport.openInputMonitoringSettings()
                    },
                    at: 0
                )
                actions.insert(
                    NoticeAction(title: "Reset Permissions") {
                        Task { await runtimeStore.resetAllPermissions() }
                    },
                    at: 1
                )
                actions.append(
                    NoticeAction(title: "Dismiss") {
                        dismissedPermissionNoticeKey = activePermissionNoticeKey
                    }
                )
            }

            notices.append(
                NoticeItem(
                    title: isInputMonitoringError(deviceStore.errorMessage) ? "Allow Input Monitoring" : usbCalloutTitle,
                    message: isInputMonitoringError(deviceStore.errorMessage)
                        ? "OpenSnek needs one more macOS permission before it can read all USB settings from this mouse."
                        : usbCalloutMessage,
                    detailLines: detailLines,
                    tone: isInputMonitoringError(deviceStore.errorMessage) ? .permission : .warning,
                    actions: actions
                )
            )
        }

        if let error = deviceStore.errorMessage, shouldShowSeparateErrorNotice {
            notices.append(
                NoticeItem(
                    title: errorNoticeTitle(for: error),
                    message: error,
                    tone: .error,
                    actions: []
                )
            )
        }

        if let warning = deviceStore.warningMessage, shouldShowSeparateWarningNotice {
            notices.append(
                NoticeItem(
                    title: "Warning",
                    message: warning,
                    tone: .warning,
                    actions: []
                )
            )
        }

        return notices
    }

    private var shouldShowSeparateErrorNotice: Bool {
        guard deviceStore.errorMessage != nil else { return false }
        if isInputMonitoringError(deviceStore.errorMessage), showsUSBAccessCallout {
            return false
        }
        if selectedDetailHandlesConnectionRecovery {
            return false
        }
        return true
    }

    private var selectedDetailHandlesConnectionRecovery: Bool {
        guard let selected = deviceStore.selectedDevice else { return false }
        guard !deviceStore.selectedDeviceIsStrictlyUnsupported,
              !deviceStore.selectedDeviceIsUnsupportedUSB else {
            return false
        }
        if let state = deviceStore.state,
           state.device.id == nil || state.device.id == selected.id {
            return false
        }

        switch deviceStore.connectionState(for: selected) {
        case .disconnected, .reconnecting:
            return true
        case .connected, .unsupported, .error:
            return false
        }
    }

    private var shouldShowSeparateWarningNotice: Bool {
        guard deviceStore.warningMessage != nil else { return false }
        return !showsUSBAccessCallout
    }

    private func errorNoticeTitle(for message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("device read is failing repeatedly") {
            return "Device Read Unstable"
        }
        if lowered.contains("failed") || lowered.contains("error") {
            return "Action Required"
        }
        return "Notice"
    }

    private var supportedDeviceRows: [SupportedDeviceRow] {
        DeviceProfiles.all
            .map { profile in
                SupportedDeviceRow(
                    id: "\(profile.id.rawValue):\(profile.transport.rawValue)",
                    familyID: profile.id.rawValue,
                    name: profile.productName,
                    transport: profile.transport,
                    productIDs: Self.productIDText(for: profile),
                    capabilities: Self.capabilityText(for: profile)
                )
            }
            .sorted { lhs, rhs in
                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameOrder != .orderedSame {
                    return nameOrder == .orderedAscending
                }
                return transportSortKey(lhs.transport) < transportSortKey(rhs.transport)
            }
    }

    private func transportSortKey(_ transport: DeviceTransportKind) -> Int {
        switch transport {
        case .usb:
            0
        case .bluetooth:
            1
        }
    }

    private static func productIDText(for profile: DeviceProfile) -> String {
        profile.supportedProducts
            .sorted()
            .map { String(format: "0x%04X", $0) }
            .joined(separator: ", ")
    }

    private static func capabilityText(for profile: DeviceProfile) -> String {
        var items: [String] = []
        if let maxDPI = profile.passiveDPIInput?.maximumDPI {
            items.append("DPI \(maxDPI / 1000)K")
        } else {
            items.append("DPI")
        }
        if profile.supportsIndependentXYDPI {
            items.append("X/Y")
        }
        if !profile.buttonLayout.writableSlots.isEmpty {
            items.append("Buttons")
        }
        if !profile.supportedLightingEffects.isEmpty ||
            !profile.usbLightingLEDIDs.isEmpty ||
            !profile.usbLightingZones.isEmpty {
            items.append("Lighting")
        }
        if profile.onboardProfileCount > 1 {
            items.append("\(profile.onboardProfileCount) profiles")
        }
        return items.joined(separator: " · ")
    }

    private var emptyState: some View {
        EmptyDeviceState(rows: supportedDeviceRows)
    }
}

private struct EmptyDeviceState: View {
    let rows: [SupportedDeviceRow]
    @State private var showsWaitingState = true
    @State private var showsSupportedDevices = false

    private var supportedFamilyCount: Int {
        Set(rows.map(\.familyID)).count
    }

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            VStack(alignment: .center, spacing: 8) {
                if showsWaitingState {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(.white.opacity(0.9))
                        Text("Waiting for devices")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text("Connect a device")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                HStack(spacing: 6) {
                    Button {
                        showsSupportedDevices = true
                    } label: {
                        Text("Supported devices")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .help("Open supported device table")

                    Text("· \(supportedFamilyCount) models · \(rows.count) connection paths")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 440, alignment: .center)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .task {
            guard showsWaitingState else { return }
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
            } catch {
                return
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                showsWaitingState = false
            }
        }
        .sheet(isPresented: $showsSupportedDevices) {
            SupportedDevicesTableSheet(rows: rows)
        }
    }
}

private struct SupportedDevicesTableSheet: View {
    let rows: [SupportedDeviceRow]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredRows: [SupportedDeviceRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        let terms = query
            .lowercased()
            .split(separator: " ")
            .map(String.init)
        return rows.filter { row in
            terms.allSatisfy { row.searchText.contains($0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Supported Devices")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(rows.count) connection paths across \(Set(rows.map(\.familyID)).count) device models")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }

            TextField("Search by model, transport, product ID, or capability", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 460)

            SupportedDevicesTable(rows: filteredRows)
        }
        .padding(22)
        .frame(minWidth: 960, minHeight: 520)
        .background(Color(hex: 0x10161D))
    }
}

private struct SupportedDeviceRow: Identifiable {
    let id: String
    let familyID: String
    let name: String
    let transport: DeviceTransportKind
    let productIDs: String
    let capabilities: String

    var searchText: String {
        [
            name,
            transport.connectionLabel,
            transport.shortLabel,
            productIDs,
            capabilities,
        ]
        .joined(separator: " ")
        .lowercased()
    }
}

private struct SupportedDevicesTable: View {
    let rows: [SupportedDeviceRow]

    var body: some View {
        VStack(spacing: 0) {
            SupportedDevicesTableHeader()
            Divider().overlay(Color.white.opacity(0.12))

            if rows.isEmpty {
                Text("No supported devices match the current search.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            SupportedDevicesTableRow(row: row)
                            Divider().overlay(Color.white.opacity(0.07))
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SupportedDevicesTableHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            tableHeader("Device")
                .frame(maxWidth: .infinity, alignment: .leading)
            tableHeader("Transport")
                .frame(width: 108, alignment: .leading)
            tableHeader("Product ID")
                .frame(width: 132, alignment: .leading)
            tableHeader("Capabilities")
                .frame(width: 320, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
    }

    private func tableHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .foregroundStyle(.white.opacity(0.58))
            .textCase(.uppercase)
    }
}

private struct SupportedDevicesTableRow: View {
    let row: SupportedDeviceRow

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(row.name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Pill(
                text: row.transport.connectionLabel,
                color: row.transport == .bluetooth ? Color(hex: 0x66D9FF) : Color(hex: 0xA8F46A),
                fontSize: 10,
                horizontalPadding: 8,
                verticalPadding: 4
            )
            .frame(width: 108, alignment: .leading)

            Text(row.productIDs)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
                .frame(width: 132, alignment: .leading)

            Text(row.capabilities)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))
                .lineLimit(1)
                .frame(width: 320, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NoticeItem {
    let title: String
    let message: String
    var detailLines: [String] = []
    let tone: StatusNoticeTone
    var actions: [NoticeAction] = []
}

private struct NoticeAction {
    let title: String
    var isProminent: Bool = false
    let handler: () -> Void
}

private enum StatusNoticeTone {
    case error
    case warning
    case permission

    var backgroundColor: Color {
        switch self {
        case .error:
            Color(hex: 0xB3261E)
        case .warning:
            Color(hex: 0x8A6A00)
        case .permission:
            Color(hex: 0x8D6B2C)
        }
    }

    var borderColor: Color {
        switch self {
        case .error:
            Color(hex: 0xFF8A80)
        case .warning:
            Color(hex: 0xF4C65D)
        case .permission:
            Color(hex: 0xF1CA82)
        }
    }
}

private struct StatusNoticeCard: View {
    let title: String
    let message: String
    let detailLines: [String]
    let tone: StatusNoticeTone
    let actions: [NoticeAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.90))

            detailLinesView

            actionButtons
        }
        .padding(12)
        .background(cardBackground)
        .shadow(color: .black.opacity(0.20), radius: 12, y: 4)
    }

    @ViewBuilder
    private var detailLinesView: some View {
        ForEach(Array(detailLines.enumerated()), id: \.offset) { _, line in
            detailLineView(for: line)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if !actions.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    if action.isProminent {
                        Button(action.title, action: action.handler)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else {
                        Button(action.title, action: action.handler)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
    }

    private func detailLineView(for line: String) -> some View {
        let usesMonospace = line.contains("tccutil") || line.contains("Denied host:")
        let fontSize = usesMonospace ? 11.0 : 12.0
        let fontDesign: Font.Design = usesMonospace ? .monospaced : .rounded

        return Text(line)
            .font(.system(size: fontSize, weight: .medium, design: fontDesign))
            .foregroundStyle(.white.opacity(0.80))
            .textSelection(.enabled)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(tone.backgroundColor.opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(tone.borderColor.opacity(0.55), lineWidth: 1)
            )
    }
}
