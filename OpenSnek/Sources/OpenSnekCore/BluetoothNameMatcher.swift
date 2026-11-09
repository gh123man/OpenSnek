import Foundation

/// Defines Bluetooth name matcher values.
public enum BluetoothNameMatcher {
    public static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowered = trimmed.lowercased()
        let withoutRazerPrefix: String
        if lowered.hasPrefix("razer ") { withoutRazerPrefix = String(trimmed.dropFirst(6)) } else { withoutRazerPrefix = trimmed }

        let pieces = withoutRazerPrefix.lowercased().split { !$0.isLetter && !$0.isNumber }.map { token -> String in
            switch token {
            case "bsk": return "basilisk"
            case "hs": return "hyperspeed"
            // The Basilisk V3 Pro 35K Phantom Green Edition advertises the run-together "BSKV3P 35K".
            case "bskv3p": return "basilisk v3 pro"
            default: return String(token)
            }
        }
        let normalized = pieces.joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    /// Ranks how specifically two names match: `nil` when they do not loosely match, `Int.max` for an
    /// exact match, otherwise the length of the shorter name. "BSKV3P 35K" therefore ranks
    /// "Basilisk V3 Pro 35K ..." above "Basilisk V3 Pro" even though both loosely match.
    public static func matchRank(_ lhs: String?, _ rhs: String?) -> Int? {
        guard let lhs = normalized(lhs), let rhs = normalized(rhs) else { return nil }
        if lhs == rhs { return Int.max }
        guard lhs.contains(rhs) || rhs.contains(lhs) else { return nil }
        return min(lhs.count, rhs.count)
    }

    public static func looselyMatches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalized(lhs), let rhs = normalized(rhs) else { return false }
        return lhs == rhs || lhs.contains(rhs) || rhs.contains(lhs)
    }
}
