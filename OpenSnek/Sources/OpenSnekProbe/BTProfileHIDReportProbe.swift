import Foundation
import IOKit.hid
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

enum BTProfileHIDClassification: Equatable, Sendable {
  case profileCyclePrelude
  case profileCycleFollowUp
  case dpi(PassiveDPIReading)
  case heartbeat
  case other

  var label: String {
    switch self {
    case .profileCyclePrelude:
      return "profile-cycle-prelude"
    case .profileCycleFollowUp:
      return "profile-cycle-followup"
    case .dpi(let reading):
      return "dpi=\(reading.dpiX)x\(reading.dpiY)"
    case .heartbeat:
      return "heartbeat"
    case .other:
      return "other"
    }
  }

  var isProfileCycleHint: Bool {
    switch self {
    case .profileCyclePrelude, .profileCycleFollowUp:
      return true
    case .dpi, .heartbeat, .other:
      return false
    }
  }
}

struct BTProfileHIDReportEvent: Sendable {
  let candidateIndex: Int
  let deviceID: String
  let productID: Int
  let productName: String
  let usagePage: Int
  let usage: Int
  let maxInputReportSize: Int
  let maxFeatureReportSize: Int
  let report: [UInt8]
  let elapsedSeconds: Double
  let classification: BTProfileHIDClassification

  var usageLabel: String {
    String(format: "0x%02x:0x%02x", usagePage, usage)
  }
}

final class BTProfileHIDReportProbe: @unchecked Sendable {
  private final class CallbackContext {
    let candidate: BTHIDProbeDeviceCandidate
    let captureStartedAt: Date
    let emit: @Sendable (BTProfileHIDReportEvent) -> Void

    init(
      candidate: BTHIDProbeDeviceCandidate,
      captureStartedAt: Date,
      emit: @escaping @Sendable (BTProfileHIDReportEvent) -> Void
    ) {
      self.candidate = candidate
      self.captureStartedAt = captureStartedAt
      self.emit = emit
    }
  }

  private struct Registration {
    let device: IOHIDDevice
    let buffer: UnsafeMutablePointer<UInt8>
    let bufferLength: CFIndex
    let context: UnsafeMutableRawPointer
  }

  private let manager: IOHIDManager
  private let candidates: [BTHIDProbeDeviceCandidate]
  private let queue = DispatchQueue(label: "open.snek.probe.bt-profile-hid")
  private let runLoopStateLock = NSLock()
  private let reportCountLock = NSLock()
  private var runLoop: CFRunLoop?
  private var thread: Thread?
  private var keepAlivePort: Port?
  private var registrationsByIndex: [Int: Registration] = [:]
  private var captureStartedAt: Date = .distantPast
  private var reportCount = 0

  var candidateCount: Int { candidates.count }

  init(productID preferredProductID: Int? = 0x00AC, preferredPeripheralName: String? = nil) throws {
    let enumeration = try enumerateBTHIDProfileCandidates(
      preferredProductID: preferredProductID,
      preferredPeripheralName: preferredPeripheralName
    )
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
    onReport: @escaping @Sendable (BTProfileHIDReportEvent) -> Void
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

  private func start(onReport: @escaping @Sendable (BTProfileHIDReportEvent) -> Void) async throws {
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
                "Failed to register any Bluetooth HID input-report callbacks"))
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
    thread.name = "open.snek.probe.bt-profile-hid"
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
    candidate: BTHIDProbeDeviceCandidate,
    onReport: @escaping @Sendable (BTProfileHIDReportEvent) -> Void
  ) -> Bool {
    let registrationDevice = Self.registrationDevice(from: candidate.device) ?? candidate.device
    let openResult = IOHIDDeviceOpen(registrationDevice, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else { return false }

    let reportLength = max(9, candidate.maxInputReportSize)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportLength)
    buffer.initialize(repeating: 0, count: reportLength)

    let contextBox = CallbackContext(
      candidate: candidate,
      captureStartedAt: captureStartedAt,
      emit: { [weak self] event in
        self?.incrementReportCount()
        onReport(event)
      }
    )
    let context = UnsafeMutableRawPointer(Unmanaged.passRetained(contextBox).toOpaque())

    IOHIDDeviceScheduleWithRunLoop(
      registrationDevice, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    IOHIDDeviceRegisterInputReportCallback(
      registrationDevice,
      buffer,
      CFIndex(reportLength),
      Self.inputReportCallback,
      context
    )

    registrationsByIndex[candidate.index] = Registration(
      device: registrationDevice,
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
    let candidate = callbackContext.candidate
    callbackContext.emit(
      BTProfileHIDReportEvent(
        candidateIndex: candidate.index,
        deviceID: candidate.deviceID,
        productID: candidate.productID,
        productName: candidate.productName,
        usagePage: candidate.usagePage,
        usage: candidate.usage,
        maxInputReportSize: candidate.maxInputReportSize,
        maxFeatureReportSize: candidate.maxFeatureReportSize,
        report: bytes,
        elapsedSeconds: Date().timeIntervalSince(callbackContext.captureStartedAt),
        classification: classify(report: bytes, descriptor: candidate.passiveDescriptor)
      )
    )
  }

  private static func classify(
    report: [UInt8],
    descriptor: PassiveDPIInputDescriptor?
  ) -> BTProfileHIDClassification {
    if isProfileCyclePrelude(report) {
      return .profileCyclePrelude
    }
    if payloadStartIndex(in: report, reportID: 0x05, allowedSubtypes: [0x39]) != nil {
      return .profileCycleFollowUp
    }
    if let descriptor {
      switch PassiveDPIParser.classify(report: report, descriptor: descriptor) {
      case .dpi(let reading):
        return .dpi(reading)
      case .heartbeat:
        return .heartbeat
      case .profileSwitch:
        return .profileCycleFollowUp
      case .other:
        break
      }
    }
    return .other
  }

  private static func isProfileCyclePrelude(_ report: [UInt8]) -> Bool {
    guard let first = report.first, first == 0x04 else { return false }
    if report.count == 1 { return true }
    return report[1] == 0x04 || report[1] == 0x00
  }

  private static func payloadStartIndex(
    in report: [UInt8],
    reportID: UInt8,
    allowedSubtypes: [UInt8]
  ) -> Int? {
    if let first = report.first, allowedSubtypes.contains(first) {
      return 0
    }

    var index = 0
    while index < report.count, report[index] == reportID {
      let candidate = index + 1
      if candidate < report.count, allowedSubtypes.contains(report[candidate]) {
        return candidate
      }
      index += 1
    }

    return nil
  }

  private static func registrationDevice(from device: IOHIDDevice) -> IOHIDDevice? {
    let service = IOHIDDeviceGetService(device)
    guard service != 0 else { return nil }
    return IOHIDDeviceCreate(kCFAllocatorDefault, service)
  }
}
