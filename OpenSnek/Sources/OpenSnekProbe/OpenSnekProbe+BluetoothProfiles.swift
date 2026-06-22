import Foundation
import OpenSnekCore
import OpenSnekProtocols

extension OpenSnekProbe {
  private struct BTProfileDPIRead {
    let target: UInt8
    let scalarRaw: Data?
    let scalar: DpiPair?
    let pairListRaw: Data?
    let pairs: [DpiPair]
    let tokenRaw: Data?
  }

  private struct BTProfileLightingRead {
    let target: UInt8
    let ledID: UInt8
    let brightnessRaw: Data?
    let brightness: UInt8?
    let stateRaw: Data?
    let color: RGBPatch?
  }

  struct BTProfileProbeSession {
    let bridge: ProbeBridge
    let preferredPeripheralName: String?
    let timeoutSeconds: TimeInterval
  }

  struct BTProfileReadSweepRequest {
    let session: BTProfileProbeSession
    let targets: [UInt8]
    let buttonSlots: [UInt8]
    let includeLiveButtons: Bool
  }

  struct BTProfileCreateRequest {
    let session: BTProfileProbeSession
    let target: UInt8
    let guid: UUID
    let profileName: String
    let owner: String
    let values: [Int]
    let active: Int
    let brightness: UInt8
  }

  struct BTProfileWriteStep {
    let session: BTProfileProbeSession
    let label: String
    let key: [UInt8]
    let payload: [UInt8]
  }

  static func printBTProfileReadSweep(_ request: BTProfileReadSweepRequest) async throws {
    let session = request.session
    let inventoryKey = BLEVendorProtocol.Key.profileTargetsGet().bytes
    let inventory = try await session.bridge.rawRead(
      key: inventoryKey,
      timeout: session.timeoutSeconds,
      preferredPeripheralName: session.preferredPeripheralName
    )
    print(
      "inventory key=\(hexString(inventoryKey)) payload=\(inventory.payload.map { hexString(Array($0)) } ?? "nil")"
    )

    let activeTargetKey = BLEVendorProtocol.Key.profileActiveTargetGet().bytes
    let activeTarget = try await session.bridge.rawRead(
      key: activeTargetKey,
      timeout: session.timeoutSeconds,
      preferredPeripheralName: session.preferredPeripheralName
    )
    let activeTargetPayload = activeTarget.payload.map { Array($0) } ?? []
    let activeTargetLabel: String
    if activeTargetPayload.count == 1 {
      activeTargetLabel = btProfileTargetLabel(activeTargetPayload[0])
    } else {
      activeTargetLabel = "unavailable"
    }
    print(
      "active-target key=\(hexString(activeTargetKey)) "
        + "payload=\(activeTarget.payload.map { hexString(Array($0)) } ?? "nil") "
        + "target=\(activeTargetLabel)"
    )

    var dpiReads: [BTProfileDPIRead] = []
    let dpiTargets = uniqueByteList([0x00] + request.targets)
    for target in dpiTargets {
      let read = try await readBTProfileDPI(
        bridge: session.bridge,
        preferredPeripheralName: session.preferredPeripheralName,
        timeoutSeconds: session.timeoutSeconds,
        target: target
      )
      dpiReads.append(read)
      print(describeBTProfileDPIRead(read))
    }

    let activePairs: [DpiPair]
    if let activeDPIRead = dpiReads.first(where: { $0.target == 0x00 }) {
      activePairs = activeDPIRead.pairs
    } else {
      activePairs = []
    }
    let storedMatches =
      dpiReads
      .filter {
        OnboardProfileLimits.containsStoredProfileID($0.target) && !$0.pairs.isEmpty
          && $0.pairs == activePairs
      }
      .map(\.target)
    if activePairs.isEmpty {
      print("fingerprint active=unavailable")
    } else if storedMatches.isEmpty {
      print("fingerprint active=\(describeDpiPairs(activePairs)) match=none")
    } else if storedMatches.count == 1, let match = storedMatches.first {
      print(
        "fingerprint active=\(describeDpiPairs(activePairs)) match=\(btProfileTargetLabel(match))")
    } else {
      print(
        "fingerprint active=\(describeDpiPairs(activePairs)) ambiguous=["
          + storedMatches.map(btProfileTargetLabel).joined(separator: ", ") + "]"
      )
    }

    let ledIDs = try await readBTProfileLightingLEDIDs(
      bridge: session.bridge,
      preferredPeripheralName: session.preferredPeripheralName,
      timeoutSeconds: session.timeoutSeconds
    )
    if !ledIDs.isEmpty {
      print(
        "lighting-leds ids=\(ledIDs.map { String(format: "0x%02x", $0) }.joined(separator: ","))")
      for target in uniqueByteList([0x00, 0x01] + request.targets) {
        for ledID in ledIDs {
          let read = try await readBTProfileLighting(
            bridge: session.bridge,
            preferredPeripheralName: session.preferredPeripheralName,
            timeoutSeconds: session.timeoutSeconds,
            target: target,
            ledID: ledID
          )
          print(describeBTProfileLightingRead(read))
        }
      }
    }

    guard !request.buttonSlots.isEmpty else { return }
    let buttonTargets = request.includeLiveButtons ? uniqueByteList([0x00, 0x01] + request.targets) : request.targets
    for target in buttonTargets {
      for slot in request.buttonSlots {
        let key = BLEVendorProtocol.Key.buttonBindGet(target: target, slot: slot).bytes
        let result = try await session.bridge.rawRead(
          key: key,
          timeout: session.timeoutSeconds,
          preferredPeripheralName: session.preferredPeripheralName
        )
        print("button \(btProfileTargetLabel(target)) slot=\(slot) key=\(hexString(key))")
        print(
          describeBTProfileButtonRead(key: key, payload: result.payload, notifies: result.notifies))
      }
    }
  }

