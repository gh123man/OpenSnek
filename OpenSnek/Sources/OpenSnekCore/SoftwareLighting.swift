import Foundation

public enum SoftwareLightingPresetID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case flame
    case scrollingRainbow = "scrolling_rainbow"
    case cometChase = "comet_chase"
    case aurora

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .flame:
            return "Flame"
        case .scrollingRainbow:
            return "Scrolling Rainbow"
        case .cometChase:
            return "Comet Chase"
        case .aurora:
            return "Aurora"
        }
    }

    public var defaultPalette: [RGBPatch] {
        switch self {
        case .flame:
            return [
                RGBPatch(r: 48, g: 0, b: 0),
                RGBPatch(r: 255, g: 48, b: 0),
                RGBPatch(r: 255, g: 176, b: 28),
            ]
        case .scrollingRainbow:
            return [
                RGBPatch(r: 255, g: 0, b: 64),
                RGBPatch(r: 255, g: 140, b: 0),
                RGBPatch(r: 255, g: 235, b: 0),
                RGBPatch(r: 20, g: 220, b: 80),
                RGBPatch(r: 0, g: 190, b: 255),
                RGBPatch(r: 130, g: 80, b: 255),
            ]
        case .cometChase:
            return [
                RGBPatch(r: 30, g: 190, b: 255),
                RGBPatch(r: 120, g: 72, b: 255),
                RGBPatch(r: 255, g: 255, b: 255),
            ]
        case .aurora:
            return [
                RGBPatch(r: 38, g: 214, b: 126),
                RGBPatch(r: 20, g: 210, b: 220),
                RGBPatch(r: 96, g: 96, b: 255),
                RGBPatch(r: 228, g: 94, b: 255),
            ]
        }
    }

    public var defaultSpeed: Double {
        1.0
    }

    public var renderSpeedMultiplier: Double {
        switch self {
        case .scrollingRainbow:
            return 3.0
        case .flame, .cometChase, .aurora:
            return 1.0
        }
    }
}

public struct SoftwareLightingEffectRequest: Codable, Hashable, Sendable {
    public static let maximumPaletteColorCount = 8

    public let presetID: SoftwareLightingPresetID
    public let framesPerSecond: Int
    public let intensity: Double
    public let speed: Double
    public let palette: [RGBPatch]

    public init(
        presetID: SoftwareLightingPresetID,
        framesPerSecond: Int = 30,
        intensity: Double = 1.0,
        speed: Double? = nil,
        palette: [RGBPatch]? = nil
    ) {
        self.presetID = presetID
        self.framesPerSecond = max(1, min(30, framesPerSecond))
        self.intensity = max(0.0, min(1.0, intensity))
        self.speed = max(0.0, min(2.0, speed ?? presetID.defaultSpeed))
        self.palette = Self.normalizedPalette(
            palette ?? presetID.defaultPalette,
            fallback: presetID.defaultPalette
        )
    }

    private static func normalizedPalette(_ palette: [RGBPatch], fallback: [RGBPatch]) -> [RGBPatch] {
        let source = palette.isEmpty ? fallback : palette
        let limited = Array(source.prefix(maximumPaletteColorCount))
        return limited.map { color in
            RGBPatch(
                r: max(0, min(255, color.r)),
                g: max(0, min(255, color.g)),
                b: max(0, min(255, color.b))
            )
        }
    }
}

public enum SoftwareLightingEngineRunState: String, Codable, Hashable, Sendable {
    case running
    case stopped
    case suspended
    case failed
}

public struct SoftwareLightingEngineStatus: Codable, Hashable, Sendable {
    public let deviceID: String
    public let state: SoftwareLightingEngineRunState
    public let request: SoftwareLightingEffectRequest?
    public let message: String?
    public let updatedAt: Date

    public init(
        deviceID: String,
        state: SoftwareLightingEngineRunState,
        request: SoftwareLightingEffectRequest?,
        message: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.deviceID = deviceID
        self.state = state
        self.request = request
        self.message = message
        self.updatedAt = updatedAt
    }

    public var isRunning: Bool {
        state == .running
    }
}

public struct SoftwareLightingFrameCell: Codable, Hashable, Sendable {
    public let index: Int
    public let id: String
    public let label: String

    public init(index: Int, id: String, label: String) {
        self.index = max(0, index)
        self.id = id
        self.label = label
    }
}

