import AppKit
import OpenSnekAppSupport
import SwiftUI
import OpenSnekCore

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
                    device.transport.supportsHIDBackedControls
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

struct OnboardProfilePillButton: View {
    let editorStore: EditorStore
    let action: () -> Void

    private var activeProfileID: Int {
        editorStore.activeOnboardProfile
    }

    private var activeSummary: OnboardProfileSummary? {
        editorStore.onboardProfileSummaries.first { $0.profileID == activeProfileID }
    }

    private var isLoadingProfiles: Bool {
        // On mapped devices the active slot id can arrive before the UUID-backed inventory.
        // Show loading here so the pill does not flash a fallback name like Base Profile.
        editorStore.isOnboardProfilePillLoading
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
            OnboardProfilePillLabel(
                profileID: activeProfileID,
                profileName: isLoadingProfiles ? "Load Profiles" : profileName,
                isLoading: isLoadingProfiles
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboard-profile-pill-button")
        .accessibilityLabel(isLoadingProfiles ? "Onboard profile Load Profiles" : "Onboard profile \(profileName)")
        .help("Manage onboard profiles")
    }
}

private struct OnboardProfilePillLabel: View {
    let profileID: Int
    let profileName: String
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 8) {
            leadingIndicator

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

    @ViewBuilder
    private var leadingIndicator: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.62)
                .frame(width: 9, height: 9)
                .accessibilityHidden(true)
        } else {
            profileDot
        }
    }

    private var profileDot: some View {
        let color = onboardProfileSlotColor(profileID)
        return Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.38), lineWidth: 1)
            )
            .shadow(color: color.opacity(0.45), radius: 6, y: 0)
            .accessibilityHidden(true)
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

struct ProfilePickerPopover: View {
    let editorStore: EditorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profiles")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityIdentifier("onboard-profiles-card")

            ProfilePickerPanel(editorStore: editorStore)
        }
        .padding(14)
        .frame(width: 680, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
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

private struct ProfilePickerPanel: View {
    let editorStore: EditorStore

    @State private var renameName = ""
    @State private var hoveredProfileID: Int?
    @State private var newLocalProfileName = ""
    @State private var localProfileRenameNames: [UUID: String] = [:]
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

    private var connectBehaviorBinding: Binding<DeviceConnectBehavior> {
        Binding(
            get: { editorStore.connectBehavior },
            set: { editorStore.updateConnectBehavior($0) }
        )
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Onboard Profiles")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))

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

        return OnboardProfileSlotRowButton(
            profile: profile,
            style: OnboardProfileSlotRowStyle(
                slotColor: slotColor,
                titleOpacity: titleOpacity,
                subtitleOpacity: subtitleOpacity,
                fillOpacity: fillOpacity,
                strokeOpacity: strokeOpacity,
                plusOpacity: plusOpacity,
                isSelected: isSelected
            ),
            isBusy: isBusy,
            accessibilityLabel: profileAccessibilityLabel(profile),
            select: {
                Task { await editorStore.selectOnboardProfile(profile.profileID) }
            },
            setHovered: { isHovered in
                if isHovered {
                    hoveredProfileID = profile.profileID
                } else if hoveredProfileID == profile.profileID {
                    hoveredProfileID = nil
                }
            }
        )
    }

    private func profileAccessibilityLabel(_ profile: OnboardProfileSummary) -> String {
        var parts = [
            profile.isAssigned ? profile.displayName : "None",
            profile.profileID == 1 ? "Base" : "Slot \(profile.profileID)"
        ]
        if profile.isActive {
            parts.append("active")
        }
        if !profile.isAssigned {
            parts.append("Load profile")
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
            actionPanelContent(selectedProfileID: selectedProfileID, selectedSummary: selectedSummary)
            .frame(maxWidth: .infinity, minHeight: max(0, profileListHeight - 24), alignment: .topLeading)
            .padding(.leading, connectorWidth + 10)
            .padding(.trailing, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: profileListHeight, alignment: .topLeading)
            .background(actionPanelBackground)
        } else {
            Color.clear
                .frame(height: slotRowHeight)
        }
    }

    @ViewBuilder
    private func actionPanelContent(selectedProfileID: Int, selectedSummary: OnboardProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if editorStore.supportsOnboardProfileCRUD {
                if selectedSummary.isAssigned {
                    actionPanelNameField(selectedProfileID: selectedProfileID, selectedSummary: selectedSummary)
                    assignedActions(selectedProfileID: selectedProfileID)
                }
            } else {
                singleSlotActions
            }

            if editorStore.supportsOnboardProfileCRUD && selectedSummary.profileID == 1 {
                baseProfileWarning
            }

            LocalProfileLibraryPanel(
                editorStore: editorStore,
                isBusy: isBusy,
                selectedSlotIsAssigned: selectedSummary.isAssigned,
                newLocalProfileName: $newLocalProfileName,
                localProfileRenameNames: $localProfileRenameNames
            )
        }
    }

    private func actionPanelNameField(selectedProfileID: Int, selectedSummary: OnboardProfileSummary) -> some View {
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
    }

    private var actionPanelBackground: some View {
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
        .accessibilityIdentifier("base-profile-synapse-warning")
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
                Label("Delete From Slot", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .help("Delete this onboard slot without deleting local profile backups")
            .disabled(isBusy || selectedProfileID <= 1)
            .accessibilityIdentifier("onboard-profile-delete-button")
        }
        .controlSize(.small)
    }

    private var singleSlotActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("On Connect")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))

            Picker("On Connect Behavior", selection: connectBehaviorBinding) {
                Text("Use Mouse Settings").tag(DeviceConnectBehavior.useMouseSettings)
                Text("Restore Last Profile").tag(DeviceConnectBehavior.restoreOpenSnekSettings)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .disabled(isBusy)
            .accessibilityIdentifier("profile-on-connect-picker")

            if editorStore.connectBehavior == .useMouseSettings {
                singleSlotSynapseWarning
            }
        }
    }

    private var singleSlotSynapseWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color(hex: 0xFFD166))
                .frame(width: 14, height: 14)
            Text("Synapse can overwrite this profile when OpenSnek uses mouse settings on connect.")
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
        .accessibilityIdentifier("single-slot-synapse-warning")
    }

    private func resetNameField(forProfileID profileID: Int?) {
        guard let profileID,
              let summary = editorStore.onboardProfileSummaries.first(where: { $0.profileID == profileID }) else {
            return
        }
        renameName = summary.isAssigned ? summary.displayName : ""
    }

    private func resetNameFieldFromSelectedProfileName(_ name: String) {
        guard let selectedProfileID,
              let summary = editorStore.onboardProfileSummaries.first(where: { $0.profileID == selectedProfileID }) else {
            return
        }
        renameName = summary.isAssigned ? name : ""
    }
}

