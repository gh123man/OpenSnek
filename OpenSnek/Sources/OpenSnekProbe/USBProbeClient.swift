import Foundation
import IOKit.hid
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

final class USBProbeClient: @unchecked Sendable {
  private let manager: IOHIDManager
  private let session: USBHIDControlSession
  private let deviceID: String
  private let productID: Int
  private let profileID: DeviceProfileID?
  private let profile: DeviceProfile?

  init(productID preferredProductID: Int? = nil) throws {
    let enumeration = try enumerateUSBProbeCandidates(preferredProductID: preferredProductID)
    guard let best = enumeration.candidates.first else {
      throw ProbeError.protocolError("No non-Bluetooth USB Razer HID control interface found")
    }

    self.manager = enumeration.manager
    self.session = USBHIDControlSession(device: best.device, deviceID: best.deviceID)
    self.deviceID = best.deviceID
    self.productID = best.productID
    self.profile = DeviceProfiles.resolve(
      vendorID: 0x1532, productID: best.productID, transport: .usb)
    self.profileID = profile?.id
  }

  func describe() -> String {
    "\(deviceID) pid=0x\(String(format: "%04x", productID))"
  }

  func supportedLightingEffects() -> [LightingEffectKind] {
    profile?.supportedLightingEffects ?? LightingEffectKind.allCases
  }

  private var customFrameCellCount: Int {
    profile?.softwareLightingFrameLayout?.cellCount
      ?? SoftwareLightingFrameLayout.basiliskV3ProUSB.cellCount
  }

  func availableLightingZones() -> [USBLightingZoneDescriptor] {
    profile?.usbLightingZones ?? []
  }

  func lightingZoneChoices() -> [String] {
    let zoneIDs = availableLightingZones().map(\.id)
    return zoneIDs.isEmpty ? ["all"] : ["all"] + zoneIDs
  }

  func lightingTargets(zoneID: String? = nil) -> [USBLightingTargetDescriptor]? {
    if let profile {
      return profile.lightingTargets(for: zoneID)
    }

    let normalizedZoneID = zoneID?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard normalizedZoneID == nil || normalizedZoneID == "" || normalizedZoneID == "all" else {
      return nil
    }
    return [USBLightingTargetDescriptor(zoneID: "led_01", zoneLabel: "LED 0x01", ledID: 0x01)]
  }

  func readLightingBrightness(zoneID: String? = nil) throws -> [USBLightingReadResult]? {
    guard let targets = lightingTargets(zoneID: zoneID) else { return nil }
    return try targets.map { target in
      USBLightingReadResult(
        target: target,
        brightness: try readLightingBrightness(ledID: target.ledID)
      )
    }
  }

  func writeLightingBrightness(value: Int, zoneID: String? = nil) throws
    -> [USBLightingWriteResult]? {
    guard let targets = lightingTargets(zoneID: zoneID) else { return nil }
    let brightness = UInt8(max(0, min(255, value)))
    return try targets.map { target in
      let args = [0x01, target.ledID, brightness]
      return USBLightingWriteResult(
        target: target,
        args: args,
        succeeded: try writeLightingCommand(cmdID: 0x04, args: args)
      )
    }
  }

  func writeLightingEffect(effect: LightingEffectPatch, zoneID: String? = nil) throws
    -> [USBLightingWriteResult]? {
    guard let targets = lightingTargets(zoneID: zoneID) else { return nil }
    return try targets.map { target in
      let args = BLEVendorProtocol.buildScrollLEDEffectArgs(effect: effect, ledID: target.ledID)
      return USBLightingWriteResult(
        target: target,
        args: args,
        succeeded: try writeLightingCommand(cmdID: 0x02, args: args)
      )
    }
  }