public struct SoftwareLightingFrameLayout: Codable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let cells: [SoftwareLightingFrameCell]

    public init(id: String, label: String, cells: [SoftwareLightingFrameCell]) {
        self.id = id
        self.label = label
        self.cells = cells.sorted { $0.index < $1.index }
    }

    public var cellCount: Int {
        cells.count
    }

    public static let basiliskV3ProUSB = SoftwareLightingFrameLayout(
        id: "basilisk_v3_pro_usb_12_cell",
        label: "Basilisk V3 Pro USB 12-cell frame",
        cells: [
            SoftwareLightingFrameCell(index: 0, id: "logo", label: "Logo"),
            SoftwareLightingFrameCell(index: 1, id: "scroll_wheel", label: "Scroll Wheel"),
            SoftwareLightingFrameCell(index: 2, id: "underglow_left_front", label: "Underglow Left Front"),
            SoftwareLightingFrameCell(index: 3, id: "underglow_left_2", label: "Underglow Left 2"),
            SoftwareLightingFrameCell(index: 4, id: "underglow_left_3", label: "Underglow Left 3"),
            SoftwareLightingFrameCell(index: 5, id: "underglow_left_4", label: "Underglow Left 4"),
            SoftwareLightingFrameCell(index: 6, id: "underglow_left_rear", label: "Underglow Left Rear"),
            SoftwareLightingFrameCell(index: 7, id: "underglow_right_rear", label: "Underglow Right Rear"),
            SoftwareLightingFrameCell(index: 8, id: "underglow_right_2", label: "Underglow Right 2"),
            SoftwareLightingFrameCell(index: 9, id: "underglow_right_3", label: "Underglow Right 3"),
            SoftwareLightingFrameCell(index: 10, id: "underglow_right_middle", label: "Underglow Right Middle"),
            SoftwareLightingFrameCell(index: 11, id: "underglow_right_front", label: "Underglow Right Front"),
        ]
    )
}

public struct USBLightingFramePatch: Codable, Hashable, Sendable {
    public let storage: UInt8
    public let row: UInt8
    public let startColumn: UInt8
    public let colors: [RGBPatch]

    public init(
        storage: UInt8 = 0x01,
        row: UInt8 = 0x00,
        startColumn: UInt8 = 0x00,
        colors: [RGBPatch]
    ) {
        self.storage = storage
        self.row = row
        self.startColumn = startColumn
        self.colors = colors.map(Self.clamped)
    }

    private static func clamped(_ color: RGBPatch) -> RGBPatch {
        RGBPatch(
            r: max(0, min(255, color.r)),
            g: max(0, min(255, color.g)),
            b: max(0, min(255, color.b))
        )
    }
}

public enum SoftwareLightingRenderer {
    public static func render(
        request: SoftwareLightingEffectRequest,
        layout: SoftwareLightingFrameLayout,
        elapsedTime: TimeInterval
    ) -> USBLightingFramePatch {
        let animationTime = max(0, elapsedTime) * request.speed * request.presetID.renderSpeedMultiplier
        let colors = (0..<layout.cellCount).map { index in
            color(
                preset: request.presetID,
                palette: request.palette,
                index: index,
                count: layout.cellCount,
                time: animationTime,
                intensity: request.intensity
            )
        }
        return USBLightingFramePatch(colors: colors)
    }

    private static func color(
        preset: SoftwareLightingPresetID,
        palette: [RGBPatch],
        index: Int,
        count: Int,
        time: TimeInterval,
        intensity: Double
    ) -> RGBPatch {
        switch preset {
        case .flame:
            return flame(palette: palette, index: index, count: count, time: time, intensity: intensity)
        case .scrollingRainbow:
            return scrollingRainbow(palette: palette, index: index, count: count, time: time, intensity: intensity)
        case .cometChase:
            return cometChase(palette: palette, index: index, count: count, time: time, intensity: intensity)
        case .aurora:
            return aurora(palette: palette, index: index, count: count, time: time, intensity: intensity)
        }
    }

    private static func flame(
        palette: [RGBPatch],
        index: Int,
        count: Int,
        time: TimeInterval,
        intensity: Double
    ) -> RGBPatch {
        let position = normalizedPosition(index: index, count: count)
        let flicker = 0.55 +
            0.25 * sin(time * 9.0 + Double(index) * 1.7) +
            0.20 * sin(time * 17.0 + Double(index) * 0.73)
        let heat = max(0.0, min(1.0, flicker * (0.85 + 0.25 * position)))
        let ember = index <= 1 ? 0.65 : 1.0
        return scaledColor(samplePalette(palette, position: heat), scale: ember * intensity)
    }

