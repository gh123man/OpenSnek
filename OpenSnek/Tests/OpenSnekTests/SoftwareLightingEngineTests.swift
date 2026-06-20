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

    func testStartingSamePhysicalDeviceWithDifferentIDReplacesExistingRun() async throws {
        let writer = RecordingSoftwareLightingFrameWriter()
        let engine = SoftwareLightingEngine(
            frameWriter: writer,
            minimumFrameInterval: 0.005,
            failureLimit: 3
        )
        let firstDevice = makeSoftwareLightingTestDevice(
            id: "software-lighting-v3-pro-first",
            serial: "000000000000",
            locationID: 0x0114_0000
        )
        let secondDevice = makeSoftwareLightingTestDevice(
            id: "software-lighting-v3-pro-second",
            serial: "ffffffffffff",
            locationID: 0x0215_0000
        )

        _ = try await engine.start(
            device: firstDevice,
            request: SoftwareLightingEffectRequest(presetID: .flame, framesPerSecond: 30)
        )
        try await waitUntil {
            await writer.deviceIDs().contains(firstDevice.id)
        }

        _ = try await engine.start(
            device: secondDevice,
            request: SoftwareLightingEffectRequest(presetID: .scrollingRainbow, framesPerSecond: 30)
        )
        let firstFrameCountAtReplacement = await writer.deviceIDs().filter { $0 == firstDevice.id }.count
        try await waitUntil {
            await writer.deviceIDs().contains(secondDevice.id)
        }

        try await Task.sleep(nanoseconds: 60_000_000)

        let deviceIDs = await writer.deviceIDs()
        XCTAssertEqual(deviceIDs.filter { $0 == firstDevice.id }.count, firstFrameCountAtReplacement)
        XCTAssertGreaterThan(deviceIDs.filter { $0 == secondDevice.id }.count, 0)
        let firstStatus = await engine.status(deviceID: firstDevice.id)
        XCTAssertEqual(firstStatus?.state, .stopped)
        let secondStatus = await engine.status(deviceID: secondDevice.id)
        XCTAssertEqual(secondStatus?.state, .running)
        XCTAssertEqual(secondStatus?.request?.presetID, .scrollingRainbow)
        await engine.stop(deviceID: secondDevice.id)
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

    func testConcurrentReplacementStartsDoNotCreateUntrackedStreams() async throws {
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

        let firstReplacement = Task {
            try await engine.start(
                device: device,
                request: SoftwareLightingEffectRequest(presetID: .scrollingRainbow, framesPerSecond: 30)
            )
        }
        try await Task.sleep(nanoseconds: 10_000_000)
        let secondReplacement = Task {
            try await engine.start(
                device: device,
                request: SoftwareLightingEffectRequest(presetID: .aurora, framesPerSecond: 30)
            )
        }

        _ = try await firstReplacement.value
        _ = try await secondReplacement.value
        try await waitUntil(timeout: 1.0) {
            let status = await engine.status(deviceID: device.id)
            let frameCount = await writer.frameCount()
            return status?.request?.presetID == .aurora && frameCount >= 2
        }

        let maxConcurrentWrites = await writer.maxConcurrentWrites()
        let status = await engine.status(deviceID: device.id)
        XCTAssertEqual(maxConcurrentWrites, 1)
        XCTAssertEqual(status?.state, .running)
        XCTAssertEqual(status?.request?.presetID, .aurora)
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

    func testBatteryMeterUsesSeededBatteryPercent() async throws {
        let writer = RecordingSoftwareLightingFrameWriter()
        let engine = SoftwareLightingEngine(
            frameWriter: writer,
            minimumFrameInterval: 0.005,
            failureLimit: 3
        )
        let device = makeSoftwareLightingTestDevice()

        _ = try await engine.start(
            device: device,
            request: SoftwareLightingEffectRequest(presetID: .batteryMeter, framesPerSecond: 30),
            batteryPercent: 74
        )

        try await waitUntil {
            await writer.frameCount() >= 2
        }
        let frames = await writer.recordedFrames()
        XCTAssertEqual(frames.first?.colors, Array(repeating: RGBPatch(r: 0, g: 0, b: 0), count: 14))
        let meterFrame = frames.dropFirst().first
        XCTAssertEqual(meterFrame?.colors[0], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(meterFrame?.colors[1], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(meterFrame?.colors[2], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(meterFrame?.colors[9], RGBPatch(r: 255, g: 255, b: 255))
        XCTAssertEqual(meterFrame?.colors[10], RGBPatch(r: 224, g: 224, b: 224))
        XCTAssertEqual(meterFrame?.colors[11], RGBPatch(r: 0, g: 0, b: 0))
        await engine.stop(deviceID: device.id)
    }

    func testBatteryMeterUpdatesWhenBatteryPercentChanges() async throws {
        let writer = RecordingSoftwareLightingFrameWriter()
        let engine = SoftwareLightingEngine(
            frameWriter: writer,
            minimumFrameInterval: 0.005,
            failureLimit: 3
        )
        let device = makeSoftwareLightingTestDevice()

        _ = try await engine.start(
            device: device,
            request: SoftwareLightingEffectRequest(presetID: .batteryMeter, framesPerSecond: 30),
            batteryPercent: 74
        )
        try await waitUntil {
            await writer.recordedFrames().contains { $0.colors[2] == RGBPatch(r: 255, g: 255, b: 255) }
        }
        let frameCountBeforeBatteryChange = await writer.frameCount()
        try await Task.sleep(nanoseconds: 50_000_000)
        let frameCountAfterStableBattery = await writer.frameCount()
        XCTAssertEqual(frameCountAfterStableBattery, frameCountBeforeBatteryChange)

        await engine.updateBatteryPercent(deviceID: device.id, batteryPercent: 20)

        try await waitUntil {
            await writer.recordedFrames().contains { $0.colors[2] == RGBPatch(r: 255, g: 255, b: 0) }
        }
        await engine.stop(deviceID: device.id)
    }

    func testBatteryMeterIsRejectedForNonV3ProSoftwareLightingDevice() async throws {
        let writer = RecordingSoftwareLightingFrameWriter()
        let engine = SoftwareLightingEngine(
            frameWriter: writer,
            minimumFrameInterval: 0.005,
            failureLimit: 3
        )
        let device = makeSoftwareLightingTestDevice(
            productID: 0x00CB,
            productName: "Basilisk V3 35K",
            profileID: .basiliskV335K
        )

        do {
            _ = try await engine.start(
                device: device,
                request: SoftwareLightingEffectRequest(presetID: .batteryMeter, framesPerSecond: 30),
                batteryPercent: 74
            )
            XCTFail("Expected battery meter to be rejected for non-V3-Pro devices")
        } catch let error as SoftwareLightingEngineError {
            XCTAssertEqual(error.localizedDescription, "Battery Meter is not supported for this device")
        }
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
    private var frameDeviceIDs: [String] = []
    private var activeWrites = 0
    private var maxActiveWrites = 0

    init(delayNanoseconds: UInt64 = 0, failAllWrites: Bool = false) {
        self.delayNanoseconds = delayNanoseconds
        self.failAllWrites = failAllWrites
    }

    func writeSoftwareLightingFrame(device: MouseDevice, frame: USBLightingFramePatch) async throws {
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
        frameDeviceIDs.append(device.id)
    }

    func frameCount() -> Int {
        frames.count
    }

    func deviceIDs() -> [String] {
        frameDeviceIDs
    }

    func recordedFrames() -> [USBLightingFramePatch] {
        frames
    }

    func maxConcurrentWrites() -> Int {
        maxActiveWrites
    }

    func activeWriteCount() -> Int {
        activeWrites
    }
}

private func makeSoftwareLightingTestDevice(
    id: String = "software-lighting-v3-pro",
    serial: String = "SOFTWARE-LIGHTING",
    locationID: Int = 1,
    productID: Int = 0x00AB,
    productName: String = "Basilisk V3 Pro",
    profileID: DeviceProfileID = .basiliskV3Pro
) -> MouseDevice {
    MouseDevice(
        id: id,
        vendor_id: 0x1532,
        product_id: productID,
        product_name: productName,
        transport: .usb,
        path_b64: "",
        serial: serial,
        firmware: "1.0.0",
        location_id: locationID,
        profile_id: profileID,
        supports_advanced_lighting_effects: true,
        onboard_profile_count: 5
    )
}
