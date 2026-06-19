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

    private var tasksByDeviceID: [String: Task<Void, Never>] = [:]
    private var desiredRequestByDeviceID: [String: SoftwareLightingEffectRequest] = [:]
    private var deviceByDeviceID: [String: MouseDevice] = [:]
    private var statusByDeviceID: [String: SoftwareLightingEngineStatus] = [:]

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
        statusByDeviceID[deviceID]
    }

    func statuses() -> [String: SoftwareLightingEngineStatus] {
        statusByDeviceID
    }

    @discardableResult
    func start(
        device: MouseDevice,
        request: SoftwareLightingEffectRequest
    ) throws -> SoftwareLightingEngineStatus {
        guard let layout = device.softwareLightingFrameLayout else {
            throw SoftwareLightingEngineError.unsupportedDevice
        }

        tasksByDeviceID[device.id]?.cancel()
        desiredRequestByDeviceID[device.id] = request
        deviceByDeviceID[device.id] = device

        let status = SoftwareLightingEngineStatus(
            deviceID: device.id,
            state: .running,
            request: request,
            message: nil
        )
        publish(status)

        let frameInterval = max(minimumFrameInterval, 1.0 / Double(request.framesPerSecond))
        tasksByDeviceID[device.id] = Task { [weak self] in
            await self?.run(
                device: device,
                layout: layout,
                request: request,
                frameInterval: frameInterval
            )
        }
        return status
    }

    @discardableResult
    func stop(deviceID: String) -> SoftwareLightingEngineStatus? {
        tasksByDeviceID.removeValue(forKey: deviceID)?.cancel()
        desiredRequestByDeviceID.removeValue(forKey: deviceID)
        deviceByDeviceID.removeValue(forKey: deviceID)

        let status = SoftwareLightingEngineStatus(
            deviceID: deviceID,
            state: .stopped,
            request: nil,
            message: nil
        )
        publish(status)
        return status
    }

    @discardableResult
    func suspend(deviceID: String, message: String) -> SoftwareLightingEngineStatus? {
        guard let request = desiredRequestByDeviceID[deviceID] else {
            return nil
        }
        tasksByDeviceID.removeValue(forKey: deviceID)?.cancel()
        deviceByDeviceID.removeValue(forKey: deviceID)
        let status = SoftwareLightingEngineStatus(
            deviceID: deviceID,
            state: .suspended,
            request: request,
            message: message
        )
        publish(status)
        return status
    }

    @discardableResult
    func resumeIfNeeded(device: MouseDevice) throws -> SoftwareLightingEngineStatus? {
        guard let request = desiredRequestByDeviceID[device.id] else { return nil }
        guard statusByDeviceID[device.id]?.state == .suspended else { return nil }
        return try start(device: device, request: request)
    }

    private func run(
        device: MouseDevice,
        layout: SoftwareLightingFrameLayout,
        request: SoftwareLightingEffectRequest,
        frameInterval: TimeInterval
    ) async {
        let startedAt = Date()
        var consecutiveFailures = 0

        while !Task.isCancelled {
            let frameStartedAt = Date()
            let elapsed = frameStartedAt.timeIntervalSince(startedAt)
            let frame = SoftwareLightingRenderer.render(
                request: request,
                layout: layout,
                elapsedTime: elapsed
            )

            do {
                try await frameWriter.writeSoftwareLightingFrame(device: device, frame: frame)
                consecutiveFailures = 0
            } catch {
                guard !Task.isCancelled else { return }
                consecutiveFailures += 1
                if consecutiveFailures >= failureLimit {
                    fail(
                        deviceID: device.id,
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

    private func fail(deviceID: String, request: SoftwareLightingEffectRequest, message: String) {
        tasksByDeviceID.removeValue(forKey: deviceID)?.cancel()
        desiredRequestByDeviceID.removeValue(forKey: deviceID)
        deviceByDeviceID.removeValue(forKey: deviceID)
        let status = SoftwareLightingEngineStatus(
            deviceID: deviceID,
            state: .failed,
            request: request,
            message: message
        )
        publish(status)
    }

    private func publish(_ status: SoftwareLightingEngineStatus) {
        statusByDeviceID[status.deviceID] = status
        statusUpdates.yield(status)
    }
}
