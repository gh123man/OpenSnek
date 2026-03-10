import Foundation
import OpenSnekCore

enum AdaptiveRefreshLane: Hashable {
    case presence
    case selectedCore
    case selectedSlow
}

enum AdaptiveRefreshPolicy {
    static let maxBackoffStep = 2
    static let failureThreshold = 3
    static let fastDpiBurstDuration: TimeInterval = 2.0
    static let fastDpiBurstExtension: TimeInterval = 1.0

    static func baseInterval(for lane: AdaptiveRefreshLane, isSceneActive: Bool) -> TimeInterval {
        switch lane {
        case .presence:
            return isSceneActive ? 15.0 : 60.0
        case .selectedCore:
            return isSceneActive ? 3.0 : 10.0
        case .selectedSlow:
            return isSceneActive ? 20.0 : 60.0
        }
    }

    static func interval(for lane: AdaptiveRefreshLane, isSceneActive: Bool, backoffStep: Int) -> TimeInterval {
        let clampedStep = max(0, min(maxBackoffStep, backoffStep))
        let multiplier = pow(2.0, Double(clampedStep))
        return baseInterval(for: lane, isSceneActive: isSceneActive) * multiplier
    }

    static func fastDpiInterval(for transport: DeviceTransportKind) -> TimeInterval {
        switch transport {
        case .usb:
            return 0.55
        case .bluetooth:
            return 0.25
        }
    }
}
