import Foundation
import IOKit.hid
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

/// Describes USB input report event data.
struct USBInputReportEvent: Sendable {
  let candidateIndex: Int
  let usagePage: Int
  let usage: Int
  let maxInputReportSize: Int
  let maxFeatureReportSize: Int
  let report: [UInt8]
  let elapsedSeconds: Double
  let passiveDPI: PassiveDPIReading?

  var usageLabel: String {
    String(format: "0x%02x:0x%02x", usagePage, usage)
  }
}

/// Coordinates USB input report probe behavior.
final class USBInputReportProbe: @unchecked Sendable {
  /// Coordinates callback context behavior.
  private final class CallbackContext {
    let emit: @Sendable ([UInt8]) -> Void

    init(emit: @escaping @Sendable ([UInt8]) -> Void) {
      self.emit = emit
    }
  }

  /// Stores registration data.
  private struct Registration {
    let device: IOHIDDevice
    let buffer: UnsafeMutablePointer<UInt8>
    let bufferLength: CFIndex
    let context: UnsafeMutableRawPointer
  }

  private let manager: IOHIDManager
  private let candidates: [USBProbeDeviceCandidate]
  private let queue = DispatchQueue(label: "open.snek.probe.usb-input")
  private let runLoopStateLock = NSLock()
  private let reportCountLock = NSLock()
  private var runLoop: CFRunLoop?
  private var thread: Thread?
  private var keepAlivePort: Port?
  private var registrationsByIndex: [Int: Registration] = [:]
  private var captureStartedAt: Date = .distantPast
  private var reportCount = 0

  var candidateCount: Int { candidates.count }

  init(productID preferredProductID: Int? = nil) throws {
    let enumeration = try enumerateUSBProbeCandidates(preferredProductID: preferredProductID)
    self.manager = enumeration.manager
    self.candidates = enumeration.candidates
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
    maxReports: Int? = nil,
    onReport: @escaping @Sendable (USBInputReportEvent) -> Void
  ) async throws -> Int {
    try await start(onReport: onReport)
    defer { stopSynchronously() }

    let deadline = Date().addingTimeInterval(max(0.1, duration))
    while Date() < deadline {
      if let maxReports, currentReportCount() >= maxReports {
        break
      }
      try await Task.sleep(nanoseconds: 50_000_000)
    }

    return currentReportCount()
  }

  private func start(onReport: @escaping @Sendable (USBInputReportEvent) -> Void) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        self.ensureRunLoopLocked()
        self.performOnRunLoopLocked {
          self.removeAllRegistrations()
          self.captureStartedAt = Date()
          self.resetReportCount()

          for candidate in self.candidates {
            _ = self.addRegistration(candidate: candidate, onReport: onReport)
          }

          if self.registrationsByIndex.isEmpty {
            continuation.resume(
              throwing: ProbeError.protocolError(
                "Failed to register any USB input-report callbacks"))
          } else {
            continuation.resume()
          }
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
    thread.name = "open.snek.probe.usb-input"
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

  private func addRegistration(
    candidate: USBProbeDeviceCandidate,
    onReport: @escaping @Sendable (USBInputReportEvent) -> Void
  ) -> Bool {
    let openResult = IOHIDDeviceOpen(candidate.device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else { return false }

    let reportLength = max(1, candidate.maxInputReportSize)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportLength)
    buffer.initialize(repeating: 0, count: reportLength)

    let captureStartedAt = self.captureStartedAt
    let contextBox = CallbackContext { [weak self] report in
      guard let self else { return }
      let observedAt = Date()
      let passiveDPI = candidate.passiveDescriptor.flatMap {
        PassiveDPIParser.parse(report: report, descriptor: $0)
      }
      self.incrementReportCount()
      onReport(
        USBInputReportEvent(
          candidateIndex: candidate.index,
          usagePage: candidate.usagePage,
          usage: candidate.usage,
          maxInputReportSize: candidate.maxInputReportSize,
          maxFeatureReportSize: candidate.maxFeatureReportSize,
          report: report,
          elapsedSeconds: observedAt.timeIntervalSince(captureStartedAt),
          passiveDPI: passiveDPI
        )
      )
    }
    let context = UnsafeMutableRawPointer(Unmanaged.passRetained(contextBox).toOpaque())

    IOHIDDeviceScheduleWithRunLoop(
      candidate.device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDDeviceRegisterInputReportCallback(
      candidate.device,
      buffer,
      CFIndex(reportLength),
      Self.inputReportCallback,
      context
    )

    registrationsByIndex[candidate.index] = Registration(
      device: candidate.device,
      buffer: buffer,
      bufferLength: CFIndex(reportLength),
      context: context
    )
    return true
  }

  private func removeAllRegistrations() {
    for index in Array(registrationsByIndex.keys) {
      removeRegistration(index: index)
    }
  }

  private func removeRegistration(index: Int) {
    guard let registration = registrationsByIndex.removeValue(forKey: index) else { return }
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

  private func stopSynchronously() {
    let stopped = DispatchSemaphore(value: 0)
    queue.async {
      guard self.runLoop != nil || !self.registrationsByIndex.isEmpty else {
        stopped.signal()
        return
      }
      self.performOnRunLoopLocked {
        self.removeAllRegistrations()
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

  private func resetReportCount() {
    reportCountLock.lock()
    reportCount = 0
    reportCountLock.unlock()
  }

  private func incrementReportCount() {
    reportCountLock.lock()
    reportCount += 1
    reportCountLock.unlock()
  }

  private func currentReportCount() -> Int {
    reportCountLock.lock()
    let count = reportCount
    reportCountLock.unlock()
    return count
  }

  private static let inputReportCallback: IOHIDReportCallback = { context, result, _, type, _, report, length in
    guard result == kIOReturnSuccess, type == kIOHIDReportTypeInput, let context else {
      return
    }
    let callbackContext = Unmanaged<CallbackContext>.fromOpaque(context).takeUnretainedValue()
    let bytes = Array(UnsafeBufferPointer(start: report, count: max(0, length)))
    callbackContext.emit(bytes)
  }
}