  static func createBTProfileTarget(_ request: BTProfileCreateRequest) async throws {
    let session = request.session
    let target = request.target
    try await writeBTProfileStep(
      BTProfileWriteStep(
        session: session,
        label: "clear-target",
        key: BLEVendorProtocol.Key.profileTargetDelete(target: target).bytes,
        payload: []
      )
    )
    try await writeBTProfileStep(
      BTProfileWriteStep(
        session: session,
        label: "prepare-1",
        key: BLEVendorProtocol.Key.profileTargetPrepare(target: target).bytes,
        payload: [0x00]
      )
    )

    let statusKey = BLEVendorProtocol.Key.profileTargetStatusGet(target: target).bytes
    let status = try await session.bridge.rawRead(
      key: statusKey,
      timeout: session.timeoutSeconds,
      preferredPeripheralName: session.preferredPeripheralName
    )
    print(
      "step=status key=\(hexString(statusKey)) payload=\(status.payload.map { hexString(Array($0)) } ?? "nil")"
    )

    try await writeBTProfileStep(
      BTProfileWriteStep(
        session: session,
        label: "apply",
        key: BLEVendorProtocol.Key.profileTargetApply(target: target).bytes,
        payload: [0x00]
      )
    )
    try await writeBTProfileStep(
      BTProfileWriteStep(
        session: session,
        label: "commit-before-metadata",
        key: BLEVendorProtocol.Key.profileTargetCommit(target: target).bytes,
        payload: []
      )
    )

    let metadataKey = BLEVendorProtocol.Key.profileMetadataSet(target: target).bytes
    for chunk in try buildBTProfileMetadataChunks(
      guid: request.guid, profileName: request.profileName, owner: request.owner) {
      let offset = Int(chunk[2]) | (Int(chunk[3]) << 8)
      try await writeBTProfileStep(
        BTProfileWriteStep(
          session: session,
          label: String(format: "metadata-0x%04x", offset),
          key: metadataKey,
          payload: chunk
        )
      )
    }

    let clampedActive = max(0, min(request.values.count - 1, request.active))
    let activeValue = UInt16(max(100, min(30_000, request.values[clampedActive])))
    try await writeBTProfileStep(
      BTProfileWriteStep(
        session: session,
        label: "stored-dpi-scalar",
        key: BLEVendorProtocol.Key.storedDpiScalarSet(target: target).bytes,
        payload: [
          UInt8(activeValue & 0xFF),
          UInt8((activeValue >> 8) & 0xFF),
          UInt8(activeValue & 0xFF),
          UInt8((activeValue >> 8) & 0xFF),
          0x00,
          0x00
        ]
      )
    )

    let dpiPayload = Array(
      BLEVendorProtocol.buildDpiStagePayload(
        active: clampedActive,
        count: request.values.count,
        slots: request.values,
        marker: 0x00,
        stageIDs: [0x01, 0x02, 0x03, 0x04, 0x05]
      ))
    try await writeBTProfileStep(
      BTProfileWriteStep(
        session: session,
        label: "stored-dpi-stages",
        key: BLEVendorProtocol.Key.storedDpiStagesSet(target: target).bytes,
        payload: dpiPayload
      )
    )
    try await writeBTProfileStep(
      BTProfileWriteStep(
        session: session,
        label: "prepare-2",
        key: BLEVendorProtocol.Key.profileTargetPrepare(target: target).bytes,
        payload: [0x00]
      )
    )
    try await writeBTProfileStep(
      BTProfileWriteStep(
        session: session,
        label: "stored-brightness",
        key: BLEVendorProtocol.Key.storedLightingBrightnessSet(target: target).bytes,
        payload: [request.brightness]
      )
    )
  }

