import Foundation
import OpenSnekCore

public protocol DeviceDriver: Sendable {
    func readState(device: MouseDevice) async throws -> MouseState
    func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState
    func readFastDpi(device: MouseDevice) async throws -> (active: Int, values: [Int])?
    func readLightingColor(device: MouseDevice) async throws -> RGBPatch?
}

public protocol DeviceRepository: Sendable {
    func listDevices() async throws -> [MouseDevice]
    func readState(device: MouseDevice) async throws -> MouseState
    func apply(device: MouseDevice, patch: DevicePatch) async throws -> MouseState
    func readDpiStagesFast(device: MouseDevice) async throws -> (active: Int, values: [Int])?
    func readLightingColor(device: MouseDevice) async throws -> RGBPatch?
}

public enum USBControlAvailability: String, Codable, Hashable, Sendable {
    case unknown
    case receiverPresentMouseReachable
    case receiverPresentMouseUnavailable
    case receiverAbsent

    public var diagnosticsLabel: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .receiverPresentMouseReachable:
            return "Mouse responding"
        case .receiverPresentMouseUnavailable:
            return "Receiver present, mouse unavailable"
        case .receiverAbsent:
            return "Receiver absent"
        }
    }

    public var blocksUSBControlInteraction: Bool {
        switch self {
        case .receiverPresentMouseUnavailable, .receiverAbsent:
            return true
        case .unknown, .receiverPresentMouseReachable:
            return false
        }
    }
}

public enum BridgeError: LocalizedError, Sendable {
    case commandFailed(String)
    case usbMouseUnavailable

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        case .usbMouseUnavailable:
            return "USB device telemetry unavailable. Feature-report interface did not return usable responses."
        }
    }
}
