import Foundation
import OpenSnekCore

enum SoftwareLightingEngineError: LocalizedError, Sendable {
    case unsupportedDevice

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            return "Software lighting is not supported for this device"
        }
    }
}

protocol SoftwareLightingFrameWriting: Sendable {
    func writeSoftwareLightingFrame(device: MouseDevice, frame: USBLightingFramePatch) async throws
}

struct BridgeSoftwareLightingFrameWriter: SoftwareLightingFrameWriting {
    let client: BridgeClient

    func writeSoftwareLightingFrame(device: MouseDevice, frame: USBLightingFramePatch) async throws {
        try await client.writeSoftwareLightingFrame(device: device, frame: frame)
    }
}

actor SoftwareLightingEngine {
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

    init(
        frameWriter: any SoftwareLightingFrameWriting,
        minimumFrameInterval: TimeInterval = 1.0 / 30.0,
        failureLimit: Int = 3
    ) {
        self.frameWriter = frameWriter
        self.minimumFrameInterval = max(0.001, minimumFrameInterval)
        self.failureLimit = max(1, failureLimit)
    }

    func updates() -> AsyncStream<SoftwareLightingEngineStatus> {
        statusUpdates.makeStream()
    }

    func status(deviceID: String) -> SoftwareLightingEngineStatus? {
        if let key = deviceKeyByDeviceID[deviceID],
           let status = statusByDeviceKey[key] {
            return status
        }
        return statusByDeviceID[deviceID]
    }

    func statuses() -> [String: SoftwareLightingEngineStatus] {
        statusByDeviceID
    }

    @discardableResult
    func start(
        device: MouseDevice,
        request: SoftwareLightingEffectRequest
    ) async throws -> SoftwareLightingEngineStatus {
        guard let layout = device.softwareLightingFrameLayout else {
            throw SoftwareLightingEngineError.unsupportedDevice
        }

        let deviceKey = Self.lightingDeviceKey(for: device)
        let generation = nextGeneration(for: deviceKey)
        if let previousTask = tasksByDeviceKey[deviceKey] {
            previousTask.cancel()
            await previousTask.value
        }
        guard generationByDeviceKey[deviceKey] == generation else {
            return supersededStatus(deviceID: device.id, deviceKey: deviceKey)
        }
        if let previousDeviceID = deviceIDByDeviceKey[deviceKey],
           previousDeviceID != device.id {
            deviceKeyByDeviceID.removeValue(forKey: previousDeviceID)
            let stopped = SoftwareLightingEngineStatus(
                deviceID: previousDeviceID,
                state: .stopped,
                request: nil,
                message: nil
            )
            statusByDeviceID[previousDeviceID] = stopped
            statusUpdates.yield(stopped)
        }
        desiredRequestByDeviceKey[deviceKey] = request
        deviceByDeviceKey[deviceKey] = device
        deviceKeyByDeviceID[device.id] = deviceKey
        deviceIDByDeviceKey[deviceKey] = device.id

        let status = SoftwareLightingEngineStatus(
            deviceID: device.id,
            state: .running,
            request: request,
            message: nil
        )
        publish(status, deviceKey: deviceKey)

        let frameInterval = max(minimumFrameInterval, 1.0 / Double(request.framesPerSecond))
        tasksByDeviceKey[deviceKey] = Task { [weak self] in
            await self?.run(
                device: device,
                deviceKey: deviceKey,
                generation: generation,
                layout: layout,
                request: request,
                frameInterval: frameInterval
            )
        }
        return status
    }

    @discardableResult
    func stop(deviceID: String) async -> SoftwareLightingEngineStatus? {
        let deviceKey = deviceKeyByDeviceID[deviceID] ?? deviceID
        let generation = nextGeneration(for: deviceKey)
        if let previousTask = tasksByDeviceKey[deviceKey] {
            previousTask.cancel()
            await previousTask.value
        }
        guard generationByDeviceKey[deviceKey] == generation else {
            return supersededStatus(deviceID: deviceID, deviceKey: deviceKey)
        }
        let statusDeviceID = deviceIDByDeviceKey[deviceKey] ?? deviceID
        desiredRequestByDeviceKey.removeValue(forKey: deviceKey)
        deviceByDeviceKey.removeValue(forKey: deviceKey)
        statusByDeviceKey.removeValue(forKey: deviceKey)
        deviceIDByDeviceKey.removeValue(forKey: deviceKey)
        tasksByDeviceKey.removeValue(forKey: deviceKey)
        removeAliases(for: deviceKey)

        let status = SoftwareLightingEngineStatus(
            deviceID: statusDeviceID,
            state: .stopped,
            request: nil,
            message: nil
        )
        statusByDeviceID[deviceID] = status
        statusByDeviceID[statusDeviceID] = status
        statusUpdates.yield(status)
        return status
    }

    @discardableResult
    func suspend(deviceID: String, message: String) async -> SoftwareLightingEngineStatus? {
        let deviceKey = deviceKeyByDeviceID[deviceID] ?? deviceID
        guard let request = desiredRequestByDeviceKey[deviceKey] else {
            return nil
        }
        let generation = nextGeneration(for: deviceKey)
        if let previousTask = tasksByDeviceKey[deviceKey] {
            previousTask.cancel()
            await previousTask.value
        }
        guard generationByDeviceKey[deviceKey] == generation else {
            return supersededStatus(deviceID: deviceID, deviceKey: deviceKey)
        }
        deviceByDeviceKey.removeValue(forKey: deviceKey)
        tasksByDeviceKey.removeValue(forKey: deviceKey)
        let statusDeviceID = deviceIDByDeviceKey[deviceKey] ?? deviceID
        let status = SoftwareLightingEngineStatus(
            deviceID: statusDeviceID,
            state: .suspended,
            request: request,
            message: message
        )
        publish(status, deviceKey: deviceKey)
        return status
    }

    @discardableResult
    func resumeIfNeeded(device: MouseDevice) async throws -> SoftwareLightingEngineStatus? {
        let deviceKey = Self.lightingDeviceKey(for: device)
        guard let request = desiredRequestByDeviceKey[deviceKey] else { return nil }
        guard statusByDeviceKey[deviceKey]?.state == .suspended else { return nil }
        return try await start(device: device, request: request)
    }

    private func run(
        device: MouseDevice,
        deviceKey: String,
        generation: UInt64,
        layout: SoftwareLightingFrameLayout,
        request: SoftwareLightingEffectRequest,
        frameInterval: TimeInterval
    ) async {
        let startedAt = Date()
        var consecutiveFailures = 0

        while !Task.isCancelled {
            guard isCurrent(deviceKey: deviceKey, generation: generation) else { return }
            let frameStartedAt = Date()
            let elapsed = frameStartedAt.timeIntervalSince(startedAt)
            let frame = SoftwareLightingRenderer.render(
                request: request,
                layout: layout,
                elapsedTime: elapsed
            )

            do {
                try await frameWriter.writeSoftwareLightingFrame(device: device, frame: frame)
                guard isCurrent(deviceKey: deviceKey, generation: generation) else { return }
                consecutiveFailures = 0
            } catch {
                guard !Task.isCancelled else { return }
                guard isCurrent(deviceKey: deviceKey, generation: generation) else { return }
                consecutiveFailures += 1
                if consecutiveFailures >= failureLimit {
                    fail(
                        deviceID: device.id,
                        deviceKey: deviceKey,
                        generation: generation,
                        request: request,
                        message: error.localizedDescription
                    )
                    return
                }
            }

            let elapsedThisFrame = Date().timeIntervalSince(frameStartedAt)
            let sleepInterval = max(0.0, frameInterval - elapsedThisFrame)
            do {
                try await Task.sleep(nanoseconds: UInt64(sleepInterval * 1_000_000_000))
            } catch {
                return
            }
        }
    }

    private func fail(
        deviceID: String,
        deviceKey: String,
        generation: UInt64,
        request: SoftwareLightingEffectRequest,
        message: String
    ) {
        guard isCurrent(deviceKey: deviceKey, generation: generation) else { return }
        tasksByDeviceKey.removeValue(forKey: deviceKey)?.cancel()
        desiredRequestByDeviceKey.removeValue(forKey: deviceKey)
        deviceByDeviceKey.removeValue(forKey: deviceKey)
        deviceIDByDeviceKey.removeValue(forKey: deviceKey)
        removeAliases(for: deviceKey)
        let status = SoftwareLightingEngineStatus(
            deviceID: deviceID,
            state: .failed,
            request: request,
            message: message
        )
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

    private func isCurrent(deviceKey: String, generation: UInt64) -> Bool {
        generationByDeviceKey[deviceKey] == generation
    }

    private func supersededStatus(deviceID: String, deviceKey: String) -> SoftwareLightingEngineStatus {
        if let status = statusByDeviceKey[deviceKey] {
            return status
        }
        if let status = statusByDeviceID[deviceID] {
            return status
        }
        return SoftwareLightingEngineStatus(
            deviceID: deviceID,
            state: .stopped,
            request: nil,
            message: nil
        )
    }

    private func removeAliases(for deviceKey: String) {
        for (deviceID, key) in deviceKeyByDeviceID where key == deviceKey {
            deviceKeyByDeviceID.removeValue(forKey: deviceID)
        }
    }

    private static func lightingDeviceKey(for device: MouseDevice) -> String {
        DevicePersistenceKeys.key(for: device)
    }
}