  static func writeBTProfileStep(_ step: BTProfileWriteStep) async throws {
    let result = try await step.session.bridge.rawWrite(
      key: step.key,
      payload: Data(step.payload),
      timeout: step.session.timeoutSeconds,
      preferredPeripheralName: step.session.preferredPeripheralName
    )
    print(
      "step=\(step.label) key=\(hexString(step.key)) payload[\(step.payload.count)]=\(hexString(step.payload)) "
        + "status=\(describeBTAckStatus(result.ack))"
    )
    guard result.ack?.status == 0x02 else {
      throw ProbeError.protocolError(
        "BT profile step '\(step.label)' failed with status \(describeBTAckStatus(result.ack))")
    }
  }

  static func buildBTProfileMetadataChunks(
    guid: UUID,
    profileName: String,
    owner: String
  ) throws -> [[UInt8]] {
    let profileNameBytes = try asciiBytes(
      profileName, maxLength: 0x74 - 0x10, fieldName: "--profile-name")
    let ownerBytes = try asciiBytes(owner, maxLength: 64, fieldName: "--owner")
    guard ownerBytes.count == 64 else {
      throw ProbeError.usage("--owner must be exactly 64 ASCII bytes")
    }

    var metadata = [UInt8](repeating: 0x00, count: 0xFA)
    writeBytes(windowsGUIDBytes(guid), into: &metadata, at: 0x00)
    writeBytes(profileNameBytes, into: &metadata, at: 0x10)
    writeBytes(ownerBytes, into: &metadata, at: 0x74)

    let chunks: [(offset: Int, length: Int)] = [
      (0x0000, 0x4C),
      (0x004C, 0x4C),
      (0x0098, 0x4C),
      (0x00E4, 0x16)
    ]
    return chunks.map { chunk in
      [
        UInt8(metadata.count & 0xFF),
        UInt8((metadata.count >> 8) & 0xFF),
        UInt8(chunk.offset & 0xFF),
        UInt8((chunk.offset >> 8) & 0xFF)
      ] + Array(metadata[chunk.offset..<(chunk.offset + chunk.length)])
    }
  }

