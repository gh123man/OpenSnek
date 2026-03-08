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

extension MouseState {
    func merged(with previous: MouseState?) -> MouseState {
        guard let previous else { return self }
        return MouseState(
            device: device.merged(with: previous.device),
            connection: connection,
            battery_percent: battery_percent ?? previous.battery_percent,
            charging: charging ?? previous.charging,
            dpi: dpi ?? previous.dpi,
            dpi_stages: DpiStages(
                active_stage: dpi_stages.active_stage ?? previous.dpi_stages.active_stage,
                values: dpi_stages.values ?? previous.dpi_stages.values
            ),
            poll_rate: poll_rate ?? previous.poll_rate,
            device_mode: device_mode ?? previous.device_mode,
            led_value: led_value ?? previous.led_value,
            capabilities: Capabilities(
                dpi_stages: capabilities.dpi_stages || previous.capabilities.dpi_stages,
                poll_rate: capabilities.poll_rate || previous.capabilities.poll_rate,
                button_remap: capabilities.button_remap || previous.capabilities.button_remap,
                lighting: capabilities.lighting || previous.capabilities.lighting
            )
        )
    }
}

struct DeviceSummary: Codable, Hashable {
    let id: String?
    let product_name: String?
    let serial: String?
    let transport: String?
    let firmware: String?
}

extension DeviceSummary {
    func merged(with previous: DeviceSummary) -> DeviceSummary {
        DeviceSummary(
            id: id ?? previous.id,
            product_name: product_name ?? previous.product_name,
            serial: serial ?? previous.serial,
            transport: transport ?? previous.transport,
            firmware: firmware ?? previous.firmware
        )
    }
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
