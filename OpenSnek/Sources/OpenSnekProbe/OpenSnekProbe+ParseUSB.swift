import Foundation
import OpenSnekCore
import OpenSnekProtocols

extension OpenSnekProbe {
  static func parseSetArgs(_ args: [String]) throws -> (values: [Int], active: Int) {
    let flags = parseFlags(args)
    guard let valuesRaw = flags["--values"] else {
      throw ProbeError.usage("Missing --values\n\(usageText)")
    }
    let values = try parseValues(valuesRaw)
    let active = max(0, (Int(flags["--active"] ?? "1") ?? 1) - 1)
    return (values, active)
  }

  static func parseCycleArgs(_ args: [String]) throws -> ProbeCycleArgs {
    let flags = parseFlags(args)
    guard let raw = flags["--sequence"] else {
      throw ProbeError.usage("Missing --sequence\n\(usageText)")
    }
    let sequence = try raw.split(separator: ";").map { try parseValues(String($0)) }
    guard !sequence.isEmpty else { throw ProbeError.usage("Empty --sequence") }
    let loops = max(1, Int(flags["--loops"] ?? "10") ?? 10)
    let active = max(0, (Int(flags["--active"] ?? "1") ?? 1) - 1)
    let sleepMs = max(0, Int(flags["--sleep-ms"] ?? "120") ?? 120)
    return ProbeCycleArgs(sequence: sequence, loops: loops, active: active, sleepMs: sleepMs)
  }

  static func parseUSBButtonReadArgs(_ args: [String]) throws -> ProbeUSBButtonReadArgs {
    let flags = parseFlags(args)
    guard let slotRaw = flags["--slot"], let slot = Int(slotRaw) else {
      throw ProbeError.usage("Missing --slot\n\(usageText)")
    }
    let profiles = try parseUSBProfiles(flags["--profile"], defaultProfiles: [0x01])
    let hypershift = UInt8(max(0, min(1, Int(flags["--hypershift"] ?? "0") ?? 0)))
    return ProbeUSBButtonReadArgs(
      slot: slot,
      profiles: profiles,
      hypershift: hypershift,
      productID: try parseOptionalUSBPID(args)
    )
  }

  static func parseUSBButtonSetArgs(_ args: [String]) throws -> ProbeUSBButtonSetArgs {
    let flags = parseFlags(args)
    guard let slotRaw = flags["--slot"], let slot = Int(slotRaw) else {
      throw ProbeError.usage("Missing --slot\n\(usageText)")
    }
    guard let kindRaw = flags["--kind"]?.lowercased() else {
      throw ProbeError.usage("Missing --kind\n\(usageText)")
    }
    let validKinds: Set<String> = [
      "default", "dpi_cycle", "dpi_clutch", "left_click", "right_click", "middle_click",
      "scroll_up", "scroll_down", "mouse_back", "mouse_forward",
      "keyboard_simple", "clear_layer"
    ]
    guard validKinds.contains(kindRaw) else {
      throw ProbeError.usage("Invalid --kind '\(kindRaw)'\n\(usageText)")
    }

    let hidKey = max(0, min(255, Int(flags["--hid-key"] ?? "4") ?? 4))
    let turboEnabled = parseBoolean(flags["--turbo"] ?? "off")
    let turboRate = ButtonBindingSupport.clampTurboRate(
      Int(flags["--turbo-rate"] ?? "\(ButtonBindingSupport.defaultTurboRate)")
        ?? ButtonBindingSupport.defaultTurboRate
    )
    let clutchDPI = Int(flags["--clutch-dpi"] ?? "").map { max(100, min(30_000, $0)) }
    let profiles = try parseUSBProfiles(flags["--profile"], defaultProfiles: [0x01, 0x00])
    return ProbeUSBButtonSetArgs(
      slot: slot,
      kind: kindRaw,
      hidKey: hidKey,
      turboEnabled: turboEnabled,
      turboRate: turboRate,
      clutchDPI: clutchDPI,
      profiles: profiles,
      productID: try parseOptionalUSBPID(args)
    )
  }

  static func parseUSBButtonSetRawArgs(_ args: [String]) throws -> ProbeUSBButtonSetRawArgs {
    let flags = parseFlags(args)
    guard let slotRaw = flags["--slot"], let slot = Int(slotRaw) else {
      throw ProbeError.usage("Missing --slot\n\(usageText)")
    }
    guard let hexRaw = flags["--hex"] else {
      throw ProbeError.usage("Missing --hex\n\(usageText)")
    }
    let functionBlock = try parseHexBytes(hexRaw)
    guard functionBlock.count == 7 else {
      throw ProbeError.usage("--hex must decode to exactly 7 bytes")
    }
    let profiles = try parseUSBProfiles(flags["--profile"], defaultProfiles: [0x01, 0x00])
    return ProbeUSBButtonSetRawArgs(
      slot: slot,
      functionBlock: functionBlock,
      profiles: profiles,
      productID: try parseOptionalUSBPID(args)
    )
  }