  static func windowsGUIDBytes(_ uuid: UUID) -> [UInt8] {
    let raw = uuid.uuid
    let bytes = [
      raw.0, raw.1, raw.2, raw.3,
      raw.4, raw.5,
      raw.6, raw.7,
      raw.8, raw.9, raw.10, raw.11, raw.12, raw.13, raw.14, raw.15
    ]
    return [
      bytes[3], bytes[2], bytes[1], bytes[0],
      bytes[5], bytes[4],
      bytes[7], bytes[6],
      bytes[8], bytes[9], bytes[10], bytes[11],
      bytes[12], bytes[13], bytes[14], bytes[15]
    ]
  }

  static func writeBytes(_ bytes: [UInt8], into target: inout [UInt8], at offset: Int) {
    for (index, byte) in bytes.enumerated() where offset + index < target.count {
      target[offset + index] = byte
    }
  }

  private static func readBTProfileDPI(
    bridge: ProbeBridge,
    preferredPeripheralName: String?,
    timeoutSeconds: TimeInterval,
    target: UInt8
  ) async throws -> BTProfileDPIRead {
    let scalarResult = try await bridge.rawRead(
      key: BLEVendorProtocol.Key.dpiScalarGet(target: target).bytes,
      timeout: timeoutSeconds,
      preferredPeripheralName: preferredPeripheralName
    )
    let pairListResult = try await bridge.rawRead(
      key: BLEVendorProtocol.Key.dpiPairListGet(target: target).bytes,
      timeout: timeoutSeconds,
      preferredPeripheralName: preferredPeripheralName
    )
    let tokenResult = try await bridge.rawRead(
      key: BLEVendorProtocol.Key.dpiStageTokenGet(target: target).bytes,
      timeout: timeoutSeconds,
      preferredPeripheralName: preferredPeripheralName
    )

    return BTProfileDPIRead(
      target: target,
      scalarRaw: scalarResult.payload,
      scalar: scalarResult.payload.flatMap(BLEVendorProtocol.parseDpiScalarPair),
      pairListRaw: pairListResult.payload,
      pairs: pairListResult.payload.flatMap(BLEVendorProtocol.parseDpiPairList) ?? [],
      tokenRaw: tokenResult.payload
    )
  }

  static func readBTProfileLightingLEDIDs(
    bridge: ProbeBridge,
    preferredPeripheralName: String?,
    timeoutSeconds: TimeInterval
  ) async throws -> [UInt8] {
    let key = BLEVendorProtocol.Key.lightingZonesGet.bytes
    let result = try await bridge.rawRead(
      key: key,
      timeout: timeoutSeconds,
      preferredPeripheralName: preferredPeripheralName
    )
    return result.payload.flatMap(BLEVendorProtocol.parseLightingLEDIDs) ?? []
  }

  private static func readBTProfileLighting(
    bridge: ProbeBridge,
    preferredPeripheralName: String?,
    timeoutSeconds: TimeInterval,
    target: UInt8,
    ledID: UInt8
  ) async throws -> BTProfileLightingRead {
    let brightnessResult = try await bridge.rawRead(
      key: BLEVendorProtocol.Key.profileLightingBrightnessGet(target: target, ledID: ledID).bytes,
      timeout: timeoutSeconds,
      preferredPeripheralName: preferredPeripheralName
    )
    let stateResult = try await bridge.rawRead(
      key: BLEVendorProtocol.Key.profileLightingZoneStateGet(target: target, ledID: ledID).bytes,
      timeout: timeoutSeconds,
      preferredPeripheralName: preferredPeripheralName
    )
    let brightness = brightnessResult.payload.flatMap { payload in
      payload.count == 1 ? payload.first : nil
    }
    return BTProfileLightingRead(
      target: target,
      ledID: ledID,
      brightnessRaw: brightnessResult.payload,
      brightness: brightness,
      stateRaw: stateResult.payload,
      color: stateResult.payload.flatMap(BLEVendorProtocol.parseV3ProLightingZoneStatePayload)
    )
  }

