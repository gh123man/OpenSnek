import Foundation
import XCTest
import OpenSnekCore
@testable import OpenSnek

final class SoftwareLightingEngineTests: XCTestCase {
    func testStartWritesFramesAndPublishesRunningStatus() async throws {
        let writer = RecordingSoftwareLightingFrameWriter()
        let engine = SoftwareLightingEngine(
            frameWriter: writer,
            minimumFrameInterval: 0.005,
            failureLimit: 3
        )
        let device = makeSoftwareLightingTestDevice()
        let stream = await engine.updates()
        async let firstStatus = Self.firstStatus(from: stream)

        let status = try await engine.start(
            device: device,
            request: SoftwareLightingEffectRequest(presetID: .flame, framesPerSecond: 30)
        )

        XCTAssertEqual(status.state, .running)
        XCTAssertEqual(status.request?.presetID, .flame)
        let receivedStatus = await firstStatus
        XCTAssertEqual(receivedStatus?.state, .running)

        try await waitUntil {
            await writer.frameCount() >= 2
        }
        await engine.stop(deviceID: device.id)
    }

    func testStartingNewPresetReplacesExistingRun() async throws {
        let writer = RecordingSoftwareLightingFrameWriter()
        let engine = SoftwareLightingEngine(
            frameWriter: writer,
            minimumFrameInterval: 0.005,
            failureLimit: 3
        )
        let device = makeSoftwareLightingTestDevice()

        _ = try await engine.start(
            device: device,
            request: SoftwareLightingEffectRequest(presetID: .flame, framesPerSecond: 30)
        )
        _ = try await engine.start(
            device: device,
            request: SoftwareLightingEffectRequest(presetID: .scrollingRainbow, framesPerSecond: 30)
        )

        let status = await engine.status(deviceID: device.id)
        XCTAssertEqual(status?.state, .running)
        XCTAssertEqual(status?.request?.presetID, .scrollingRainbow)
        await engine.stop(deviceID: device.id)
    }

    func testStartingNewPresetWaitsForInFlightWriteBeforeReplacement() async throws {
        let writer = RecordingSoftwareLightingFrameWriter(delayNanoseconds: 120_000_000)
        let engine = SoftwareLightingEngine(
            frameWriter: writer,
            minimumFrameInterval: 0.001,
            failureLimit: 3
        )
        let device = makeSoftwareLightingTestDevice()

        _ = try await engine.start(
            device: device,
            request: SoftwareLightingEffectRequest(presetID: .flame, framesPerSecond: 30)
        )

        try await waitUntil(timeout: 1.0) {
            await writer.activeWriteCount() == 1
        }

        _ = try await engine.start(
            device: device,
            request: SoftwareLightingEffectRequest(presetID: .scrollingRainbow, framesPerSecond: 30)
        )

        try await waitUntil(timeout: 1.0) {
            await writer.frameCount() >= 2
        }
        let maxConcurrentWrites = await writer.maxConcurrentWrites()
        XCTAssertEqual(maxConcurrentWrites, 1)

        let status = await engine.status(deviceID: device.id)
        XCTAssertEqual(status?.state, .running)
        XCTAssertEqual(status?.request?.presetID, .scrollingRainbow)
        await engine.stop(deviceID: device.id)
    }

    func testSlowFrameWritesDoNotOverlap() async throws {
        let writer = RecordingSoftwareLightingFrameWriter(delayNanoseconds: 40_000_000)
        let engine = SoftwareLightingEngine(
            frameWriter: writer,
            minimumFrameInterval: 0.001,
            failureLimit: 3
        )
        let device = makeSoftwareLightingTestDevice()

        _ = try await engine.start(
            device: device,
            request: SoftwareLightingEffectRequest(presetID: .cometChase, framesPerSecond: 30)
        )

        try await waitUntil(timeout: 1.0) {
            await writer.frameCount() >= 3
        }
        let maxConcurrentWrites = await writer.maxConcurrentWrites()
        XCTAssertEqual(maxConcurrentWrites, 1)
        await engine.stop(deviceID: device.id)
    }

