import Foundation
import XCTest
import OpenSnekAppSupport
import OpenSnekCore
import OpenSnekHardware
@testable import OpenSnek

actor MultiDeviceStubBackend: DeviceBackend {
    nonisolated var usesRemoteServiceTransport: Bool { false }

    private let devices: [MouseDevice]
    private var stateByDeviceID: [String: MouseState]
    private var fastByDeviceID: [String: DpiFastSnapshot]
    private var readOrder: [String] = []

    init(devices: [MouseDevice], stateByDeviceID: [String: MouseState]) {
        self.devices = devices
        self.stateByDeviceID = stateByDeviceID
        self.fastByDeviceID = stateByDeviceID.reduce(into: [:]) { partialResult, entry in
            if let active = entry.value.dpi_stages.active_stage,
               let values = entry.value.dpi_stages.values {
                partialResult[entry.key] = DpiFastSnapshot(active: active, values: values)
            }
        }
    }

    func listDevices() async throws -> [MouseDevice] {
        devices
    }

    func readState(device: MouseDevice) async throws -> MouseState {
        readOrder.append(device.id)
        guard let state = stateByDeviceID[device.id] else {
            throw NSError(domain: "AppStateMultiDeviceTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing stub state for \(device.id)"
            ])
        }
        return state
    }

    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot? {
        fastByDeviceID[device.id]
    }

    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool {
        true
    }

    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .granted,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState {
        throw NSError(domain: "AppStateMultiDeviceTests", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "apply not implemented"
        ])
    }

    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? {
        nil
    }

    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? {
        nil
    }

    func recordedReadOrder() -> [String] {
        readOrder
    }

    func readCount() -> Int {
        readOrder.count
    }

    func resetReadOrder() {
        readOrder = []
    }

    func setState(_ state: MouseState, for deviceID: String) {
        stateByDeviceID[deviceID] = state
        if let active = state.dpi_stages.active_stage,
           let values = state.dpi_stages.values {
            fastByDeviceID[deviceID] = DpiFastSnapshot(active: active, values: values)
        }
    }

    func setFastSnapshot(_ snapshot: DpiFastSnapshot, for deviceID: String) {
        fastByDeviceID[deviceID] = snapshot
    }
}

actor PartiallyFailingMultiDeviceStubBackend: DeviceBackend {
    nonisolated var usesRemoteServiceTransport: Bool { false }

    private let devices: [MouseDevice]
    private let failingDeviceIDs: Set<String>
    private var stateByDeviceID: [String: MouseState]
    private var readOrder: [String] = []

    init(devices: [MouseDevice], stateByDeviceID: [String: MouseState], failingDeviceIDs: Set<String>) {
        self.devices = devices
        self.stateByDeviceID = stateByDeviceID
        self.failingDeviceIDs = failingDeviceIDs
    }

    func listDevices() async throws -> [MouseDevice] {
        devices
    }

    func readState(device: MouseDevice) async throws -> MouseState {
        readOrder.append(device.id)
        if failingDeviceIDs.contains(device.id) {
            throw NSError(domain: "AppStateMultiDeviceTests", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "USB device telemetry unavailable. Feature-report interface did not return usable responses."
            ])
        }
        guard let state = stateByDeviceID[device.id] else {
            throw NSError(domain: "AppStateMultiDeviceTests", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Missing stub state for \(device.id)"
            ])
        }
        return state
    }

    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? {
        nil
    }

    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool {
        false
    }

    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .granted,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState {
        throw NSError(domain: "AppStateMultiDeviceTests", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "apply not implemented"
        ])
    }

    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? {
        nil
    }

    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? {
        nil
    }

    func recordedReadOrder() -> [String] {
        readOrder
    }
}