  func writeLightingCustomFrame(
    storage: UInt8,
    row: UInt8,
    startColumn: UInt8,
    colors: [RGBPatch],
    responseAttempts: Int = 6,
    responseDelayUs: useconds_t = 35_000
  ) throws -> USBLightingCustomFrameResult {
    let args = USBHIDProtocol.lightingCustomFrameArgs(
      storage: storage,
      row: row,
      startColumn: startColumn,
      colors: colors
    )
    return USBLightingCustomFrameResult(
      args: args,
      succeeded: try writeLightingCommand(
        cmdID: 0x03,
        args: args,
        responseAttempts: responseAttempts,
        responseDelayUs: responseDelayUs
      )
    )
  }

  func runLightingConcurrencyProbe(
    frames: Int,
    commandLoops: Int,
    intervalMs: Int,
    responseDelayUs: useconds_t,
    unlocked: Bool
  ) async -> USBLightingConcurrencyProbeResult {
    let startedAt = Date()
    async let frameStats = runFrameStream(
      frames: frames,
      intervalMs: intervalMs,
      responseDelayUs: responseDelayUs,
      unlocked: unlocked
    )
    async let commandStats = runConcurrentPollRateCommands(
      loops: commandLoops,
      responseDelayUs: responseDelayUs,
      unlocked: unlocked
    )
    let (framesResult, commandsResult) = await (frameStats, commandStats)
    return USBLightingConcurrencyProbeResult(
      mode: unlocked ? "unlocked" : "locked",
      elapsedMs: Date().timeIntervalSince(startedAt) * 1000.0,
      frameStats: framesResult,
      commandReadStats: commandsResult.reads,
      commandWriteStats: commandsResult.writes
    )
  }

  private func runFrameStream(
    frames: Int,
    intervalMs: Int,
    responseDelayUs: useconds_t,
    unlocked: Bool
  ) async -> USBLightingConcurrencyOperationStats {
    var durations: [Double] = []
    var successes = 0
    var failures = 0
    let intervalNs = UInt64(max(0, intervalMs)) * 1_000_000

    for index in 0..<max(0, frames) {
      let startedAt = Date()
      let colors = customFrameColors(frameIndex: index)
      do {
        let succeeded: Bool
        if unlocked {
          let args = USBHIDProtocol.lightingCustomFrameArgs(
            storage: 0x01,
            row: 0x00,
            startColumn: 0x00,
            colors: colors
          )
          let response = try rawCommandUnlocked(
            USBRawCommandRequest(
              classID: 0x0F,
              cmdID: 0x03,
              size: UInt8(args.count),
              args: args,
              transactionID: 0x1F,
              responseAttempts: 8,
              responseDelayUs: responseDelayUs
            ))
          succeeded = response?[0] == 0x02
        } else {
          succeeded = try writeLightingCustomFrame(
            storage: 0x01,
            row: 0x00,
            startColumn: 0x00,
            colors: colors,
            responseAttempts: 8,
            responseDelayUs: responseDelayUs
          ).succeeded
        }
        if succeeded {
          successes += 1
        } else {
          failures += 1
        }
      } catch {
        failures += 1
      }
      let elapsedMs = Date().timeIntervalSince(startedAt) * 1000.0
      durations.append(elapsedMs)
      let elapsedNs = UInt64(max(0.0, elapsedMs) * 1_000_000.0)
      if intervalNs > elapsedNs {
        try? await Task.sleep(nanoseconds: intervalNs - elapsedNs)
      }
    }

    return operationStats(
      attempts: max(0, frames), successes: successes, failures: failures, durations: durations)
  }