  private static func describeBTProfileLightingRead(_ read: BTProfileLightingRead) -> String {
    let brightness = read.brightness.map { String($0) } ?? "nil"
    let color = read.color.map { String(format: "%02x%02x%02x", $0.r, $0.g, $0.b) } ?? "unparsed"
    return
      "lighting \(btProfileTargetLabel(read.target)) "
      + "led=0x\(String(format: "%02x", read.ledID)) " + "brightness=\(brightness) "
      + "rawBrightness=\(read.brightnessRaw.map { hexString(Array($0)) } ?? "nil") "
      + "color=\(color) " + "rawState=\(read.stateRaw.map { hexString(Array($0)) } ?? "nil")"
  }

  private static func describeBTProfileDPIRead(_ read: BTProfileDPIRead) -> String {
    let scalar = read.scalar.map { "\($0.x)x\($0.y)" } ?? "nil"
    let pairs = read.pairs.isEmpty ? "nil" : describeDpiPairs(read.pairs)
    let token = read.tokenRaw.flatMap(\.first).map { String(format: "0x%02x", $0) } ?? "nil"
    return
      "target \(btProfileTargetLabel(read.target)) "
      + "scalar=\(scalar) stages=\(pairs) token=\(token) "
      + "rawScalar=\(read.scalarRaw.map { hexString(Array($0)) } ?? "nil") "
      + "rawStages=\(read.pairListRaw.map { hexString(Array($0)) } ?? "nil") "
      + "rawToken=\(read.tokenRaw.map { hexString(Array($0)) } ?? "nil")"
  }

  static func describeBTProfileButtonRead(
    key: [UInt8],
    payload: Data?,
    notifies: [Data]
  ) -> String {
    let raw = bestEffortBTButtonPayload(
      payload: payload,
      notifies: notifies,
      slot: key.count > 3 ? key[3] : 0x00
    )
    let rawDescription =
      raw.isEmpty ? "payload=nil" : "payload[\(raw.count)]=\(hexString(Array(raw)))"
    let decodedBlocks = decodeBTButtonReadFunctionBlocks(
      key: key,
      payload: raw,
      notifies: notifies
    )
    guard !decodedBlocks.isEmpty else {
      return rawDescription
    }

    let decodedDescription = decodedBlocks.map { decoded in
      "decoded-\(decoded.label)[\(decoded.block.count)]=\(hexString(decoded.block)) \(describeUSBFunctionBlock(decoded.block))"
    }.joined(separator: " ")
    return rawDescription + " " + decodedDescription
  }

  static func describeBTAckStatus(_ ack: BLEVendorProtocol.NotifyHeader?) -> String {
    guard let ack else { return "nil" }
    return String(format: "0x%02x", ack.status)
  }

  static func describeDpiPairs(_ pairs: [DpiPair]) -> String {
    "[" + pairs.map { "\($0.x)x\($0.y)" }.joined(separator: ",") + "]"
  }

  static func btProfileTargetLabel(_ target: UInt8) -> String {
    switch target {
    case 0x00:
      return "hardware-active(target=0)"
    case 0x01:
      return "live-projection(target=1)"
    default:
      return "stored-slot=\(Int(target) - 1)(target=\(target))"
    }
  }

  static func uniqueByteList(_ values: [UInt8]) -> [UInt8] {
    var seen: Set<UInt8> = []
    return values.filter { seen.insert($0).inserted }
  }

  static func decodeBTButtonReadFunctionBlock(
    key: [UInt8],
    payload: Data,
    notifies: [Data]
  ) -> [UInt8]? {
    guard key.count == 4, key[0] == 0x08, key[1] == 0x84 else {
      return nil
    }
    if let decoded = decodeDuplicatedBTButtonReadFrame(bytes: Array(payload), slot: key[3]) {
      return decoded
    }
    for frame in notifies {
      if let decoded = decodeDuplicatedBTButtonReadFrame(bytes: Array(frame), slot: key[3]) {
        return decoded
      }
    }
    return nil
  }