actor DisconnectingMultiDeviceStubBackend: DeviceBackend {
    nonisolated var usesRemoteServiceTransport: Bool { false }

    private let devices: [MouseDevice]
    private var stateByDeviceID: [String: MouseState]
    private var unavailable = false

    init(devices: [MouseDevice], stateByDeviceID: [String: MouseState]) {
        self.devices = devices
        self.stateByDeviceID = stateByDeviceID
    }

    func listDevices() async throws -> [MouseDevice] {
        devices
    }

    func readState(device: MouseDevice) async throws -> MouseState {
        if unavailable {
            throw NSError(domain: "AppStateMultiDeviceTests", code: 6, userInfo: [
                NSLocalizedDescriptionKey: "Device not available"
            ])
        }
        guard let state = stateByDeviceID[device.id] else {
            throw NSError(domain: "AppStateMultiDeviceTests", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "Missing stub state for \(device.id)"
            ])
        }
        return state
    }

    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? {
        nil
    }

    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool {
        true
    }

    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .granted,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState {
        throw NSError(domain: "AppStateMultiDeviceTests", code: 8, userInfo: [
            NSLocalizedDescriptionKey: "apply not implemented"
        ])
    }

    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? {
        nil
    }

    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? {
        nil
    }

    func setUnavailable(_ unavailable: Bool) {
        self.unavailable = unavailable
    }
}

