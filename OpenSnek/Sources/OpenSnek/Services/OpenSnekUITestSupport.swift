#if DEBUG
import Foundation
import OpenSnekCore

struct UITestApplyEvent {
    let device: MouseDevice
    let patch: DevicePatch
    let state: MouseState?
    let activeApplyCount: Int
    let maxConcurrentApplyCount: Int
    let elapsed: TimeInterval?
    let readbackPolicy: String
    let error: Error?
}

struct UITestProfileMutationEvent {
    let device: MouseDevice
    let profileID: Int
    let mutation: OnboardProfileMutation
    let activeMutationCount: Int
    let maxConcurrentMutationCount: Int
    let elapsed: TimeInterval?
    let error: Error?
}

enum OpenSnekUITestSupport {
    private static let eventsPathEnvironmentKey = "OPEN_SNEK_UITEST_EVENTS_PATH"
    private static let runIDEnvironmentKey = "OPEN_SNEK_UITEST_RUN_ID"
    private static let forceLocalBackendEnvironmentKey = "OPEN_SNEK_UITEST_FORCE_LOCAL_BACKEND"
    private static let eventsPathArgument = "--ui-test-events-path"
    private static let runIDArgument = "--ui-test-run-id"
    private static let forceLocalBackendArgument = "--ui-test-force-local-backend"

    static var isEnabled: Bool {
        guard let path = eventLogPath() else { return false }
        return !path.isEmpty
    }

    static var forcesLocalBackend: Bool {
        if ProcessInfo.processInfo.arguments.contains(forceLocalBackendArgument) {
            return true
        }
        return boolEnvironmentValue(ProcessInfo.processInfo.environment[forceLocalBackendEnvironmentKey], defaultValue: false)
    }

    static func recordLaunch(role: OpenSnekProcessRole) {
        recorder.record(name: "launch", source: role.rawValue)
    }

    static func recordHIDAccessStatus(_ status: HIDAccessStatus, source: String) {
        recorder.record(
            name: "hidAccessStatus",
            source: source,
            hidAccessStatus: OpenSnekUITestHIDAccessSnapshot(status)
        )
    }

    static func recordListDevices(_ devices: [MouseDevice], elapsed: TimeInterval, source: String) {
        recorder.record(
            name: "listDevices",
            source: source,
            devices: devices.map(OpenSnekUITestDeviceSnapshot.init),
            elapsed: elapsed
        )
    }

    static func recordListDevicesError(_ error: Error, elapsed: TimeInterval, source: String) {
        recorder.record(
            name: "listDevicesError",
            source: source,
            elapsed: elapsed,
            error: error.localizedDescription
        )
    }

    static func recordReadState(device: MouseDevice, state: MouseState, elapsed: TimeInterval, source: String) {
        recorder.record(
            name: "readState",
            source: source,
            deviceID: device.id,
            scope: OpenSnekUITestScopeSnapshot(device),
            state: OpenSnekUITestStateSnapshot(state),
            elapsed: elapsed
        )
    }

    static func recordApplyStart(_ event: UITestApplyEvent) {
        recorder.record(
            name: "applyStart",
            deviceID: event.device.id,
            scope: OpenSnekUITestScopeSnapshot(event.device),
            patch: OpenSnekUITestPatchSnapshot(event.patch),
            activeApplyCount: event.activeApplyCount,
            maxConcurrentApplyCount: event.maxConcurrentApplyCount,
            readbackPolicy: event.readbackPolicy
        )
    }

    static func recordApplyEnd(_ event: UITestApplyEvent) {
        recorder.record(
            name: "applyEnd",
            deviceID: event.device.id,
            scope: OpenSnekUITestScopeSnapshot(event.device),
            patch: OpenSnekUITestPatchSnapshot(event.patch),
            state: event.state.map(OpenSnekUITestStateSnapshot.init),
            activeApplyCount: event.activeApplyCount,
            maxConcurrentApplyCount: event.maxConcurrentApplyCount,
            elapsed: event.elapsed,
            readbackPolicy: event.readbackPolicy
        )
    }

    static func recordApplyError(_ event: UITestApplyEvent) {
        recorder.record(
            name: "applyError",
            deviceID: event.device.id,
            scope: OpenSnekUITestScopeSnapshot(event.device),
            patch: OpenSnekUITestPatchSnapshot(event.patch),
            activeApplyCount: event.activeApplyCount,
            maxConcurrentApplyCount: event.maxConcurrentApplyCount,
            elapsed: event.elapsed,
            readbackPolicy: event.readbackPolicy,
            error: event.error?.localizedDescription
        )
    }

