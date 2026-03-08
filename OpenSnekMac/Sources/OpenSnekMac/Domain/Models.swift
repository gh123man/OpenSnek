import Foundation

struct MouseDevice: Codable, Identifiable, Hashable {
    let id: String
    let vendor_id: Int
    let product_id: Int
    let product_name: String
    let transport: String
    let path_b64: String
    let serial: String?
    let firmware: String?

    var connectionLabel: String {
        transport == "bluetooth" ? "Bluetooth" : "USB"
    }
}

struct DpiPair: Codable, Hashable {
    let x: Int
    let y: Int
}

struct DpiStages: Codable, Hashable {
    let active_stage: Int?
    let values: [Int]?
}

struct DeviceMode: Codable, Hashable {
    let mode: Int
    let param: Int
}

struct Capabilities: Codable, Hashable {
    let dpi_stages: Bool
    let poll_rate: Bool
    let button_remap: Bool
    let lighting: Bool
}

struct MouseState: Codable, Hashable {
    let device: DeviceSummary
    let connection: String
    let battery_percent: Int?
    let charging: Bool?
    let dpi: DpiPair?
    let dpi_stages: DpiStages
    let poll_rate: Int?
    let device_mode: DeviceMode?
    let led_value: Int?
    let capabilities: Capabilities
}

struct DeviceSummary: Codable, Hashable {
    let id: String?
    let product_name: String?
    let serial: String?
    let transport: String?
    let firmware: String?
}

struct BridgeEnvelope: Codable {
    let ok: Bool
    let error: String?
    let devices: [MouseDevice]?
    let state: MouseState?
    let before: MouseState?
    let after: MouseState?
}

struct RGBPatch: Sendable {
    let r: Int
    let g: Int
    let b: Int
}

struct ButtonBindingPatch: Sendable {
    let slot: Int
    let kind: ButtonBindingKind
    let hidKey: Int?
}

struct DevicePatch: Sendable {
    var pollRate: Int? = nil
    var dpiStages: [Int]? = nil
    var activeStage: Int? = nil
    var ledBrightness: Int? = nil
    var ledRGB: RGBPatch? = nil
    var buttonBinding: ButtonBindingPatch? = nil
}

enum ButtonBindingKind: String, CaseIterable, Identifiable {
    case `default`
    case leftClick = "left_click"
    case rightClick = "right_click"
    case middleClick = "middle_click"
    case mouseBack = "mouse_back"
    case mouseForward = "mouse_forward"
    case keyboardSimple = "keyboard_simple"
    case clearLayer = "clear_layer"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .default: return "Default"
        case .leftClick: return "Left Click"
        case .rightClick: return "Right Click"
        case .middleClick: return "Middle Click"
        case .mouseBack: return "Mouse Back"
        case .mouseForward: return "Mouse Forward"
        case .keyboardSimple: return "Keyboard Key"
        case .clearLayer: return "Clear Layer"
        }
    }
}