  static func parseUSBInputListenArgs(_ args: [String]) throws -> ProbeUSBInputListenArgs {
    let flags = parseFlags(args)
    let durationSeconds = max(0.5, Double(flags["--duration"] ?? "15") ?? 15.0)
    let maxReportsRaw = max(0, Int(flags["--max-reports"] ?? "0") ?? 0)
    let maxReports = maxReportsRaw > 0 ? maxReportsRaw : nil
    return ProbeUSBInputListenArgs(
      durationSeconds: durationSeconds,
      maxReports: maxReports,
      productID: try parseOptionalUSBPID(args)
    )
  }

  static func parseUSBProfileReadArgs(_ args: [String]) throws -> ProbeUSBProfileReadArgs {
    let flags = parseFlags(args)
    let profiles: [UInt8]
    if let raw = flags["--profiles"] {
      profiles = try parseUInt8List(raw)
      guard !profiles.isEmpty else { throw ProbeError.usage("Empty --profiles") }
    } else if let raw = flags["--stored-slots"] {
      let storedSlots = try parseStoredSlots(raw, optionName: "--stored-slots")
      profiles = storedSlots.map { OnboardProfileLimits.profileID(forStoredSlot: $0) }
    } else {
      profiles = OnboardProfileLimits.storedProfileIDs
    }

    let buttonSlotsRaw = flags["--button-slots"] ?? "5"
    let normalizedButtonSlots = buttonSlotsRaw.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let buttonSlots: [UInt8]
    if normalizedButtonSlots.isEmpty || normalizedButtonSlots == "none"
      || normalizedButtonSlots == "off" {
      buttonSlots = []
    } else {
      buttonSlots = try parseUInt8List(buttonSlotsRaw)
    }

    let includeEffective = parseBoolean(
      flags["--include-effective"] ?? flags["--include-live"] ?? "on")
    return ProbeUSBProfileReadArgs(
      profiles: uniqueByteList(profiles),
      buttonSlots: uniqueByteList(buttonSlots),
      includeEffective: includeEffective,
      productID: try parseOptionalUSBPID(args)
    )
  }

  static func parseUSBProfileVerifyWritesArgs(
    _ args: [String],
    command: String = "usb-profile-verify-writes"
  ) throws -> (profile: UInt8, productID: Int?) {
    let flags = parseFlags(args)
    guard parseBoolean(flags["--yes"] ?? "off") else {
      throw ProbeError.usage(
        "\(command) sends guarded writes to a stored profile; pass --yes to continue\n\(usageText)")
    }

    let profile = try parseUSBStoredProfile(flags: flags, command: command)
    return (profile, try parseOptionalUSBPID(args))
  }

  static func parseUSBProfileCloneArgs(_ args: [String]) throws -> ProbeUSBProfileCloneArgs {
    let flags = parseFlags(args)
    guard parseBoolean(flags["--yes"] ?? "off") else {
      throw ProbeError.usage(
        "usb-profile-clone overwrites a stored profile; pass --yes to continue\n\(usageText)")
    }

    let sourceProfile = try parseUSBProfileSelector(
      flags: flags,
      profileKey: "--source-profile",
      storedSlotKey: "--source-stored-slot",
      command: "usb-profile-clone"
    )
    let targetProfile = try parseUSBProfileSelector(
      flags: flags,
      profileKey: "--target-profile",
      storedSlotKey: "--target-stored-slot",
      command: "usb-profile-clone"
    )
    guard sourceProfile != targetProfile else {
      throw ProbeError.usage("usb-profile-clone source and target must be different")
    }
    guard OnboardProfileLimits.containsStoredProfileID(targetProfile) else {
      throw ProbeError.usage(
        "usb-profile-clone target must be a stored profile \(OnboardProfileLimits.storedProfileIDRangeDescription)"
      )
    }

    let buttonSlotsRaw = flags["--button-slots"] ?? "5"
    let normalizedButtonSlots = buttonSlotsRaw.trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    let buttonSlots: [UInt8]
    if normalizedButtonSlots.isEmpty || normalizedButtonSlots == "none"
      || normalizedButtonSlots == "off" {
      buttonSlots = []
    } else {
      buttonSlots = try parseUInt8List(buttonSlotsRaw)
    }
    let metadataMode = try USBProfileCloneMetadataMode.parse(flags["--metadata"] ?? "repair")
    let targetName = flags["--target-name"]
    if let targetName {
      _ = try asciiBytes(targetName, maxLength: 0x74 - 0x10, fieldName: "--target-name")
    }
    let targetIdentifier: UUID?
    if let raw = flags["--target-uuid"] {
      guard let uuid = UUID(uuidString: raw) else {
        throw ProbeError.usage("Invalid --target-uuid '\(raw)'")
      }
      targetIdentifier = uuid
    } else {
      targetIdentifier = nil
    }
    return ProbeUSBProfileCloneArgs(
      sourceProfile: sourceProfile,
      targetProfile: targetProfile,
      metadataMode: metadataMode,
      targetName: targetName,
      targetIdentifier: targetIdentifier,
      cloneMappedContent: parseBoolean(flags["--content"] ?? "on"),
      buttonSlots: uniqueByteList(buttonSlots),
      productID: try parseOptionalUSBPID(args)
    )
  }

