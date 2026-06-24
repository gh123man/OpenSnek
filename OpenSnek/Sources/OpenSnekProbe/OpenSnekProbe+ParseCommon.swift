import Foundation
import OpenSnekCore
import OpenSnekProtocols

/// Adds parse common behavior to `OpenSnekProbe`.
extension OpenSnekProbe {
  static func parseUSBLightingZoneArgs(_ args: [String]) throws -> (
    zoneID: String?, productID: Int?
  ) {
    let flags = parseFlags(args)
    return (parseLightingZoneID(flags["--zone"]), try parseOptionalUSBPID(args))
  }

  static func parseUSBLightingBrightnessArgs(_ args: [String]) throws
    -> ProbeUSBLightingBrightnessArgs {
    let flags = parseFlags(args)
    guard let valueRaw = flags["--value"], let value = Int(valueRaw) else {
      throw ProbeError.usage("Missing --value\n\(usageText)")
    }
    return ProbeUSBLightingBrightnessArgs(
      value: max(0, min(255, value)),
      zoneID: parseLightingZoneID(flags["--zone"]),
      productID: try parseOptionalUSBPID(args)
    )
  }

  static func parseUSBLightingEffectArgs(_ args: [String]) throws
    -> ProbeUSBLightingEffectArgs {
    let flags = parseFlags(args)
    guard let kindRaw = flags["--kind"], let kind = parseLightingEffectKind(kindRaw) else {
      throw ProbeError.usage("Missing or invalid --kind\n\(usageText)")
    }

    let primary = try parseRGBPatch(flags["--color"]) ?? RGBPatch(r: 0, g: 255, b: 0)
    let secondary = try parseRGBPatch(flags["--secondary"]) ?? RGBPatch(r: 0, g: 170, b: 255)
    let direction = try parseLightingDirection(flags["--direction"] ?? "left")
    let speed = max(1, min(4, Int(flags["--speed"] ?? "2") ?? 2))
    let effect = LightingEffectPatch(
      kind: kind,
      primary: primary,
      secondary: secondary,
      waveDirection: direction,
      reactiveSpeed: speed
    )
    return ProbeUSBLightingEffectArgs(
      effect: effect,
      zoneID: parseLightingZoneID(flags["--zone"]),
      productID: try parseOptionalUSBPID(args)
    )
  }

  static func parseUSBLightingFrameArgs(_ args: [String]) throws -> ProbeUSBLightingFrameArgs {
    let flags = parseFlags(args)
    let productID = try parseOptionalUSBPID(args)
    let maxCellCount =
      DeviceProfiles.resolve(
        vendorID: 0x1532,
        productID: productID ?? 0x00AB,
        transport: .usb
      )?.softwareLightingFrameLayout?.cellCount
      ?? SoftwareLightingFrameLayout.basiliskV3ProUSB.cellCount
    let maxColumn = max(0, maxCellCount - 1)
    guard let colorsRaw = flags["--colors"] else {
      throw ProbeError.usage("Missing --colors\n\(usageText)")
    }
    let colors = try parseRGBPatchList(colorsRaw)
    guard !colors.isEmpty else {
      throw ProbeError.usage("--colors must include at least one RGB value")
    }
    guard colors.count <= maxCellCount else {
      throw ProbeError.usage(
        "--colors supports at most \(maxCellCount) custom-frame cells for this profile")
    }
    let startColumn = parseUInt8(flags["--start-col"] ?? "0") ?? 0x00
    guard Int(startColumn) <= maxColumn else {
      throw ProbeError.usage("--start-col must be in the custom-frame range 0..\(maxColumn)")
    }
    let endColumnInt = Int(startColumn) + colors.count - 1
    guard endColumnInt <= maxColumn else {
      throw ProbeError.usage("--colors extends past custom-frame column \(maxColumn)")
    }
    let storage = parseUInt8(flags["--storage"] ?? "0x01") ?? 0x01
    guard storage == 0x00 || storage == 0x01 else {
      throw ProbeError.usage("--storage must be 0x00 or 0x01")
    }
    let row = parseUInt8(flags["--row"] ?? "0") ?? 0x00
    return ProbeUSBLightingFrameArgs(
      colors: colors,
      storage: storage,
      row: row,
      startColumn: startColumn,
      endColumn: UInt8(endColumnInt),
      productID: productID
    )
  }

