@preconcurrency import Foundation
import IOKit.hid
import OpenSnekCore

/// Stores passive DPI reading data.
public struct PassiveDPIReading: Hashable, Codable, Sendable {
    public let dpiX: Int
    public let dpiY: Int

    public init(dpiX: Int, dpiY: Int) {
        self.dpiX = dpiX
        self.dpiY = dpiY
    }
}

/// Describes passive DPI event data.
public struct PassiveDPIEvent: Hashable, Sendable {
    public let deviceID: String
    public let dpiX: Int
    public let dpiY: Int
    public let observedAt: Date

    public init(deviceID: String, dpiX: Int, dpiY: Int, observedAt: Date) {
        self.deviceID = deviceID
        self.dpiX = dpiX
        self.dpiY = dpiY
        self.observedAt = observedAt
    }
}

/// Describes passive DPI heartbeat event data.
public struct PassiveDPIHeartbeatEvent: Sendable {
    public let deviceID: String
    public let observedAt: Date

    public init(
        deviceID: String,
        observedAt: Date
    ) {
        self.deviceID = deviceID
        self.observedAt = observedAt
    }
}

/// Describes passive profile switch event data.
public struct PassiveProfileSwitchEvent: Sendable {
    public let deviceID: String
    public let observedAt: Date

    public init(
        deviceID: String,
        observedAt: Date
    ) {
        self.deviceID = deviceID
        self.observedAt = observedAt
    }
}

/// Defines passive DPI input classification values.
public enum PassiveDPIInputClassification: Hashable, Sendable {
    case dpi(PassiveDPIReading)
    case heartbeat
    case profileSwitch
    case other
}

/// Defines passive DPI parser values.
public enum PassiveDPIParser {
    public static func classify(
        report: [UInt8],
        descriptor: PassiveDPIInputDescriptor,
        profileSwitchPreludeSatisfied: Bool = false
    ) -> PassiveDPIInputClassification {
        if matchesProfileSwitchPrefix(report: report, descriptor: descriptor) {
            guard descriptor.profileSwitchPreludePrefixes.isEmpty || profileSwitchPreludeSatisfied else {
                return .other
            }
            return .profileSwitch
        }

        let allowedSubtypes = [descriptor.subtype, descriptor.heartbeatSubtype].compactMap { $0 }
        guard report.count >= descriptor.minInputReportSize,
              let payloadStart = payloadStartIndex(
                  in: report,
                  descriptor: descriptor,
                  allowedSubtypes: allowedSubtypes
              ) else {
            return .other
        }

        let subtype = report[payloadStart]
        if subtype == descriptor.subtype {
            guard report.count > payloadStart + 4 else { return .other }

            let dpiX = (Int(report[payloadStart + 1]) << 8) | Int(report[payloadStart + 2])
            let dpiY = (Int(report[payloadStart + 3]) << 8) | Int(report[payloadStart + 4])
            let dpiRange = DeviceProfiles.minimumDPI...descriptor.maximumDPI
            guard dpiRange.contains(dpiX), dpiRange.contains(dpiY) else { return .other }
            return .dpi(PassiveDPIReading(dpiX: dpiX, dpiY: dpiY))
        }

        if let heartbeatSubtype = descriptor.heartbeatSubtype, subtype == heartbeatSubtype {
            return .heartbeat
        }

        return .other
    }

    public static func parse(
        report: [UInt8],
        descriptor: PassiveDPIInputDescriptor
    ) -> PassiveDPIReading? {
        guard case .dpi(let reading) = classify(report: report, descriptor: descriptor) else { return nil }
        return reading
    }

    public static func matchesProfileSwitchPrelude(
        report: [UInt8],
        descriptor: PassiveDPIInputDescriptor
    ) -> Bool {
        matchesAnyPrefix(
            report: report,
            prefixes: descriptor.profileSwitchPreludePrefixes
        )
    }

