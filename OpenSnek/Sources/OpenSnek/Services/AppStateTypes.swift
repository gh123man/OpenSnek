import Foundation
import OpenSnekCore
import SwiftUI

/// Stores device status indicator data.
struct DeviceStatusIndicator {
    let label: String
    let color: Color
}

/// Defines device connection state values.
enum DeviceConnectionState: Equatable {
    case disconnected
    case reconnecting
    case connected
    case unsupported
    case error

    var indicator: DeviceStatusIndicator {
        switch self {
        case .disconnected:
            DeviceStatusIndicator(label: "Disconnected", color: Color(hex: 0xFF453A))
        case .reconnecting:
            DeviceStatusIndicator(label: "Reconnecting", color: Color(hex: 0xFFD60A))
        case .connected:
            DeviceStatusIndicator(label: "Connected", color: Color(hex: 0x30D158))
        case .unsupported:
            DeviceStatusIndicator(label: "Unsupported", color: Color(hex: 0xFFD60A))
        case .error:
            DeviceStatusIndicator(label: "Error", color: Color(hex: 0xFF453A))
        }
    }

    var allowsInteraction: Bool {
        self == .connected
    }

    var diagnosticsLabel: String {
        switch self {
        case .disconnected:
            "Disconnected"
        case .reconnecting:
            "Reconnecting to live telemetry"
        case .connected:
            "Live"
        case .unsupported:
            "Unsupported"
        case .error:
            "Error"
        }
    }
}

/// Defines DPI update transport status values.
enum DpiUpdateTransportStatus: String, Codable, Equatable, Sendable {
    case unknown
    case listening
    case streamActive
    case pollingFallback
    case realTimeHID
    case unsupported

    var diagnosticsLabel: String {
        switch self {
        case .unknown:
            "Checking"
        case .listening:
            "Listening for first HID event"
        case .streamActive:
            "HID stream active"
        case .pollingFallback:
            "Polling fallback active"
        case .realTimeHID:
            "Real-time HID active"
        case .unsupported:
            "Unsupported"
        }
    }
}

/// Stores remote client presence state.
struct RemoteClientPresenceState {
    let expiresAt: Date
    let selectedDeviceID: String?
}

/// Defines button profile source values.
enum ButtonProfileSource: Hashable, Codable, Identifiable {
    case openSnekProfile(UUID)
    case mouseSlot(Int)

    var id: String {
        switch self {
        case .openSnekProfile(let id):
            return "openSnek:\(id.uuidString)"
        case .mouseSlot(let slot):
            return "mouseSlot:\(slot)"
        }
    }
}

/// Stores USB button profile summary data.
struct USBButtonProfileSummary: Identifiable, Hashable {
    let profile: Int
    let isHardwareActive: Bool
    let isLiveActive: Bool
    let isCustomized: Bool?

    var id: Int { profile }
}

/// Defines polling profile values.
enum PollingProfile: Equatable {
    case foreground
    case serviceIdle
    case serviceInteractive

    var refreshStateInterval: TimeInterval {
        switch self {
        case .foreground, .serviceInteractive:
            2.0
        case .serviceIdle:
            8.0
        }
    }

    var devicePresenceInterval: TimeInterval {
        switch self {
        case .foreground, .serviceInteractive:
            1.2
        case .serviceIdle:
            4.0
        }
    }

    var fastDpiInterval: TimeInterval? {
        switch self {
        case .foreground:
            0.20
        case .serviceInteractive:
            0.25
        case .serviceIdle:
            nil
        }
    }
}

/// Defines runtime wake schedule values.
enum RuntimeWakeSchedule {
    /// Carries app state types context.
    struct Context {
        let now: Date
        let profile: PollingProfile
        let refreshStateIntervalOverride: TimeInterval?
        let devicePresenceIntervalOverride: TimeInterval?
        let fastDpiInterval: TimeInterval?
        let usesRemoteServiceTransport: Bool
        let lastDevicePresencePollAt: Date
        let lastRefreshStatePollAt: Date
        let lastFastDpiPollAt: Date
        let lastRemoteClientPresencePingAt: Date
        let transientStatusUntil: Date?
        let nextRemoteClientPresenceExpiry: Date?
    }

    static let minimumSleepInterval: TimeInterval = 0.10
    static let suspendedForSleepInterval: TimeInterval = 60.0