private struct OnboardProfileSlotRowStyle {
    let slotColor: Color
    let titleOpacity: Double
    let subtitleOpacity: Double
    let fillOpacity: Double
    let strokeOpacity: Double
    let plusOpacity: Double
    let isSelected: Bool
}

private struct OnboardProfileSlotRowButton: View {
    let profile: OnboardProfileSummary
    let style: OnboardProfileSlotRowStyle
    let isBusy: Bool
    let accessibilityLabel: String
    let select: () -> Void
    let setHovered: (Bool) -> Void

    var body: some View {
        Button(action: select) {
            rowContent
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityIdentifier("onboard-profile-row-\(profile.profileID)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityLabel)
        .onHover(perform: setHovered)
    }

    private var rowContent: some View {
        mainContent
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(style.fillOpacity))
        )
        .overlay(rowBorder)
        .shadow(
            color: profile.isActive ? Color(hex: 0x30D158).opacity(0.35) : .clear,
            radius: profile.isActive ? 8 : 0,
            x: 0,
            y: 0
        )
    }

    private var mainContent: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(style.slotColor.opacity(profile.isAssigned || style.isSelected ? 0.95 : 0.45))
                .frame(width: 4, height: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.isAssigned ? profile.displayName : "None")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(style.titleOpacity))
                    .lineLimit(1)
                Text(profile.profileID == 1 ? "Base" : "Slot \(profile.profileID)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(style.subtitleOpacity))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
            trailingAccessory
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if profile.isActive {
            activeBadge
        } else if !profile.isAssigned {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white.opacity(style.plusOpacity))
                .frame(width: 22, height: 22)
                .accessibilityLabel("Load profile")
        }
    }

    private var activeBadge: some View {
        Text("active")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(Color(hex: 0x30D158))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color(hex: 0x30D158).opacity(0.14))
            )
            .accessibilityIdentifier("onboard-profile-row-\(profile.profileID)-active-badge")
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(
                profile.isActive
                    ? Color(hex: 0x30D158).opacity(0.95)
                    : Color.white.opacity(style.strokeOpacity),
                lineWidth: profile.isActive ? 2 : 1
            )
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

