import OpenSnekAppSupport
import SwiftUI

struct LocalProfileLibraryPanel: View {
    let editorStore: EditorStore
    let isBusy: Bool
    @Binding var newLocalProfileName: String
    @Binding var localProfileRenameNames: [UUID: String]
    @State private var isNewProfilePresented = false
    @State private var localProfileActionInFlight = false
    private let localProfileListMaxHeight: CGFloat = 184
    private let localProfileRowHeight: CGFloat = 42
    private let localProfileRowSpacing: CGFloat = 6

    private var showsLoadingOverlay: Bool {
        isBusy || localProfileActionInFlight
    }

    private var visibleProfiles: [OpenSnekLocalProfile] {
        editorStore.visibleLocalProfilesForReplacement
    }

    private var canCreateFromMouse: Bool {
        editorStore.deviceStore.selectedDevice != nil
    }

    private var localProfileListHeight: CGFloat {
        let rowCount = visibleProfiles.count
        let rowHeights = CGFloat(rowCount) * localProfileRowHeight
        let spacing = CGFloat(max(0, rowCount - 1)) * localProfileRowSpacing
        return min(localProfileListMaxHeight, rowHeights + spacing)
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                localProfileSection
                newLocalProfileSection
            }
            .opacity(showsLoadingOverlay ? 0.45 : 1.0)

            if showsLoadingOverlay {
                loadingOverlay
            }
        }
    }

    private var loadingOverlay: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading profile...")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.80))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.38))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityIdentifier("local-profile-loading-overlay")
    }

    private var localProfileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Replace Profile")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))

            if visibleProfiles.isEmpty {
                Text("No local profiles yet")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: localProfileRowSpacing) {
                        ForEach(visibleProfiles) { profile in
                            LocalProfileLibraryRow(
                                editorStore: editorStore,
                                profile: profile,
                                isBusy: isBusy,
                                actionInFlight: $localProfileActionInFlight,
                                renameName: Binding(
                                    get: { localProfileRenameNames[profile.id] ?? profile.name },
                                    set: { localProfileRenameNames[profile.id] = $0 }
                                )
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(height: localProfileListHeight)
                .accessibilityIdentifier("local-profile-replace-list")
            }
        }
        .accessibilityIdentifier("local-profile-replace-section")
    }

    private var newLocalProfileSection: some View {
        Button {
            isNewProfilePresented = true
        } label: {
            Label("New Profile", systemImage: "plus.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(showsLoadingOverlay)
        .accessibilityIdentifier("local-profile-create-button")
        .popover(
            isPresented: $isNewProfilePresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            newProfilePopover
        }
    }

    private var newProfilePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Profile")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            TextField("Profile name", text: $newLocalProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .accessibilityIdentifier("local-profile-new-name-field")

            HStack(spacing: 8) {
                Button {
                    createNewLocalProfile(copying: nil)
                } label: {
                    Label("Start Fresh", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(newProfileNameIsEmpty)
                .accessibilityIdentifier("local-profile-start-fresh-button")

                Menu {
                    if canCreateFromMouse {
                        Button("Current Mouse") {
                            createNewLocalProfileFromMouse()
                        }
                    }
                    if canCreateFromMouse && !visibleProfiles.isEmpty {
                        Divider()
                    }
                    if visibleProfiles.isEmpty {
                        Text("No profiles")
                    } else {
                        ForEach(visibleProfiles) { profile in
                            Button(profile.name) {
                                createNewLocalProfile(copying: profile.id)
                            }
                        }
                    }
                } label: {
                    Label("Copy From", systemImage: "doc.on.doc")
                }
                .menuStyle(.button)
                .disabled(newProfileNameIsEmpty || (!canCreateFromMouse && visibleProfiles.isEmpty))
                .accessibilityIdentifier("local-profile-copy-source-picker")
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(Color(hex: 0x111820))
    }

    private var newProfileNameIsEmpty: Bool {
        newLocalProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createNewLocalProfile(copying sourceID: UUID?) {
        editorStore.createLocalProfile(name: newLocalProfileName, copying: sourceID)
        newLocalProfileName = ""
        isNewProfilePresented = false
    }

    private func createNewLocalProfileFromMouse() {
        let name = newLocalProfileName
        newLocalProfileName = ""
        isNewProfilePresented = false
        Task {
            await editorStore.createLocalProfileFromMouse(name: name)
        }
    }
}

private struct LocalProfileLibraryRow: View {
    let editorStore: EditorStore
    let profile: OpenSnekLocalProfile
    let isBusy: Bool
    @Binding var actionInFlight: Bool
    @Binding var renameName: String
    @State private var isManagementPresented = false

    private var appearsApplicable: Bool {
        editorStore.localProfileCanApply(profile) || profile.content.dpi != nil
    }

    private var isDisabled: Bool {
        isBusy || actionInFlight
    }

    var body: some View {
        actionRow
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(rowBackground)
    }

    private var actionRow: some View {
        ZStack(alignment: .trailing) {
            replaceButton
            managementButton
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
    }

    private var replaceButton: some View {
        Button {
            replaceProfile()
        } label: {
            HStack(spacing: 0) {
                Text(profile.name)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Color.clear
                    .frame(width: 42, height: 1)
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .contentShape(Rectangle())
        .disabled(isDisabled)
        .accessibilityIdentifier("local-profile-replace-\(profile.id.uuidString)")
        .accessibilityLabel(profile.name)
    }

    private var managementButton: some View {
        Button {
            isManagementPresented = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("Manage \(profile.name)")
        .help("Manage local profile")
        .accessibilityIdentifier("local-profile-manage-\(profile.id.uuidString)")
        .popover(
            isPresented: $isManagementPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            managementPopover
        }
    }

    private func replaceProfile() {
        guard !actionInFlight else { return }
        actionInFlight = true
        Task { @MainActor in
            await editorStore.replaceSelectedProfile(with: profile.id)
            actionInFlight = false
        }
    }

    private var managementPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))

            TextField("Profile name", text: $renameName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .accessibilityIdentifier("local-profile-rename-field-\(profile.id.uuidString)")

            Button {
                editorStore.renameLocalProfile(id: profile.id, name: renameName)
                isManagementPresented = false
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isDisabled || renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Rename local profile")
            .accessibilityIdentifier("local-profile-rename-button-\(profile.id.uuidString)")

            Divider()

            Button(role: .destructive) {
                editorStore.deleteLocalProfile(id: profile.id)
                isManagementPresented = false
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isDisabled)
            .accessibilityIdentifier("local-profile-delete-\(profile.id.uuidString)")
        }
        .padding(12)
        .background(Color(hex: 0x111820))
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.white.opacity(appearsApplicable ? 0.040 : 0.018))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(appearsApplicable ? 0.10 : 0.04), lineWidth: 1)
            )
    }
}
