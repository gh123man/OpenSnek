import Foundation
import OpenSnekCore

/// Defines the device driver contract.
public protocol DeviceDriver: Sendable {
    func readState(device: MouseDevice) async throws -> MouseState
    func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState
    func readFastDpi(device: MouseDevice) async throws -> (active: Int, values: [Int])?
    func readLightingColor(device: MouseDevice) async throws -> RGBPatch?
}

/// Defines the device repository contract.
public protocol DeviceRepository: Sendable {
    func listDevices() async throws -> [MouseDevice]
    func readState(device: MouseDevice) async throws -> MouseState
    func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState
    func readDpiStagesFast(device: MouseDevice) async throws -> (active: Int, values: [Int])?
    func readLightingColor(device: MouseDevice) async throws -> RGBPatch?
}

/// Defines USB control availability values.
public enum USBControlAvailability: String, Codable, Hashable, Sendable {
    case unknown
    case receiverPresentMouseReachable
    case receiverPresentMouseUnavailable
    case receiverAbsent
    case noControlInterface

    public var diagnosticsLabel: String {
        switch self {
        case .unknown: return "Unknown"
        case .receiverPresentMouseReachable: return "Device responding"
        case .receiverPresentMouseUnavailable: return "Receiver present, device unavailable"
        case .receiverAbsent: return "Receiver absent"
        case .noControlInterface: return "No Razer control interface"
        }
    }

    public var blocksUSBControlInteraction: Bool {
        switch self {
        case .receiverPresentMouseUnavailable, .receiverAbsent, .noControlInterface: return true
        case .unknown, .receiverPresentMouseReachable: return false
        }
    }
}

/// Describes bridge failures.
public enum BridgeError: LocalizedError, Sendable {
    case commandFailed(String)
    case usbMouseUnavailable
    case usbNoControlInterface

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        case .usbMouseUnavailable: return "USB device telemetry unavailable. Feature-report interface did not return usable responses."
        case .usbNoControlInterface: return "This Razer device does not expose the standard Razer USB control interface, so OpenSnek cannot configure it on macOS."
        }
    }
}