  static func parseUSBLightingConcurrencyArgs(_ args: [String]) throws
    -> ProbeUSBLightingConcurrencyArgs {
    let flags = parseFlags(args)
    let modes: [USBLightingConcurrencyMode]
    switch flags["--mode"] ?? "locked" {
    case "locked":
      modes = [.locked]
    case "unlocked":
      modes = [.unlocked]
    case "both":
      modes = [.locked, .unlocked]
    default:
      throw ProbeError.usage("--mode must be locked, unlocked, or both\n\(usageText)")
    }

    let frames = max(1, Int(flags["--frames"] ?? "90") ?? 90)
    let commands = max(1, Int(flags["--commands"] ?? "30") ?? 30)
    let intervalMs = max(0, Int(flags["--interval-ms"] ?? "33") ?? 33)
    let responseDelayUs = useconds_t(max(500, Int(flags["--response-delay-us"] ?? "1000") ?? 1000))
    return ProbeUSBLightingConcurrencyArgs(
      modes: modes,
      frames: frames,
      commands: commands,
      intervalMs: intervalMs,
      responseDelayUs: responseDelayUs,
      productID: try parseOptionalUSBPID(args)
    )
  }

  static func parseUSBRawArgs(_ args: [String]) throws -> ProbeUSBRawArgs {
    let flags = parseFlags(args)
    guard let classRaw = flags["--class"], let classID = parseUInt8(classRaw) else {
      throw ProbeError.usage("Missing or invalid --class\n\(usageText)")
    }
    guard let cmdRaw = flags["--cmd"], let cmdID = parseUInt8(cmdRaw) else {
      throw ProbeError.usage("Missing or invalid --cmd\n\(usageText)")
    }
    let parsedArgs = try parseCSVBytes(flags["--args"] ?? "")
    let size = parseUInt8(flags["--size"] ?? "") ?? UInt8(parsedArgs.count)
    let responseAttempts = max(1, Int(flags["--response-attempts"] ?? "12") ?? 12)
    let responseDelayUs = useconds_t(
      max(1_000, Int(flags["--response-delay-us"] ?? "40000") ?? 40_000))
    return ProbeUSBRawArgs(
      classID: classID,
      cmdID: cmdID,
      size: size,
      args: parsedArgs,
      responseAttempts: responseAttempts,
      responseDelayUs: responseDelayUs,
      productID: try parseOptionalUSBPID(args)
    )
  }

  static func parseOptionalUSBPID(_ args: [String]) throws -> Int? {
    let flags = parseFlags(args)
    guard let raw = flags["--pid"] else { return nil }
    guard let value = parseUInt16(raw) else {
      throw ProbeError.usage("Invalid --pid '\(raw)'")
    }
    return Int(value)
  }

  static func parseOptionalBTPID(_ args: [String]) throws -> Int? {
    let flags = parseFlags(args)
    guard let raw = flags["--pid"] else { return nil }
    guard let value = parseUInt16(raw) else {
      throw ProbeError.usage("Invalid --pid '\(raw)'")
    }
    return Int(value)
  }

  static func parseBTProfileTarget(flags: [String: String]) throws -> UInt8 {
    if let targetRaw = flags["--target"] {
      guard let target = parseUInt8(targetRaw) else {
        throw ProbeError.usage("Invalid --target '\(targetRaw)'")
      }
      return target
    }
    if let storedSlotRaw = flags["--stored-slot"] {
      let storedSlot = try parseStoredSlot(storedSlotRaw, optionName: "--stored-slot")
      return OnboardProfileLimits.profileID(forStoredSlot: storedSlot)
    }
    throw ProbeError.usage("Missing --stored-slot or --target\n\(usageText)")
  }