    private static func payloadStartIndex(
        in report: [UInt8],
        descriptor: PassiveDPIInputDescriptor,
        allowedSubtypes: [UInt8]
    ) -> Int? {
        if let first = report.first, allowedSubtypes.contains(first) {
            return 0
        }

        var index = 0
        while index < report.count, report[index] == descriptor.reportID {
            let candidate = index + 1
            if candidate < report.count, allowedSubtypes.contains(report[candidate]) {
                return candidate
            }
            index += 1
        }

        return nil
    }

    private static func matchesProfileSwitchPrefix(
        report: [UInt8],
        descriptor: PassiveDPIInputDescriptor
    ) -> Bool {
        matchesAnyPrefix(
            report: report,
            prefixes: descriptor.profileSwitchPrefixes
        )
    }

    private static func matchesAnyPrefix(
        report: [UInt8],
        prefixes: [[UInt8]]
    ) -> Bool {
        prefixes.contains { prefix in
            guard !prefix.isEmpty, report.count >= prefix.count else { return false }
            return zip(prefix, report).allSatisfy { expected, actual in
                expected == actual
            }
        }
    }
}

/// Monitors passive DPI event changes.
public final class PassiveDPIEventMonitor: @unchecked Sendable {
    /// Stores watch target data.
    public struct WatchTarget: @unchecked Sendable {
        public let deviceID: String
        public let targetID: String
        public let device: IOHIDDevice
        public let deviceIdentityToken: String
        public let descriptor: PassiveDPIInputDescriptor

        public init(
            deviceID: String,
            targetID: String,
            device: IOHIDDevice,
            deviceIdentityToken: String,
            descriptor: PassiveDPIInputDescriptor
        ) {
            self.deviceID = deviceID
            self.targetID = targetID
            self.device = device
            self.deviceIdentityToken = deviceIdentityToken
            self.descriptor = descriptor
        }
    }

    /// Coordinates callback context behavior.
    private final class CallbackContext {
        let deviceID: String
        let descriptor: PassiveDPIInputDescriptor
        let emit: @Sendable (PassiveDPIEvent) -> Void
        let emitHeartbeat: @Sendable (PassiveDPIHeartbeatEvent) -> Void
        let emitProfileSwitch: @Sendable (PassiveProfileSwitchEvent) -> Void
        var lastProfileSwitchPreludeAt: Date?

        init(
            deviceID: String,
            descriptor: PassiveDPIInputDescriptor,
            emit: @escaping @Sendable (PassiveDPIEvent) -> Void,
            emitHeartbeat: @escaping @Sendable (PassiveDPIHeartbeatEvent) -> Void,
            emitProfileSwitch: @escaping @Sendable (PassiveProfileSwitchEvent) -> Void
        ) {
            self.deviceID = deviceID
            self.descriptor = descriptor
            self.emit = emit
            self.emitHeartbeat = emitHeartbeat
            self.emitProfileSwitch = emitProfileSwitch
        }

        func profileSwitchPreludeSatisfied(observedAt: Date, window: TimeInterval) -> Bool {
            guard !descriptor.profileSwitchPreludePrefixes.isEmpty else { return true }
            guard let lastProfileSwitchPreludeAt else { return false }
            let age = observedAt.timeIntervalSince(lastProfileSwitchPreludeAt)
            if age >= 0, age <= window {
                return true
            }
            self.lastProfileSwitchPreludeAt = nil
            return false
        }
    }