private struct UnsupportedButtonsFootnote: View {
    let entries: [DocumentedButtonSlot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Text("OpenSnek can still use the rest of the device normally.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.60))

            unsupportedRows
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(footnoteBackground)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.72))
            Text("Some buttons can't be changed yet")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private var unsupportedRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(entries) { entry in
                UnsupportedButtonFootnoteRow(entry: entry)
            }
        }
    }

    private var footnoteBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.white.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct UnsupportedButtonFootnoteRow: View {
    let entry: DocumentedButtonSlot

    var body: some View {
        Text("\(entry.descriptor.friendlyName): \(entry.note ?? entry.access.defaultNotice ?? "Unsupported")")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct LabeledControlRow<Control: View>: View {
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
        return VStack(alignment: .leading, spacing: 8) {
            ButtonBindingHeaderRow(editorStore: editorStore, row: row, profileID: profileID)
            keyboardSection
            dpiClutchSection(profileID: profileID)
            turboSection
            noticeSection
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

    @ViewBuilder
    private var keyboardSection: some View {
        if row.selectedKind == .keyboardSimple {
            ButtonBindingKeyboardControls(editorStore: editorStore, row: row)
        }
    }

    @ViewBuilder
    private func dpiClutchSection(profileID: DeviceProfileID?) -> some View {
        if row.selectedKind == .dpiClutch {
            ButtonBindingDpiClutchControls(editorStore: editorStore, row: row, profileID: profileID)
        }
    }

    @ViewBuilder
    private var turboSection: some View {
        if row.turboEligible {
            ButtonBindingTurboControls(editorStore: editorStore, row: row)
        }
    }

    @ViewBuilder
    private var noticeSection: some View {
        if let notice = row.notice {
            ButtonBindingNoticeRow(notice: notice)
        }
    }
}

private struct ButtonBindingHeaderRow: View {
    let editorStore: EditorStore
    let row: ButtonBindingRowModel
    let profileID: DeviceProfileID?

    var body: some View {
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
                ForEach(ButtonBindingSupport.availableButtonBindingKinds(profileID: profileID)) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 220, alignment: .trailing)
            .disabled(!row.isEditable)
            .accessibilityIdentifier("button-binding-kind-picker-\(row.slot)")
        }
    }
}

private struct ButtonBindingKeyboardControls: View {
    let editorStore: EditorStore
    let row: ButtonBindingRowModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Spacer()
            KeyboardBindingEditor(
                hidKey: row.keyboardHidKey,
                hidModifiers: row.keyboardHidModifiers,
                supportsModifierChords: row.supportsKeyboardModifierChords,
                isEditable: row.isEditable
            ) { selection in
                editorStore.updateButtonBindingKeyboardShortcut(
                    slot: row.slot,
                    hidKey: selection.hidKey,
                    hidModifiers: selection.hidModifiers
                )
            }
        }
    }
}

private struct ButtonBindingDpiClutchControls: View {
    let editorStore: EditorStore
    let row: ButtonBindingRowModel
    let profileID: DeviceProfileID?

    private var dpiRange: ClosedRange<Int> {
        DeviceProfiles.dpiRange(for: profileID)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            clutchValueRow
            clutchSliderRow
        }
    }

    private var clutchValueRow: some View {
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
    }

    private var clutchSliderRow: some View {
        HStack(spacing: 8) {
            Spacer()
            Text("100")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            clutchSlider

            Text("\(dpiRange.upperBound)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            Text("\(row.clutchDPI)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.76))
                .frame(width: 56, alignment: .trailing)
        }
    }

    private var clutchSlider: some View {
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
    }
}

private struct ButtonBindingTurboControls: View {
    let editorStore: EditorStore
    let row: ButtonBindingRowModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                Spacer()
                turboToggle
            }

            if row.turboEnabled {
                turboRateControls
                ButtonBindingNoticeRow(notice: "Turbo rate: 1..20 presses per second")
            }
        }
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

    private var turboRateControls: some View {
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
    }
}

private struct ButtonBindingNoticeRow: View {
    let notice: String

    var body: some View {
        HStack {
            Spacer()
            Text(notice)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
    }
}