    static func recordOverlapDetected(
        device: MouseDevice,
        patch: DevicePatch,
        activeApplyCount: Int,
        maxConcurrentApplyCount: Int
    ) {
        recorder.record(
            name: "overlapDetected",
            deviceID: device.id,
            scope: OpenSnekUITestScopeSnapshot(device),
            patch: OpenSnekUITestPatchSnapshot(patch),
            activeApplyCount: activeApplyCount,
            maxConcurrentApplyCount: maxConcurrentApplyCount
        )
    }

    static func recordOnboardProfileMutationStart(_ event: UITestProfileMutationEvent) {
        recorder.record(
            name: "onboardProfileMutationStart",
            deviceID: event.device.id,
            scope: OpenSnekUITestScopeSnapshot(event.device),
            profileID: event.profileID,
            onboardMutation: UITestProfileMutationSnapshot(event.mutation),
            activeApplyCount: event.activeMutationCount,
            maxConcurrentApplyCount: event.maxConcurrentMutationCount
        )
    }

    static func recordOnboardProfileMutationEnd(_ event: UITestProfileMutationEvent) {
        recorder.record(
            name: "onboardProfileMutationEnd",
            deviceID: event.device.id,
            scope: OpenSnekUITestScopeSnapshot(event.device),
            profileID: event.profileID,
            onboardMutation: UITestProfileMutationSnapshot(event.mutation),
            activeApplyCount: event.activeMutationCount,
            maxConcurrentApplyCount: event.maxConcurrentMutationCount,
            elapsed: event.elapsed
        )
    }

    static func recordOnboardProfileMutationError(_ event: UITestProfileMutationEvent) {
        recorder.record(
            name: "onboardProfileMutationError",
            deviceID: event.device.id,
            scope: OpenSnekUITestScopeSnapshot(event.device),
            profileID: event.profileID,
            onboardMutation: UITestProfileMutationSnapshot(event.mutation),
            activeApplyCount: event.activeMutationCount,
            maxConcurrentApplyCount: event.maxConcurrentMutationCount,
            elapsed: event.elapsed,
            error: event.error?.localizedDescription
        )
    }

    static func recordOnboardProfileMutationOverlapDetected(
        device: MouseDevice,
        profileID: Int,
        mutation: OnboardProfileMutation,
        activeMutationCount: Int,
        maxConcurrentMutationCount: Int
    ) {
        recorder.record(
            name: "overlapDetected",
            source: "onboard-profile",
            deviceID: device.id,
            scope: OpenSnekUITestScopeSnapshot(device),
            profileID: profileID,
            onboardMutation: UITestProfileMutationSnapshot(mutation),
            activeApplyCount: activeMutationCount,
            maxConcurrentApplyCount: maxConcurrentMutationCount
        )
    }

    static func recordUSBCommand(
        device: MouseDevice,
        classID: UInt8,
        cmdID: UInt8,
        size: UInt8,
        args: [UInt8]
    ) {
        recorder.record(
            name: "usbCommand",
            deviceID: device.id,
            scope: OpenSnekUITestScopeSnapshot(device),
            command: OpenSnekUITestUSBCommandSnapshot(
                name: usbCommandName(classID: classID, cmdID: cmdID),
                protocolName: protocolName(for: device.transport),
                classID: Int(classID),
                cmdID: Int(cmdID),
                size: Int(size),
                args: args.map(Int.init)
            )
        )
    }

    private static let recorder = OpenSnekUITestEventRecorder()

    fileprivate static func eventLogPath(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> String? {
        if let value = environment[eventsPathEnvironmentKey], !value.isEmpty {
            return value
        }
        return argumentValue(after: eventsPathArgument, in: arguments)
    }

    fileprivate static func runID(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> String {
        if let value = environment[runIDEnvironmentKey], !value.isEmpty {
            return value
        }
        return argumentValue(after: runIDArgument, in: arguments) ?? UUID().uuidString
    }

    private static func boolEnvironmentValue(_ value: String?, defaultValue: Bool) -> Bool {
        guard let value else { return defaultValue }
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "0", "false", "no", "off":
            return false
        case "1", "true", "yes", "on":
            return true
        default:
            return defaultValue
        }
    }

    private static func argumentValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        let value = arguments[valueIndex]
        return value.isEmpty ? nil : value
    }

    private static func usbCommandName(classID: UInt8, cmdID: UInt8) -> String {
        switch (classID, cmdID) {
        case (0x00, 0x05):
            return "usbSetPollRate"
        case (0x0F, 0x03):
            return "usbLightingCustomFrame"
        default:
            return "usbCommand"
        }
    }

    private static func protocolName(for transport: DeviceTransportKind) -> String {
        switch transport {
        case .usb:
            return "usb-hid"
        case .bluetooth:
            return "ble-vendor"
        }
    }
}

