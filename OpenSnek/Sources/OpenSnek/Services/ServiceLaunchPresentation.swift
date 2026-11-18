import Foundation
import OpenSnekCore

/// A one-launch copy of the menu service's presentation. Live updates still use its IPC backend.
struct ServiceLaunchPresentation: Codable {
    static let environmentKey = "OPEN_SNEK_SERVICE_PRESENTATION"
    let processID: Int32
    let createdAt: Date
    let snapshot: SharedServiceSnapshot
    let hidAccessStatus: HIDAccessStatus
    let transportStatuses: [String: DpiUpdateTransportStatus]
    let disconnectedDeviceIDs: Set<String>
    let inventory: OnboardProfileInventory?
    let activeProfile: OnboardProfileSnapshot?

    var encoded: String? {
        // Leave room for the inherited environment when launching an unbundled executable.
        guard let data = try? BackendCodec.encode(self), data.count <= 48 * 1024 else { return nil }
        return data.base64EncodedString()
    }

    static func decode(_ value: String?, servicePID: Int32?, now: Date = Date()) -> Self? {
        guard let value, value.utf8.count <= 64 * 1024, let data = Data(base64Encoded: value), let presentation = try? BackendCodec.decode(Self.self, from: data), presentation.processID == servicePID, (0...10).contains(now.timeIntervalSince(presentation.createdAt)) else { return nil }
        return presentation
    }
}

/// Transfers only currently reachable device state and the matching selected hardware profile.
@MainActor extension AppStateDeviceController {
    func makeLaunchPresentation(prepared: ServiceProfilePreparation, hidAccess: HIDAccessStatus) -> ServiceLaunchPresentation {
        let reachable = Set(deviceStore.devices.filter { connectionState(for: $0) == .connected }.map(\.id))
        let states = stateCacheByDeviceID.filter { reachable.contains($0.key) }
        let snapshot = SharedServiceSnapshot(
            devices: deviceStore.devices, stateByDeviceID: states, lastUpdatedByDeviceID: lastUpdatedByDeviceID.filter { states[$0.key] != nil }, softwareLightingStatusByDeviceID: deviceStore.softwareLightingStatusByDeviceID,
            usbControlAvailabilityByDeviceID: deviceStore.usbControlAvailabilityByDeviceID, selectedDeviceID: deviceStore.selectedDeviceID)
        let id = deviceStore.selectedDeviceID
        let active = id.flatMap { states[$0]?.active_onboard_profile }
        let matches = prepared.device == deviceStore.selectedDevice && prepared.profile?.profileID == active
        return ServiceLaunchPresentation(
            processID: ProcessInfo.processInfo.processIdentifier, createdAt: Date(), snapshot: snapshot, hidAccessStatus: hidAccess, transportStatuses: dpiUpdateTransportStatusByDeviceID, disconnectedDeviceIDs: Set(deviceStore.devices.filter { connectionState(for: $0) == .disconnected }.map(\.id)),
            inventory: matches ? prepared.inventory : nil, activeProfile: matches ? prepared.profile : nil)
    }

    func applyLaunchPresentation(_ presentation: ServiceLaunchPresentation) {
        guard environment.usesRemoteServiceTransport, deviceStore.devices.isEmpty else { return }
        let snapshot = presentation.snapshot
        if let id = snapshot.selectedDeviceID, let selected = snapshot.devices.first(where: { $0.id == id }) {
            // Start on the menu selection before list hydration can schedule work for the first device.
            deviceStore.selectedDeviceID = id
            if let active = snapshot.stateByDeviceID[id]?.active_onboard_profile, editorController.supportsOnboardProfileCRUD(device: selected) {
                if let inventory = presentation.inventory, inventory.activeProfileID == active {
                    editorController.onboardProfileInventoryByDeviceID[id] = inventory
                    if inventory.assignedProfileIDs.allSatisfy({ inventory.summary(for: $0)?.metadata != nil }), presentation.activeProfile?.profileID == active { editorController.editorStore.preloadedProfilePickerDeviceID = id }
                }
                if let profile = presentation.activeProfile, profile.profileID == active { editorController.seedLaunchProfile(profile, device: selected) }
            }
        }
        unavailableDeviceIDs.formUnion(presentation.disconnectedDeviceIDs)
        applyRemoteServiceSnapshot(snapshot, isLaunchPresentation: true)
        for (id, status) in presentation.transportStatuses { setDpiUpdateTransportStatus(status, for: id) }
        if let device = deviceStore.selectedDevice, let state = snapshot.stateByDeviceID[device.id] {
            let profile = editorController.currentActiveOnboardProfileSnapshot(for: state)
            editorController.editorStore.editableButtonBindings = profile?.buttonBindings ?? editorController.currentSourceBindings(for: device)
            if let profile {
                editorController.hydratedButtonBindingsKey = editorController.buttonBindingsHydrationKey(device: device, profile: profile.profileID)
                editorController.syncLocalProfile(from: profile, device: device, source: "menuLaunch")
            }
        }
        AppLog.debug("AppState", "applied menu launch presentation devices=\(snapshot.devices.count) selected=\(deviceStore.selectedDeviceID ?? "nil") activeProfile=\(presentation.activeProfile?.profileID.description ?? "nil")")
    }
}

/// Keeps a single read-only preparation for the selected mouse. Invalidations discard in-flight results too.
struct ServiceProfilePreparation: Sendable {
    private(set) var device: MouseDevice?
    private var profileID: Int?
    private(set) var token: UUID?
    private(set) var inventory: OnboardProfileInventory?
    private(set) var profile: OnboardProfileSnapshot?

    mutating func begin(device: MouseDevice, profileID: Int, retryFailed: Bool) -> UUID? {
        if self.device == device, self.profileID == profileID, token != nil || profile != nil || !retryFailed { return nil }
        self = Self()
        let token = UUID()
        self.device = device
        self.profileID = profileID
        self.token = token
        return token
    }

    mutating func finish(token: UUID, inventory: OnboardProfileInventory, profile: OnboardProfileSnapshot) {
        guard self.token == token else { return }
        self.inventory = inventory
        self.profile = profile
    }

    mutating func end(token: UUID) { if self.token == token { self.token = nil } }

    mutating func invalidate(deviceID: String) { if device?.id == deviceID { self = Self() } }
}

/// Resolves missing slot names sequentially for both service preparation and manual refresh.
extension OnboardProfileInventory {
    func fillingMissingNames(_ readMetadata: @Sendable (Int) async throws -> OnboardProfileMetadata) async -> Self {
        let profileIDsNeedingNames = assignedProfileIDs.filter { summary(for: $0)?.metadata == nil }
        guard !profileIDsNeedingNames.isEmpty else { return self }
        var summaries = profiles
        for profileID in profileIDsNeedingNames {
            guard let metadata = try? await readMetadata(profileID) else { continue }
            guard let index = summaries.firstIndex(where: { $0.profileID == profileID }) else { continue }
            let existing = summaries[index]
            summaries[index] = OnboardProfileSummary(profileID: existing.profileID, metadata: metadata, isAssigned: existing.isAssigned, isActive: existing.isActive, isBaseProfile: existing.isBaseProfile)
        }
        return OnboardProfileInventory(activeProfileID: activeProfileID, maxProfileID: maxProfileID, assignedProfileIDs: assignedProfileIDs, profiles: summaries)
    }
}