    /// Identifies registration values.
    private struct RegistrationKey: Hashable {
        let deviceID: String
        let targetID: String

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.deviceID == rhs.deviceID && lhs.targetID == rhs.targetID
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(deviceID)
            hasher.combine(targetID)
        }
    }

    /// Stores registration data.
    private struct Registration {
        let device: IOHIDDevice
        let deviceIdentityToken: String
        let descriptor: PassiveDPIInputDescriptor
        let buffer: UnsafeMutablePointer<UInt8>
        let bufferLength: CFIndex
        let context: UnsafeMutableRawPointer
    }

    public var onEvent: (@Sendable (PassiveDPIEvent) -> Void)?
    public var onHeartbeat: (@Sendable (PassiveDPIHeartbeatEvent) -> Void)?
    public var onProfileSwitch: (@Sendable (PassiveProfileSwitchEvent) -> Void)?
    private static let profileSwitchPreludeWindow: TimeInterval = 0.5
    private let queue = DispatchQueue(label: "open.snek.hid.passive-dpi")
    private let runLoopStateLock = NSLock()
    private var runLoop: CFRunLoop?
    private var thread: Thread?
    private var keepAlivePort: Port?
    private var registrationsByKey: [RegistrationKey: Registration] = [:]

    public init() {}

    public func replaceTargets(
        _ targets: [WatchTarget],
        forceRebuildDeviceIDs: Set<String> = []
    ) async -> Set<String> {
        await withCheckedContinuation { continuation in
            queue.async {
                self.ensureRunLoopLocked()
                self.performOnRunLoopLocked {
                    let active = self.replaceTargetsOnRunLoop(
                        targets,
                        forceRebuildDeviceIDs: forceRebuildDeviceIDs
                    )
                    continuation.resume(returning: active)
                }
            }
        }
    }

    private func ensureRunLoopLocked() {
        runLoopStateLock.lock()
        if runLoop != nil {
            runLoopStateLock.unlock()
            return
        }
        runLoopStateLock.unlock()

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }

            let keepAlivePort = Port()
            RunLoop.current.add(keepAlivePort, forMode: .default)
            let currentRunLoop = CFRunLoopGetCurrent()

            self.runLoopStateLock.lock()
            self.keepAlivePort = keepAlivePort
            self.runLoop = currentRunLoop
            self.runLoopStateLock.unlock()
            ready.signal()

            while !Thread.current.isCancelled {
                let _: Void = autoreleasepool {
                    CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 1.0, false)
                }
            }
        }
        thread.name = "open.snek.hid.passive-dpi"
        runLoopStateLock.lock()
        self.thread = thread
        runLoopStateLock.unlock()
        thread.start()
        ready.wait()
    }

    private func performOnRunLoopLocked(_ block: @escaping () -> Void) {
        guard let runLoop else {
            block()
            return
        }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    private func replaceTargetsOnRunLoop(
        _ targets: [WatchTarget],
        forceRebuildDeviceIDs: Set<String>
    ) -> Set<String> {
        var desiredByKey: [RegistrationKey: WatchTarget] = [:]
        for target in targets {
            let key = RegistrationKey(
                deviceID: target.deviceID,
                targetID: target.targetID
            )
            desiredByKey[key] = target
        }

        let obsoleteKeys = Set(registrationsByKey.keys).subtracting(desiredByKey.keys)
        for key in obsoleteKeys {
            removeRegistration(key: key)
        }
        if !forceRebuildDeviceIDs.isEmpty {
            let forcedKeys = registrationsByKey.keys.filter { forceRebuildDeviceIDs.contains($0.deviceID) }
            for key in forcedKeys {
                removeRegistration(key: key)
            }
        }

        var activeDeviceIDs: Set<String> = []
        for (key, target) in desiredByKey {
            if let existing = registrationsByKey[key],
               Self.shouldReuseRegistration(
                existingDescriptor: existing.descriptor,
                existingDeviceIdentityToken: existing.deviceIdentityToken,
                targetDescriptor: target.descriptor,
                targetDeviceIdentityToken: target.deviceIdentityToken
               ) {
                activeDeviceIDs.insert(target.deviceID)
                continue
            }

            removeRegistration(key: key)
            if addRegistration(target: target, key: key) {
                activeDeviceIDs.insert(target.deviceID)
            }
        }

        return activeDeviceIDs
    }

    private func addRegistration(target: WatchTarget, key: RegistrationKey) -> Bool {
        // Recreate the HID device on the passive-monitor thread before opening it.
        // Reusing the discovery-thread wrapper across run loops can leave BLE
        // passive listeners stuck on startup heartbeat traffic with no later DPI callbacks.
        let registrationDevice = Self.registrationDevice(from: target.device) ?? target.device
        let openResult = IOHIDDeviceOpen(registrationDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { return false }

        let reportLength = max(
            target.descriptor.minInputReportSize,
            USBHIDSupport.intProperty(registrationDevice, key: kIOHIDMaxInputReportSizeKey as CFString) ?? target.descriptor.minInputReportSize
        )
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportLength)
        buffer.initialize(repeating: 0, count: reportLength)

        let contextBox = CallbackContext(
            deviceID: target.deviceID,
            descriptor: target.descriptor
        ) { [weak self] event in
            self?.onEvent?(event)
        } emitHeartbeat: { [weak self] event in
            self?.onHeartbeat?(event)
        } emitProfileSwitch: { [weak self] event in
            self?.onProfileSwitch?(event)
        }
        let context = UnsafeMutableRawPointer(Unmanaged.passRetained(contextBox).toOpaque())

        IOHIDDeviceScheduleWithRunLoop(registrationDevice, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(
            registrationDevice,
            buffer,
            CFIndex(reportLength),
            Self.inputReportCallback,
            context
        )

        registrationsByKey[key] = Registration(
            device: registrationDevice,
            deviceIdentityToken: target.deviceIdentityToken,
            descriptor: target.descriptor,
            buffer: buffer,
            bufferLength: CFIndex(reportLength),
            context: context
        )
        return true
    }

    private func removeRegistration(key: RegistrationKey) {
        guard let registration = registrationsByKey.removeValue(forKey: key) else { return }
        IOHIDDeviceUnscheduleFromRunLoop(
            registration.device,
            CFRunLoopGetCurrent(),
            CFRunLoopMode.defaultMode.rawValue
        )
        IOHIDDeviceClose(registration.device, IOOptionBits(kIOHIDOptionsTypeNone))
        registration.buffer.deinitialize(count: Int(registration.bufferLength))
        registration.buffer.deallocate()
        Unmanaged<CallbackContext>.fromOpaque(registration.context).release()
    }

    static func shouldReuseRegistration(
        existingDescriptor: PassiveDPIInputDescriptor,
        existingDeviceIdentityToken: String,
        targetDescriptor: PassiveDPIInputDescriptor,
        targetDeviceIdentityToken: String
    ) -> Bool {
        existingDescriptor == targetDescriptor &&
            existingDeviceIdentityToken == targetDeviceIdentityToken
    }

    private static let inputReportCallback: IOHIDReportCallback = { context, result, _, reportType, _, report, reportLength in
        guard result == kIOReturnSuccess, reportType == kIOHIDReportTypeInput, let context else { return }
        let callbackContext = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
        let bytes = Array(UnsafeBufferPointer(start: report, count: max(0, reportLength)))
        let observedAt = Date()
        if PassiveDPIParser.matchesProfileSwitchPrelude(report: bytes, descriptor: callbackContext.descriptor) {
            callbackContext.lastProfileSwitchPreludeAt = observedAt
            return
        }

        let profileSwitchPreludeSatisfied = callbackContext.profileSwitchPreludeSatisfied(
            observedAt: observedAt,
            window: PassiveDPIEventMonitor.profileSwitchPreludeWindow
        )
        switch PassiveDPIParser.classify(
            report: bytes,
            descriptor: callbackContext.descriptor,
            profileSwitchPreludeSatisfied: profileSwitchPreludeSatisfied
        ) {
        case .dpi(let reading):
            callbackContext.emit(
                PassiveDPIEvent(
                    deviceID: callbackContext.deviceID,
                    dpiX: reading.dpiX,
                    dpiY: reading.dpiY,
                    observedAt: observedAt
                )
            )
        case .heartbeat:
            callbackContext.emitHeartbeat(
                PassiveDPIHeartbeatEvent(
                    deviceID: callbackContext.deviceID,
                    observedAt: observedAt
                )
            )
        case .profileSwitch:
            callbackContext.lastProfileSwitchPreludeAt = nil
            callbackContext.emitProfileSwitch(
                PassiveProfileSwitchEvent(
                    deviceID: callbackContext.deviceID,
                    observedAt: observedAt
                )
            )
        case .other:
            break
        }
    }

    private static func registrationDevice(from device: IOHIDDevice) -> IOHIDDevice? {
        let service = IOHIDDeviceGetService(device)
        guard service != 0 else { return nil }
        return IOHIDDeviceCreate(kCFAllocatorDefault, service)
    }
}
