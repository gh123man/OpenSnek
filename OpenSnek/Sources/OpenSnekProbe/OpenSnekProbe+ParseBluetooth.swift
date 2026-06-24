import Foundation
import OpenSnekCore
import OpenSnekProtocols

/// Adds parse Bluetooth behavior to `OpenSnekProbe`.
extension OpenSnekProbe {
  static func parseBTRawReadArgs(_ args: [String]) throws -> ProbeBTRawReadArgs {
    let flags = parseFlags(args)
    guard let keyRaw = flags["--key"] else {
      throw ProbeError.usage("Missing --key\n\(usageText)")
    }
    let key = try parseHexBytes(keyRaw)
    guard key.count == 4 else {
      throw ProbeError.usage("Invalid --key '\(keyRaw)' (expected 8 hex chars)")
    }
    let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "600").map { $0 / 1000.0 } ?? 0.6)
    let preferredPeripheralName = parsePeripheralName(flags["--name"])
    return ProbeBTRawReadArgs(
      key: key,
      preferredPeripheralName: preferredPeripheralName,
      timeoutSeconds: timeoutSeconds
    )
  }

  static func parseBTRawWriteArgs(_ args: [String]) throws -> ProbeBTRawWriteArgs {
    let flags = parseFlags(args)
    guard let keyRaw = flags["--key"] else {
      throw ProbeError.usage("Missing --key\n\(usageText)")
    }
    guard let payloadRaw = flags["--payload"] else {
      throw ProbeError.usage("Missing --payload\n\(usageText)")
    }
    let key = try parseHexBytes(keyRaw)
    guard key.count == 4 else {
      throw ProbeError.usage("Invalid --key '\(keyRaw)' (expected 8 hex chars)")
    }
    let payload = try parseHexBytes(payloadRaw)
    let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "900").map { $0 / 1000.0 } ?? 0.9)
    let preferredPeripheralName = parsePeripheralName(flags["--name"])
    return ProbeBTRawWriteArgs(
      key: key,
      payload: payload,
      preferredPeripheralName: preferredPeripheralName,
      timeoutSeconds: timeoutSeconds
    )
  }

  static func parseBTProfileReadArgs(_ args: [String]) throws -> ProbeBTProfileReadArgs {
    let flags = parseFlags(args)
    let targets = try parseBTProfileTargets(flags: flags)
    let buttonSlots = try parseUInt8List(flags["--button-slots"] ?? "")
    let includeLiveButtons = parseBoolean(flags["--include-live-buttons"] ?? "off")
    let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "900").map { $0 / 1000.0 } ?? 0.9)
    let preferredPeripheralName = parsePeripheralName(flags["--name"])
    return ProbeBTProfileReadArgs(
      preferredPeripheralName: preferredPeripheralName,
      targets: targets,
      buttonSlots: buttonSlots,
      includeLiveButtons: includeLiveButtons,
      timeoutSeconds: timeoutSeconds
    )
  }

  static func parseBTProfileActiveSetArgs(_ args: [String]) throws
    -> ProbeBTProfileActiveSetArgs {
    let flags = parseFlags(args)
    guard parseBoolean(flags["--yes"] ?? "off") else {
      throw ProbeError.usage(
        "bt-profile-active-set changes the hardware-active Bluetooth target; pass --yes to continue\n\(usageText)"
      )
    }
    let target = try parseBTProfileTarget(flags: flags)
    guard OnboardProfileLimits.containsPersistentProfileID(target) else {
      throw ProbeError.usage(
        "bt-profile-active-set targets known Bluetooth profile targets \(OnboardProfileLimits.persistentProfileIDRangeDescription), not target \(target)"
      )
    }
    let timeoutSeconds = max(
      0.1, Double(flags["--timeout-ms"] ?? "1200").map { $0 / 1000.0 } ?? 1.2)
    let preferredPeripheralName = parsePeripheralName(flags["--name"])
    return ProbeBTProfileActiveSetArgs(
      preferredPeripheralName: preferredPeripheralName,
      target: target,
      timeoutSeconds: timeoutSeconds
    )
  }

  static func parseBTProfileCreateArgs(_ args: [String]) throws -> ProbeBTProfileCreateArgs {
    let flags = parseFlags(args)
    guard parseBoolean(flags["--yes"] ?? "off") else {
      throw ProbeError.usage(
        "bt-profile-create clears and rewrites a persistent onboard target; pass --yes to continue\n\(usageText)"
      )
    }
    let target = try parseBTProfileTarget(flags: flags)
    guard OnboardProfileLimits.containsStoredProfileID(target) else {
      throw ProbeError.usage(
        "bt-profile-create expects a stored target (use --stored-slot \(OnboardProfileLimits.storedSlotRangeDescription) or --target \(OnboardProfileLimits.storedProfileIDRangeDescription))"
      )
    }
    let profileName =
      flags["--profile-name"]
      ?? "OPENSNEK_MAC_SLOT_\(Int(target) - OnboardProfileLimits.storedSlotProfileIDOffset)"
    _ = try asciiBytes(profileName, maxLength: 0x74 - 0x10, fieldName: "--profile-name")

    let owner =
      flags["--owner"] ?? "31933b5452df5708882d4fb55d0b2905f16d829500fe936c56f98d5cd0241a76"
    let ownerBytes = try asciiBytes(owner, maxLength: 64, fieldName: "--owner")
    guard ownerBytes.count == 64 else {
      throw ProbeError.usage("--owner must be exactly 64 ASCII bytes")
    }

    let guid: UUID
    if let guidRaw = flags["--guid"] {
      guard let parsed = UUID(uuidString: guidRaw) else {
        throw ProbeError.usage("Invalid --guid '\(guidRaw)'")
      }
      guid = parsed
    } else {
      guid = UUID()
    }

    let values = try parseValues(flags["--values"] ?? "400,800,1600,3200,6400")
    let active = max(0, min(values.count - 1, (Int(flags["--active"] ?? "3") ?? 3) - 1))
    let brightness = UInt8(max(0, min(255, Int(flags["--brightness"] ?? "84") ?? 84)))
    let timeoutSeconds = max(
      0.1, Double(flags["--timeout-ms"] ?? "1400").map { $0 / 1000.0 } ?? 1.4)
    let preferredPeripheralName = parsePeripheralName(flags["--name"])
    return ProbeBTProfileCreateArgs(
      preferredPeripheralName: preferredPeripheralName,
      target: target,
      guid: guid,
      profileName: profileName,
      owner: owner,
      values: values,
      active: active,
      brightness: brightness,
      timeoutSeconds: timeoutSeconds
    )
  }

  static func parseBTProfileButtonReadArgs(_ args: [String]) throws
    -> ProbeBTProfileButtonReadArgs {
    let flags = parseFlags(args)
    guard let slotRaw = flags["--button-slot"] ?? flags["--slot"],
      let buttonSlot = parseUInt8(slotRaw)
    else {
      throw ProbeError.usage("Missing or invalid --button-slot\n\(usageText)")
    }
    let target = try parseBTProfileTarget(flags: flags)
    let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "900").map { $0 / 1000.0 } ?? 0.9)
    let preferredPeripheralName = parsePeripheralName(flags["--name"])
    return ProbeBTProfileButtonReadArgs(
      preferredPeripheralName: preferredPeripheralName,
      target: target,
      buttonSlot: buttonSlot,
      timeoutSeconds: timeoutSeconds
    )
  }

  static func parseBTProfileButtonSetArgs(_ args: [String]) throws
    -> ProbeBTProfileButtonSetArgs {
    let flags = parseFlags(args)
    guard parseBoolean(flags["--yes"] ?? "off") else {
      throw ProbeError.usage(
        "bt-profile-button-set writes persistent onboard target data; pass --yes to continue\n\(usageText)"
      )
    }
    guard let slotRaw = flags["--button-slot"] ?? flags["--slot"],
      let buttonSlot = parseUInt8(slotRaw)
    else {
      throw ProbeError.usage("Missing or invalid --button-slot\n\(usageText)")
    }
    let target = try parseBTProfileTarget(flags: flags)
    guard OnboardProfileLimits.containsStoredProfileID(target) else {
      throw ProbeError.usage(
        "bt-profile-button-set expects a stored target (use --stored-slot \(OnboardProfileLimits.storedSlotRangeDescription) or --target \(OnboardProfileLimits.storedProfileIDRangeDescription))"
      )
    }

    let payload: [UInt8]
    if let payloadRaw = flags["--payload"] {
      payload = try parseHexBytes(payloadRaw)
      guard payload.count == 10 else {
        throw ProbeError.usage("--payload must decode to exactly 10 bytes")
      }
      guard payload[0] == target, payload[1] == buttonSlot else {
        throw ProbeError.usage(
          "--payload first bytes must match target/button-slot (expected \(String(format: "%02x %02x", target, buttonSlot)))"
        )
      }
    } else {
      let kindRaw = flags["--kind"] ?? ButtonBindingKind.keyboardSimple.rawValue
      guard let kind = ButtonBindingKind(rawValue: kindRaw) else {
        throw ProbeError.usage("Invalid --kind '\(kindRaw)'")
      }
      let hidKey = parseUInt8(flags["--hid-key"] ?? "") ?? 0x09
      let hidModifiers = parseUInt8(flags["--hid-modifiers"] ?? "") ?? 0x00
      let turboEnabled = parseBoolean(flags["--turbo"] ?? "off")
      let turboRate = UInt16(
        ButtonBindingSupport.clampTurboRate(
          Int(flags["--turbo-rate"] ?? "\(ButtonBindingSupport.defaultTurboRate)")
            ?? ButtonBindingSupport.defaultTurboRate
        )
      )
      let clutchDPI = Int(flags["--clutch-dpi"] ?? "").map { max(100, min(30_000, $0)) }
      let livePayload = BLEVendorProtocol.buildButtonPayload(
        slot: buttonSlot,
        kind: kind,
        hidKey: hidKey,
        hidModifiers: hidModifiers,
        turboEnabled: turboEnabled && kind.supportsTurbo,
        turboRate: turboRate,
        clutchDPI: clutchDPI
      )
      payload = Array(
        BLEVendorProtocol.retargetButtonPayload(livePayload, target: target, slot: buttonSlot))
    }

    let projectLive = parseBoolean(flags["--project-live"] ?? "off")
    let timeoutSeconds = max(
      0.1, Double(flags["--timeout-ms"] ?? "1100").map { $0 / 1000.0 } ?? 1.1)
    let preferredPeripheralName = parsePeripheralName(flags["--name"])
    return ProbeBTProfileButtonSetArgs(
      preferredPeripheralName: preferredPeripheralName,
      target: target,
      buttonSlot: buttonSlot,
      payload: payload,
      projectLive: projectLive,
      timeoutSeconds: timeoutSeconds
    )
  }

  static func parseBTProfileHIDWatchArgs(_ args: [String]) throws
    -> ProbeBTProfileHIDWatchArgs {
    let flags = parseFlags(args)
    let durationSeconds = max(0.5, Double(flags["--duration"] ?? "20") ?? 20.0)
    let maxReportsRaw = max(0, Int(flags["--max-reports"] ?? "0") ?? 0)
    let maxReports = maxReportsRaw > 0 ? maxReportsRaw : nil
    let productID = try parseOptionalBTPID(args) ?? 0x00AC
    let preferredPeripheralName = parsePeripheralName(flags["--name"])
    return ProbeBTProfileHIDWatchArgs(
      durationSeconds: durationSeconds,
      maxReports: maxReports,
      productID: productID,
      preferredPeripheralName: preferredPeripheralName
    )
  }

  static func parseBTProfileWatchArgs(_ args: [String]) throws -> ProbeBTProfileWatchArgs {
    let flags = parseFlags(args)
    let buttonSlot = UInt8(max(0, min(255, Int(flags["--slot"] ?? "4") ?? 4)))
    let pollMs = max(0, Int(flags["--poll-ms"] ?? "1000") ?? 1000)
    let samples = max(1, Int(flags["--samples"] ?? "20") ?? 20)
    let timeoutSeconds = max(0.1, Double(flags["--timeout-ms"] ?? "900").map { $0 / 1000.0 } ?? 0.9)
    let preferredPeripheralName = parsePeripheralName(flags["--name"])
    return ProbeBTProfileWatchArgs(
      preferredPeripheralName: preferredPeripheralName,
      buttonSlot: buttonSlot,
      pollMs: pollMs,
      samples: samples,
      timeoutSeconds: timeoutSeconds
    )
  }

  static func parseBTLightingZoneArgs(_ args: [String]) throws -> (
    zoneID: String?, preferredPeripheralName: String?
  ) {
    let flags = parseFlags(args)
    return (parseLightingZoneID(flags["--zone"]), parsePeripheralName(flags["--name"]))
  }

  static func parseBTLightingBrightnessArgs(_ args: [String]) throws
    -> ProbeBTLightingBrightnessArgs {
    let flags = parseFlags(args)
    guard let valueRaw = flags["--value"], let value = Int(valueRaw) else {
      throw ProbeError.usage("Missing --value\n\(usageText)")
    }
    return ProbeBTLightingBrightnessArgs(
      value: max(0, min(255, value)),
      zoneID: parseLightingZoneID(flags["--zone"]),
      preferredPeripheralName: parsePeripheralName(flags["--name"])
    )
  }

  static func parseBTLightingColorArgs(_ args: [String]) throws -> ProbeBTLightingColorArgs {
    let flags = parseFlags(args)
    guard let color = try parseRGBPatch(flags["--color"]) else {
      throw ProbeError.usage("Missing or invalid --color\n\(usageText)")
    }
    return ProbeBTLightingColorArgs(
      color: color,
      zoneID: parseLightingZoneID(flags["--zone"]),
      preferredPeripheralName: parsePeripheralName(flags["--name"])
    )
  }

}