actor DeviceListUpdatingStubBackend: DeviceBackend {
    nonisolated var usesRemoteServiceTransport: Bool { false }

    private var devices: [MouseDevice]
    private var stateByDeviceID: [String: MouseState]
    private var usesFastDPIPolling: Bool
    private var dpiUpdateTransportStatusOverride: DpiUpdateTransportStatus?
    private var usbControlAvailabilityByDeviceID: [String: USBControlAvailability] = [:]
    private var usbControlAvailabilityProbeCountByDeviceID: [String: Int] = [:]
    private var hidAccessAuthorization: HIDAccessAuthorization
    private var readCountByDeviceID: [String: Int] = [:]
    private var transientReadFailuresByDeviceID: [String: [String]] = [:]
    private var applyPatches: [DevicePatch] = []
    private var applyDeviceIDs: [String] = []
    private let stateUpdateStreamPair = AsyncStream.makeStream(of: BackendStateUpdate.self)

    init(
        devices: [MouseDevice],
        stateByDeviceID: [String: MouseState],
        shouldUseFastDPIPolling: Bool = false,
        dpiUpdateTransportStatus: DpiUpdateTransportStatus? = nil,
        hidAccessAuthorization: HIDAccessAuthorization = .granted
    ) {
        self.devices = devices
        self.stateByDeviceID = stateByDeviceID
        self.usesFastDPIPolling = shouldUseFastDPIPolling
        self.dpiUpdateTransportStatusOverride = dpiUpdateTransportStatus
        self.hidAccessAuthorization = hidAccessAuthorization
    }

    func listDevices() async throws -> [MouseDevice] {
        devices
    }

    func readState(device: MouseDevice) async throws -> MouseState {
        readCountByDeviceID[device.id, default: 0] += 1
        if var failures = transientReadFailuresByDeviceID[device.id], !failures.isEmpty {
            let message = failures.removeFirst()
            transientReadFailuresByDeviceID[device.id] = failures
            throw NSError(domain: "AppStateMultiDeviceTests", code: 8, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
        guard let state = stateByDeviceID[device.id] else {
            throw NSError(domain: "AppStateMultiDeviceTests", code: 9, userInfo: [
                NSLocalizedDescriptionKey: "Missing stub state for \(device.id)"
            ])
        }
        return state
    }

    func readDpiStagesFast(device: MouseDevice) async throws -> DpiFastSnapshot? {
        guard let state = stateByDeviceID[device.id],
              let active = state.dpi_stages.active_stage,
              let values = state.dpi_stages.values else {
            return nil
        }
        return DpiFastSnapshot(active: active, values: values)
    }

    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool {
        usesFastDPIPolling
    }

    func dpiUpdateTransportStatus(device _: MouseDevice) async -> DpiUpdateTransportStatus {
        dpiUpdateTransportStatusOverride ?? (usesFastDPIPolling ? .pollingFallback : .realTimeHID)
    }

    func usbControlAvailability(device: MouseDevice) async throws -> USBControlAvailability {
        usbControlAvailabilityProbeCountByDeviceID[device.id, default: 0] += 1
        return usbControlAvailabilityByDeviceID[device.id] ?? .unknown
    }

    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: hidAccessAuthorization,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        stateUpdateStreamPair.stream
    }

    func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState {
        applyDeviceIDs.append(device.id)
        applyPatches.append(patch)
        guard let current = stateByDeviceID[device.id] else {
            throw NSError(domain: "AppStateMultiDeviceTests", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Missing apply state for \(device.id)"
            ])
        }
        let next = stateApplying(patch, to: current)
        stateByDeviceID[device.id] = next
        return next
    }

    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? {
        nil
    }

    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? {
        nil
    }

    func setState(_ state: MouseState, for deviceID: String) {
        stateByDeviceID[deviceID] = state
    }

    func setTransientReadFailures(_ messages: [String], for deviceID: String) {
        transientReadFailuresByDeviceID[deviceID] = messages
    }

    func emitDeviceListUpdate(_ devices: [MouseDevice], updatedAt: Date = Date()) {
        self.devices = devices
        stateUpdateStreamPair.continuation.yield(.deviceList(devices, updatedAt: updatedAt))
    }

    func setShouldUseFastDPIPolling(_ value: Bool) {
        usesFastDPIPolling = value
    }

    func setDpiUpdateTransportStatus(_ value: DpiUpdateTransportStatus?) {
        dpiUpdateTransportStatusOverride = value
    }

    func setUSBControlAvailability(_ value: USBControlAvailability, for deviceID: String) {
        usbControlAvailabilityByDeviceID[deviceID] = value
    }

    func readCount(for deviceID: String) -> Int {
        readCountByDeviceID[deviceID] ?? 0
    }

    func usbControlAvailabilityProbeCount(for deviceID: String) -> Int {
        usbControlAvailabilityProbeCountByDeviceID[deviceID] ?? 0
    }

    func applyCount() -> Int {
        applyPatches.count
    }

    func recordedPatches() -> [DevicePatch] {
        applyPatches
    }

    func recordedApplyDeviceIDs() -> [String] {
        applyDeviceIDs
    }

    private func stateApplying(_ patch: DevicePatch, to current: MouseState) -> MouseState {
        let nextStages: [Int]? = patch.dpiStages ?? current.dpi_stages.values
        let nextActive = patch.activeStage ?? current.dpi_stages.active_stage
        let resolvedStages = DpiStages(active_stage: nextActive, values: nextStages)
        let nextDpi: DpiPair? = {
            guard let values = nextStages, !values.isEmpty else {
                return current.dpi
            }
            let activeIndex = max(0, min(values.count - 1, nextActive ?? 0))
            return DpiPair(x: values[activeIndex], y: values[activeIndex])
        }()

        return MouseState(
            device: current.device,
            connection: current.connection,
            battery_percent: current.battery_percent,
            charging: current.charging,
            dpi: nextDpi,
            dpi_stages: resolvedStages,
            poll_rate: patch.pollRate ?? current.poll_rate,
            sleep_timeout: patch.sleepTimeout ?? current.sleep_timeout,
            device_mode: patch.deviceMode ?? current.device_mode,
            low_battery_threshold_raw: patch.lowBatteryThresholdRaw ?? current.low_battery_threshold_raw,
            scroll_mode: patch.scrollMode ?? current.scroll_mode,
            scroll_acceleration: patch.scrollAcceleration ?? current.scroll_acceleration,
            scroll_smart_reel: patch.scrollSmartReel ?? current.scroll_smart_reel,
            active_onboard_profile: current.active_onboard_profile,
            onboard_profile_count: current.onboard_profile_count,
            led_value: patch.ledBrightness ?? current.led_value,
            capabilities: current.capabilities
        )
    }
}

struct MultiDeviceTestIdentity {
    let transport: DeviceTransportKind
    let serial: String
    let locationID: Int
}

