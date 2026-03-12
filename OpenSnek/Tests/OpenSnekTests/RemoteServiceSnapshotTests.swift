import Foundation
import XCTest
import OpenSnekCore
@testable import OpenSnek

final class RemoteServiceSnapshotTests: XCTestCase {
    func testRemoteServiceBackendUsesSnapshotFeed() async {
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false)
        }

        let usesRemoteSnapshots = await MainActor.run { appState.usesRemoteServiceUpdates }
        XCTAssertTrue(usesRemoteSnapshots)
    }

    func testApplyRemoteServiceSnapshotHydratesSelectedState() async {
        let appState = await MainActor.run {
            AppState(launchRole: .app, backend: SnapshotTestRemoteBackend(), autoStart: false)
        }

        let device = MouseDevice(
            id: "snapshot-device",
            vendor_id: 0x1532,
            product_id: 0x00AB,
            product_name: "Snapshot Mouse",
            transport: .usb,
            path_b64: "",
            serial: "SNAPSHOT",
            firmware: "1.0.0",
            location_id: 1,
            profile_id: .basiliskV3Pro,
            supports_advanced_lighting_effects: true,
            onboard_profile_count: 1
        )
        let state = MouseState(
            device: DeviceSummary(
                id: device.id,
                product_name: device.product_name,
                serial: device.serial,
                transport: device.transport,
                firmware: device.firmware
            ),
            connection: "usb",
            battery_percent: 81,
            charging: false,
            dpi: DpiPair(x: 2400, y: 2400),
            dpi_stages: DpiStages(active_stage: 1, values: [800, 2400, 6400]),
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
        let snapshot = SharedServiceSnapshot(
            devices: [device],
            stateByDeviceID: [device.id: state],
            lastUpdatedByDeviceID: [device.id: Date(timeIntervalSince1970: 1_773_320_000)]
        )

        await MainActor.run {
            appState.applyRemoteServiceSnapshot(snapshot)
        }

        let selectedDeviceID = await MainActor.run { appState.selectedDeviceID }
        let selectedDpi = await MainActor.run { appState.state?.dpi?.x }
        let activeStage = await MainActor.run { appState.editableActiveStage }
        let pollRate = await MainActor.run { appState.editablePollRate }

        XCTAssertEqual(selectedDeviceID, device.id)
        XCTAssertEqual(selectedDpi, 2400)
        XCTAssertEqual(activeStage, 2)
        XCTAssertEqual(pollRate, 1000)
    }
}

private final class SnapshotTestRemoteBackend: DeviceBackend {
    var usesRemoteServiceTransport: Bool { true }

    func listDevices() async throws -> [MouseDevice] { [] }
    func readState(device _: MouseDevice) async throws -> MouseState { throw SnapshotBackendError.unimplemented }
    func readDpiStagesFast(device _: MouseDevice) async throws -> DpiFastSnapshot? { nil }
    func apply(device _: MouseDevice, patch _: DevicePatch) async throws -> MouseState { throw SnapshotBackendError.unimplemented }
    func readLightingColor(device _: MouseDevice) async throws -> RGBPatch? { nil }
    func debugUSBReadButtonBinding(device _: MouseDevice, slot _: Int, profile _: Int) async throws -> [UInt8]? { nil }
}

private enum SnapshotBackendError: Error {
    case unimplemented
}
