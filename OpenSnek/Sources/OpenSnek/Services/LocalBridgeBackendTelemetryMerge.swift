import Foundation
import Network
import OpenSnekCore
import OpenSnekHardware

extension LocalBridgeBackend {
    nonisolated static func mergedApplyState(_ state: MouseState, previous: MouseState?) -> MouseState {
        state.merged(with: previous)
    }

    nonisolated static func shouldReuseCachedStateForRead(
        device: MouseDevice,
        cachedAt: Date,
        now: Date,
        shouldUseFastDPIPolling: Bool
    ) -> Bool {
        guard now.timeIntervalSince(cachedAt) < 1.0 else { return false }
        if device.transport == .bluetooth, !shouldUseFastDPIPolling {
            return false
        }
        return true
    }

    nonisolated static func shouldReuseCachedFastSnapshot(
        device: MouseDevice,
        cachedAt: Date,
        now: Date,
        shouldUseFastDPIPolling: Bool
    ) -> Bool {
        if device.transport == .bluetooth, !shouldUseFastDPIPolling {
            return true
        }

        return now.timeIntervalSince(cachedAt) < 0.2
    }

    nonisolated static func completedReadWasSuperseded(startedAt: Date, latestCachedAt: Date?) -> Bool {
        guard let latestCachedAt else { return false }
        return latestCachedAt > startedAt
    }

    nonisolated static func isDeviceNotAvailableError(_ error: any Error) -> Bool {
        let lowered = error.localizedDescription.lowercased()
        return lowered.contains("device not available") || lowered.contains("no device")
    }

    nonisolated static func passiveDpiEventHasAmbiguousStageMatch(
        previous: MouseState?,
        event: PassiveDPIEvent
    ) -> Bool {
        guard let previous,
              let values = previous.dpi_stages.values,
              values.count > 1 else {
            return false
        }
        let matchingIndices = values.enumerated().compactMap { index, value in
            value == event.dpiX ? index : nil
        }
        return matchingIndices.count != 1
    }

    nonisolated static func seededStateForPassiveDpiEvent(
        device: MouseDevice,
        event: PassiveDPIEvent,
        fastSnapshot: DpiFastSnapshot? = nil
    ) -> MouseState {
        let knownStageValues = fastSnapshot?.values.isEmpty == false
            ? fastSnapshot?.values
            : [event.dpiX]
        let matchingIndices = (knownStageValues ?? []).enumerated().compactMap { index, value in
            value == event.dpiX ? index : nil
        }
        let resolvedActiveStage: Int?
        if matchingIndices.count == 1 {
            resolvedActiveStage = matchingIndices[0]
        } else if let fastSnapshot {
            resolvedActiveStage = max(0, min(fastSnapshot.values.count - 1, fastSnapshot.active))
        } else {
            resolvedActiveStage = 0
        }

        return MouseState(
            device: DeviceSummary(
                id: device.id,
                product_name: device.product_name,
                serial: device.serial,
                transport: device.transport,
                firmware: device.firmware
            ),
            connection: device.connectionLabel,
            battery_percent: nil,
            charging: nil,
            dpi: DpiPair(x: event.dpiX, y: event.dpiY),
            dpi_stages: DpiStages(
                active_stage: resolvedActiveStage,
                values: knownStageValues,
                pairs: knownStageValues?.count == 1 ? [DpiPair(x: event.dpiX, y: event.dpiY)] : nil
            ),
            poll_rate: nil,
            sleep_timeout: nil,
            device_mode: nil,
            low_battery_threshold_raw: nil,
            scroll_mode: nil,
            scroll_acceleration: nil,
            scroll_smart_reel: nil,
            active_onboard_profile: nil,
            onboard_profile_count: device.onboard_profile_count,
            led_value: nil,
            capabilities: Capabilities(
                dpi_stages: true,
                poll_rate: device.transport == .usb,
                power_management: true,
                button_remap: device.button_layout != nil,
                lighting: device.showsLightingControls
            )
        )
    }
}