    static func nextSleepInterval(_ context: Context) -> TimeInterval {
        var intervals: [TimeInterval] = []

        if context.usesRemoteServiceTransport {
            intervals.append(max(0, 1.0 - context.now.timeIntervalSince(context.lastRemoteClientPresencePingAt)))
        } else {
            let devicePresenceInterval = context.devicePresenceIntervalOverride ?? context.profile.devicePresenceInterval
            let refreshStateInterval = context.refreshStateIntervalOverride ?? context.profile.refreshStateInterval
            intervals.append(max(0, devicePresenceInterval - context.now.timeIntervalSince(context.lastDevicePresencePollAt)))
            intervals.append(max(0, refreshStateInterval - context.now.timeIntervalSince(context.lastRefreshStatePollAt)))
            if let fastInterval = context.fastDpiInterval {
                intervals.append(max(0, fastInterval - context.now.timeIntervalSince(context.lastFastDpiPollAt)))
            }
        }

        if let transientStatusUntil = context.transientStatusUntil {
            intervals.append(max(0, transientStatusUntil.timeIntervalSince(context.now)))
        }

        if let nextRemoteClientPresenceExpiry = context.nextRemoteClientPresenceExpiry {
            intervals.append(max(0, nextRemoteClientPresenceExpiry.timeIntervalSince(context.now)))
        }

        let nextDue = intervals.filter { $0.isFinite && $0 >= 0 }.min() ?? 1.0
        return max(minimumSleepInterval, nextDue)
    }
}

/// Adds scoped helpers for `DevicePatch`.
extension DevicePatch {
    var isEmpty: Bool {
        if pollRate != nil { return false }
        if sleepTimeout != nil { return false }
        if deviceMode != nil { return false }
        if lowBatteryThresholdRaw != nil { return false }
        if scrollMode != nil { return false }
        if scrollAcceleration != nil { return false }
        if scrollSmartReel != nil { return false }
        if affectsDpiStages { return false }
        if ledBrightness != nil { return false }
        if ledRGB != nil { return false }
        if lightingEffect != nil { return false }
        if usbLightingZoneLEDIDs != nil { return false }
        if buttonBinding != nil { return false }
        if usbButtonProfileAction != nil { return false }
        return true
    }

    var describe: String {
        var parts: [String] = []
        if let deviceMode { parts.append("mode=(\(deviceMode.mode),\(deviceMode.param))") }
        if let lowBatteryThresholdRaw { parts.append("lowBatt=0x\(String(lowBatteryThresholdRaw, radix: 16))") }
        if let scrollMode { parts.append("scrollMode=\(scrollMode)") }
        if let scrollAcceleration { parts.append("scrollAccel=\(scrollAcceleration)") }
        if let scrollSmartReel { parts.append("smartReel=\(scrollSmartReel)") }
        if let pollRate { parts.append("poll=\(pollRate)") }
        if let sleepTimeout { parts.append("sleep=\(sleepTimeout)") }
        if let dpiStages { parts.append("stages=\(dpiStages)") }
        if let dpiStagePairs { parts.append("stagePairs=\(dpiStagePairs)") }
        if let activeStage { parts.append("active=\(activeStage)") }
        if let ledBrightness { parts.append("led=\(ledBrightness)") }
        if let ledRGB { parts.append("rgb=(\(ledRGB.r),\(ledRGB.g),\(ledRGB.b))") }
        if let lightingEffect {
            var detail = "fx=\(lightingEffect.kind.rawValue)"
            if lightingEffect.kind.usesWaveDirection {
                detail += ",dir=\(lightingEffect.waveDirection.rawValue)"
            }
            if lightingEffect.kind.usesReactiveSpeed {
                detail += ",speed=\(lightingEffect.reactiveSpeed)"
            }
            if lightingEffect.kind.usesPrimaryColor {
                detail += ",p=(\(lightingEffect.primary.r),\(lightingEffect.primary.g),\(lightingEffect.primary.b))"
            }
            if lightingEffect.kind.usesSecondaryColor {
                detail += ",s=(\(lightingEffect.secondary.r),\(lightingEffect.secondary.g),\(lightingEffect.secondary.b))"
            }
            parts.append(detail)
        }
        if let buttonBinding {
            var detail = "button(slot=\(buttonBinding.slot),kind=\(buttonBinding.kind.rawValue)"
            if buttonBinding.turboEnabled {
                detail += ",turbo=on,rate=\(buttonBinding.turboRate ?? ButtonBindingSupport.defaultTurboRate)"
            }
            if buttonBinding.kind == .dpiClutch {
                detail += ",dpi=\(buttonBinding.clutchDPI ?? ButtonBindingSupport.defaultBasiliskDPIClutchDPI)"
            }
            detail += ")"
            parts.append(detail)
        }
        if let usbButtonProfileAction {
            var detail = "usbProfileAction(kind=\(usbButtonProfileAction.kind.rawValue),target=\(usbButtonProfileAction.targetProfile)"
            if let sourceProfile = usbButtonProfileAction.sourceProfile {
                detail += ",source=\(sourceProfile)"
            }
            detail += ")"
            parts.append(detail)
        }
        return parts.isEmpty ? "empty" : parts.joined(separator: " ")
    }
}
