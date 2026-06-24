import Foundation
import OpenSnekCore

/// Formats software lighting diagnostics for targeted wake/reconnect logs.
enum SoftwareLightingDiagnostics {
    static func requestSummary(_ request: SoftwareLightingEffectRequest?) -> String {
        guard let request else { return "nil" }
        return String(
            format: "%@/fps=%d/speed=%.2f/intensity=%.2f/colors=%d",
            request.presetID.rawValue,
            request.framesPerSecond,
            request.speed,
            request.intensity,
            request.palette.count
        )
    }

    static func statusSummary(_ status: SoftwareLightingEngineStatus?) -> String {
        guard let status else { return "nil" }
        return String(
            format: "%@ request=%@ updatedAt=%.3f",
            status.state.rawValue,
            requestSummary(status.request),
            status.updatedAt.timeIntervalSince1970
        )
    }

    static func seconds(_ interval: TimeInterval) -> String {
        String(format: "%.2fs", interval)
    }
}
