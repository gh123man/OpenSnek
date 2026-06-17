import Foundation
import Darwin
import IOKit
import IOKit.hid
import OpenSnekProtocols

public enum USBHIDSupport {
    public static func intProperty(_ device: IOHIDDevice, key: CFString) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key) else { return nil }
        if CFGetTypeID(value) == CFNumberGetTypeID() {
            return (value as! NSNumber).intValue
        }
        return nil
    }

    public static func stringProperty(_ device: IOHIDDevice, key: CFString) -> String? {
        guard let value = IOHIDDeviceGetProperty(device, key) else { return nil }
        if CFGetTypeID(value) == CFStringGetTypeID() {
            return value as? String
        }
        return nil
    }

    public static func handlePreferenceScore(device: IOHIDDevice) -> Int {
        let maxFeatureReport = intProperty(device, key: kIOHIDMaxFeatureReportSizeKey as CFString) ?? 0
        let usagePage = intProperty(device, key: kIOHIDPrimaryUsagePageKey as CFString) ?? 0
        let usage = intProperty(device, key: kIOHIDPrimaryUsageKey as CFString) ?? 0

        var score = 0
        if maxFeatureReport >= 90 {
            score += 100
        } else if maxFeatureReport > 0 {
            score += maxFeatureReport
        }
        if usagePage == 0x01 && usage == 0x02 {
            score += 25
        }
        return score
    }

    public static func registryEntryID(_ device: IOHIDDevice) -> UInt64? {
        let service = IOHIDDeviceGetService(device)
        guard service != 0 else { return nil }

        var entryID: UInt64 = 0
        let result = IORegistryEntryGetRegistryEntryID(service, &entryID)
        guard result == KERN_SUCCESS else { return nil }
        return entryID
    }

    public static func deviceIdentityToken(_ device: IOHIDDevice) -> String {
        if let entryID = registryEntryID(device) {
            return "registry:\(entryID)"
        }
        return "pointer:\(UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque()))"
    }
}

public final class USBHIDControlSession: @unchecked Sendable {
    private struct InterprocessDeviceLock {
        let fd: Int32

        func release() {
            _ = flock(fd, LOCK_UN)
            _ = close(fd)
        }
    }

    private final class DeviceLockRegistry: @unchecked Sendable {
        private let registryLock = NSLock()
        private var deviceLocks: [String: NSRecursiveLock] = [:]

        func lock(for deviceID: String) -> NSRecursiveLock {
            registryLock.lock()
            defer { registryLock.unlock() }
            if let lock = deviceLocks[deviceID] {
                return lock
            }
            let lock = NSRecursiveLock()
            lock.name = "open.snek.usb.device.\(deviceID)"
            deviceLocks[deviceID] = lock
            return lock
        }
    }

    public let device: IOHIDDevice
    public let deviceID: String

    private static let deviceLockRegistry = DeviceLockRegistry()
    private var cachedTxn: UInt8?

    public init(device: IOHIDDevice, deviceID: String) {
        self.device = device
        self.deviceID = deviceID
    }

    public func withExclusiveDeviceAccess<T>(_ body: () throws -> T) throws -> T {
        let lock = Self.deviceLock(for: deviceID)
        lock.lock()
        defer { lock.unlock() }

        let depth = Self.currentThreadLockDepth(for: deviceID)
        if depth > 0 {
            Self.setCurrentThreadLockDepth(depth + 1, for: deviceID)
            defer { Self.setCurrentThreadLockDepth(depth, for: deviceID) }
            return try body()
        }

        let fileLock = try Self.acquireInterprocessDeviceLock(for: deviceID)
        Self.setCurrentThreadLockDepth(1, for: deviceID)
        defer {
            Self.setCurrentThreadLockDepth(0, for: deviceID)
            fileLock.release()
        }
        return try body()
    }

    public func invalidateCachedTransaction() {
        try? withExclusiveDeviceAccess {
            cachedTxn = nil
        }
    }

    public func perform(
        classID: UInt8,
        cmdID: UInt8,
        size: UInt8,
        args: [UInt8],
        transactionID: UInt8? = nil,
        allowTxnRescan: Bool = true,
        responseAttempts: Int = 6,
        responseDelayUs: useconds_t = 35_000
    ) throws -> [UInt8]? {
        try withExclusiveDeviceAccess {
            for txn in Self.transactionCandidates(
                preferredTransactionID: transactionID,
                cachedTransactionID: cachedTxn,
                allowTxnRescan: allowTxnRescan
            ) {
                let report = USBHIDProtocol.createReport(txn: txn, classID: classID, cmdID: cmdID, size: size, args: args)
                guard let response = try exchange(
                    report: report,
                    expectedClassID: classID,
                    expectedCmdID: cmdID,
                    responseAttempts: responseAttempts,
                    responseDelayUs: responseDelayUs
                ) else {
                    continue
                }
                if response.count < 90 { continue }
                if response[0] == 0x01 { continue }
                cachedTxn = transactionID ?? txn
                return response
            }

            if transactionID == nil {
                cachedTxn = nil
            }
            return nil
        }
    }

