import Foundation
import OpenSnekCore
import OpenSnekProtocols

enum USBProfileCloneMetadataMode: String {
  case repair
  case exact

  static func parse(_ raw: String) throws -> USBProfileCloneMetadataMode {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard let mode = USBProfileCloneMetadataMode(rawValue: normalized) else {
      throw ProbeError.usage("Invalid --metadata '\(raw)' (expected repair or exact)")
    }
    return mode
  }
}

struct ProbeCycleArgs {
  let sequence: [[Int]]
  let loops: Int
  let active: Int
  let sleepMs: Int
}

struct ProbeUSBButtonReadArgs {
  let slot: Int
  let profiles: [UInt8]
  let hypershift: UInt8
  let productID: Int?
}

struct ProbeUSBButtonSetArgs {
  let slot: Int
  let kind: String
  let hidKey: Int
  let turboEnabled: Bool
  let turboRate: Int
  let clutchDPI: Int?
  let profiles: [UInt8]
  let productID: Int?
}

struct ProbeUSBButtonSetRawArgs {
  let slot: Int
  let functionBlock: [UInt8]
  let profiles: [UInt8]
  let productID: Int?
}

struct ProbeUSBInputListenArgs {
  let durationSeconds: TimeInterval
  let maxReports: Int?
  let productID: Int?
}

struct ProbeUSBProfileReadArgs {
  let profiles: [UInt8]
  let buttonSlots: [UInt8]
  let includeEffective: Bool
  let productID: Int?
}

struct ProbeUSBProfileCloneArgs {
  let sourceProfile: UInt8
  let targetProfile: UInt8
  let metadataMode: USBProfileCloneMetadataMode
  let targetName: String?
  let targetIdentifier: UUID?
  let cloneMappedContent: Bool
  let buttonSlots: [UInt8]
  let productID: Int?
}

struct ProbeBTRawReadArgs {
  let key: [UInt8]
  let preferredPeripheralName: String?
  let timeoutSeconds: TimeInterval
}

struct ProbeBTRawWriteArgs {
  let key: [UInt8]
  let payload: [UInt8]
  let preferredPeripheralName: String?
  let timeoutSeconds: TimeInterval
}

struct ProbeBTProfileReadArgs {
  let preferredPeripheralName: String?
  let targets: [UInt8]
  let buttonSlots: [UInt8]
  let includeLiveButtons: Bool
  let timeoutSeconds: TimeInterval
}

struct ProbeBTProfileActiveSetArgs {
  let preferredPeripheralName: String?
  let target: UInt8
  let timeoutSeconds: TimeInterval
}

struct ProbeBTProfileCreateArgs {
  let preferredPeripheralName: String?
  let target: UInt8
  let guid: UUID
  let profileName: String
  let owner: String
  let values: [Int]
  let active: Int
  let brightness: UInt8
  let timeoutSeconds: TimeInterval
}

struct ProbeBTProfileButtonReadArgs {
  let preferredPeripheralName: String?
  let target: UInt8
  let buttonSlot: UInt8
  let timeoutSeconds: TimeInterval
}

struct ProbeBTProfileButtonSetArgs {
  let preferredPeripheralName: String?
  let target: UInt8
  let buttonSlot: UInt8
  let payload: [UInt8]
  let projectLive: Bool
  let timeoutSeconds: TimeInterval
}

struct ProbeBTProfileHIDWatchArgs {
  let durationSeconds: TimeInterval
  let maxReports: Int?
  let productID: Int?
  let preferredPeripheralName: String?
}

struct ProbeBTProfileWatchArgs {
  let preferredPeripheralName: String?
  let buttonSlot: UInt8
  let pollMs: Int
  let samples: Int
  let timeoutSeconds: TimeInterval
}

struct ProbeBTLightingBrightnessArgs {
  let value: Int
  let zoneID: String?
  let preferredPeripheralName: String?
}

struct ProbeBTLightingColorArgs {
  let color: RGBPatch
  let zoneID: String?
  let preferredPeripheralName: String?
}

struct ProbeUSBLightingBrightnessArgs {
  let value: Int
  let zoneID: String?
  let productID: Int?
}

struct ProbeUSBLightingEffectArgs {
  let effect: LightingEffectPatch
  let zoneID: String?
  let productID: Int?
}

struct ProbeUSBLightingFrameArgs {
  let colors: [RGBPatch]
  let storage: UInt8
  let row: UInt8
  let startColumn: UInt8
  let endColumn: UInt8
  let productID: Int?
}

enum USBLightingConcurrencyMode {
  case locked
  case unlocked
}

struct ProbeUSBLightingConcurrencyArgs {
  let modes: [USBLightingConcurrencyMode]
  let frames: Int
  let commands: Int
  let intervalMs: Int
  let responseDelayUs: useconds_t
  let productID: Int?
}

struct ProbeUSBRawArgs {
  let classID: UInt8
  let cmdID: UInt8
  let size: UInt8
  let args: [UInt8]
  let responseAttempts: Int
  let responseDelayUs: useconds_t
  let productID: Int?
}

enum OpenSnekProbe {
  static func run() async throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else {
      throw ProbeError.usage(usageText)
    }
    let commandArgs = Array(args.dropFirst())
    try await dispatchCommand(command, commandArgs: commandArgs)
  }

  private static func dispatchCommand(_ command: String, commandArgs: [String]) async throws {
    if command.hasPrefix("bt-") {
      try await runBluetoothCommand(command, commandArgs: commandArgs)
    } else if command.hasPrefix("usb-") {
      try await runUSBCommand(command, commandArgs: commandArgs)
    } else {
      try await runDPICommand(command, commandArgs: commandArgs)
    }
  }

  private static func runDPICommand(_ command: String, commandArgs: [String]) async throws {
    switch command {
    case "dpi-read":
      let bridge = ProbeBridge()
      let snapshot = try await bridge.readDpi()
      print("active=\(snapshot.active + 1) count=\(snapshot.count) values=\(snapshot.values)")
    case "dpi-set":
      let bridge = ProbeBridge()
      let parsed = try parseSetArgs(commandArgs)
      let snapshot = try await bridge.setDpi(
        active: parsed.active,
        values: parsed.values
      )
      print("applied active=\(snapshot.active + 1) values=\(snapshot.values)")
    case "dpi-cycle":
      let bridge = ProbeBridge()
      let parsed = try parseCycleArgs(commandArgs)
      for i in 0..<parsed.loops {
        let values = parsed.sequence[i % parsed.sequence.count]
        let snapshot = try await bridge.setDpi(
          active: parsed.active,
          values: values
        )
        print("loop \(i + 1): active=\(snapshot.active + 1) values=\(snapshot.values)")
        if parsed.sleepMs > 0 {
          try await Task.sleep(nanoseconds: UInt64(parsed.sleepMs) * 1_000_000)
        }
      }
    default:
      throw ProbeError.usage("Unknown command '\(command)'\n\(usageText)")
    }
  }

}

do {
  try await OpenSnekProbe.run()
  Foundation.exit(EXIT_SUCCESS)
} catch {
  fputs("error: \(error.localizedDescription)\n", stderr)
}