private final class OpenSnekUITestEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let runID: String
    private let eventsURL: URL?
    private var didPrepareFile = false

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        runID = OpenSnekUITestSupport.runID(environment: environment, arguments: arguments)
        eventsURL = OpenSnekUITestSupport.eventLogPath(environment: environment, arguments: arguments).flatMap { path in
            path.isEmpty ? nil : URL(fileURLWithPath: path)
        }
    }

    func record(
        name: String,
        source: String? = nil,
        deviceID: String? = nil,
        scope: OpenSnekUITestScopeSnapshot? = nil,
        profileID: Int? = nil,
        devices: [OpenSnekUITestDeviceSnapshot]? = nil,
        patch: OpenSnekUITestPatchSnapshot? = nil,
        onboardMutation: UITestProfileMutationSnapshot? = nil,
        command: OpenSnekUITestUSBCommandSnapshot? = nil,
        state: OpenSnekUITestStateSnapshot? = nil,
        activeApplyCount: Int? = nil,
        maxConcurrentApplyCount: Int? = nil,
        elapsed: TimeInterval? = nil,
        readbackPolicy: String? = nil,
        hidAccessStatus: OpenSnekUITestHIDAccessSnapshot? = nil,
        error: String? = nil
    ) {
        guard let eventsURL else { return }

        let event = OpenSnekUITestEvent(
            timestamp: Date().timeIntervalSince1970,
            runID: runID,
            name: name,
            source: source,
            deviceID: deviceID,
            scope: scope,
            profileID: profileID,
            devices: devices,
            patch: patch,
            onboardMutation: onboardMutation,
            command: command,
            state: state,
            activeApplyCount: activeApplyCount,
            maxConcurrentApplyCount: maxConcurrentApplyCount,
            elapsed: elapsed,
            readbackPolicy: readbackPolicy,
            hidAccessStatus: hidAccessStatus,
            error: error
        )

        lock.lock()
        defer { lock.unlock() }

        prepareFileIfNeeded(eventsURL)
        guard let data = try? encoder.encode(event) else { return }
        append(data + Data([0x0A]), to: eventsURL)
    }

    private func prepareFileIfNeeded(_ url: URL) {
        guard !didPrepareFile else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        didPrepareFile = true
    }

    private func append(_ data: Data, to url: URL) {
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: data)
    }
}

private struct OpenSnekUITestEvent: Encodable {
    let timestamp: TimeInterval
    let runID: String
    let name: String
    let source: String?
    let deviceID: String?
    let scope: OpenSnekUITestScopeSnapshot?
    let profileID: Int?
    let devices: [OpenSnekUITestDeviceSnapshot]?
    let patch: OpenSnekUITestPatchSnapshot?
    let onboardMutation: UITestProfileMutationSnapshot?
    let command: OpenSnekUITestUSBCommandSnapshot?
    let state: OpenSnekUITestStateSnapshot?
    let activeApplyCount: Int?
    let maxConcurrentApplyCount: Int?
    let elapsed: TimeInterval?
    let readbackPolicy: String?
    let hidAccessStatus: OpenSnekUITestHIDAccessSnapshot?
    let error: String?
}

private struct OpenSnekUITestScopeSnapshot: Encodable {
    let protocolName: String
    let transport: String
    let vendorID: Int
    let productID: Int
    let productName: String
    let profileID: String?

    init(_ device: MouseDevice) {
        protocolName = device.transport == .usb ? "usb-hid" : "ble-vendor"
        transport = device.transport.rawValue
        vendorID = device.vendor_id
        productID = device.product_id
        productName = device.product_name
        profileID = device.profile_id?.rawValue
    }
}

private struct OpenSnekUITestDeviceSnapshot: Encodable {
    let id: String
    let protocolName: String
    let transport: String
    let vendorID: Int
    let productID: Int
    let productName: String
    let profileID: String?
    let serial: String?

    init(_ device: MouseDevice) {
        id = device.id
        protocolName = device.transport == .usb ? "usb-hid" : "ble-vendor"
        transport = device.transport.rawValue
        vendorID = device.vendor_id
        productID = device.product_id
        productName = device.product_name
        profileID = device.profile_id?.rawValue
        serial = device.serial
    }
}

private struct OpenSnekUITestPatchSnapshot: Encodable {
    let pollRate: Int?
    let sleepTimeout: Int?
    let lowBatteryThresholdRaw: Int?
    let scrollMode: Int?
    let scrollAcceleration: Bool?
    let scrollSmartReel: Bool?
    let activeStage: Int?
    let dpiStages: [Int]?
    let dpiStagePairs: [OpenSnekUITestDpiPairSnapshot]?
    let ledBrightness: Int?
    let ledRGB: OpenSnekUITestRGBSnapshot?

