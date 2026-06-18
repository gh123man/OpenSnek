import XCTest
@testable import OpenSnek
import OpenSnekCore
import OpenSnekHardware
import OpenSnekProtocols

final class BridgeClientBluetoothFallbackTests: XCTestCase {
    private func makeBluetoothDevice(
        productID: Int,
        profileID: DeviceProfileID?
    ) -> MouseDevice {
        MouseDevice(
            id: "bt-device-\(productID)",
            vendor_id: 0x068E,
            product_id: productID,
            product_name: "Test Device",
            transport: .bluetooth,
            path_b64: "",
            serial: nil,
            firmware: nil,
            profile_id: profileID
        )
    }

    func testResolveBluetoothBatteryStateIgnoresVendorChargingForBasiliskV3ProBluetooth() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro),
            vendorRaw: 77,
            vendorStatus: 1,
            usbFallback: (12, false)
        )

        XCTAssertEqual(resolved.percent, 77)
        XCTAssertEqual(resolved.charging, false)
    }

    func testResolveBluetoothBatteryStateForcesNotChargingForBasiliskV3XBluetooth() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00BA, profileID: .basiliskV3XHyperspeed),
            vendorRaw: 77,
            vendorStatus: 1,
            usbFallback: (12, true)
        )

        XCTAssertEqual(resolved.percent, 77)
        XCTAssertEqual(resolved.charging, false)
    }

    func testResolveBluetoothBatteryStateForcesNotChargingForOrochiV2Bluetooth() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x0095, profileID: .orochiV2),
            vendorRaw: 77,
            vendorStatus: 1,
            usbFallback: (12, true)
        )

        XCTAssertEqual(resolved.percent, 77)
        XCTAssertEqual(resolved.charging, false)
    }

    func testBluetoothDeltaStateDisablesLightingForOrochiV2() async throws {
        let client = BridgeClient(startHIDMonitoring: false)
        let state = try await client.buildBluetoothDeltaState(
            device: makeBluetoothDevice(productID: 0x0095, profileID: .orochiV2),
            includeDpi: false,
            includeLighting: false,
            includePower: false
        )

        XCTAssertFalse(state.capabilities.lighting)
        XCTAssertNil(state.led_value)
    }

    func testBluetoothDpiStageWriteResolvesCompletePatchWithoutCurrentRead() throws {
        let device = makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro)
        let pairs = [
            DpiPair(x: 500, y: 500),
            DpiPair(x: 900, y: 900),
            DpiPair(x: 1400, y: 1400),
        ]
        let resolved = try BridgeClient.resolveBluetoothDpiStageWrite(
            device: device,
            patch: DevicePatch(
                dpiStages: pairs.map(\.x),
                dpiStagePairs: pairs,
                activeStage: 2
            ),
            current: nil
        )

        XCTAssertEqual(resolved.active, 2)
        XCTAssertEqual(resolved.stages, [500, 900, 1400])
        XCTAssertEqual(resolved.pairs, pairs)
    }

    func testBluetoothOnboardActiveOnlyProjectionDoesNotCarryStaleDpi() async throws {
        let device = makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro)
        let profile = try XCTUnwrap(DeviceProfiles.resolve(
            vendorID: device.vendor_id,
            productID: device.product_id,
            transport: device.transport
        ))
        let client = BridgeClient(startHIDMonitoring: false)
        let loadedSnapshot = OnboardProfileSnapshot(
            profileID: 2,
            metadata: OnboardProfileMetadata(name: "Stored 2"),
            dpi: OnboardDPIProfileSnapshot(
                scalar: DpiPair(x: 1200, y: 1200),
                activeStage: 1,
                pairs: [
                    DpiPair(x: 400, y: 400),
                    DpiPair(x: 1200, y: 1200),
                    DpiPair(x: 1300, y: 1300),
                ],
                stageIDs: [1, 2, 3],
                marker: 0x03
            )
        )

        let loadedState = await client.storeProjectedActiveOnboardProfileState(
            device: device,
            profile: profile,
            activeProfileID: 2,
            snapshot: loadedSnapshot
        )
        XCTAssertEqual(loadedState.dpi_stages.values, [400, 1200, 1300])

        let activeOnly = await client.storeProjectedActiveOnboardProfileState(
            device: device,
            profile: profile,
            activeProfileID: 2
        )
        XCTAssertNil(activeOnly.dpi)
        XCTAssertNil(activeOnly.dpi_stages.active_stage)
        XCTAssertNil(activeOnly.dpi_stages.values)
        XCTAssertEqual(activeOnly.active_onboard_profile, 2)
    }

    func testBluetoothOnboardSnapshotDrivesPassiveDpiExpectation() {
        let dpi = OnboardDPIProfileSnapshot(
            scalar: DpiPair(x: 1200, y: 1200),
            activeStage: 1,
            pairs: [
                DpiPair(x: 400, y: 400),
                DpiPair(x: 1200, y: 1200),
                DpiPair(x: 1300, y: 1300),
            ],
            stageIDs: [1, 2, 3],
            marker: 0x03
        )
        let snapshot = BridgeClient.bluetoothDpiSnapshot(from: dpi)
        let expected = BridgeClient.bluetoothPassiveDpiExpectation(
            event: PassiveDPIEvent(deviceID: "bt-device:bluetooth", dpiX: 1200, dpiY: 1200, observedAt: Date()),
            snapshot: snapshot,
            state: nil
        )

        XCTAssertEqual(snapshot.count, 3)
        XCTAssertEqual(Array(snapshot.slots.prefix(snapshot.count)), [400, 1200, 1300])
        XCTAssertEqual(expected?.active, 1)
        XCTAssertEqual(expected?.values, [400, 1200, 1300])
    }

    func testBluetoothOnboardProfileReadStateSkipsGenericTelemetryPolling() {
        XCTAssertFalse(
            BridgeClient.shouldPollBluetoothGenericTelemetryForReadState(supportsMappedOnboardProfiles: true)
        )
        XCTAssertTrue(
            BridgeClient.shouldPollBluetoothGenericTelemetryForReadState(supportsMappedOnboardProfiles: false)
        )
    }

    func testBluetoothVendorTransactionSerializesConcurrentWork() async throws {
        let client = BridgeClient(startHIDMonitoring: false)
        let gate = AsyncTestGate()
        let firstEntered = AsyncTestFlag()
        let secondStarted = AsyncTestFlag()
        let secondEntered = AsyncTestFlag()

        let first = Task {
            try await client.withBluetoothVendorTransaction(operation: "test first", logTransaction: false) {
                await firstEntered.set()
                await gate.wait()
            }
        }
        try await waitUntil { await firstEntered.value }

        let second = Task {
            await secondStarted.set()
            try await client.withBluetoothVendorTransaction(operation: "test second", logTransaction: false) {
                await secondEntered.set()
            }
        }
        try await waitUntil { await secondStarted.value }
        try await Task.sleep(nanoseconds: 50_000_000)

        let enteredBeforeRelease = await secondEntered.value
        XCTAssertFalse(enteredBeforeRelease)

        await gate.open()
        try await first.value
        try await second.value
        let enteredAfterRelease = await secondEntered.value
        XCTAssertTrue(enteredAfterRelease)
    }

    func testBluetoothVendorTransactionAllowsNestedWorkOnSameTask() async throws {
        let client = BridgeClient(startHIDMonitoring: false)
        let innerEntered = AsyncTestFlag()

        try await client.withBluetoothVendorTransaction(operation: "test outer", logTransaction: false) {
            try await client.withBluetoothVendorTransaction(operation: "test inner", logTransaction: false) {
                await innerEntered.set()
            }
        }

        let nestedEntered = await innerEntered.value
        XCTAssertTrue(nestedEntered)
    }

    func testCompleteBluetoothOnboardProfileMetadataRequiresAllIdentityFields() throws {
        let identifier = try XCTUnwrap(UUID(uuidString: "01234567-89ab-4cde-8f01-23456789abcd"))
        let complete = BridgeClient.completeBluetoothOnboardProfileMetadata(
            USBHIDProtocol.OnboardProfileMetadata(
                identifier: identifier,
                name: "Slot 2",
                owner: "OpenSnek"
            )
        )

        XCTAssertEqual(complete?.identifier, identifier)
        XCTAssertEqual(complete?.name, "Slot 2")
        XCTAssertEqual(complete?.owner, "OpenSnek")
        XCTAssertNil(
            BridgeClient.completeBluetoothOnboardProfileMetadata(
                USBHIDProtocol.OnboardProfileMetadata(identifier: nil, name: "Slot 2", owner: "OpenSnek")
            )
        )
        XCTAssertNil(
            BridgeClient.completeBluetoothOnboardProfileMetadata(
                USBHIDProtocol.OnboardProfileMetadata(identifier: identifier, name: nil, owner: "OpenSnek")
            )
        )
        XCTAssertNil(
            BridgeClient.completeBluetoothOnboardProfileMetadata(
                USBHIDProtocol.OnboardProfileMetadata(identifier: identifier, name: "Slot 2", owner: nil)
            )
        )

        let erased = BLEVendorProtocol.parseProfileMetadata(
            [UInt8](repeating: 0xFF, count: BLEVendorProtocol.onboardProfileMetadataLength)
        )
        XCTAssertNil(BridgeClient.completeBluetoothOnboardProfileMetadata(erased))
    }

    func testResolveBluetoothBatteryStateKeepsChargingUnknownWhenStatusMissing() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro),
            vendorRaw: 87,
            vendorStatus: nil,
            usbFallback: nil
        )

        XCTAssertEqual(resolved.percent, 87)
        XCTAssertNil(resolved.charging)
    }

    func testResolveBluetoothBatteryStateFillsOnlyMissingFieldsFromUSBFallback() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro),
            vendorRaw: 240,
            vendorStatus: nil,
            usbFallback: (20, true)
        )

        XCTAssertEqual(resolved.percent, 94)
        XCTAssertEqual(resolved.charging, true)
    }

    func testResolveBluetoothBatteryStateKeepsV3ProChargingUnknownWithoutUSBFallback() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro),
            vendorRaw: 77,
            vendorStatus: 1,
            usbFallback: nil
        )

        XCTAssertEqual(resolved.percent, 77)
        XCTAssertNil(resolved.charging)
    }

    func testResolveBluetoothBatteryStateUsesUSBFallbackWhenVendorBatteryMissing() {
        let resolved = BridgeClient.resolveBluetoothBatteryState(
            device: makeBluetoothDevice(productID: 0x00AC, profileID: .basiliskV3Pro),
            vendorRaw: nil,
            vendorStatus: 0,
            usbFallback: (64, true)
        )

        XCTAssertEqual(resolved.percent, 64)
        XCTAssertEqual(resolved.charging, true)
    }

    func testSupportedBluetoothFallbackUsesResolvedProfile() {
        let summary = BLEVendorTransportClient.ConnectedPeripheralSummary(
            name: "Razer Basilisk V3 X HyperSpeed",
            identifier: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        )

        let device = BridgeClient.makeBluetoothFallbackDevice(summary: summary)

        XCTAssertEqual(device.vendor_id, 0x068E)
        XCTAssertEqual(device.product_id, 0x00BA)
        XCTAssertEqual(device.profile_id, .basiliskV3XHyperspeed)
        XCTAssertEqual(device.product_name, "Razer Basilisk V3 X HyperSpeed")
        XCTAssertEqual(device.transport, .bluetooth)
        XCTAssertNotNil(device.button_layout)
    }

    func testSupportedBluetoothFallbackUsesResolvedProfileForBasiliskV3ProAlias() {
        let summary = BLEVendorTransportClient.ConnectedPeripheralSummary(
            name: "BSK V3 PRO",
            identifier: UUID(uuidString: "99999999-2222-3333-4444-555555555555")!
        )

        let device = BridgeClient.makeBluetoothFallbackDevice(summary: summary)

        XCTAssertEqual(device.vendor_id, 0x068E)
        XCTAssertEqual(device.product_id, 0x00AC)
        XCTAssertEqual(device.profile_id, .basiliskV3Pro)
        XCTAssertEqual(device.product_name, "BSK V3 PRO")
        XCTAssertEqual(device.transport, .bluetooth)
        XCTAssertNotNil(device.button_layout)
    }

    func testUnsupportedBluetoothFallbackRemainsGeneric() {
        let summary = BLEVendorTransportClient.ConnectedPeripheralSummary(
            name: "Razer Cobra Pro",
            identifier: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        )

        let device = BridgeClient.makeBluetoothFallbackDevice(summary: summary)

        XCTAssertEqual(device.vendor_id, 0x068E)
        XCTAssertEqual(device.product_id, 0x0000)
        XCTAssertNil(device.profile_id)
        XCTAssertEqual(device.product_name, "Razer Cobra Pro")
        XCTAssertEqual(device.transport, .bluetooth)
        XCTAssertNil(device.button_layout)
        XCTAssertFalse(device.supports_advanced_lighting_effects)
    }

    func testPreferredBluetoothControlWarmupNameUsesResolvedProfile() {
        let preferredName = BridgeClient.preferredBluetoothControlWarmupName(
            vendorID: 0x068E,
            productID: 0x00BA,
            transport: .bluetooth
        )

        XCTAssertEqual(preferredName, "Basilisk V3 X HyperSpeed")
    }

    func testPreferredBluetoothControlWarmupNameUsesResolvedProfileForBasiliskV3Pro() {
        let preferredName = BridgeClient.preferredBluetoothControlWarmupName(
            vendorID: 0x068E,
            productID: 0x00AC,
            transport: .bluetooth
        )

        XCTAssertEqual(preferredName, "Basilisk V3 Pro")
    }

    func testPreferredBluetoothControlWarmupNameSkipsNonBluetoothDevices() {
        let preferredName = BridgeClient.preferredBluetoothControlWarmupName(
            vendorID: 0x1532,
            productID: 0x00B9,
            transport: .usb
        )

        XCTAssertNil(preferredName)
    }
}

private actor AsyncTestFlag {
    private(set) var value = false

    func set() {
        value = true
    }
}

private actor AsyncTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

private func waitUntil(
    timeout: TimeInterval = 1.0,
    pollInterval: UInt64 = 10_000_000,
    _ predicate: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await predicate() {
            return
        }
        try await Task.sleep(nanoseconds: pollInterval)
    }
    XCTFail("Timed out waiting for condition")
}
