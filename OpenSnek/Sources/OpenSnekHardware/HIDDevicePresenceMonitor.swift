import Foundation
import IOKit.hid

public final class HIDDevicePresenceMonitor {
    public var onDevicesChanged: (() -> Void)?

    private let vendorIDs: [Int]
    private var manager: IOHIDManager?
    private var isStarted = false
    private var pendingNotifyWorkItem: DispatchWorkItem?

    public init(vendorIDs: [Int]) {
        self.vendorIDs = vendorIDs
    }

    deinit {
        stop()
    }

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches = vendorIDs.map { [kIOHIDVendorIDKey: $0] as CFDictionary } as CFArray
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.handleDeviceEvent, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.handleDeviceEvent, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            self.manager = manager
        } else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            isStarted = false
        }
    }

    public func stop() {
        pendingNotifyWorkItem?.cancel()
        pendingNotifyWorkItem = nil

        guard let manager else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        isStarted = false
    }

    private func scheduleChangeNotification() {
        pendingNotifyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onDevicesChanged?()
        }
        pendingNotifyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
    }

    private static let handleDeviceEvent: IOHIDDeviceCallback = { context, _, _, _ in
        guard let context else { return }
        let monitor = Unmanaged<HIDDevicePresenceMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.scheduleChangeNotification()
    }
}
