import Foundation
import OpenSnekCore
import OpenSnekHardware

/// Coordinates app state device behavior.
@MainActor final class AppStateDeviceController {
    static let bluetoothPassiveHeartbeatConnectedInterval: TimeInterval = 1.5
    static let usbPassiveActivityConnectedInterval: TimeInterval = 3.5
    static let usbControlUnavailableDebounceInterval: TimeInterval = 0.35
    static let usbReceiverRecoveryProbeInterval: TimeInterval = 2.0
    static let usbPhysicalConnectStatusGraceInterval: TimeInterval = BridgeClient.usbReconnectSettleInterval + 1.5
    static let recentDynamicDpiMutationMergeWindow: TimeInterval = 1.0
    static let usbTelemetryUnavailableMessage = "USB device telemetry unavailable. Feature-report interface did not return usable responses."

    /// Carries Bluetooth realtime refresh delay context.
    struct BluetoothRealtimeRefreshDelayContext {
        let transport: DeviceTransportKind
        let transportStatus: DpiUpdateTransportStatus?
        let lastHeartbeatAt: Date?
        let lastFullStateRefreshStartedAt: Date?
        let minimumRefreshInterval: TimeInterval
        let now: Date
    }

    /// Carries editor presentation hydration request data.
    struct EditorPresentationHydrationRequest {
        let state: MouseState
        let device: MouseDevice
        let holdsPersistedConnectPresentation: Bool
        let applyController: AppStateApplyController
        let editorController: AppStateEditorController
        let scheduleButtonHydration: Bool
    }

    /// Carries recent dynamic DPI refresh context.
    struct RecentDynamicDpiRefreshContext {
        let fetched: MouseState
        let latestCachedState: MouseState?
        let cachedStateBeforeRefresh: MouseState?
        let latestCachedStableUpdateAt: Date?
        let sourceDevice: MouseDevice
        let presentationDevice: MouseDevice
        let sourceDeviceID: String
        let start: Date
    }

    /// Carries successful refresh context.
    struct SuccessfulRefreshContext {
        let merged: MouseState
        let sourceDevice: MouseDevice
        let presentationDevice: MouseDevice
        let previous: MouseState?
        let sourceDeviceID: String
        let start: Date
        let shouldFocusOnActivity: Bool
        let clearSeededReconnectState: Bool
    }

    let environment: AppEnvironment
    let deviceStore: DeviceStore
    @WeakBound("AppStateDeviceController", dependency: "editorController") var editorController: AppStateEditorController
    @WeakBound("AppStateDeviceController", dependency: "applyController") var applyController: AppStateApplyController
    @WeakBound("AppStateDeviceController", dependency: "runtimeController") var runtimeController: AppStateRuntimeController

    var stateCacheByDeviceID: [String: MouseState] = [:]
    var lastUpdatedByDeviceID: [String: Date] = [:]
    var lastStateMutationAtByDeviceID: [String: Date] = [:]
    var refreshingStateDeviceIDs: Set<String> = []
    var refreshingFastDpiDeviceIDs: Set<String> = []
    var suppressFastDpiUntilByDeviceID: [String: Date] = [:]
    var lastUSBFastDpiAtByDeviceID: [String: Date] = [:]
    var lastRealtimeCorrectionAtByDeviceID: [String: Date] = [:]
    var lastPassiveHeartbeatAtByDeviceID: [String: Date] = [:]
    var lastFullStateRefreshStartedAtByDeviceID: [String: Date] = [:]
    var isPollingDevices = false
    var isRefreshingDevices = false
    var refreshFailureCountByDeviceID: [String: Int] = [:]
    var stateRefreshSuppressedUntilByDeviceID: [String: Date] = [:]
    var usbTelemetryUnavailableBackoffDeviceIDs: Set<String> = []
    var usbControlAvailabilityByDeviceID: [String: USBControlAvailability] = [:]
    var lastUSBReceiverRecoveryProbeAtByDeviceID: [String: Date] = [:]
    var pendingUSBControlUnavailableTasksByDeviceID: [String: Task<Void, Never>] = [:]
    var usbPhysicalConnectSettlingUntilByDeviceID: [String: Date] = [:]
    var usbPhysicalConnectSettleTasksByDeviceID: [String: Task<Void, Never>] = [:]
    var unavailableDeviceIDs: Set<String> = []
    var dpiUpdateTransportStatusByDeviceID: [String: DpiUpdateTransportStatus] = [:]
    var pendingSettingsRestoreDeviceIDs: Set<String> = []
    var pendingSettingsRestoreGenerationByDeviceID: [String: Int] = [:]
    var restoringSettingsDeviceIDs: Set<String> = []
    var settingsRestoreRevisionByDeviceID: [String: Int] = [:]
    var seededReconnectStateDeviceIDs: Set<String> = []
    var selectedRecoveryRefreshTask: Task<Void, Never>?
    var selectedRecoveryRefreshDeviceID: String?
    var selectedEditorHydrationTasksByDeviceID: [String: Task<Void, Never>] = [:]
    var selectedEditorHydrationTokensByDeviceID: [String: UUID] = [:]
    var remoteSnapshotSoftwareLightingAutoStartKeys: Set<String> = []
    var isTearingDown = false

    init(environment: AppEnvironment, deviceStore: DeviceStore) {
        self.environment = environment
        self.deviceStore = deviceStore
    }

