import Foundation
import XCTest
import OpenSnekCore
@testable import OpenSnek

final class BackgroundServiceTransportTests: XCTestCase {
    func testCoordinatorConnectsToPublishedServiceAndRoutesRequests() async throws {
        let suiteName = "BackgroundServiceTransportTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backend = StubServiceBackend()
        let host = try BackgroundServiceHost(backend: backend, defaults: defaults)
        try await host.start()
        defer { host.stop() }

        let publishedPort = defaults.integer(forKey: BackgroundServiceCoordinator.portDefaultsKey)
        XCTAssertGreaterThan(publishedPort, 0)
        XCTAssertEqual(
            defaults.integer(forKey: BackgroundServiceCoordinator.pidDefaultsKey),
            Int(ProcessInfo.processInfo.processIdentifier)
        )

        let coordinator = await MainActor.run {
            BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!)
        }
        let connectedBackend = try await coordinator.connectToRunningService()
        let serviceBackend = try XCTUnwrap(connectedBackend)

        let devices = try await serviceBackend.listDevices()
        XCTAssertEqual(devices.map(\.id), ["test-mouse"])

        let state = try await serviceBackend.readState(device: devices[0])
        XCTAssertEqual(state.poll_rate, 1000)
        XCTAssertEqual(state.dpi_stages.values, [800, 1600, 3200])
        XCTAssertEqual(state.dpi_stages.active_stage, 1)

        let applied = try await serviceBackend.apply(
            device: devices[0],
            patch: DevicePatch(pollRate: 500, dpiStages: [1200, 2400, 3600], activeStage: 2)
        )
        XCTAssertEqual(applied.poll_rate, 500)
        XCTAssertEqual(applied.dpi_stages.values, [1200, 2400, 3600])
        XCTAssertEqual(applied.dpi_stages.active_stage, 2)

        let fast = try await serviceBackend.readDpiStagesFast(device: devices[0])
        XCTAssertEqual(fast, DpiFastSnapshot(active: 2, values: [1200, 2400, 3600]))
        let usesFastPolling = await serviceBackend.shouldUseFastDPIPolling(device: devices[0])
        XCTAssertTrue(usesFastPolling)
        let transportStatus = await serviceBackend.dpiUpdateTransportStatus(device: devices[0])
        XCTAssertEqual(transportStatus, .listening)

        let lighting = try await serviceBackend.readLightingColor(device: devices[0])
        XCTAssertEqual(lighting, RGBPatch(r: 10, g: 20, b: 30))

        let binding = try await serviceBackend.debugUSBReadButtonBinding(device: devices[0], slot: 5, profile: 2)
        XCTAssertEqual(binding, [0xAA, 0x55, 0x05, 0x02])
    }

    func testCoordinatorStreamsStateUpdatesOverServiceSocket() async throws {
        let suiteName = "BackgroundServiceTransportTests.stream.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backend = StubServiceBackend()
        let host = try BackgroundServiceHost(backend: backend, defaults: defaults)
        try await host.start()
        defer { host.stop() }

        let coordinator = await MainActor.run {
            BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!)
        }
        let connectedBackend = try await coordinator.connectToRunningService()
        let serviceBackend = try XCTUnwrap(connectedBackend)
        let devices = try await serviceBackend.listDevices()
        let device = try XCTUnwrap(devices.first)

        let firstTwoUpdatesTask = Task<[BackendStateUpdate], Never> {
            var received: [BackendStateUpdate] = []
            let stream = await serviceBackend.stateUpdates()
            for await update in stream {
                received.append(update)
                if received.count == 2 {
                    break
                }
            }
            return received
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        await backend.emitDeviceStateUpdate(
            MouseState(
                device: DeviceSummary(
                    id: device.id,
                    product_name: device.product_name,
                    serial: device.serial,
                    transport: device.transport,
                    firmware: device.firmware
                ),
                connection: "usb",
                battery_percent: 87,
                charging: false,
                dpi: DpiPair(x: 3200, y: 3200),
                dpi_stages: DpiStages(active_stage: 2, values: [800, 1600, 3200]),
                poll_rate: 1000,
                device_mode: DeviceMode(mode: 0x00, param: 0x00),
                led_value: 64,
                capabilities: Capabilities(
                    dpi_stages: true,
                    poll_rate: true,
                    power_management: true,
                    button_remap: true,
                    lighting: true
                )
            ),
            deviceID: device.id
        )

        let received = await firstTwoUpdatesTask.value
        XCTAssertEqual(received.count, 2)
        guard case .deviceList(let streamedDevices, _) = received[0] else {
            return XCTFail("Expected initial device list update")
        }
        XCTAssertEqual(streamedDevices.map(\.id), [device.id])
        guard case .deviceState(let updatedDeviceID, let updatedState, _) = received[1] else {
            return XCTFail("Expected device state update")
        }
        XCTAssertEqual(updatedDeviceID, device.id)
        XCTAssertEqual(updatedState.dpi?.x, 3200)
    }

    func testCoordinatorStreamsDpiTransportStatusUpdatesOverServiceSocket() async throws {
        let suiteName = "BackgroundServiceTransportTests.transport.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let backend = StubServiceBackend()
        let host = try BackgroundServiceHost(backend: backend, defaults: defaults)
        try await host.start()
        defer { host.stop() }

        let coordinator = await MainActor.run {
            BackgroundServiceCoordinator(defaults: UserDefaults(suiteName: suiteName)!)
        }
        let connectedBackend = try await coordinator.connectToRunningService()
        let serviceBackend = try XCTUnwrap(connectedBackend)
        let devices = try await serviceBackend.listDevices()
        let device = try XCTUnwrap(devices.first)

        let firstTwoUpdatesTask = Task<[BackendStateUpdate], Never> {
            var received: [BackendStateUpdate] = []
            let stream = await serviceBackend.stateUpdates()
            for await update in stream {
                received.append(update)
                if received.count == 2 {
                    break
                }
            }
            return received
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        await backend.emitDpiTransportStatusUpdate(.streamActive, deviceID: device.id)

        let received = await firstTwoUpdatesTask.value
        XCTAssertEqual(received.count, 2)
        guard case .deviceList = received[0] else {
            return XCTFail("Expected initial device list update")
        }
        guard case .dpiTransportStatus(let updatedDeviceID, let status, _) = received[1] else {
            return XCTFail("Expected DPI transport status update")
        }
        XCTAssertEqual(updatedDeviceID, device.id)
        XCTAssertEqual(status, .streamActive)
    }
}