  private func runConcurrentPollRateCommands(
    loops: Int,
    responseDelayUs: useconds_t,
    unlocked: Bool
  ) async -> (
    reads: USBLightingConcurrencyOperationStats, writes: USBLightingConcurrencyOperationStats
  ) {
    var readDurations: [Double] = []
    var writeDurations: [Double] = []
    var readSuccesses = 0
    var readFailures = 0
    var writeSuccesses = 0
    var writeFailures = 0

    for _ in 0..<max(0, loops) {
      let readStartedAt = Date()
      var pollRaw: UInt8?
      do {
        let response: [UInt8]?
        if unlocked {
          response = try rawCommandUnlocked(
            USBRawCommandRequest(
              classID: 0x00,
              cmdID: 0x85,
              size: 0x01,
              args: [],
              transactionID: 0x1E,
              responseAttempts: 8,
              responseDelayUs: responseDelayUs
            ))
        } else {
          response = try rawCommand(
            classID: 0x00,
            cmdID: 0x85,
            size: 0x01,
            args: [],
            responseAttempts: 8,
            responseDelayUs: responseDelayUs
          )
        }
        if let response, response[0] == 0x02, response.count > 8 {
          pollRaw = response[8]
          readSuccesses += 1
        } else {
          readFailures += 1
        }
      } catch {
        readFailures += 1
      }
      readDurations.append(Date().timeIntervalSince(readStartedAt) * 1000.0)

      let writeStartedAt = Date()
      do {
        let args = [pollRaw ?? 0x01]
        let response: [UInt8]?
        if unlocked {
          response = try rawCommandUnlocked(
            USBRawCommandRequest(
              classID: 0x00,
              cmdID: 0x05,
              size: 0x01,
              args: args,
              transactionID: 0x1D,
              responseAttempts: 8,
              responseDelayUs: responseDelayUs
            ))
        } else {
          response = try rawCommand(
            classID: 0x00,
            cmdID: 0x05,
            size: 0x01,
            args: args,
            responseAttempts: 8,
            responseDelayUs: responseDelayUs
          )
        }
        if response?[0] == 0x02 {
          writeSuccesses += 1
        } else {
          writeFailures += 1
        }
      } catch {
        writeFailures += 1
      }
      writeDurations.append(Date().timeIntervalSince(writeStartedAt) * 1000.0)

      try? await Task.sleep(nanoseconds: 5_000_000)
    }

    return (
      operationStats(
        attempts: max(0, loops),
        successes: readSuccesses,
        failures: readFailures,
        durations: readDurations
      ),
      operationStats(
        attempts: max(0, loops),
        successes: writeSuccesses,
        failures: writeFailures,
        durations: writeDurations
      )
    )
  }

  private func operationStats(
    attempts: Int,
    successes: Int,
    failures: Int,
    durations: [Double]
  ) -> USBLightingConcurrencyOperationStats {
    let average = durations.isEmpty ? 0.0 : durations.reduce(0.0, +) / Double(durations.count)
    return USBLightingConcurrencyOperationStats(
      attempts: attempts,
      successes: successes,
      failures: failures,
      averageMs: average,
      maxMs: durations.max() ?? 0.0
    )
  }

  private func customFrameColors(frameIndex: Int) -> [RGBPatch] {
    let cellCount = customFrameCellCount
    var colors: [RGBPatch] = []
    colors.reserveCapacity(cellCount)
    for index in 0..<cellCount {
      colors.append(
        customFrameColor(cellIndex: index, cellCount: cellCount, frameIndex: frameIndex))
    }
    return colors
  }

  private func customFrameColor(cellIndex: Int, cellCount: Int, frameIndex: Int) -> RGBPatch {
    let hue = (Double(cellIndex) / Double(cellCount)) + (Double(frameIndex) * 0.04)
    let phase = hue - floor(hue)
    let red = customFrameColorChannel(phase: phase)
    let green = customFrameColorChannel(phase: phase + 0.333)
    let blue = customFrameColorChannel(phase: phase + 0.666)
    return RGBPatch(r: red, g: green, b: blue)
  }

  private func customFrameColorChannel(phase: Double) -> Int {
    let value = (0.5 + 0.5 * sin(phase * .pi * 2.0)) * 255.0
    return Int(round(value))
  }

