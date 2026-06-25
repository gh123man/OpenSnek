import Foundation
import OpenSnekCore

/// Describes software lighting engine failures.
enum SoftwareLightingEngineError: LocalizedError, Sendable {
    case unsupportedDevice
    case unsupportedPreset(SoftwareLightingPresetID)

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice: return "Software lighting is not supported for this device"
        case .unsupportedPreset(let preset): return "\(preset.label) is not supported for this device"
        }
    }
}

/// Describes recoverable software lighting frame-write failures.
enum SoftwareLightingFrameWriteFailure: LocalizedError, Sendable {
    case deviceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable(let message): return message
        }
    }

    static func recoverableDeviceUnavailable(from error: any Error) -> SoftwareLightingFrameWriteFailure? {
        if BridgeClient.isUSBTelemetryUnavailableError(error) { return .deviceUnavailable(error.localizedDescription) }
        let lowered = error.localizedDescription.lowercased()
        if lowered.contains("device not available") || lowered.contains("no device") { return .deviceUnavailable(error.localizedDescription) }
        return nil
    }
}

/// Defines the software lighting frame writing contract.
protocol SoftwareLightingFrameWriting: Sendable { func writeSoftwareLightingFrame(device: MouseDevice, frame: USBLightingFramePatch) async throws }

/// Stores bridge software lighting frame writer data.
struct BridgeSoftwareLightingFrameWriter: SoftwareLightingFrameWriting {
    let client: BridgeClient

    func writeSoftwareLightingFrame(device: MouseDevice, frame: USBLightingFramePatch) async throws {
        do { try await client.writeSoftwareLightingFrame(device: device, frame: frame) } catch {
            if let recoverable = SoftwareLightingFrameWriteFailure.recoverableDeviceUnavailable(from: error) { throw recoverable }
            throw error
        }
    }
}