    private static func scrollingRainbow(
        palette: [RGBPatch],
        index: Int,
        count: Int,
        time: TimeInterval,
        intensity: Double
    ) -> RGBPatch {
        let hue = normalizedPosition(index: index, count: count) - time * 0.18
        return scaledColor(samplePalette(palette, position: hue, cyclic: true), scale: 0.95 * intensity)
    }

    private static func cometChase(
        palette: [RGBPatch],
        index: Int,
        count: Int,
        time: TimeInterval,
        intensity: Double
    ) -> RGBPatch {
        let countDouble = max(1.0, Double(count))
        let head = time * 4.8
        let distance = circularDistance(Double(index), head, countDouble)
        let glow = max(0.0, 1.0 - distance / 4.0)
        let corePulse = index <= 1 ? 0.25 + 0.20 * sin(time * 6.0) : 0.0
        let value = max(corePulse, pow(glow, 2.2)) * intensity
        let cometColor = samplePalette(palette, position: time * 0.16, cyclic: true)
        return scaledColor(cometColor, scale: value)
    }

    private static func aurora(
        palette: [RGBPatch],
        index: Int,
        count: Int,
        time: TimeInterval,
        intensity: Double
    ) -> RGBPatch {
        let position = normalizedPosition(index: index, count: count)
        let waveA = 0.5 + 0.5 * sin(time * 1.4 + position * .pi * 4.0)
        let waveB = 0.5 + 0.5 * sin(time * 0.9 - position * .pi * 6.0)
        let value = (0.35 + 0.55 * waveB) * intensity
        let color = samplePalette(palette, position: waveA, cyclic: true)
        return scaledColor(color, scale: value)
    }

    private static func normalizedPosition(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        return Double(index) / Double(count - 1)
    }

    private static func circularDistance(_ a: Double, _ b: Double, _ count: Double) -> Double {
        let raw = abs((a - b).truncatingRemainder(dividingBy: count))
        return min(raw, count - raw)
    }

    private static func scaled(_ value: Double, intensity: Double) -> Int {
        Int(round(max(0.0, min(255.0, value * intensity))))
    }

    private static func scaledColor(_ color: RGBPatch, scale: Double) -> RGBPatch {
        RGBPatch(
            r: scaled(Double(color.r), intensity: scale),
            g: scaled(Double(color.g), intensity: scale),
            b: scaled(Double(color.b), intensity: scale)
        )
    }

    private static func samplePalette(
        _ palette: [RGBPatch],
        position: Double,
        cyclic: Bool = false
    ) -> RGBPatch {
        guard !palette.isEmpty else { return RGBPatch(r: 0, g: 0, b: 0) }
        guard palette.count > 1 else { return palette[0] }

        let normalized = cyclic ? positiveFraction(position) : max(0.0, min(1.0, position))
        let scaledPosition = normalized * Double(cyclic ? palette.count : palette.count - 1)
        let lowerIndex = Int(floor(scaledPosition)) % palette.count
        let upperIndex = (lowerIndex + 1) % palette.count
        let mix = scaledPosition - floor(scaledPosition)
        let lower = palette[lowerIndex]
        let upper = palette[upperIndex]

        return RGBPatch(
            r: lerpChannel(lower.r, upper.r, mix),
            g: lerpChannel(lower.g, upper.g, mix),
            b: lerpChannel(lower.b, upper.b, mix)
        )
    }

    private static func lerpChannel(_ a: Int, _ b: Int, _ mix: Double) -> Int {
        Int(round(Double(a) + (Double(b - a) * max(0.0, min(1.0, mix)))))
    }

    private static func hsv(hue: Double, saturation: Double, value: Double) -> RGBPatch {
        let h = positiveFraction(hue) * 6.0
        let s = max(0.0, min(1.0, saturation))
        let v = max(0.0, min(1.0, value))
        let c = v * s
        let x = c * (1.0 - abs(h.truncatingRemainder(dividingBy: 2.0) - 1.0))
        let m = v - c

        let rgb: (Double, Double, Double)
        switch h {
        case 0..<1:
            rgb = (c, x, 0)
        case 1..<2:
            rgb = (x, c, 0)
        case 2..<3:
            rgb = (0, c, x)
        case 3..<4:
            rgb = (0, x, c)
        case 4..<5:
            rgb = (x, 0, c)
        default:
            rgb = (c, 0, x)
        }

        return RGBPatch(
            r: Int(round((rgb.0 + m) * 255)),
            g: Int(round((rgb.1 + m) * 255)),
            b: Int(round((rgb.2 + m) * 255))
        )
    }

    private static func positiveFraction(_ value: Double) -> Double {
        let fraction = value - floor(value)
        return fraction < 0 ? fraction + 1.0 : fraction
    }
}
