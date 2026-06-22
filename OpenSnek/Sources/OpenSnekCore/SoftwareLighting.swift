import Foundation

public enum SoftwareLightingPresetID: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case flame
    case scrollingRainbow = "scrolling_rainbow"
    case cometChase = "comet_chase"
    case nightRider = "night_rider"
    case aurora
    case jellybeans
    case batteryMeter = "battery_meter"

    public static let animatedPresets: [SoftwareLightingPresetID] = [
        .flame,
        .scrollingRainbow,
        .cometChase,
        .nightRider,
        .aurora,
        .jellybeans
    ]

    public static let basiliskV3ProPresets: [SoftwareLightingPresetID] = animatedPresets + [.batteryMeter]

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .flame:
            return "Flame"
        case .scrollingRainbow:
            return "Scrolling Rainbow"
        case .cometChase:
            return "Comet Chase"
        case .nightRider:
            return "Night Rider"
        case .aurora:
            return "Aurora"
        case .jellybeans:
            return "Jellybeans"
        case .batteryMeter:
            return "Battery Meter"
        }
    }

    public var defaultPalette: [RGBPatch] {
        switch self {
        case .flame:
            return [
                RGBPatch(r: 48, g: 0, b: 0),
                RGBPatch(r: 255, g: 48, b: 0),
                RGBPatch(r: 255, g: 176, b: 28)
            ]
        case .scrollingRainbow:
            return [
                RGBPatch(r: 255, g: 0, b: 64),
                RGBPatch(r: 255, g: 140, b: 0),
                RGBPatch(r: 255, g: 235, b: 0),
                RGBPatch(r: 20, g: 220, b: 80),
                RGBPatch(r: 0, g: 190, b: 255),
                RGBPatch(r: 130, g: 80, b: 255)
            ]
        case .cometChase:
            return [
                RGBPatch(r: 30, g: 190, b: 255),
                RGBPatch(r: 120, g: 72, b: 255),
                RGBPatch(r: 255, g: 255, b: 255)
            ]
        case .nightRider:
            return [
                RGBPatch(r: 255, g: 0, b: 0)
            ]
        case .aurora:
            return [
                RGBPatch(r: 38, g: 214, b: 126),
                RGBPatch(r: 20, g: 210, b: 220),
                RGBPatch(r: 96, g: 96, b: 255),
                RGBPatch(r: 228, g: 94, b: 255)
            ]
        case .jellybeans:
            return [
                RGBPatch(r: 255, g: 20, b: 96),
                RGBPatch(r: 255, g: 112, b: 0),
                RGBPatch(r: 255, g: 232, b: 0),
                RGBPatch(r: 46, g: 230, b: 54),
                RGBPatch(r: 0, g: 220, b: 255),
                RGBPatch(r: 0, g: 92, b: 255),
                RGBPatch(r: 144, g: 48, b: 255),
                RGBPatch(r: 255, g: 56, b: 228)
            ]
        case .batteryMeter:
            return [
                RGBPatch(r: 255, g: 0, b: 0),
                RGBPatch(r: 255, g: 255, b: 0),
                RGBPatch(r: 255, g: 255, b: 255)
            ]
        }
    }

    public var defaultSpeed: Double {
        switch self {
        case .batteryMeter:
            return 0.0
        case .flame, .scrollingRainbow, .cometChase, .nightRider, .aurora, .jellybeans:
            return 1.0
        }
    }

    public var renderSpeedMultiplier: Double {
        switch self {
        case .scrollingRainbow:
            return 3.0
        case .flame, .cometChase, .nightRider, .aurora, .jellybeans, .batteryMeter:
            return 1.0
        }
    }

    public var isAnimated: Bool {
        switch self {
        case .batteryMeter:
            return false
        case .flame, .scrollingRainbow, .cometChase, .nightRider, .aurora, .jellybeans:
            return true
        }
    }

    public var usesPaletteControls: Bool {
        switch self {
        case .batteryMeter:
            return false
        case .flame, .scrollingRainbow, .cometChase, .nightRider, .aurora, .jellybeans:
            return true
        }
    }

    public var usesSpeedControl: Bool {
        isAnimated
    }

    public var maximumPaletteColorCount: Int {
        switch self {
        case .nightRider:
            return 1
        case .flame, .scrollingRainbow, .cometChase, .aurora, .jellybeans, .batteryMeter:
            return SoftwareLightingEffectRequest.maximumPaletteColorCount
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
            fallback: presetID.defaultPalette,
            maximumColorCount: presetID.maximumPaletteColorCount
        )
    }

    private static func normalizedPalette(
        _ palette: [RGBPatch],
        fallback: [RGBPatch],
        maximumColorCount: Int
    ) -> [RGBPatch] {
        let source = palette.isEmpty ? fallback : palette
        let limited = Array(source.prefix(max(1, maximumColorCount)))
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

    private static let basiliskV3USBCells = [
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
        SoftwareLightingFrameCell(index: 12, id: "underglow_tail_1", label: "Underglow Tail 1"),
        SoftwareLightingFrameCell(index: 13, id: "underglow_tail_2", label: "Underglow Tail 2")
    ]

    public static let basiliskV3ProUSB = SoftwareLightingFrameLayout(
        id: "basilisk_v3_family_usb_14_cell",
        label: "Basilisk V3-family USB 14-cell frame",
        cells: basiliskV3USBCells
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
    private struct BatteryMeterProgressAnchor {
        let chargeFraction: Double
        let fillFraction: Double
    }

    private static let batteryMeterLowFlashPeriod: TimeInterval = 1.0
    private static let batteryMeterLowFlashDutyCycle = 0.5
    private static let batteryMeterVisualMidpointFillFraction = 4.5 / 12.0
    private static let batteryMeterProgressAnchors = [
        BatteryMeterProgressAnchor(chargeFraction: 0.0, fillFraction: 0.0),
        BatteryMeterProgressAnchor(chargeFraction: 0.2, fillFraction: 0.2),
        // Hardware light-bar geometry reads 50% as centered at 4.5 of the 12 strip cells.
        BatteryMeterProgressAnchor(chargeFraction: 0.5, fillFraction: batteryMeterVisualMidpointFillFraction),
        BatteryMeterProgressAnchor(chargeFraction: 1.0, fillFraction: 1.0)
    ]

    private struct RenderSample {
        let preset: SoftwareLightingPresetID
        let palette: [RGBPatch]
        let index: Int
        let count: Int
        let time: TimeInterval
        let intensity: Double
        let batteryPercent: Int?
    }

    public static func render(
        request: SoftwareLightingEffectRequest,
        layout: SoftwareLightingFrameLayout,
        elapsedTime: TimeInterval,
        batteryPercent: Int? = nil
    ) -> USBLightingFramePatch {
        let renderTime = max(0, elapsedTime)
        let animationTime: TimeInterval
        if request.presetID == .batteryMeter {
            animationTime = renderTime
        } else {
            animationTime = renderTime * request.speed * request.presetID.renderSpeedMultiplier
        }
        let colors = (0..<layout.cellCount).map { index in
            color(
                RenderSample(
                    preset: request.presetID,
                    palette: request.palette,
                    index: index,
                    count: layout.cellCount,
                    time: animationTime,
                    intensity: request.intensity,
                    batteryPercent: batteryPercent
                )
            )
        }
        return USBLightingFramePatch(colors: colors)
    }

    private static func color(_ sample: RenderSample) -> RGBPatch {
        switch sample.preset {
        case .flame:
            return flame(
                palette: sample.palette,
                index: sample.index,
                count: sample.count,
                time: sample.time,
                intensity: sample.intensity
            )
        case .scrollingRainbow:
            return scrollingRainbow(
                palette: sample.palette,
                index: sample.index,
                count: sample.count,
                time: sample.time,
                intensity: sample.intensity
            )
        case .cometChase:
            return cometChase(
                palette: sample.palette,
                index: sample.index,
                count: sample.count,
                time: sample.time,
                intensity: sample.intensity
            )
        case .nightRider:
            return nightRider(
                palette: sample.palette,
                index: sample.index,
                count: sample.count,
                time: sample.time,
                intensity: sample.intensity
            )
        case .aurora:
            return aurora(
                palette: sample.palette,
                index: sample.index,
                count: sample.count,
                time: sample.time,
                intensity: sample.intensity
            )
        case .jellybeans:
            return jellybeans(
                palette: sample.palette,
                index: sample.index,
                count: sample.count,
                time: sample.time,
                intensity: sample.intensity
            )
        case .batteryMeter:
            return batteryMeter(
                index: sample.index,
                count: sample.count,
                time: sample.time,
                batteryPercent: sample.batteryPercent,
                intensity: sample.intensity
            )
        }
    }

    private static func batteryMeter(
        index: Int,
        count: Int,
        time: TimeInterval,
        batteryPercent: Int?,
        intensity: Double
    ) -> RGBPatch {
        let stripStartIndex = count > 2 ? 2 : 0
        if index < stripStartIndex {
            return scaledColor(RGBPatch(r: 255, g: 255, b: 255), scale: intensity)
        }

        guard let batteryPercent else { return RGBPatch(r: 0, g: 0, b: 0) }
        let percent = max(0, min(100, batteryPercent))
        let stripCellCount = max(1, count - stripStartIndex)
        let stripIndex = index - stripStartIndex
        let progress = batteryMeterProgress(percent: percent, stripCellCount: stripCellCount)
        let fullCellCount = Int(floor(progress))
        let partialCellScale = progress - Double(fullCellCount)

        let color: RGBPatch
        if percent < 15 {
            color = RGBPatch(r: 255, g: 0, b: 0)
        } else if percent < 30 {
            color = RGBPatch(r: 255, g: 255, b: 0)
        } else {
            color = RGBPatch(r: 255, g: 255, b: 255)
        }

        if percent < 15, !batteryMeterLowFlashIsOn(time: time) {
            return RGBPatch(r: 0, g: 0, b: 0)
        }

        if stripIndex < fullCellCount {
            return scaledColor(color, scale: intensity)
        }
        if stripIndex == fullCellCount, partialCellScale > 0, fullCellCount < stripCellCount {
            return scaledColor(color, scale: intensity * partialCellScale)
        }
        return RGBPatch(r: 0, g: 0, b: 0)
    }

    private static func batteryMeterProgress(percent: Int, stripCellCount: Int) -> Double {
        let chargeFraction = Double(percent) / 100.0
        return batteryMeterFillFraction(chargeFraction: chargeFraction) * Double(stripCellCount)
    }

    private static func batteryMeterFillFraction(chargeFraction: Double) -> Double {
        let clampedCharge = max(0.0, min(1.0, chargeFraction))
        var previous = batteryMeterProgressAnchors[0]
        for anchor in batteryMeterProgressAnchors.dropFirst() {
            guard clampedCharge > anchor.chargeFraction else {
                let span = anchor.chargeFraction - previous.chargeFraction
                guard span > 0 else { return anchor.fillFraction }
                let phase = (clampedCharge - previous.chargeFraction) / span
                return previous.fillFraction + ((anchor.fillFraction - previous.fillFraction) * phase)
            }
            previous = anchor
        }
        return batteryMeterProgressAnchors.last?.fillFraction ?? clampedCharge
    }

    private static func batteryMeterLowFlashIsOn(time: TimeInterval) -> Bool {
        let phase = positiveModulo(time, batteryMeterLowFlashPeriod) / batteryMeterLowFlashPeriod
        return phase < batteryMeterLowFlashDutyCycle
    }

    private static func flame(
        palette: [RGBPatch],
        index: Int,
        count: Int,
        time: TimeInterval,
        intensity: Double
    ) -> RGBPatch {
        let position = normalizedPosition(index: index, count: count)
        let seed = UInt64(index + 1)
        let slowRate = 1.9 + 1.8 * hashUnit(seed &* 0x9E37_79B9)
        let midRate = 4.0 + 3.3 * hashUnit(seed &* 0x85EB_CA6B)
        let fastRate = 8.0 + 7.5 * hashUnit(seed &* 0xC2B2_AE35)
        let slow = smoothRandom(time: time, rate: slowRate, seed: seed &* 0x27D4_EB2D)
        let mid = smoothRandom(time: time, rate: midRate, seed: seed &* 0x1656_67B1)
        let fast = smoothRandom(time: time, rate: fastRate, seed: seed &* 0xD3A2_646C)
        let pulse = 0.5 + 0.5 * sin(time * (5.0 + 3.0 * hashUnit(seed &* 0x94D0_49BB)) + hashUnit(seed) * .pi * 2.0)
        let flicker = 0.18 + 0.34 * slow + 0.24 * mid + 0.18 * fast + 0.06 * pulse
        let heat = max(0.0, min(1.0, flicker * (0.82 + 0.28 * position)))
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
        let phase = positiveFraction(time * 0.18)
        let hue = cyclicPosition(index: index, count: count) - phase
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

    private static func nightRider(
        palette: [RGBPatch],
        index: Int,
        count: Int,
        time: TimeInterval,
        intensity: Double
    ) -> RGBPatch {
        let color = paletteColor(palette, slot: 0)
        let stripStartIndex = count > 2 ? 2 : 0
        if index < stripStartIndex {
            let pulse = 0.18 + 0.46 * (0.5 + 0.5 * sin(time * 1.1 - .pi / 2.0))
            return scaledColor(color, scale: pulse * intensity)
        }

        let stripCount = max(1, count - stripStartIndex)
        let stripIndex = index - stripStartIndex
        let maxPosition = Double(max(0, stripCount - 1))
        let head = pingPong(time * 4.0, max: maxPosition)
        let distance = abs(Double(stripIndex) - head)
        let core = max(0.0, 1.0 - distance / 0.85)
        let halo = max(0.0, 1.0 - distance / 3.0)
        let value = max(core, pow(halo, 2.4) * 0.28)
        return scaledColor(color, scale: value * intensity)
    }

    private static func jellybeans(
        palette: [RGBPatch],
        index: Int,
        count: Int,
        time: TimeInterval,
        intensity: Double
    ) -> RGBPatch {
        let tickRate = 7.0
        let currentTick = max(0, Int(floor(time * tickRate)))
        let lastChangeTick = latestJellybeanChangeTick(for: index, count: count, atOrBefore: currentTick)
        let previousChangeTick = lastChangeTick.flatMap {
            latestJellybeanChangeTick(for: index, count: count, atOrBefore: $0 - 1)
        }
        let previousSlot = previousChangeTick.map {
            jellybeanPaletteSlot(index: index, tick: $0, paletteCount: palette.count, previousSlot: nil)
        } ?? initialJellybeanPaletteSlot(index: index, paletteCount: palette.count)
        let slot = lastChangeTick.map {
            jellybeanPaletteSlot(index: index, tick: $0, paletteCount: palette.count, previousSlot: previousSlot)
        } ?? previousSlot
        return scaledColor(paletteColor(palette, slot: slot), scale: 0.95 * intensity)
    }

    private static func normalizedPosition(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        return Double(index) / Double(count - 1)
    }

    private static func cyclicPosition(index: Int, count: Int) -> Double {
        guard count > 0 else { return 0 }
        return Double(index) / Double(count)
    }

    private static func latestJellybeanChangeTick(for index: Int, count: Int, atOrBefore tick: Int) -> Int? {
        guard count > 0, tick >= 1 else { return nil }
        for candidate in stride(from: tick, through: 1, by: -1)
        where jellybeanLEDIndex(tick: candidate, count: count) == index {
            return candidate
        }
        return nil
    }

    private static func jellybeanLEDIndex(tick: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(hash(UInt64(max(0, tick)) &+ 0xA24B_AED4_963E_E407) % UInt64(count))
    }

    private static func initialJellybeanPaletteSlot(index: Int, paletteCount: Int) -> Int {
        guard paletteCount > 0 else { return 0 }
        return Int(hash(UInt64(index + 1) &* 0x9E37_79B9_7F4A_7C15) % UInt64(paletteCount))
    }

    private static func jellybeanPaletteSlot(
        index: Int,
        tick: Int,
        paletteCount: Int,
        previousSlot: Int?
    ) -> Int {
        guard paletteCount > 0 else { return 0 }
        var slot = Int(hash(UInt64(max(0, tick)) &* 0xBF58_476D_1CE4_E5B9 &+ UInt64(index + 1)) % UInt64(paletteCount))
        if paletteCount > 1, let previousSlot, slot == previousSlot {
            slot = (slot + 1) % paletteCount
        }
        return slot
    }

    private static func circularDistance(_ a: Double, _ b: Double, _ count: Double) -> Double {
        let raw = abs((a - b).truncatingRemainder(dividingBy: count))
        return min(raw, count - raw)
    }

    private static func pingPong(_ value: Double, max maxValue: Double) -> Double {
        guard maxValue > 0 else { return 0 }
        let period = maxValue * 2.0
        let position = positiveModulo(value, period)
        return position <= maxValue ? position : period - position
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

    private static func paletteColor(_ palette: [RGBPatch], slot: Int) -> RGBPatch {
        guard !palette.isEmpty else { return RGBPatch(r: 0, g: 0, b: 0) }
        return palette[max(0, slot) % palette.count]
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
        let clampedMix = max(0.0, min(1.0, mix))
        let start = Double(a)
        let delta = Double(b - a)
        let interpolated = start + delta * clampedMix
        return Int(round(interpolated))
    }

    private static func positiveFraction(_ value: Double) -> Double {
        let fraction = value - floor(value)
        let positive = fraction < 0 ? fraction + 1.0 : fraction
        if positive < 1e-12 || 1.0 - positive < 1e-12 {
            return 0
        }
        return positive
    }

    private static func positiveModulo(_ value: Double, _ modulus: Double) -> Double {
        guard modulus > 0 else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: modulus)
        return remainder < 0 ? remainder + modulus : remainder
    }

    private static func smoothRandom(time: TimeInterval, rate: Double, seed: UInt64) -> Double {
        let sample = max(0, time) * rate
        let lower = floor(sample)
        let mix = smoothstep(sample - lower)
        let a = hashUnit(seed &+ UInt64(lower))
        let b = hashUnit(seed &+ UInt64(lower + 1))
        return a + (b - a) * mix
    }

    private static func smoothstep(_ value: Double) -> Double {
        let x = max(0.0, min(1.0, value))
        return x * x * (3.0 - 2.0 * x)
    }

    private static func hashUnit(_ seed: UInt64) -> Double {
        Double(hash(seed) & 0x00FF_FFFF) / Double(0x00FF_FFFF)
    }

    private static func hash(_ seed: UInt64) -> UInt64 {
        var value = seed &+ 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