  private struct BTButtonReadFunctionBlock {
    let label: String
    let block: [UInt8]
  }

  private static func decodeBTButtonReadFunctionBlocks(
    key: [UInt8],
    payload: Data,
    notifies: [Data]
  ) -> [BTButtonReadFunctionBlock] {
    if let duplicated = decodeBTButtonReadFunctionBlock(
      key: key, payload: payload, notifies: notifies) {
      return [BTButtonReadFunctionBlock(label: "function", block: duplicated)]
    }
    guard key.count == 4, key[0] == 0x08, key[1] == 0x84 else {
      return []
    }
    if let interleaved = decodeInterleavedBTButtonReadFrame(bytes: Array(payload), slot: key[3]) {
      return interleaved
    }
    for frame in notifies {
      if let interleaved = decodeInterleavedBTButtonReadFrame(bytes: Array(frame), slot: key[3]) {
        return interleaved
      }
    }
    return []
  }

  static func decodeDuplicatedBTButtonReadFrame(bytes: [UInt8], slot: UInt8) -> [UInt8]? {
    guard bytes.count >= 16, bytes[0] == slot, bytes[1] == 0x00 else {
      return nil
    }

    var block: [UInt8] = []
    block.reserveCapacity(7)
    for index in stride(from: 2, through: 14, by: 2) {
      guard index + 1 < bytes.count, bytes[index] == bytes[index + 1] else {
        return nil
      }
      block.append(bytes[index])
    }
    return block
  }

  private static func decodeInterleavedBTButtonReadFrame(bytes: [UInt8], slot: UInt8)
    -> [BTButtonReadFunctionBlock]? {
    guard bytes.count >= 16, bytes[0] == slot, bytes[1] == 0x00 else {
      return nil
    }

    var evenLane: [UInt8] = []
    var oddLane: [UInt8] = []
    evenLane.reserveCapacity(7)
    oddLane.reserveCapacity(7)
    for index in stride(from: 2, through: 14, by: 2) {
      guard index + 1 < bytes.count else { return nil }
      evenLane.append(bytes[index])
      oddLane.append(bytes[index + 1])
    }
    guard evenLane != oddLane else { return nil }

    return [
      BTButtonReadFunctionBlock(label: "even-lane", block: evenLane),
      BTButtonReadFunctionBlock(label: "odd-lane", block: oddLane)
    ]
  }

  struct BTProfileWatchSnapshot: Equatable {
    let buttonPayloadHex: String
    let buttonDescription: String
    let dpiPayloadHex: String
    let dpiActive: Int?
    let dpiCount: Int?
    let dpiValues: [Int]
    let dpiStageIDs: [UInt8]

    var signature: String {
      var parts: [String] = []
      parts.reserveCapacity(6)
      parts.append(buttonPayloadHex)
      parts.append(dpiPayloadHex)
      parts.append(dpiActive.map(String.init) ?? "nil")
      parts.append(dpiCount.map(String.init) ?? "nil")
      parts.append(dpiValues.map(String.init).joined(separator: ","))
      parts.append(dpiStageIDs.map(Self.hexByte).joined(separator: ","))
      return parts.joined(separator: "|")
    }

    var summary: String {
      let dpiSummary: String
      if let dpiActive, let dpiCount {
        let stageIDs = dpiStageIDs.map { String(format: "%02x", $0) }.joined(separator: ",")
        dpiSummary =
          "dpi(active=\(dpiActive + 1)/\(dpiCount) values=\(dpiValues) stageIDs=[\(stageIDs)])"
      } else {
        dpiSummary = "dpi(payload=\(dpiPayloadHex))"
      }
      return "button=\(buttonDescription) \(dpiSummary)"
    }

    static func hexByte(_ value: UInt8) -> String {
      String(format: "%02x", value)
    }
  }

