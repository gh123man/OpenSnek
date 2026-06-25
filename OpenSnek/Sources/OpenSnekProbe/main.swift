import Foundation
import OpenSnekCore
import OpenSnekProtocols

/// Defines USB profile clone metadata mode values.
enum USBProfileCloneMetadataMode: String {
    case repair
    case exact

    static func parse(_ raw: String) throws -> USBProfileCloneMetadataMode {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let mode = USBProfileCloneMetadataMode(rawValue: normalized) else { throw ProbeError.usage("Invalid --metadata '\(raw)' (expected repair or exact)") }
        return mode
    }
}

/// Stores probe cycle args data.
struct ProbeCycleArgs {
    let sequence: [[Int]]
    let loops: Int
    let active: Int
    let sleepMs: Int
}

/// Stores probe USB button read args data.
struct ProbeUSBButtonReadArgs {
    let slot: Int
    let profiles: [UInt8]
    let hypershift: UInt8
    let productID: Int?
}

/// Stores probe USB button set args data.
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

/// Stores probe USB button set raw args data.
struct ProbeUSBButtonSetRawArgs {
    let slot: Int
    let functionBlock: [UInt8]
    let profiles: [UInt8]
    let productID: Int?
}

/// Stores probe USB input listen args data.
struct ProbeUSBInputListenArgs {
    let durationSeconds: TimeInterval
    let maxReports: Int?
    let productID: Int?
}

/// Stores probe USB profile read args data.
struct ProbeUSBProfileReadArgs {
    let profiles: [UInt8]
    let buttonSlots: [UInt8]
    let includeEffective: Bool
    let productID: Int?
}

/// Stores probe USB profile clone args data.
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

/// Stores probe BT raw read args data.
struct ProbeBTRawReadArgs {
    let key: [UInt8]
    let preferredPeripheralName: String?
    let timeoutSeconds: TimeInterval
}

/// Stores probe BT raw write args data.
struct ProbeBTRawWriteArgs {
    let key: [UInt8]
    let payload: [UInt8]
    let preferredPeripheralName: String?
    let timeoutSeconds: TimeInterval
}

/// Stores probe BT profile read args data.
struct ProbeBTProfileReadArgs {
    let preferredPeripheralName: String?
    let targets: [UInt8]
    let buttonSlots: [UInt8]
    let includeLiveButtons: Bool
    let timeoutSeconds: TimeInterval
}

/// Stores probe BT profile active set args data.
struct ProbeBTProfileActiveSetArgs {
    let preferredPeripheralName: String?
    let target: UInt8
    let timeoutSeconds: TimeInterval
}

/// Stores probe BT profile create args data.
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

/// Stores probe BT profile button read args data.
struct ProbeBTProfileButtonReadArgs {
    let preferredPeripheralName: String?
    let target: UInt8
    let buttonSlot: UInt8
    let timeoutSeconds: TimeInterval
}

/// Stores probe BT profile button set args data.
struct ProbeBTProfileButtonSetArgs {
    let preferredPeripheralName: String?
    let target: UInt8
    let buttonSlot: UInt8
    let payload: [UInt8]
    let projectLive: Bool
    let timeoutSeconds: TimeInterval
}

/// Stores probe BT profile HID watch args data.
struct ProbeBTProfileHIDWatchArgs {
    let durationSeconds: TimeInterval
    let maxReports: Int?
    let productID: Int?
    let preferredPeripheralName: String?
}

/// Stores probe BT profile watch args data.
struct ProbeBTProfileWatchArgs {
    let preferredPeripheralName: String?
    let buttonSlot: UInt8
    let pollMs: Int
    let samples: Int
    let timeoutSeconds: TimeInterval
}

/// Stores probe BT lighting brightness args data.
struct ProbeBTLightingBrightnessArgs {
    let value: Int
    let zoneID: String?
    let preferredPeripheralName: String?
}

/// Stores probe BT lighting color args data.
struct ProbeBTLightingColorArgs {
    let color: RGBPatch
    let zoneID: String?
    let preferredPeripheralName: String?
}

/// Stores probe USB lighting brightness args data.
struct ProbeUSBLightingBrightnessArgs {
    let value: Int
    let zoneID: String?
    let productID: Int?
}

/// Stores probe USB lighting effect args data.
struct ProbeUSBLightingEffectArgs {
    let effect: LightingEffectPatch
    let zoneID: String?
    let productID: Int?
}

/// Stores probe USB lighting frame args data.
struct ProbeUSBLightingFrameArgs {
    let colors: [RGBPatch]
    let storage: UInt8
    let row: UInt8
    let startColumn: UInt8
    let endColumn: UInt8
    let productID: Int?
}

/// Defines USB lighting concurrency mode values.
enum USBLightingConcurrencyMode {
    case locked
    case unlocked
}

/// Stores probe USB lighting concurrency args data.
struct ProbeUSBLightingConcurrencyArgs {
    let modes: [USBLightingConcurrencyMode]
    let frames: Int
    let commands: Int
    let intervalMs: Int
    let responseDelayUs: useconds_t
    let productID: Int?
}

/// Stores probe USB raw args data.
struct ProbeUSBRawArgs {
    let classID: UInt8
    let cmdID: UInt8
    let size: UInt8
    let args: [UInt8]
    let responseAttempts: Int
    let responseDelayUs: useconds_t
    let productID: Int?
}

/// Defines OpenSnek probe values.
enum OpenSnekProbe {
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else { throw ProbeError.usage(usageText) }
        let commandArgs = Array(args.dropFirst())
        try await dispatchCommand(command, commandArgs: commandArgs)
    }

    private static func dispatchCommand(_ command: String, commandArgs: [String]) async throws {
        if command.hasPrefix("bt-") { try await runBluetoothCommand(command, commandArgs: commandArgs) } else if command.hasPrefix("usb-") { try await runUSBCommand(command, commandArgs: commandArgs) } else { try await runDPICommand(command, commandArgs: commandArgs) }
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
            let snapshot = try await bridge.setDpi(active: parsed.active, values: parsed.values)
            print("applied active=\(snapshot.active + 1) values=\(snapshot.values)")
        case "dpi-cycle":
            let bridge = ProbeBridge()
            let parsed = try parseCycleArgs(commandArgs)
            for i in 0..<parsed.loops {
                let values = parsed.sequence[i % parsed.sequence.count]
                let snapshot = try await bridge.setDpi(active: parsed.active, values: values)
                print("loop \(i + 1): active=\(snapshot.active + 1) values=\(snapshot.values)")
                if parsed.sleepMs > 0 { try await Task.sleep(nanoseconds: UInt64(parsed.sleepMs) * 1_000_000) }
            }
        default: throw ProbeError.usage("Unknown command '\(command)'\n\(usageText)")
        }
    }

}

do {
    try await OpenSnekProbe.run()
    Foundation.exit(EXIT_SUCCESS)
} catch { fputs("error: \(error.localizedDescription)\n", stderr) }