    func tearDown() {
        isTearingDown = true
        selectedRecoveryRefreshTask?.cancel()
        selectedRecoveryRefreshTask = nil
        selectedRecoveryRefreshDeviceID = nil
        selectedEditorHydrationTasksByDeviceID.values.forEach { $0.cancel() }
        selectedEditorHydrationTasksByDeviceID.removeAll()
        selectedEditorHydrationTokensByDeviceID.removeAll()
        remoteSnapshotSoftwareLightingAutoStartKeys.removeAll()
        pendingUSBControlUnavailableTasksByDeviceID.values.forEach { $0.cancel() }
        pendingUSBControlUnavailableTasksByDeviceID.removeAll()
        lastUSBReceiverRecoveryProbeAtByDeviceID.removeAll()
        usbPhysicalConnectSettleTasksByDeviceID.values.forEach { $0.cancel() }
        usbPhysicalConnectSettleTasksByDeviceID.removeAll()
        usbPhysicalConnectSettlingUntilByDeviceID.removeAll()
    }

    func bind(editorController: AppStateEditorController, applyController: AppStateApplyController, runtimeController: AppStateRuntimeController) {
        _editorController.bind(editorController)
        _applyController.bind(applyController)
        _runtimeController.bind(runtimeController)
    }

    var optionalEditorController: AppStateEditorController? { _editorController.optionalValue }

    var optionalApplyController: AppStateApplyController? { _applyController.optionalValue }

    var optionalRuntimeController: AppStateRuntimeController? { _runtimeController.optionalValue }

    func cachedState(for deviceID: String) -> MouseState? { stateCacheByDeviceID[deviceID] }

    func armPendingSettingsRestore(for deviceIDs: some Sequence<String>) {
        for deviceID in deviceIDs {
            pendingSettingsRestoreDeviceIDs.insert(deviceID)
            pendingSettingsRestoreGenerationByDeviceID[deviceID, default: 0] += 1
        }
    }

    func deviceIDsSharingIdentity(with device: MouseDevice) -> Set<String> {
        let identityKey = deviceIdentityKey(device)
        let matchingDeviceIDs = deviceStore.devices.filter { deviceIdentityKey($0) == identityKey }.map(\.id)
        return Set(matchingDeviceIDs).union([device.id])
    }

    func isRestoringSettings(for device: MouseDevice) -> Bool { !deviceIDsSharingIdentity(with: device).isDisjoint(with: restoringSettingsDeviceIDs) }

    func settingsRestoreRevision(for device: MouseDevice) -> Int { deviceIDsSharingIdentity(with: device).reduce(0) { partialResult, deviceID in max(partialResult, settingsRestoreRevisionByDeviceID[deviceID, default: 0]) } }

    func bumpSettingsRestoreRevision(for device: MouseDevice) { for deviceID in deviceIDsSharingIdentity(with: device) { settingsRestoreRevisionByDeviceID[deviceID, default: 0] += 1 } }

    func cancelPendingSettingsRestore(for device: MouseDevice) {
        for deviceID in deviceIDsSharingIdentity(with: device) {
            pendingSettingsRestoreDeviceIDs.remove(deviceID)
            pendingSettingsRestoreGenerationByDeviceID[deviceID, default: 0] += 1
            settingsRestoreRevisionByDeviceID[deviceID, default: 0] += 1
        }
    }

    func storeState(_ state: MouseState, for deviceID: String, updatedAt: Date) {
        stateCacheByDeviceID[deviceID] = state
        lastUpdatedByDeviceID[deviceID] = updatedAt
        lastStateMutationAtByDeviceID[deviceID] = updatedAt
    }

    func setFastDpiSuppressed(until: Date, for deviceID: String) { suppressFastDpiUntilByDeviceID[deviceID] = until }

    func diagnosticsConnectionLines(for device: MouseDevice) -> [String] {
        let deviceConnectionState = connectionState(for: device)
        let presence = deviceStore.devices.contains(where: { $0.id == device.id }) ? "Detected by macOS" : "Not detected"
        let dpiPath = deviceConnectionState == .disconnected ? "Unavailable while disconnected" : dpiUpdateTransportStatus(for: device).diagnosticsLabel
        var lines = ["Presence: \(presence)", "Telemetry: \(deviceConnectionState.diagnosticsLabel)", "DPI updates: \(dpiPath)"]
        if device.transport == .usb { lines.insert("USB control: \(usbControlAvailability(for: device).diagnosticsLabel)", at: 2) }
        return lines
    }

    func refreshConnectionDiagnostics(for device: MouseDevice) async {
        guard !isTearingDown else { return }
        guard !isStrictlyUnsupported(device) else {
            setDpiUpdateTransportStatus(.unsupported, for: device.id)
            return
        }
        guard resolvedProfile(for: device)?.passiveDPIInput != nil else {
            setDpiUpdateTransportStatus(.unsupported, for: device.id)
            return
        }
        guard deviceStore.devices.contains(where: { $0.id == device.id }) || deviceStore.selectedDeviceID == device.id else {
            setDpiUpdateTransportStatus(.unknown, for: device.id)
            return
        }
        let transportStatus = await environment.backend.dpiUpdateTransportStatus(device: device)
        guard deviceStore.devices.contains(where: { $0.id == device.id }) || deviceStore.selectedDeviceID == device.id else { return }
        setDpiUpdateTransportStatus(transportStatus, for: device.id)
    }

}
