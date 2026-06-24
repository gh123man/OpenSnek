import Foundation
import IOKit.hid
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

/// Describes USB input value event data.
struct USBInputValueEvent: Sendable {
  let candidateIndex: Int
  let deviceUsagePage: Int
  let deviceUsage: Int
  let elementUsagePage: Int
  let elementUsage: Int
  let reportID: Int
  let integerValue: Int
  let elapsedSeconds: Double

  var deviceUsageLabel: String {
    String(format: "0x%02x:0x%02x", deviceUsagePage, deviceUsage)
  }

  var elementUsageLabel: String {
    String(format: "0x%04x:0x%04x", elementUsagePage, elementUsage)
  }
}

/// Coordinates USB input value probe behavior.
final class USBInputValueProbe: @unchecked Sendable {
  /// Coordinates callback context behavior.
  private final class CallbackContext {
    let emit: @Sendable (IOHIDValue, UInt?) -> Void

    init(emit: @escaping @Sendable (IOHIDValue, UInt?) -> Void) {
      self.emit = emit
    }
  }

  private let manager: IOHIDManager
  private let candidates: [USBProbeDeviceCandidate]
  private let candidateByPointer: [UInt: USBProbeDeviceCandidate]
  private let queue = DispatchQueue(label: "open.snek.probe.usb-value")
  private let runLoopStateLock = NSLock()
  private let eventCountLock = NSLock()
  private var runLoop: CFRunLoop?
  private var thread: Thread?
  private var keepAlivePort: Port?
  private var callbackContext: UnsafeMutableRawPointer?
  private var captureStartedAt: Date = .distantPast
  private var eventCount = 0

  var candidateCount: Int { candidates.count }

  init(productID preferredProductID: Int? = nil) throws {
    let enumeration = try enumerateUSBProbeCandidates(preferredProductID: preferredProductID)
    self.manager = enumeration.manager
    self.candidates = enumeration.candidates
    self.candidateByPointer = Dictionary(
      uniqueKeysWithValues: enumeration.candidates.map { ($0.devicePointer, $0) })
  }

  deinit {
    stopSynchronously()
    IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
  }

  func describeCandidates() -> [String] {
    candidates.map { $0.describe() }
  }

  func capture(
    duration: TimeInterval,
    maxEvents: Int? = nil,
    onValue: @escaping @Sendable (USBInputValueEvent) -> Void
  ) async throws -> Int {
    try await start(onValue: onValue)
    defer { stopSynchronously() }

    let deadline = Date().addingTimeInterval(max(0.1, duration))
    while Date() < deadline {
      if let maxEvents, currentEventCount() >= maxEvents {
        break
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    return currentEventCount()
  }

  private func start(onValue: @escaping @Sendable (USBInputValueEvent) -> Void) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        self.ensureRunLoopLocked()
        self.performOnRunLoopLocked {
          self.stopManagerCallbackOnRunLoop()
          self.captureStartedAt = Date()
          self.resetEventCount()

          let captureStartedAt = self.captureStartedAt
          let candidateByPointer = self.candidateByPointer
          let contextBox = CallbackContext { [weak self] value, senderPointer in
            guard let self,
              let senderPointer,
              let candidate = candidateByPointer[senderPointer]
            else { return }
            let element = IOHIDValueGetElement(value)
            let observedAt = Date()
            self.incrementEventCount()
            onValue(
              USBInputValueEvent(
                candidateIndex: candidate.index,
                deviceUsagePage: candidate.usagePage,
                deviceUsage: candidate.usage,
                elementUsagePage: Int(IOHIDElementGetUsagePage(element)),
                elementUsage: Int(IOHIDElementGetUsage(element)),
                reportID: Int(IOHIDElementGetReportID(element)),
                integerValue: IOHIDValueGetIntegerValue(value),
                elapsedSeconds: observedAt.timeIntervalSince(captureStartedAt)
              )
            )
          }
          let context = UnsafeMutableRawPointer(Unmanaged.passRetained(contextBox).toOpaque())
          self.callbackContext = context

          IOHIDManagerScheduleWithRunLoop(
            self.manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
          IOHIDManagerRegisterInputValueCallback(self.manager, Self.inputValueCallback, context)
          continuation.resume()
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
    thread.name = "open.snek.probe.usb-value"
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

  private func stopSynchronously() {
    let stopped = DispatchSemaphore(value: 0)
    queue.async {
      guard self.runLoop != nil || self.callbackContext != nil else {
        stopped.signal()
        return
      }
      self.performOnRunLoopLocked {
        self.stopManagerCallbackOnRunLoop()
        self.runLoopStateLock.lock()
        let runLoop = self.runLoop
        let thread = self.thread
        self.keepAlivePort = nil
        self.runLoop = nil
        self.thread = nil
        self.runLoopStateLock.unlock()
        thread?.cancel()
        if let runLoop {
          CFRunLoopStop(runLoop)
          CFRunLoopWakeUp(runLoop)
        }
        stopped.signal()
      }
    }
    stopped.wait()
  }

  private func stopManagerCallbackOnRunLoop() {
    IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
    IOHIDManagerUnscheduleFromRunLoop(
      manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    if let callbackContext {
      Unmanaged<CallbackContext>.fromOpaque(callbackContext).release()
      self.callbackContext = nil
    }
  }

  private func resetEventCount() {
    eventCountLock.lock()
    eventCount = 0
    eventCountLock.unlock()
  }

  private func incrementEventCount() {
    eventCountLock.lock()
    eventCount += 1
    eventCountLock.unlock()
  }

  private func currentEventCount() -> Int {
    eventCountLock.lock()
    let count = eventCount
    eventCountLock.unlock()
    return count
  }

  private static let inputValueCallback: IOHIDValueCallback = { context, _, sender, value in
    guard let context else { return }
    let callbackContext = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
    let senderPointer = sender.map { UInt(bitPattern: $0) }
    callbackContext.emit(value, senderPointer)
  }
}