  static func parseBTProfileTargets(flags: [String: String]) throws -> [UInt8] {
    if let targetsRaw = flags["--targets"] {
      let targets = try parseUInt8List(targetsRaw)
      guard !targets.isEmpty else { throw ProbeError.usage("Empty --targets") }
      return targets
    }
    if let storedSlotsRaw = flags["--stored-slots"] {
      let storedSlots = try parseStoredSlots(storedSlotsRaw, optionName: "--stored-slots")
      return storedSlots.map { OnboardProfileLimits.profileID(forStoredSlot: $0) }
    }
    return OnboardProfileLimits.storedProfileIDs
  }

  static func parseStoredSlot(_ raw: String, optionName: String) throws -> UInt8 {
    guard let storedSlot = parseUInt8(raw), OnboardProfileLimits.containsStoredSlot(storedSlot)
    else {
      throw ProbeError.usage(
        "Invalid \(optionName) '\(raw)' (expected \(OnboardProfileLimits.storedSlotRangeDescription))"
      )
    }
    return storedSlot
  }

  static func parseStoredSlots(_ raw: String, optionName: String) throws -> [UInt8] {
    let storedSlots = try parseUInt8List(raw)
    guard !storedSlots.isEmpty else { throw ProbeError.usage("Empty \(optionName)") }
    for storedSlot in storedSlots where !OnboardProfileLimits.containsStoredSlot(storedSlot) {
      throw ProbeError.usage(
        "Invalid \(optionName) value '\(storedSlot)' (expected \(OnboardProfileLimits.storedSlotRangeDescription))"
      )
    }
    return storedSlots
  }

  static func parseUSBProfiles(_ raw: String?, defaultProfiles: [UInt8]) throws -> [UInt8] {
    guard let raw else { return defaultProfiles }
    let normalized = raw.lowercased()
    switch normalized {
    case "default", "persistent", "1":
      return [0x01]
    case "direct", "0":
      return [0x00]
    case "both", "all":
      return [0x01, 0x00]
    default:
      throw ProbeError.usage("Invalid --profile '\(raw)' (expected default/direct/both)")
    }
  }