  private func rawCommandUnlocked(_ request: USBRawCommandRequest) throws -> [UInt8]? {
    let report = USBHIDProtocol.createReport(
      txn: request.transactionID,
      classID: request.classID,
      cmdID: request.cmdID,
      size: request.size,
      args: request.args
    )
    let openResult = IOHIDDeviceOpen(session.device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard openResult == kIOReturnSuccess else {
      if openResult == kIOReturnNotPermitted {
        throw BridgeError.commandFailed(
          "USB HID access denied. Grant Input Monitoring and relaunch.")
      }
      return nil
    }
    defer { IOHIDDeviceClose(session.device, IOOptionBits(kIOHIDOptionsTypeNone)) }

    let setResult = report.withUnsafeBufferPointer { ptr -> IOReturn in
      guard let base = ptr.baseAddress else { return kIOReturnError }
      return IOHIDDeviceSetReport(
        session.device, kIOHIDReportTypeFeature, CFIndex(0), base, ptr.count)
    }
    guard setResult == kIOReturnSuccess else {
      if setResult == kIOReturnNotPermitted {
        throw BridgeError.commandFailed(
          "USB HID access denied. Grant Input Monitoring and relaunch.")
      }
      return nil
    }

    for _ in 0..<max(1, request.responseAttempts) {
      usleep(request.responseDelayUs)
      var out = [UInt8](repeating: 0, count: 90)
      var length = out.count
      let getResult = out.withUnsafeMutableBufferPointer { ptr -> IOReturn in
        guard let base = ptr.baseAddress else { return kIOReturnError }
        return IOHIDDeviceGetReport(
          session.device, kIOHIDReportTypeFeature, CFIndex(0), base, &length)
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
      if USBHIDProtocol.isValidResponse(
        candidate,
        txn: request.transactionID,
        classID: request.classID,
        cmdID: request.cmdID
      ) {
        return candidate
      }
    }
    return nil
  }

  func readBattery() throws -> USBBatteryReadResult? {
    guard
      let response = try session.perform(
        classID: 0x07,
        cmdID: 0x80,
        size: 0x02,
        args: []
      ), response[0] == 0x02, response.count > 9
    else {
      return nil
    }

    let charging = response[8] == 0x01
    let rawLevel = response[9]
    let percent = Int((Double(rawLevel) / 255.0) * 100.0)
    return USBBatteryReadResult(
      charging: charging,
      rawLevel: rawLevel,
      percent: percent
    )
  }

  func profileLightingTargets() -> [USBLightingTargetDescriptor] {
    lightingTargets(zoneID: nil) ?? [
      USBLightingTargetDescriptor(zoneID: "led_01", zoneLabel: "LED 0x01", ledID: 0x01)
    ]
  }

  func readProfileSummaryRaw() throws -> [UInt8]? {
    guard let response = try rawCommand(classID: 0x00, cmdID: 0x87, size: 0x00, args: []),
      response[0] == 0x02,
      response.count > 10
    else {
      return nil
    }
    return Array(response[8...10])
  }

  func readProfileCount() throws -> UInt8? {
    guard let response = try rawCommand(classID: 0x05, cmdID: 0x80, size: 0x00, args: []) else {
      return nil
    }
    return USBHIDProtocol.onboardProfileCount(from: response)
  }

  func readProfileInventory() throws -> USBHIDProtocol.OnboardProfileInventory? {
    guard let response = try rawCommand(classID: 0x05, cmdID: 0x81, size: 0x00, args: []) else {
      return nil
    }
    return USBHIDProtocol.onboardProfileInventory(from: response)
  }

  func readActiveProfileID() throws -> UInt8? {
    guard let response = try rawCommand(classID: 0x05, cmdID: 0x84, size: 0x00, args: []),
      let active = USBHIDProtocol.activeProfileID(from: response)
    else {
      return nil
    }
    return active
  }

  func writeActiveProfileID(_ profile: UInt8) throws -> Bool {
    let args = USBHIDProtocol.activeProfileSetArgs(profile: profile)
    guard
      let response = try rawCommand(
        classID: 0x05,
        cmdID: 0x04,
        size: 0x01,
        args: args
      )
    else {
      return false
    }
    return USBHIDProtocol.activeProfileSetAccepted(from: response, profile: profile)
  }

  func readProfileDPIScalar(profile: UInt8) throws -> (raw: [UInt8], pair: DpiPair?)? {
    guard
      let response = try rawCommand(
        classID: 0x04,
        cmdID: 0x85,
        size: 0x07,
        args: [profile]
      ), response[0] == 0x02, response.count > 12, response[8] == profile
    else {
      return nil
    }
    let raw = Array(response[8..<min(response.count, 15)])
    let pair = DpiPair(
      x: (Int(response[9]) << 8) | Int(response[10]),
      y: (Int(response[11]) << 8) | Int(response[12])
    )
    return (raw, pair)
  }

  func writeProfileDPIScalar(profile: UInt8, pair: DpiPair) throws -> Bool {
    let dpiX = max(100, min(30_000, pair.x))
    let dpiY = max(100, min(30_000, pair.y))
    let args: [UInt8] = [
      profile,
      UInt8((dpiX >> 8) & 0xFF),
      UInt8(dpiX & 0xFF),
      UInt8((dpiY >> 8) & 0xFF),
      UInt8(dpiY & 0xFF),
      0x00,
      0x00
    ]
    guard
      let response = try rawCommand(
        classID: 0x04,
        cmdID: 0x05,
        size: 0x07,
        args: args
      )
    else {
      return false
    }
    return writeEchoMatches(response: response, classID: 0x04, cmdID: 0x05, args: args)
  }

  func readProfileDPIStages(profile: UInt8) throws -> USBProfileDPIStagesReadResult? {
    guard
      let response = try rawCommand(
        classID: 0x04,
        cmdID: 0x86,
        size: 0x26,
        args: [profile]
      ), response[0] == 0x02, response.count > 10, response[8] == profile
    else {
      return nil
    }
    let raw = Array(response[8..<min(response.count, 8 + 0x26)])
    let activeToken = response[9]
    let count = max(0, min(5, Int(response[10])))
    var pairs: [DpiPair] = []
    var stageIDs: [UInt8] = []
    for index in 0..<count {
      let offset = 11 + index * 7
      guard offset + 4 < response.count else { break }
      stageIDs.append(response[offset])
      pairs.append(
        DpiPair(
          x: (Int(response[offset + 1]) << 8) | Int(response[offset + 2]),
          y: (Int(response[offset + 3]) << 8) | Int(response[offset + 4])
        )
      )
    }
    return USBProfileDPIStagesReadResult(
      raw: raw,
      activeToken: activeToken,
      pairs: pairs,
      stageIDs: stageIDs
    )
  }

  func writeProfileDPIStagesRaw(_ raw: [UInt8]) throws -> Bool {
    guard !raw.isEmpty else { return false }
    guard
      let response = try rawCommand(
        classID: 0x04,
        cmdID: 0x06,
        size: 0x26,
        args: raw
      )
    else {
      return false
    }
    return writeEchoMatches(response: response, classID: 0x04, cmdID: 0x06, args: raw)
  }

  func readProfileLightingBrightness(profile: UInt8, ledID: UInt8) throws -> (
    raw: [UInt8], brightness: Int?
  )? {
    guard
      let response = try rawCommand(
        classID: 0x0F,
        cmdID: 0x84,
        size: 0x03,
        args: [profile, ledID, 0x00]
      ), response[0] == 0x02, response.count > 10, response[8] == profile, response[9] == ledID
    else {
      return nil
    }
    return (Array(response[8..<min(response.count, 11)]), Int(response[10]))
  }

  func writeProfileLightingBrightness(profile: UInt8, ledID: UInt8, brightness: Int) throws -> Bool {
    let value = UInt8(max(0, min(255, brightness)))
    let args = [profile, ledID, value]
    guard
      let response = try rawCommand(
        classID: 0x0F,
        cmdID: 0x04,
        size: 0x03,
        args: args
      )
    else {
      return false
    }
    return writeEchoMatches(response: response, classID: 0x0F, cmdID: 0x04, args: args)
  }

  func readProfileMetadataBytes(profile: UInt8) throws -> USBProfileMetadataReadResult? {
    var chunks: [USBHIDProtocol.OnboardProfileMetadataChunk] = []
    for offset in USBHIDProtocol.onboardProfileMetadataChunkOffsets {
      let args = USBHIDProtocol.onboardProfileMetadataReadArgs(slot: profile, offset: offset)
      guard
        let response = try rawCommand(
          classID: 0x05,
          cmdID: 0x88,
          size: USBHIDProtocol.onboardProfileMetadataReadSize,
          args: args
        ),
        let chunk = USBHIDProtocol.onboardProfileMetadataChunk(
          from: response,
          expectedSlot: profile,
          expectedOffset: offset
        )
      else {
        continue
      }
      chunks.append(chunk)
    }
    guard !chunks.isEmpty else { return nil }
    let bytes = USBHIDProtocol.mergeOnboardProfileMetadataChunks(chunks)
    return USBProfileMetadataReadResult(
      chunks: chunks,
      bytes: bytes,
      metadata: USBHIDProtocol.parseOnboardProfileMetadata(bytes)
    )
  }

  func readProfileMetadata(profile: UInt8) throws -> (
    chunks: [USBHIDProtocol.OnboardProfileMetadataChunk],
    metadata: USBHIDProtocol.OnboardProfileMetadata
  )? {
    guard let read = try readProfileMetadataBytes(profile: profile) else { return nil }
    return (read.chunks, read.metadata)
  }

  func writeProfileMetadataBytes(profile: UInt8, metadata: [UInt8]) throws -> Bool {
    guard metadata.count >= USBHIDProtocol.onboardProfileMetadataLength else {
      throw ProbeError.usage(
        "Profile metadata must be at least \(USBHIDProtocol.onboardProfileMetadataLength) bytes")
    }
    var sawIndeterminateTail = false
    for offset in USBHIDProtocol.onboardProfileMetadataWritableChunkOffsets {
      let args = USBHIDProtocol.onboardProfileMetadataWriteArgs(
        slot: profile,
        offset: offset,
        metadata: metadata
      )
      let isTailOffset = offset >= USBHIDProtocol.onboardProfileMetadataKnownFieldLength
      let response = try rawCommand(
        classID: 0x05,
        cmdID: 0x08,
        size: USBHIDProtocol.onboardProfileMetadataReadSize,
        args: args,
        responseAttempts: isTailOffset ? 16 : 10,
        responseDelayUs: 50_000
      )
      if response?[0] == 0x02 {
        usleep(25_000)
        continue
      }
      if isTailOffset {
        sawIndeterminateTail = true
        continue
      }
      return false
    }
    if sawIndeterminateTail {
      usleep(120_000)
    }
    guard let readback = try readProfileMetadataBytes(profile: profile) else {
      return false
    }
    return Array(readback.bytes.prefix(USBHIDProtocol.onboardProfileMetadataLength))
      == Array(metadata.prefix(USBHIDProtocol.onboardProfileMetadataLength))
  }

  func deleteProfile(profile: UInt8) throws -> Bool {
    let args = [profile]
    guard
      let response = try rawCommand(
        classID: 0x05,
        cmdID: 0x03,
        size: 0x01,
        args: args
      )
    else {
      return false
    }
    return writeEchoMatches(response: response, classID: 0x05, cmdID: 0x03, args: args)
  }

  func readButtonFunction(profile: UInt8, slot: UInt8, hypershift: UInt8 = 0x00) throws -> [UInt8]? {
    var args: [UInt8] = [profile, slot, hypershift]
    args.append(contentsOf: [UInt8](repeating: 0x00, count: 7))
    guard
      let response = try session.perform(
        classID: 0x02,
        cmdID: 0x8C,
        size: UInt8(args.count),
        args: args,
        responseAttempts: 12,
        responseDelayUs: 40_000
      ), response[0] == 0x02
    else {
      return nil
    }

    return ButtonBindingSupport.extractUSBFunctionBlock(
      response: response,
      profile: profile,
      slot: slot,
      hypershift: hypershift,
      profileID: profileID
    )
  }

  func writeButtonFunction(
    profile: UInt8, slot: UInt8, hypershift: UInt8 = 0x00, functionBlock: [UInt8]
  ) throws -> Bool {
    guard functionBlock.count == 7 else {
      throw ProbeError.usage("Function block must be exactly 7 bytes")
    }
    let args = [profile, slot, hypershift] + functionBlock
    guard
      let response = try session.perform(
        classID: 0x02,
        cmdID: 0x0C,
        size: UInt8(args.count),
        args: args,
        responseAttempts: 12,
        responseDelayUs: 40_000
      )
    else {
      return false
    }
    return response[0] == 0x02
  }

  func writeButtonBinding(_ request: USBButtonBindingWriteRequest) throws -> Bool {
    guard let bindingKind = ButtonBindingKind(rawValue: request.kind) else {
      throw ProbeError.usage("Invalid --kind '\(request.kind)'")
    }
    let functionBlock = ButtonBindingSupport.buildUSBFunctionBlock(
      slot: request.slot,
      kind: bindingKind,
      hidKey: request.hidKey,
      turboEnabled: request.turboEnabled && bindingKind.supportsTurbo,
      turboRate: request.turboRate,
      clutchDPI: request.clutchDPI,
      profileID: profileID
    )
    let clampedSlot = UInt8(max(0, min(255, request.slot)))
    var wroteAny = false
    for profile in request.profiles
    where try writeButtonFunction(profile: profile, slot: clampedSlot, functionBlock: functionBlock) {
      wroteAny = true
    }
    return wroteAny
  }

  func rawCommand(
    classID: UInt8,
    cmdID: UInt8,
    size: UInt8,
    args: [UInt8],
    responseAttempts: Int = 12,
    responseDelayUs: useconds_t = 40_000
  ) throws -> [UInt8]? {
    try session.perform(
      classID: classID,
      cmdID: cmdID,
      size: size,
      args: args,
      responseAttempts: responseAttempts,
      responseDelayUs: responseDelayUs
    )
  }

  private func readLightingBrightness(ledID: UInt8) throws -> Int? {
    let args: [UInt8] = [0x01, ledID, 0x00]
    guard
      let response = try session.perform(
        classID: 0x0F,
        cmdID: 0x84,
        size: 0x03,
        args: args
      ), response[0] == 0x02, response.count > 10
    else {
      return nil
    }
    return Int(response[10])
  }

  private func writeLightingCommand(
    cmdID: UInt8,
    args: [UInt8],
    responseAttempts: Int = 6,
    responseDelayUs: useconds_t = 35_000
  ) throws -> Bool {
    guard
      let response = try session.perform(
        classID: 0x0F,
        cmdID: cmdID,
        size: UInt8(max(0, min(255, args.count))),
        args: args,
        responseAttempts: responseAttempts,
        responseDelayUs: responseDelayUs
      )
    else {
      return false
    }
    return response[0] == 0x02
  }

  private func writeEchoMatches(response: [UInt8], classID: UInt8, cmdID: UInt8, args: [UInt8])
    -> Bool {
    guard response.count >= 8 + args.count else { return false }
    guard response[0] == 0x02, response[6] == classID, response[7] == cmdID else {
      return false
    }
    return Array(response[8..<(8 + args.count)]) == args
  }
}