    func testRepeatedFrameFailuresPublishFailedStatus() async throws {
        let writer = RecordingSoftwareLightingFrameWriter(failAllWrites: true)
        let engine = SoftwareLightingEngine(
            frameWriter: writer,
            minimumFrameInterval: 0.001,
            failureLimit: 2
        )
        let device = makeSoftwareLightingTestDevice()

        _ = try await engine.start(
            device: device,
            request: SoftwareLightingEffectRequest(presetID: .aurora, framesPerSecond: 30)
        )

        try await waitUntil(timeout: 1.0) {
            let status = await engine.status(deviceID: device.id)
            return status?.state == .failed
        }
        let status = await engine.status(deviceID: device.id)
        XCTAssertEqual(status?.request?.presetID, .aurora)
        XCTAssertNotNil(status?.message)
    }

    func testSuspendRetainsDesiredPresetAndResumeRestartsIt() async throws {
        let writer = RecordingSoftwareLightingFrameWriter()
        let engine = SoftwareLightingEngine(
            frameWriter: writer,
            minimumFrameInterval: 0.005,
            failureLimit: 3
        )
        let device = makeSoftwareLightingTestDevice()

        _ = try await engine.start(
            device: device,
            request: SoftwareLightingEffectRequest(presetID: .scrollingRainbow, framesPerSecond: 30)
        )
        let suspended = await engine.suspend(deviceID: device.id, message: "Device disconnected")
        XCTAssertEqual(suspended?.state, .suspended)
        XCTAssertEqual(suspended?.request?.presetID, .scrollingRainbow)

        let resumed = try await engine.resumeIfNeeded(device: device)
        XCTAssertEqual(resumed?.state, .running)
        XCTAssertEqual(resumed?.request?.presetID, .scrollingRainbow)
        await engine.stop(deviceID: device.id)
    }

    private static func firstStatus(
        from stream: AsyncStream<SoftwareLightingEngineStatus>
    ) async -> SoftwareLightingEngineStatus? {
        for await status in stream {
            return status
        }
        return nil
    }

    private func waitUntil(
        timeout: TimeInterval = 0.5,
        pollInterval: UInt64 = 10_000_000,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: pollInterval)
        }
        XCTFail("Timed out waiting for condition")
    }
}

private actor RecordingSoftwareLightingFrameWriter: SoftwareLightingFrameWriting {
    private let delayNanoseconds: UInt64
    private let failAllWrites: Bool
    private var frames: [USBLightingFramePatch] = []
    private var activeWrites = 0
    private var maxActiveWrites = 0

    init(delayNanoseconds: UInt64 = 0, failAllWrites: Bool = false) {
        self.delayNanoseconds = delayNanoseconds
        self.failAllWrites = failAllWrites
    }

    func writeSoftwareLightingFrame(device _: MouseDevice, frame: USBLightingFramePatch) async throws {
        activeWrites += 1
        maxActiveWrites = max(maxActiveWrites, activeWrites)
        defer { activeWrites -= 1 }

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if failAllWrites {
            throw NSError(domain: "SoftwareLightingEngineTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Injected frame failure"
            ])
        }
        frames.append(frame)
    }

    func frameCount() -> Int {
        frames.count
    }

    func maxConcurrentWrites() -> Int {
        maxActiveWrites
    }

    func activeWriteCount() -> Int {
        activeWrites
    }
}

private func makeSoftwareLightingTestDevice() -> MouseDevice {
    MouseDevice(
        id: "software-lighting-v3-pro",
        vendor_id: 0x1532,
        product_id: 0x00AB,
        product_name: "Basilisk V3 Pro",
        transport: .usb,
        path_b64: "",
        serial: "SOFTWARE-LIGHTING",
        firmware: "1.0.0",
        location_id: 1,
        profile_id: .basiliskV3Pro,
        supports_advanced_lighting_effects: true,
        onboard_profile_count: 5
    )
}