private actor StubServiceBackend: DeviceBackend {
    nonisolated var usesRemoteServiceTransport: Bool { false }

    private let device = MouseDevice(
        id: "test-mouse",
        vendor_id: 0x1532,
        product_id: 0x00B9,
        product_name: "Stub Mouse",
        transport: .usb,
        path_b64: "",
        serial: "SERIAL",
        firmware: "1.0.0",
        location_id: 1,
        profile_id: .basiliskV3XHyperspeed,
        supports_advanced_lighting_effects: true,
        onboard_profile_count: 1
    )

    private var state = MouseState(
        device: DeviceSummary(
            id: "test-mouse",
            product_name: "Stub Mouse",
            serial: "SERIAL",
            transport: .usb,
            firmware: "1.0.0"
        ),
        connection: "usb",
        battery_percent: 87,
        charging: false,
        dpi: DpiPair(x: 800, y: 800),
        dpi_stages: DpiStages(active_stage: 1, values: [800, 1600, 3200]),
        poll_rate: 1000,
        device_mode: DeviceMode(mode: 0x00, param: 0x00),
        led_value: 64,
        capabilities: Capabilities(
            dpi_stages: true,
            poll_rate: true,
            power_management: true,
            button_remap: true,
            lighting: true
        )
    )
    private let stateUpdateStreamPair = AsyncStream.makeStream(of: BackendStateUpdate.self)

    func listDevices() async throws -> [MouseDevice] {
        [device]
    }

    func readState(device _: MouseDevice) async throws -> MouseState {
        state
    }

    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? {
        guard let active = state.dpi_stages.active_stage,
              let values = state.dpi_stages.values else {
            return nil
        }
        return DpiFastSnapshot(active: active, values: values)
    }

    func shouldUseFastDPIPolling(device _: MouseDevice) async -> Bool {
        true
    }

    func dpiUpdateTransportStatus(device _: MouseDevice) async -> DpiUpdateTransportStatus {
        .listening
    }

    func hidAccessStatus() async -> HIDAccessStatus {
        HIDAccessStatus(
            authorization: .granted,
            hostLabel: "Test Host (io.opensnek.OpenSnek)",
            bundleIdentifier: "io.opensnek.OpenSnek",
            detail: nil
        )
    }

    func stateUpdates() async -> AsyncStream<BackendStateUpdate> {
        stateUpdateStreamPair.stream
    }

    func apply(device _: MouseDevice, patch: DevicePatch) async throws -> MouseState {
        let nextValues = patch.dpiStages ?? state.dpi_stages.values
        let nextActive = patch.activeStage ?? state.dpi_stages.active_stage
        let nextPollRate = patch.pollRate ?? state.poll_rate
        let nextDpiValue = nextValues?.dropFirst(max(0, (nextActive ?? 1) - 1)).first ?? state.dpi?.x ?? 800

        state = MouseState(
            device: state.device,
            connection: state.connection,
            battery_percent: state.battery_percent,
            charging: state.charging,
            dpi: DpiPair(x: nextDpiValue, y: nextDpiValue),
            dpi_stages: DpiStages(active_stage: nextActive, values: nextValues),
            poll_rate: nextPollRate,
            sleep_timeout: state.sleep_timeout,
            device_mode: state.device_mode,
            low_battery_threshold_raw: state.low_battery_threshold_raw,
            scroll_mode: state.scroll_mode,
            scroll_acceleration: state.scroll_acceleration,
            scroll_smart_reel: state.scroll_smart_reel,
            active_onboard_profile: state.active_onboard_profile,
            onboard_profile_count: state.onboard_profile_count,
            led_value: state.led_value,
            capabilities: state.capabilities
        )
        return state
    }

    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? {
        RGBPatch(r: 10, g: 20, b: 30)
    }

    func debugUSBReadButtonBinding(device _: MouseDevice, slot: Int, profile: Int) async throws -> [UInt8]? {
        [0xAA, 0x55, UInt8(slot & 0xFF), UInt8(profile & 0xFF)]
    }

    func emitDeviceStateUpdate(_ nextState: MouseState, deviceID: String, updatedAt: Date = Date()) {
        state = nextState
        stateUpdateStreamPair.continuation.yield(
            .deviceState(deviceID: deviceID, state: nextState, updatedAt: updatedAt)
        )
    }

    func emitDpiTransportStatusUpdate(
        _ status: DpiUpdateTransportStatus,
        deviceID: String,
        updatedAt: Date = Date()
    ) {
        stateUpdateStreamPair.continuation.yield(
            .dpiTransportStatus(deviceID: deviceID, status: status, updatedAt: updatedAt)
        )
    }
}
