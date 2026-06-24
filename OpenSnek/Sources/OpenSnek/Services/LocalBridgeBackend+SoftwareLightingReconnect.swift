import Foundation
import OpenSnekCore
import OpenSnekHardware

/// Adds software lighting reconnect recovery to `LocalBridgeBackend`.
extension LocalBridgeBackend {
    func reassertSoftwareLightingAfterProfileChange(device: MouseDevice, state: MouseState) async {
        do {
            let previousStatus = await softwareLightingEngine.status(deviceID: device.id)
            guard let status = try await softwareLightingEngine.reassertIfRunning(
                device: device,
                batteryPercent: state.battery_percent
            ) else {
                AppLog.debug(
                    "LightingTrace",
                    "software lighting profile-change reassert skipped device=\(device.id) " +
                        "status=\(SoftwareLightingDiagnostics.statusSummary(previousStatus))"
                )
                return
            }
            handleSoftwareLightingStatus(status)
            let presetText = status.request?.presetID.rawValue ?? "<none>"
            let profileText = state.active_onboard_profile.map(String.init) ?? "<nil>"
            AppLog.debug(
                "Backend",
                "software lighting reasserted after profile change device=\(device.id) " +
                    "profile=\(profileText) preset=\(presetText)"
            )
        } catch {
            AppLog.warning(
                "Backend",
                "software lighting reassert failed after profile change device=\(device.id): \(error.localizedDescription)"
            )
        }
    }

    func reassertRunningSoftwareLightingAfterPresenceReconnect(
        event: HIDDevicePresenceEvent?,
        devices: [MouseDevice]
    ) async {
        let candidates: [MouseDevice]
        if let eventDeviceID = event?.deviceID,
           let eventDevice = devices.first(where: { $0.id == eventDeviceID }) {
            candidates = [eventDevice]
        } else {
            candidates = devices
        }
        for device in candidates where device.supportsSoftwareLightingEffects {
            await reassertRunningSoftwareLightingAfterReconnect(
                device: device,
                reason: "devicePresence"
            )
        }
    }

    func reassertRunningSoftwareLightingAfterReconnect(device: MouseDevice, reason: String) async {
        guard device.supportsSoftwareLightingEffects else { return }
        let deviceKey = DevicePersistenceKeys.key(for: device)
        let now = Date()
        if let lastReassertAt = softwareLightingReconnectReassertAtByDeviceKey[deviceKey],
           now.timeIntervalSince(lastReassertAt) < Self.softwareLightingReconnectReassertInterval {
            return
        }
        guard softwareLightingReconnectReassertInFlightKeys.insert(deviceKey).inserted else { return }
        defer {
            softwareLightingReconnectReassertInFlightKeys.remove(deviceKey)
        }

        do {
            let previousStatus = await softwareLightingEngine.status(deviceID: device.id)
            guard let status = try await softwareLightingEngine.reassertIfRunning(
                device: device,
                batteryPercent: cachedStateByDeviceID[device.id]?.battery_percent
                    ?? reconnectSeedStateByDeviceID[device.id]?.battery_percent
            ) else {
                AppLog.debug(
                    "LightingTrace",
                    "software lighting reconnect reassert skipped reason=\(reason) " +
                        "device=\(device.id) status=\(SoftwareLightingDiagnostics.statusSummary(previousStatus))"
                )
                return
            }
            softwareLightingReconnectReassertAtByDeviceKey[deviceKey] = Date()
            handleSoftwareLightingStatus(status)
            AppLog.event(
                "Backend",
                "software lighting reasserted after reconnect reason=\(reason) " +
                    "device=\(device.id) preset=\(status.request?.presetID.rawValue ?? "<none>")"
            )
        } catch {
            AppLog.warning(
                "Backend",
                "software lighting reconnect reassert failed reason=\(reason) " +
                    "device=\(device.id): \(error.localizedDescription)"
            )
        }
    }
}
