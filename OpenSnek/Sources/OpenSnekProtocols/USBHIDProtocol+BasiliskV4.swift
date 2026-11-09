import Foundation
import OpenSnekCore

/// Preserves the V4 receiver's opaque DPI row bytes and separately addressed lighting state.
public extension USBHIDProtocol {
    static func basiliskV4DPIBaseline(payload: [UInt8], previous: [UInt8]?) -> [UInt8]? {
        guard payload.count == 38, (1...5).contains(Int(payload[2])) else { return nil }
        let count = Int(payload[2])
        var baseline: [UInt8]
        if count == 5 {
            baseline = payload
        } else {
            guard let previous, previous.count == 38 else { return nil }
            baseline = previous
            baseline.replaceSubrange(0..<(3 + count * 7), with: payload.prefix(3 + count * 7))
        }
        let ids = (0..<5).map { baseline[3 + $0 * 7] }
        guard Set(ids).count == 5, ids.prefix(count).contains(baseline[1]) else { return nil }
        let range = DeviceProfiles.dpiRange(for: .basiliskV4Hyperspeed)
        for index in 0..<5 {
            let offset = 3 + index * 7
            let x = Int(baseline[offset + 1]) << 8 | Int(baseline[offset + 2])
            let y = Int(baseline[offset + 3]) << 8 | Int(baseline[offset + 4])
            guard range.contains(x), range.contains(y) else { return nil }
        }
        return baseline
    }

    static func basiliskV4DPIWriteArgs(baseline: [UInt8], active: Int, pairs: [DpiPair]) -> [UInt8]? {
        guard (1...5).contains(pairs.count), pairs.indices.contains(active), var args = basiliskV4DPIBaseline(payload: baseline, previous: baseline) else { return nil }
        args[0] = 1
        args[1] = args[3 + active * 7]
        args[2] = UInt8(pairs.count)
        for (index, pair) in pairs.enumerated() {
            let offset = 3 + index * 7
            let x = DeviceProfiles.clampDPI(pair.x, profileID: .basiliskV4Hyperspeed)
            let y = DeviceProfiles.clampDPI(pair.y, profileID: .basiliskV4Hyperspeed)
            args[offset + 1] = UInt8(x >> 8)
            args[offset + 2] = UInt8(x & 0xFF)
            args[offset + 3] = UInt8(y >> 8)
            args[offset + 4] = UInt8(y & 0xFF)
        }
        return args
    }

    /// GET always reports live target 0 and physical LED 0A, even for writes to target 1 / LED 00.
    static func basiliskV4LightingWriteMatches(response: [UInt8], args: [UInt8]) -> Bool {
        guard let state = profileLightingEffectState(from: response, expectedLEDID: 0x0A), args.count >= 6, state.payload.count >= args.count else { return false }
        return Array(state.payload[2..<args.count]) == Array(args.dropFirst(2))
    }
}