func makeTestDevice(
    id: String,
    productName: String,
    identity: MultiDeviceTestIdentity,
    profile: DeviceProfileID
) -> MouseDevice {
    MouseDevice(
        id: id,
        vendor_id: 0x1532,
        product_id: identity.transport == .bluetooth ? 0x00BA : 0x00AB,
        product_name: productName,
        transport: identity.transport,
        path_b64: "",
        serial: identity.serial,
        firmware: "1.0.0",
        location_id: identity.locationID,
        profile_id: profile,
        supports_advanced_lighting_effects: true,
        onboard_profile_count: 1
    )
}

func makeTestState(
    device: MouseDevice,
    connection: String,
    batteryPercent: Int,
    dpiValues: [Int],
    activeStage: Int
) -> MouseState {
    let dpiValue = dpiValues.indices.contains(activeStage) ? dpiValues[activeStage] : (dpiValues.first ?? 0)
    return MouseState(
        device: DeviceSummary(
            id: device.id,
            product_name: device.product_name,
            serial: device.serial,
            transport: device.transport,
            firmware: device.firmware
        ),
        connection: connection,
        battery_percent: batteryPercent,
        charging: false,
        dpi: DpiPair(x: dpiValue, y: dpiValue),
        dpi_stages: DpiStages(active_stage: activeStage, values: dpiValues),
        poll_rate: 1000,
        device_mode: DeviceMode(mode: 0x00, param: 0x00),
        led_value: 64,
        capabilities: Capabilities(
            dpi_stages: true,
            poll_rate: true,
            power_management: true,
            button_remap: true,
            lighting: true
        )
    )
}

func makeMultiDeviceSettingsSnapshot(color: OpenSnekCore.RGBColor) -> PersistedDeviceSettingsSnapshot {
    PersistedDeviceSettingsSnapshot(
        stageCount: 3,
        stageValues: [900, 1800, 3600],
        stagePairs: [
            DpiPair(x: 900, y: 900),
            DpiPair(x: 1800, y: 1800),
            DpiPair(x: 3600, y: 3600)
        ],
        activeStage: 3,
        pollRate: 500,
        sleepTimeout: 420,
        lowBatteryThresholdRaw: 0x20,
        scrollMode: 1,
        scrollAcceleration: true,
        scrollSmartReel: false,
        ledBrightness: 77,
        primaryLightingColor: color,
        lightingEffect: nil,
        usbLightingZoneID: "scroll_wheel",
        buttonBindings: [:]
    )
}

func clearMultiDeviceLightingPreferences(for device: MouseDevice) {
    let defaults = UserDefaults.standard
    let key = DevicePersistenceKeys.key(for: device)
    let legacyKey = DevicePersistenceKeys.legacyKey(for: device)
    let prefixes = [
        "lightingColor.\(key)",
        "lightingColor.\(legacyKey)",
        "lightingZone.\(key)",
        "lightingZone.\(legacyKey)",
        "lightingEffect.\(key)",
        "lightingEffect.\(legacyKey)",
        "connectBehavior.\(key)",
        "connectBehavior.\(legacyKey)",
        "settingsSnapshot.\(key)",
        "settingsSnapshot.\(legacyKey)"
    ]
    for storedKey in defaults.dictionaryRepresentation().keys
    where prefixes.contains(where: { storedKey.hasPrefix($0) }) {
        defaults.removeObject(forKey: storedKey)
    }
}

func waitForAppStateCondition(
    timeout: TimeInterval = 1.0,
    condition: @escaping @Sendable () async -> Bool
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if await condition() {
                    return
                }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            throw NSError(domain: "AppStateMultiDeviceTests", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "Timed out waiting for AppState condition"
            ])
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw NSError(domain: "AppStateMultiDeviceTests", code: 12, userInfo: [
                NSLocalizedDescriptionKey: "Timed out waiting for AppState condition"
            ])
        }

        _ = try await group.next()
        group.cancelAll()
    }
}
