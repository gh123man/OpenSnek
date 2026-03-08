import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var devices: [MouseDevice] = []
    var selectedDeviceID: String?
    var state: MouseState?

    var isLoading = false
    var isApplying = false
    var isRefreshingState = false
    var errorMessage: String?
    var lastUpdated: Date?

    var editableStageValues: [Int] = [800, 1600, 3200, 6400, 12000]
    var editableStageCount = 3
    var singleStageMode = false
    var editableActiveStage = 1
    var editablePollRate = 1000
    var editableLedBrightness = 64
    var editableColor = RGBColor(r: 0, g: 255, b: 0)
    var editableButtonSlot = 2
    var editableButtonKind: ButtonBindingKind = .rightClick
    var editableHidKey = 4

    private let client = BridgeClient()
    private var isHydrating = false
    private var dpiApplyTask: Task<Void, Never>?
    private var pollApplyTask: Task<Void, Never>?
    private var ledApplyTask: Task<Void, Never>?
    private var colorApplyTask: Task<Void, Never>?
    private var buttonApplyTask: Task<Void, Never>?
    private var activeStageApplyTask: Task<Void, Never>?
    private var hasPendingLocalEdits = false
    private var pendingPatch: DevicePatch?
    private var applyDrainTask: Task<Void, Never>?
    private var stateCacheByDeviceID: [String: MouseState] = [:]
    private var isRefreshingDpiFast = false
    private var stateRevision: UInt64 = 0
    var isEditingDpiControl = false
    private var lastLocalEditAt: Date?

    var selectedDevice: MouseDevice? {
        guard let selectedDeviceID else { return nil }
        return devices.first(where: { $0.id == selectedDeviceID })
    }

    func refreshDevices() async {
        let start = Date()
        AppLog.event("AppState", "refreshDevices start")
        isLoading = true
        defer { isLoading = false }

        do {
            let listed = try await client.listDevices()
            devices = listed
            AppLog.event("AppState", "refreshDevices found=\(listed.count)")
            if selectedDeviceID == nil {
                selectedDeviceID = listed.first?.id
            }
            if let selected = selectedDevice, !listed.contains(selected) {
                selectedDeviceID = listed.first?.id
            }
            if let selectedDeviceID, let cached = stateCacheByDeviceID[selectedDeviceID] {
                state = cached
            }
            errorMessage = nil
        } catch {
            AppLog.error("AppState", "refreshDevices failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        await refreshState()
        AppLog.event("AppState", "refreshDevices end elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s")
    }

    func refreshState() async {
        guard let selectedDevice else {
            state = nil
            return
        }
        guard !isRefreshingState, !isApplying, !hasPendingLocalEdits else {
            AppLog.debug(
                "AppState",
                "refreshState skipped refreshing=\(isRefreshingState) applying=\(isApplying) pendingEdits=\(hasPendingLocalEdits)"
            )
            return
        }

        if let cached = stateCacheByDeviceID[selectedDevice.id] {
            state = cached
        }

        isRefreshingState = true
        defer { isRefreshingState = false }
        let refreshRevision = stateRevision

        let start = Date()
        do {
            let fetched = try await client.readState(device: selectedDevice)
            guard refreshRevision == stateRevision else {
                AppLog.debug("AppState", "refreshState stale-drop rev=\(refreshRevision) current=\(stateRevision)")
                return
            }
            let merged = fetched.merged(with: stateCacheByDeviceID[selectedDevice.id])
            stateCacheByDeviceID[selectedDevice.id] = merged
            if state != merged {
                state = merged
            }
            lastUpdated = Date()
            if shouldHydrateEditable {
                hydrateEditable(from: merged)
            }
            errorMessage = nil
            AppLog.debug(
                "AppState",
                "refreshState ok device=\(selectedDevice.id) active=\(merged.dpi_stages.active_stage.map(String.init) ?? "nil") " +
                "values=\(merged.dpi_stages.values?.map(String.init).joined(separator: ",") ?? "nil") " +
                "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
            )
        } catch {
            if stateCacheByDeviceID[selectedDevice.id] == nil {
                AppLog.error("AppState", "refreshState failed no-cache: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            } else {
                // Keep last known-good UI stable on transient polling failures.
                AppLog.debug("AppState", "refreshState transient-failure masked: \(error.localizedDescription)")
                errorMessage = nil
            }
        }
    }

    func updateStage(_ index: Int, value: Int) {
        guard index >= 0 && index < editableStageValues.count else { return }
        editableStageValues[index] = max(100, min(30000, value))
    }

    func stageValue(_ index: Int) -> Int {
        guard index >= 0 && index < editableStageValues.count else { return 800 }
        return editableStageValues[index]
    }

    func applyDpiStages() async {
        let count = singleStageMode ? 1 : max(1, min(5, editableStageCount))
        let values = Array(editableStageValues.prefix(count)).map { max(100, min(30000, $0)) }
        let active = singleStageMode ? 0 : max(0, min(count - 1, editableActiveStage - 1))

        enqueueApply(DevicePatch(dpiStages: values, activeStage: active))
    }

    func scheduleAutoApplyDpi() {
        guard !isHydrating else { return }
        hasPendingLocalEdits = true
        lastLocalEditAt = Date()
        dpiApplyTask?.cancel()
        dpiApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 220_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyDpiStages()
        }
    }

    func applyActiveStageOnly() async {
        let count = singleStageMode ? 1 : max(1, min(5, editableStageCount))
        let active = singleStageMode ? 0 : max(0, min(count - 1, editableActiveStage - 1))
        enqueueApply(DevicePatch(activeStage: active))
    }

    func scheduleAutoApplyActiveStage() {
        guard !isHydrating else { return }
        hasPendingLocalEdits = true
        lastLocalEditAt = Date()
        activeStageApplyTask?.cancel()
        activeStageApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyActiveStageOnly()
        }
    }

    func applyPollRate() async {
        enqueueApply(DevicePatch(pollRate: editablePollRate))
    }

    func scheduleAutoApplyPollRate() {
        guard !isHydrating else { return }
        hasPendingLocalEdits = true
        lastLocalEditAt = Date()
        pollApplyTask?.cancel()
        pollApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyPollRate()
        }
    }

    func applyLedBrightness() async {
        enqueueApply(DevicePatch(ledBrightness: editableLedBrightness))
    }

    func scheduleAutoApplyLedBrightness() {
        guard !isHydrating else { return }
        hasPendingLocalEdits = true
        lastLocalEditAt = Date()
        ledApplyTask?.cancel()
        ledApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyLedBrightness()
        }
    }

    func applyLedColor() async {
        enqueueApply(DevicePatch(ledRGB: RGBPatch(r: editableColor.r, g: editableColor.g, b: editableColor.b)))
    }

    func scheduleAutoApplyLedColor() {
        guard !isHydrating else { return }
        hasPendingLocalEdits = true
        lastLocalEditAt = Date()
        colorApplyTask?.cancel()
        colorApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyLedColor()
        }
    }

    func applyButtonBinding() async {
        let binding = ButtonBindingPatch(
            slot: editableButtonSlot,
            kind: editableButtonKind,
            hidKey: editableButtonKind == .keyboardSimple ? editableHidKey : nil
        )
        enqueueApply(DevicePatch(buttonBinding: binding))
    }

    func scheduleAutoApplyButton() {
        guard !isHydrating else { return }
        hasPendingLocalEdits = true
        lastLocalEditAt = Date()
        buttonApplyTask?.cancel()
        buttonApplyTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 260_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.applyButtonBinding()
        }
    }

    func refreshDpiFast() async {
        guard let selectedDevice, selectedDevice.transport == "bluetooth" else { return }
        guard !isRefreshingDpiFast, !isRefreshingState, !isApplying else { return }
        guard !hasPendingLocalEdits else { return }

        isRefreshingDpiFast = true
        defer { isRefreshingDpiFast = false }
        let fastRevision = stateRevision

        do {
            guard let fast = try await client.readDpiStagesFast(device: selectedDevice) else { return }
            guard fastRevision == stateRevision else {
                AppLog.debug("AppState", "refreshDpiFast stale-drop rev=\(fastRevision) current=\(stateRevision)")
                return
            }
            let previous = stateCacheByDeviceID[selectedDevice.id] ?? state
            guard let previous else { return }

            let active = max(0, min(fast.values.count - 1, fast.active))
            let currentDpiValue = fast.values[active]
            let updated = MouseState(
                device: previous.device,
                connection: previous.connection,
                battery_percent: previous.battery_percent,
                charging: previous.charging,
                dpi: DpiPair(x: currentDpiValue, y: currentDpiValue),
                dpi_stages: DpiStages(active_stage: active, values: fast.values),
                poll_rate: previous.poll_rate,
                device_mode: previous.device_mode,
                led_value: previous.led_value,
                capabilities: previous.capabilities
            )

            stateCacheByDeviceID[selectedDevice.id] = updated
            if state != updated {
                state = updated
            }
            if shouldHydrateEditable {
                hydrateEditable(from: updated)
            }
        } catch {
            // Ignore fast-poll transient failures to keep UI stable.
        }
    }

    private func enqueueApply(_ patch: DevicePatch) {
        if let pendingPatch {
            self.pendingPatch = pendingPatch.merged(with: patch)
        } else {
            pendingPatch = patch
        }
        hasPendingLocalEdits = true
        lastLocalEditAt = Date()
        stateRevision &+= 1

        if applyDrainTask == nil {
            applyDrainTask = Task { [weak self] in
                await self?.drainApplyQueue()
            }
        }
    }

    private func drainApplyQueue() async {
        while let patch = pendingPatch {
            pendingPatch = nil
            await applyNow(patch: patch)
            hasPendingLocalEdits = pendingPatch != nil
        }
        hasPendingLocalEdits = false
        applyDrainTask = nil
    }

    private func applyNow(patch: DevicePatch) async {
        guard let selectedDevice else {
            errorMessage = "No device selected"
            return
        }

        stateRevision &+= 1
        AppLog.event("AppState", "apply start device=\(selectedDevice.id) patch=\(patch.describe)")
        isApplying = true
        defer { isApplying = false }

        let start = Date()
        do {
            let next = try await client.apply(device: selectedDevice, patch: patch)
            let merged = next.merged(with: stateCacheByDeviceID[selectedDevice.id])
            stateCacheByDeviceID[selectedDevice.id] = merged
            if state != merged {
                state = merged
            }
            lastUpdated = Date()
            lastLocalEditAt = nil
            hydrateEditable(from: merged)
            errorMessage = nil
            AppLog.event(
                "AppState",
                "apply ok device=\(selectedDevice.id) active=\(merged.dpi_stages.active_stage.map(String.init) ?? "nil") " +
                "values=\(merged.dpi_stages.values?.map(String.init).joined(separator: ",") ?? "nil") " +
                "elapsed=\(String(format: "%.3f", Date().timeIntervalSince(start)))s"
            )
        } catch {
            AppLog.error("AppState", "apply failed device=\(selectedDevice.id): \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private var shouldHydrateEditable: Bool {
        guard !isApplying, !isEditingDpiControl, !hasPendingLocalEdits else { return false }
        guard let lastLocalEditAt else { return true }
        return Date().timeIntervalSince(lastLocalEditAt) > 0.8
    }

    private func hydrateEditable(from state: MouseState) {
        isHydrating = true
        defer { isHydrating = false }

        if let values = state.dpi_stages.values, !values.isEmpty {
            editableStageCount = max(1, min(5, values.count))
            singleStageMode = editableStageCount == 1
            for i in 0..<editableStageValues.count {
                if i < values.count {
                    editableStageValues[i] = max(100, min(30000, values[i]))
                }
            }
        }

        if let active = state.dpi_stages.active_stage {
            editableActiveStage = max(1, min(5, active + 1))
        }

        if let poll = state.poll_rate {
            editablePollRate = poll
        }

        if let led = state.led_value {
            editableLedBrightness = led
        }
    }
}

private extension DevicePatch {
    var describe: String {
        var parts: [String] = []
        if let pollRate { parts.append("poll=\(pollRate)") }
        if let dpiStages { parts.append("stages=\(dpiStages)") }
        if let activeStage { parts.append("active=\(activeStage)") }
        if let ledBrightness { parts.append("led=\(ledBrightness)") }
        if let ledRGB { parts.append("rgb=(\(ledRGB.r),\(ledRGB.g),\(ledRGB.b))") }
        if let buttonBinding { parts.append("button(slot=\(buttonBinding.slot),kind=\(buttonBinding.kind.rawValue))") }
        return parts.isEmpty ? "empty" : parts.joined(separator: " ")
    }
}

struct RGBColor {
    var r: Int
    var g: Int
    var b: Int
}