    static func transactionCandidates(
        preferredTransactionID: UInt8?,
        cachedTransactionID: UInt8?,
        allowTxnRescan: Bool
    ) -> [UInt8] {
        if let preferredTransactionID {
            return [preferredTransactionID]
        }
        let candidates: [UInt8]
        if let cachedTransactionID {
            candidates = allowTxnRescan ? [cachedTransactionID, 0x1F, 0x3F, 0xFF] : [cachedTransactionID]
        } else {
            candidates = [0x1F, 0x3F, 0xFF]
        }
        var seen = Set<UInt8>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func deviceLock(for deviceID: String) -> NSRecursiveLock {
        deviceLockRegistry.lock(for: deviceID)
    }

    static func interprocessLockFileName(for deviceID: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
        let sanitized = String(deviceID.map { allowed.contains($0) ? $0 : "_" })
        return sanitized.isEmpty ? "unknown-usb-device.lock" : "\(sanitized).lock"
    }

    private static func interprocessLockURL(for deviceID: String) throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Caches/OpenSnek/HIDLocks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(interprocessLockFileName(for: deviceID))
    }

    private static func acquireInterprocessDeviceLock(for deviceID: String) throws -> InterprocessDeviceLock {
        let url = try interprocessLockURL(for: deviceID)
        let fd = url.path.withCString { path in
            open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard fd >= 0 else {
            throw BridgeError.commandFailed("USB HID lock open failed for \(deviceID): errno \(errno)")
        }

        while true {
            if flock(fd, LOCK_EX) == 0 {
                return InterprocessDeviceLock(fd: fd)
            }
            if errno == EINTR {
                continue
            }
            let lockErrno = errno
            _ = close(fd)
            throw BridgeError.commandFailed("USB HID lock failed for \(deviceID): errno \(lockErrno)")
        }
    }

    private static func currentThreadLockDepth(for deviceID: String) -> Int {
        Thread.current.threadDictionary[threadLockDepthKey(for: deviceID)] as? Int ?? 0
    }

    private static func setCurrentThreadLockDepth(_ depth: Int, for deviceID: String) {
        let key = threadLockDepthKey(for: deviceID)
        if depth <= 0 {
            Thread.current.threadDictionary.removeObject(forKey: key)
        } else {
            Thread.current.threadDictionary[key] = depth
        }
    }

    private static func threadLockDepthKey(for deviceID: String) -> String {
        "open.snek.usb.device.lock.depth.\(deviceID)"
    }

    private func exchange(
        report: [UInt8],
        expectedClassID: UInt8,
        expectedCmdID: UInt8,
        responseAttempts: Int,
        responseDelayUs: useconds_t
    ) throws -> [UInt8]? {
        let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            if openResult == kIOReturnNotPermitted {
                throw BridgeError.commandFailed("USB HID access denied. Grant Input Monitoring and relaunch.")
            }
            return nil
        }
        defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

        let setResult = report.withUnsafeBufferPointer { ptr -> IOReturn in
            guard let base = ptr.baseAddress else { return kIOReturnError }
            return IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, CFIndex(0), base, ptr.count)
        }
        guard setResult == kIOReturnSuccess else {
            if setResult == kIOReturnNotPermitted {
                throw BridgeError.commandFailed("USB HID access denied. Grant Input Monitoring and relaunch.")
            }
            return nil
        }

        for _ in 0..<max(1, responseAttempts) {
            usleep(responseDelayUs)
            var out = [UInt8](repeating: 0, count: 90)
            var length = out.count
            let getResult = out.withUnsafeMutableBufferPointer { ptr -> IOReturn in
                guard let base = ptr.baseAddress else { return kIOReturnError }
                return IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, CFIndex(0), base, &length)
            }
            guard getResult == kIOReturnSuccess, length > 0 else { continue }

            let raw = Array(out.prefix(length))
            let candidate: [UInt8]
            if raw.count == 91 {
                candidate = Array(raw.dropFirst())
            } else if raw.count == 90 {
                candidate = raw
            } else if raw.count > 90 {
                candidate = Array(raw.suffix(90))
            } else {
                continue
            }

            if candidate[0] == 0x00 { continue }
            if !USBHIDProtocol.isValidResponse(candidate, txn: report[1], classID: expectedClassID, cmdID: expectedCmdID) {
                continue
            }
            return candidate
        }
        return nil
    }
}