  static func parseFlags(_ args: [String]) -> [String: String] {
    var result: [String: String] = [:]
    var i = 0
    while i < args.count {
      let key = args[i]
      if key.hasPrefix("--") {
        if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
          result[key] = args[i + 1]
          i += 2
        } else {
          result[key] = "true"
          i += 1
        }
      } else {
        i += 1
      }
    }
    return result
  }

  static func parseValues(_ raw: String) throws -> [Int] {
    let values = raw.split(separator: ",").compactMap {
      Int($0.trimmingCharacters(in: .whitespaces))
    }
    let clipped = values.prefix(DeviceProfiles.maximumDpiStageCount).map {
      DeviceProfiles.clampDPI($0, profileID: nil)
    }
    guard !clipped.isEmpty else {
      throw ProbeError.usage("Invalid DPI values: \(raw)")
    }
    return clipped
  }

  static func parseBoolean(_ raw: String) -> Bool {
    switch raw.lowercased() {
    case "1", "true", "yes", "on":
      return true
    default:
      return false
    }
  }

  static func parseLightingZoneID(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized.isEmpty || normalized == "all" ? nil : normalized
  }

  static func parsePeripheralName(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  static func parseLightingEffectKind(_ raw: String) -> LightingEffectKind? {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "off":
      return .off
    case "static", "static_color", "staticcolor":
      return .staticColor
    case "spectrum":
      return .spectrum
    case "wave":
      return .wave
    case "reactive":
      return .reactive
    case "pulse_random", "pulserandom", "random":
      return .pulseRandom
    case "pulse_single", "pulsesingle", "single":
      return .pulseSingle
    case "pulse_dual", "pulsedual", "dual":
      return .pulseDual
    default:
      return nil
    }
  }

  static func parseLightingDirection(_ raw: String) throws -> LightingWaveDirection {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "left", "1":
      return .left
    case "right", "2":
      return .right
    default:
      throw ProbeError.usage("Invalid --direction '\(raw)' (expected left/right)")
    }
  }

  static func parseRGBPatch(_ raw: String?) throws -> RGBPatch? {
    guard let raw else { return nil }
    let bytes = try parseHexBytes(raw)
    guard bytes.count == 3 else {
      throw ProbeError.usage("Invalid RGB hex '\(raw)' (expected 6 hex chars)")
    }
    return RGBPatch(r: Int(bytes[0]), g: Int(bytes[1]), b: Int(bytes[2]))
  }

  static func parseRGBPatchList(_ raw: String) throws -> [RGBPatch] {
    try raw
      .split(separator: ",")
      .map { token -> RGBPatch in
        let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let color = try parseRGBPatch(value) else {
          throw ProbeError.usage("Invalid RGB hex '\(value)' (expected 6 hex chars)")
        }
        return color
      }
  }

  static func parseHexBytes(_ raw: String) throws -> [UInt8] {
    let normalized =
      raw
      .replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive])
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "_", with: "")
    guard normalized.count % 2 == 0 else {
      throw ProbeError.usage("Invalid hex byte string: \(raw)")
    }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(normalized.count / 2)
    var idx = normalized.startIndex
    while idx < normalized.endIndex {
      let next = normalized.index(idx, offsetBy: 2)
      let chunk = normalized[idx..<next]
      guard let value = UInt8(chunk, radix: 16) else {
        throw ProbeError.usage("Invalid hex byte string: \(raw)")
      }
      bytes.append(value)
      idx = next
    }
    return bytes
  }

  static func parseUInt8List(_ raw: String) throws -> [UInt8] {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    return
      try trimmed
      .split(separator: ",")
      .map { token -> UInt8 in
        let valueRaw = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = parseUInt8(valueRaw) else {
          throw ProbeError.usage("Invalid byte value '\(valueRaw)'")
        }
        return value
      }
  }

  static func asciiBytes(_ value: String, maxLength: Int, fieldName: String) throws
    -> [UInt8] {
    let bytes = Array(value.utf8)
    guard bytes.count <= maxLength else {
      throw ProbeError.usage("\(fieldName) must be \(maxLength) ASCII bytes or fewer")
    }
    guard bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else {
      throw ProbeError.usage("\(fieldName) must contain printable ASCII only")
    }
    return bytes
  }

  static func parseCSVBytes(_ raw: String) throws -> [UInt8] {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return [] }
    return
      try trimmed
      .split(separator: ",")
      .map { chunk in
        let token = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = parseCSVByte(token) else {
          throw ProbeError.usage("Invalid byte value '\(token)'")
        }
        return value
      }
  }

  static func parseCSVByte(_ raw: String) -> UInt8? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.lowercased().hasPrefix("0x") {
      return UInt8(trimmed.dropFirst(2), radix: 16)
    }
    if trimmed.count == 2
      || trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "abcdefABCDEF")) != nil {
      return UInt8(trimmed, radix: 16)
    }
    return UInt8(trimmed, radix: 10)
  }

  static func parseUInt8(_ raw: String) -> UInt8? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.lowercased().hasPrefix("0x") {
      return UInt8(trimmed.dropFirst(2), radix: 16)
    }
    return UInt8(trimmed, radix: 10)
  }

  static func parseUInt16(_ raw: String) -> UInt16? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.lowercased().hasPrefix("0x") {
      return UInt16(trimmed.dropFirst(2), radix: 16)
    }
    return UInt16(trimmed, radix: 10)
  }

  static func describeUSBFunctionBlock(_ block: [UInt8]) -> String {
    ButtonBindingSupport.describeUSBFunctionBlock(block)
  }

}
