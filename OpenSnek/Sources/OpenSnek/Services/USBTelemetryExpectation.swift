import Foundation
import OpenSnekCore

/// Describes which USB telemetry a device's profile actually exposes.
///
/// A missing read is only meaningful for a control the device claims to offer. Accessories and
/// keyboards intentionally omit mouse telemetry: the Mouse Dock has no DPI or poll rate, and some
/// accessories cannot read their lighting state at all. Reporting those gaps as incomplete
/// telemetry makes healthy devices look degraded, so every telemetry expectation is derived from
/// the resolved profile instead of assuming mouse-shaped hardware.
struct USBTelemetryExpectation {
    let dpiStages: Bool
    let pollRate: Bool
    let lighting: Bool

    /// Unprofiled devices keep the historical assumption that every control is available; only
    /// profiles that explicitly opt out relax the expectation.
    init(profile: DeviceProfile?) {
        dpiStages = profile?.supportsDPIControls ?? true
        pollRate = profile?.supportsPollRateControls ?? true
        lighting = profile?.supportsLightingStateReads ?? true
    }

    /// Names the supported telemetry that is genuinely absent from a state snapshot, in the same
    /// order the diagnostics user sees them.
    static func missingTelemetry(state: MouseState, profile: DeviceProfile?) -> [String] {
        let expectation = USBTelemetryExpectation(profile: profile)
        var missing: [String] = []
        if expectation.dpiStages, state.dpi_stages.values == nil { missing.append("DPI stages") }
        if expectation.pollRate, state.poll_rate == nil { missing.append("poll rate") }
        if expectation.lighting, state.led_value == nil { missing.append("lighting") }
        return missing
    }
}