/// Serializes software lighting engine state and operations.
actor SoftwareLightingEngine {
    /// Carries render loop context.
    private struct RenderLoopContext {
        let device: MouseDevice
        let deviceKey: String
        let generation: UInt64
        let layout: SoftwareLightingFrameLayout
        let request: SoftwareLightingEffectRequest
        let frameInterval: TimeInterval
    }

    private let frameWriter: any SoftwareLightingFrameWriting
    private let minimumFrameInterval: TimeInterval
    private let failureLimit: Int
    private let statusUpdates = BroadcastStream<SoftwareLightingEngineStatus>()

    private var tasksByDeviceKey: [String: Task<Void, Never>] = [:]
    private var desiredRequestByDeviceKey: [String: SoftwareLightingEffectRequest] = [:]
    private var deviceByDeviceKey: [String: MouseDevice] = [:]
    private var deviceKeyByDeviceID: [String: String] = [:]
    private var deviceIDByDeviceKey: [String: String] = [:]
    private var statusByDeviceKey: [String: SoftwareLightingEngineStatus] = [:]
    private var statusByDeviceID: [String: SoftwareLightingEngineStatus] = [:]
    private var generationByDeviceKey: [String: UInt64] = [:]
    private var batteryPercentByDeviceKey: [String: Int] = [:]

    init(frameWriter: any SoftwareLightingFrameWriting, minimumFrameInterval: TimeInterval = 1.0 / 30.0, failureLimit: Int = 3) {
        self.frameWriter = frameWriter
        self.minimumFrameInterval = max(0.001, minimumFrameInterval)
        self.failureLimit = max(1, failureLimit)
    }

    func updates() -> AsyncStream<SoftwareLightingEngineStatus> { statusUpdates.makeStream() }

    func status(deviceID: String) -> SoftwareLightingEngineStatus? {
        if let key = deviceKeyByDeviceID[deviceID], let status = statusByDeviceKey[key] { return status }
        return statusByDeviceID[deviceID]
    }

    @discardableResult func start(device: MouseDevice, request: SoftwareLightingEffectRequest, batteryPercent: Int? = nil) async throws -> SoftwareLightingEngineStatus {
        guard let layout = device.softwareLightingFrameLayout else { throw SoftwareLightingEngineError.unsupportedDevice }
        guard device.supportsSoftwareLightingPreset(request.presetID) else { throw SoftwareLightingEngineError.unsupportedPreset(request.presetID) }

        let deviceKey = Self.lightingDeviceKey(for: device)
        if let batteryPercent { batteryPercentByDeviceKey[deviceKey] = Self.clampedBatteryPercent(batteryPercent) }
        let generation = nextGeneration(for: deviceKey)
        if let previousTask = tasksByDeviceKey[deviceKey] {
            previousTask.cancel()
            await previousTask.value
        }
        guard generationByDeviceKey[deviceKey] == generation else { return supersededStatus(deviceID: device.id, deviceKey: deviceKey) }
        if let previousDeviceID = deviceIDByDeviceKey[deviceKey], previousDeviceID != device.id {
            deviceKeyByDeviceID.removeValue(forKey: previousDeviceID)
            let stopped = SoftwareLightingEngineStatus(deviceID: previousDeviceID, state: .stopped, request: nil, message: nil)
            statusByDeviceID[previousDeviceID] = stopped
            statusUpdates.yield(stopped)
        }
        desiredRequestByDeviceKey[deviceKey] = request
        deviceByDeviceKey[deviceKey] = device
        deviceKeyByDeviceID[device.id] = deviceKey
        deviceIDByDeviceKey[deviceKey] = device.id

        let status = SoftwareLightingEngineStatus(deviceID: device.id, state: .running, request: request, message: nil)
        publish(status, deviceKey: deviceKey)

        let frameInterval = max(minimumFrameInterval, 1.0 / Double(request.framesPerSecond))
        tasksByDeviceKey[deviceKey] = Task { [weak self] in await self?.run(RenderLoopContext(device: device, deviceKey: deviceKey, generation: generation, layout: layout, request: request, frameInterval: frameInterval)) }
        return status
    }

    @discardableResult func stop(deviceID: String) async -> SoftwareLightingEngineStatus? {
        let deviceKey = deviceKeyByDeviceID[deviceID] ?? deviceID
        let generation = nextGeneration(for: deviceKey)
        if let previousTask = tasksByDeviceKey[deviceKey] {
            previousTask.cancel()
            await previousTask.value
        }
        guard generationByDeviceKey[deviceKey] == generation else { return supersededStatus(deviceID: deviceID, deviceKey: deviceKey) }
        let statusDeviceID = deviceIDByDeviceKey[deviceKey] ?? deviceID
        desiredRequestByDeviceKey.removeValue(forKey: deviceKey)
        deviceByDeviceKey.removeValue(forKey: deviceKey)
        statusByDeviceKey.removeValue(forKey: deviceKey)
        deviceIDByDeviceKey.removeValue(forKey: deviceKey)
        batteryPercentByDeviceKey.removeValue(forKey: deviceKey)
        tasksByDeviceKey.removeValue(forKey: deviceKey)
        removeAliases(for: deviceKey)

        let status = SoftwareLightingEngineStatus(deviceID: statusDeviceID, state: .stopped, request: nil, message: nil)
        statusByDeviceID[deviceID] = status
        statusByDeviceID[statusDeviceID] = status
        statusUpdates.yield(status)
        return status
    }

    @discardableResult func stopAll() async -> [SoftwareLightingEngineStatus] {
        var deviceKeys = Set(tasksByDeviceKey.keys)
        deviceKeys.formUnion(desiredRequestByDeviceKey.keys)
        deviceKeys.formUnion(deviceIDByDeviceKey.keys)
        deviceKeys.formUnion(statusByDeviceKey.keys)
        guard !deviceKeys.isEmpty else { return [] }

        var stopGenerations: [String: UInt64] = [:]
        let tasks = tasksByDeviceKey
        for deviceKey in deviceKeys {
            stopGenerations[deviceKey] = nextGeneration(for: deviceKey)
            tasksByDeviceKey[deviceKey]?.cancel()
        }
        for task in tasks.values { await task.value }

        var statuses: [SoftwareLightingEngineStatus] = []
        for deviceKey in deviceKeys.sorted() {
            guard generationByDeviceKey[deviceKey] == stopGenerations[deviceKey] else { continue }
            let statusDeviceID = deviceIDByDeviceKey[deviceKey] ?? statusByDeviceKey[deviceKey]?.deviceID ?? deviceKey
            let aliasDeviceIDs = Set(deviceKeyByDeviceID.filter { $0.value == deviceKey }.map(\.key) + [statusDeviceID])

            desiredRequestByDeviceKey.removeValue(forKey: deviceKey)
            deviceByDeviceKey.removeValue(forKey: deviceKey)
            statusByDeviceKey.removeValue(forKey: deviceKey)
            deviceIDByDeviceKey.removeValue(forKey: deviceKey)
            batteryPercentByDeviceKey.removeValue(forKey: deviceKey)
            tasksByDeviceKey.removeValue(forKey: deviceKey)
            removeAliases(for: deviceKey)

            let status = SoftwareLightingEngineStatus(deviceID: statusDeviceID, state: .stopped, request: nil, message: nil)
            for deviceID in aliasDeviceIDs { statusByDeviceID[deviceID] = status }
            statusUpdates.yield(status)
            statuses.append(status)
        }
        return statuses
    }

    @discardableResult func suspend(deviceID: String, message: String) async -> SoftwareLightingEngineStatus? {
        let deviceKey = deviceKeyByDeviceID[deviceID] ?? deviceID
        guard let request = desiredRequestByDeviceKey[deviceKey] else { return nil }
        let generation = nextGeneration(for: deviceKey)
        if let previousTask = tasksByDeviceKey[deviceKey] {
            previousTask.cancel()
            await previousTask.value
        }
        guard generationByDeviceKey[deviceKey] == generation else { return supersededStatus(deviceID: deviceID, deviceKey: deviceKey) }
        deviceByDeviceKey.removeValue(forKey: deviceKey)
        tasksByDeviceKey.removeValue(forKey: deviceKey)
        let statusDeviceID = deviceIDByDeviceKey[deviceKey] ?? deviceID
        let status = SoftwareLightingEngineStatus(deviceID: statusDeviceID, state: .suspended, request: request, message: message)
        publish(status, deviceKey: deviceKey)
        return status
    }

    @discardableResult func resumeIfNeeded(device: MouseDevice, batteryPercent: Int? = nil) async throws -> SoftwareLightingEngineStatus? {
        let deviceKey = Self.lightingDeviceKey(for: device)
        guard let request = desiredRequestByDeviceKey[deviceKey] else { return nil }
        guard statusByDeviceKey[deviceKey]?.state == .suspended else { return nil }
        return try await start(device: device, request: request, batteryPercent: batteryPercent)
    }

    @discardableResult func reassertIfRunning(device: MouseDevice, batteryPercent: Int? = nil) async throws -> SoftwareLightingEngineStatus? {
        let deviceKey = Self.lightingDeviceKey(for: device)
        let status = statusByDeviceKey[deviceKey] ?? statusByDeviceID[device.id]
        guard status?.state == .running else { return nil }
        guard let request = desiredRequestByDeviceKey[deviceKey] ?? status?.request else { return nil }
        return try await start(device: device, request: request, batteryPercent: batteryPercent)
    }

    func updateBatteryPercent(deviceID: String, batteryPercent: Int?) {
        let deviceKey = deviceKeyByDeviceID[deviceID] ?? deviceID
        guard let batteryPercent else {
            batteryPercentByDeviceKey.removeValue(forKey: deviceKey)
            return
        }
        batteryPercentByDeviceKey[deviceKey] = Self.clampedBatteryPercent(batteryPercent)
    }

    private func run(_ context: RenderLoopContext) async {
        let device = context.device
        let deviceKey = context.deviceKey
        let generation = context.generation
        let layout = context.layout
        let request = context.request
        let frameInterval = context.frameInterval
        let startedAt = Date()
        var consecutiveFailures = 0
        var lastWrittenFrame: USBLightingFramePatch?

        if request.presetID == .batteryMeter {
            let clearFrame = SoftwareLightingRenderer.render(request: request, layout: layout, elapsedTime: 0.0, batteryPercent: nil)
            do {
                try await frameWriter.writeSoftwareLightingFrame(device: device, frame: clearFrame)
                guard isCurrent(deviceKey: deviceKey, generation: generation) else { return }
                lastWrittenFrame = clearFrame
            } catch {
                guard !Task.isCancelled else { return }
                guard isCurrent(deviceKey: deviceKey, generation: generation) else { return }
                if suspendForRecoverableFrameFailure(error, deviceID: device.id, deviceKey: deviceKey, generation: generation, request: request) { return }
                consecutiveFailures += 1
                if consecutiveFailures >= failureLimit {
                    fail(deviceID: device.id, deviceKey: deviceKey, generation: generation, request: request, message: error.localizedDescription)
                    return
                }
            }
        }

        while !Task.isCancelled {
            guard isCurrent(deviceKey: deviceKey, generation: generation) else { return }
            let frameStartedAt = Date()
            let elapsed = frameStartedAt.timeIntervalSince(startedAt)
            let frame = SoftwareLightingRenderer.render(request: request, layout: layout, elapsedTime: elapsed, batteryPercent: batteryPercentByDeviceKey[deviceKey])
            guard frame != lastWrittenFrame else {
                let elapsedThisFrame = Date().timeIntervalSince(frameStartedAt)
                let sleepInterval = max(0.0, frameInterval - elapsedThisFrame)
                do { try await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000)) } catch { return }
                continue
            }

            do {
                try await frameWriter.writeSoftwareLightingFrame(device: device, frame: frame)
                guard isCurrent(deviceKey: deviceKey, generation: generation) else { return }
                lastWrittenFrame = frame
                consecutiveFailures = 0
            } catch {
                guard !Task.isCancelled else { return }
                guard isCurrent(deviceKey: deviceKey, generation: generation) else { return }
                if suspendForRecoverableFrameFailure(error, deviceID: device.id, deviceKey: deviceKey, generation: generation, request: request) { return }
                consecutiveFailures += 1
                if consecutiveFailures >= failureLimit {
                    fail(deviceID: device.id, deviceKey: deviceKey, generation: generation, request: request, message: error.localizedDescription)
                    return
                }
            }

            let elapsedThisFrame = Date().timeIntervalSince(frameStartedAt)
            let sleepInterval = max(0.0, frameInterval - elapsedThisFrame)
            do { try await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000)) } catch { return }
        }
    }

    private func suspendForRecoverableFrameFailure(_ error: any Error, deviceID: String, deviceKey: String, generation: UInt64, request: SoftwareLightingEffectRequest) -> Bool {
        guard let recoverable = error as? SoftwareLightingFrameWriteFailure else { return false }
        suspendCurrentRun(deviceID: deviceID, deviceKey: deviceKey, generation: generation, request: request, message: recoverable.localizedDescription)
        return true
    }

    private func suspendCurrentRun(deviceID: String, deviceKey: String, generation: UInt64, request: SoftwareLightingEffectRequest, message: String) {
        guard isCurrent(deviceKey: deviceKey, generation: generation) else { return }
        tasksByDeviceKey.removeValue(forKey: deviceKey)?.cancel()
        deviceByDeviceKey.removeValue(forKey: deviceKey)
        let status = SoftwareLightingEngineStatus(deviceID: deviceID, state: .suspended, request: request, message: message)
        publish(status, deviceKey: deviceKey)
    }

    private func fail(deviceID: String, deviceKey: String, generation: UInt64, request: SoftwareLightingEffectRequest, message: String) {
        guard isCurrent(deviceKey: deviceKey, generation: generation) else { return }
        tasksByDeviceKey.removeValue(forKey: deviceKey)?.cancel()
        desiredRequestByDeviceKey.removeValue(forKey: deviceKey)
        deviceByDeviceKey.removeValue(forKey: deviceKey)
        deviceIDByDeviceKey.removeValue(forKey: deviceKey)
        batteryPercentByDeviceKey.removeValue(forKey: deviceKey)
        removeAliases(for: deviceKey)
        let status = SoftwareLightingEngineStatus(deviceID: deviceID, state: .failed, request: request, message: message)
        publish(status, deviceKey: deviceKey)
    }

    private func publish(_ status: SoftwareLightingEngineStatus, deviceKey: String) {
        statusByDeviceKey[deviceKey] = status
        statusByDeviceID[status.deviceID] = status
        statusUpdates.yield(status)
    }

    private func nextGeneration(for deviceKey: String) -> UInt64 {
        let generation = generationByDeviceKey[deviceKey, default: 0] &+ 1
        generationByDeviceKey[deviceKey] = generation
        return generation
    }

    private func isCurrent(deviceKey: String, generation: UInt64) -> Bool { generationByDeviceKey[deviceKey] == generation }

    private func supersededStatus(deviceID: String, deviceKey: String) -> SoftwareLightingEngineStatus {
        if let status = statusByDeviceKey[deviceKey] { return status }
        if let status = statusByDeviceID[deviceID] { return status }
        return SoftwareLightingEngineStatus(deviceID: deviceID, state: .stopped, request: nil, message: nil)
    }

    private func removeAliases(for deviceKey: String) { for (deviceID, key) in deviceKeyByDeviceID where key == deviceKey { deviceKeyByDeviceID.removeValue(forKey: deviceID) } }

    private static func lightingDeviceKey(for device: MouseDevice) -> String { DevicePersistenceKeys.key(for: device) }

    private static func clampedBatteryPercent(_ value: Int) -> Int { max(0, min(100, value)) }
}