  static func parseUSBProfileActiveSetArgs(_ args: [String]) throws -> (
    profile: UInt8, productID: Int?
  ) {
    let flags = parseFlags(args)
    guard parseBoolean(flags["--yes"] ?? "off") else {
      throw ProbeError.usage(
        "usb-profile-active-set changes the hardware-active USB profile; pass --yes to continue\n\(usageText)"
      )
    }

    let profile: UInt8
    if let raw = flags["--profile"] {
      guard let parsed = parseUInt8(raw) else {
        throw ProbeError.usage("Invalid --profile '\(raw)'")
      }
      profile = parsed
    } else if let raw = flags["--stored-slot"] {
      let storedSlot = try parseStoredSlot(raw, optionName: "--stored-slot")
      profile = OnboardProfileLimits.profileID(forStoredSlot: storedSlot)
    } else {
      throw ProbeError.usage("Missing --profile or --stored-slot\n\(usageText)")
    }

    guard OnboardProfileLimits.containsPersistentProfileID(profile) else {
      throw ProbeError.usage(
        "usb-profile-active-set targets known USB profiles \(OnboardProfileLimits.persistentProfileIDRangeDescription), not profile \(profile)"
      )
    }
    return (profile, try parseOptionalUSBPID(args))
  }

  static func parseUSBProfileDeleteArgs(_ args: [String]) throws -> (
    profile: UInt8, productID: Int?
  ) {
    let flags = parseFlags(args)
    guard parseBoolean(flags["--yes"] ?? "off") else {
      throw ProbeError.usage(
        "usb-profile-delete unassigns a stored profile from the hardware cycle ring; pass --yes to continue\n\(usageText)"
      )
    }

    let profile = try parseUSBStoredProfile(flags: flags, command: "usb-profile-delete")
    return (profile, try parseOptionalUSBPID(args))
  }

  static func parseUSBProfileSelector(
    flags: [String: String],
    profileKey: String,
    storedSlotKey: String,
    command: String
  ) throws -> UInt8 {
    let profile: UInt8
    if let raw = flags[profileKey] {
      guard let parsed = parseUInt8(raw) else {
        throw ProbeError.usage("Invalid \(profileKey) '\(raw)'")
      }
      profile = parsed
    } else if let raw = flags[storedSlotKey] {
      let storedSlot = try parseStoredSlot(raw, optionName: storedSlotKey)
      profile = OnboardProfileLimits.profileID(forStoredSlot: storedSlot)
    } else {
      throw ProbeError.usage("Missing \(profileKey) or \(storedSlotKey)\n\(usageText)")
    }

    guard OnboardProfileLimits.containsPersistentProfileID(profile) else {
      throw ProbeError.usage(
        "\(command) only targets known USB profiles \(OnboardProfileLimits.persistentProfileIDRangeDescription), not profile \(profile)"
      )
    }
    return profile
  }

  static func parseUSBStoredProfile(flags: [String: String], command: String) throws
    -> UInt8 {
    let profile: UInt8
    if let raw = flags["--profile"] {
      guard let parsed = parseUInt8(raw) else {
        throw ProbeError.usage("Invalid --profile '\(raw)'")
      }
      profile = parsed
    } else if let raw = flags["--stored-slot"] {
      let storedSlot = try parseStoredSlot(raw, optionName: "--stored-slot")
      profile = OnboardProfileLimits.profileID(forStoredSlot: storedSlot)
    } else {
      throw ProbeError.usage("Missing --profile or --stored-slot\n\(usageText)")
    }

    guard OnboardProfileLimits.containsStoredProfileID(profile) else {
      throw ProbeError.usage(
        "\(command) only targets known stored USB profiles \(OnboardProfileLimits.storedProfileIDRangeDescription), not live/base profile \(profile)"
      )
    }
    return profile
  }

}