    init(_ patch: DevicePatch) {
        pollRate = patch.pollRate
        sleepTimeout = patch.sleepTimeout
        lowBatteryThresholdRaw = patch.lowBatteryThresholdRaw
        scrollMode = patch.scrollMode
        scrollAcceleration = patch.scrollAcceleration
        scrollSmartReel = patch.scrollSmartReel
        activeStage = patch.activeStage
        dpiStages = patch.dpiStages
        dpiStagePairs = patch.dpiStagePairs?.map(OpenSnekUITestDpiPairSnapshot.init)
        ledBrightness = patch.ledBrightness
        ledRGB = patch.ledRGB.map(OpenSnekUITestRGBSnapshot.init)
    }
}

private struct UITestProfileMutationSnapshot: Encodable {
    let metadataName: String?
    let dpiActiveStage: Int?
    let dpiStages: [Int]?
    let dpiStagePairs: [OpenSnekUITestDpiPairSnapshot]?
    let buttonBindingSlots: [Int]?
    let buttonBindingKindsBySlot: [String: String]?
    let buttonBindingClutchDPIBySlot: [String: Int]?
    let brightnessByLEDID: [String: Int]?
    let staticColorLEDIDs: [Int]?
    let scrollMode: Int?
    let scrollAcceleration: Bool?
    let scrollSmartReel: Bool?

    init(_ mutation: OnboardProfileMutation) {
        metadataName = mutation.metadata?.name
        dpiActiveStage = mutation.dpi?.activeStage
        dpiStages = mutation.dpi?.values
        dpiStagePairs = mutation.dpi?.pairs.map(OpenSnekUITestDpiPairSnapshot.init)
        buttonBindingSlots = mutation.buttonBindings?.keys.sorted()
        buttonBindingKindsBySlot = mutation.buttonBindings.map { bindings in
            Dictionary(uniqueKeysWithValues: bindings.map { (String($0.key), $0.value.kind.rawValue) })
        }
        buttonBindingClutchDPIBySlot = mutation.buttonBindings.map { bindings in
            Dictionary(uniqueKeysWithValues: bindings.compactMap { slot, draft in
                draft.clutchDPI.map { (String(slot), $0) }
            })
        }
        brightnessByLEDID = mutation.brightnessByLEDID.map { values in
            Dictionary(uniqueKeysWithValues: values.map { (String($0.key), $0.value) })
        }
        staticColorLEDIDs = mutation.staticColorByLEDID?.keys.sorted()
        scrollMode = mutation.scrollMode
        scrollAcceleration = mutation.scrollAcceleration
        scrollSmartReel = mutation.scrollSmartReel
    }
}

private struct OpenSnekUITestUSBCommandSnapshot: Encodable {
    let name: String
    let protocolName: String
    let classID: Int
    let cmdID: Int
    let size: Int
    let args: [Int]
}

private struct OpenSnekUITestStateSnapshot: Encodable {
    let connection: String
    let pollRate: Int?
    let dpi: Int?
    let activeStage: Int?
    let dpiStages: [Int]?
    let dpiStagePairs: [OpenSnekUITestDpiPairSnapshot]?
    let sleepTimeout: Int?
    let lowBatteryThresholdRaw: Int?
    let scrollMode: Int?
    let scrollAcceleration: Bool?
    let scrollSmartReel: Bool?
    let activeOnboardProfile: Int?
    let ledValue: Int?

    init(_ state: MouseState) {
        connection = state.connection
        pollRate = state.poll_rate
        dpi = state.dpi?.x
        activeStage = state.dpi_stages.active_stage
        dpiStages = state.dpi_stages.values
        dpiStagePairs = state.dpi_stages.pairs?.map(OpenSnekUITestDpiPairSnapshot.init)
        sleepTimeout = state.sleep_timeout
        lowBatteryThresholdRaw = state.low_battery_threshold_raw
        scrollMode = state.scroll_mode
        scrollAcceleration = state.scroll_acceleration
        scrollSmartReel = state.scroll_smart_reel
        activeOnboardProfile = state.active_onboard_profile
        ledValue = state.led_value
    }
}

private struct OpenSnekUITestDpiPairSnapshot: Encodable {
    let x: Int
    let y: Int

    init(_ pair: DpiPair) {
        x = pair.x
        y = pair.y
    }
}

private struct OpenSnekUITestRGBSnapshot: Encodable {
    let r: Int
    let g: Int
    let b: Int

    init(_ rgb: RGBPatch) {
        r = rgb.r
        g = rgb.g
        b = rgb.b
    }
}

private struct OpenSnekUITestHIDAccessSnapshot: Encodable {
    let authorization: String
    let hostLabel: String
    let bundleIdentifier: String?
    let detail: String?

    init(_ status: HIDAccessStatus) {
        authorization = status.authorization.rawValue
        hostLabel = status.hostLabel
        bundleIdentifier = status.bundleIdentifier
        detail = status.detail
    }
}
#endif