  static func readBTProfileWatchSnapshot(
    bridge: ProbeBridge,
    preferredPeripheralName: String?,
    timeoutSeconds: TimeInterval,
    buttonSlot: UInt8
  ) async throws -> BTProfileWatchSnapshot {
    let buttonKey = BLEVendorProtocol.Key.buttonBind(slot: buttonSlot).bytes
    let buttonResult = try await bridge.rawRead(
      key: buttonKey,
      timeout: timeoutSeconds,
      preferredPeripheralName: preferredPeripheralName
    )
    let buttonPayload = bestEffortBTButtonPayload(
      payload: buttonResult.payload,
      notifies: buttonResult.notifies,
      slot: buttonSlot
    )
    let buttonPayloadHex = hexString(Array(buttonPayload))
    let buttonDescription = describeBTProfileWatchButtonPayload(
      slot: buttonSlot,
      payload: buttonPayload,
      notifies: buttonResult.notifies
    )

    let dpiResult = try await bridge.rawRead(
      key: BLEVendorProtocol.Key.dpiStagesGet.bytes,
      timeout: timeoutSeconds,
      preferredPeripheralName: preferredPeripheralName
    )
    let dpiPayload = dpiResult.payload ?? Data()
    let dpiPayloadHex = hexString(Array(dpiPayload))
    let dpiSnapshot = BLEVendorProtocol.parseDpiStageSnapshot(blob: dpiPayload)

    return BTProfileWatchSnapshot(
      buttonPayloadHex: buttonPayloadHex,
      buttonDescription: buttonDescription,
      dpiPayloadHex: dpiPayloadHex,
      dpiActive: dpiSnapshot?.active,
      dpiCount: dpiSnapshot?.count,
      dpiValues: dpiSnapshot.map { Array($0.slots.prefix($0.count)) } ?? [],
      dpiStageIDs: dpiSnapshot.map { Array($0.stageIDs.prefix($0.count)) } ?? []
    )
  }

  static func describeBTProfileWatchButtonPayload(
    slot: UInt8,
    payload: Data,
    notifies: [Data]
  ) -> String {
    let key = BLEVendorProtocol.Key.buttonBind(slot: slot).bytes
    if let decoded = decodeBTButtonReadFunctionBlock(key: key, payload: payload, notifies: notifies) {
      return "decoded[\(hexString(decoded))]"
    }

    let bytes = Array(payload)
    if bytes.isEmpty {
      return "no-payload"
    }
    if bytes.count >= 9,
      bytes[0] == slot,
      bytes[1] == 0x00,
      bytes[2] == 0x02,
      bytes[3] == 0x01,
      bytes[4] == 0x02,
      bytes[5] == 0x01,
      bytes[6] == 0x00,
      bytes[7] == 0x04,
      bytes[8] == 0x45 {
      return "f12-variant[\(hexString(bytes))]"
    }

    return "raw[\(hexString(bytes))]"
  }

  static func bestEffortBTButtonPayload(
    payload: Data?,
    notifies: [Data],
    slot: UInt8
  ) -> Data {
    if let payload, !payload.isEmpty {
      return payload
    }
    if let frame = notifies.first(where: { frame in
      frame.count >= 16 && frame.first == slot
    }) {
      return frame
    }
    return payload ?? Data()
  }

  static func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
  }

  static func describeBTNotifyFrames(_ frames: [Data]) -> String {
    if frames.isEmpty {
      return "notifies: none"
    }
    let lines = frames.enumerated().map { index, frame in
      let header = BLEVendorProtocol.NotifyHeader(data: frame)
      let headerDetail: String
      if let header {
        headerDetail =
          " req=0x\(String(format: "%02x", header.req)) status=0x\(String(format: "%02x", header.status)) len=\(header.payloadLength)"
      } else {
        headerDetail = ""
      }
      return "notify[\(index)] len=\(frame.count)\(headerDetail) \(hexString(Array(frame)))"
    }
    return lines.joined(separator: "\n")
  }

}
