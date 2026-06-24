import Foundation
import XCTest
import OpenSnekCore
import OpenSnekProtocols
@testable import OpenSnekHardware
@testable import OpenSnek

/// Exercises USB passive DPI parser merge behavior.
final class USBPassiveDPIParserMergeTests: XCTestCase {
    func testPassiveDPIParserAcceptsObservedUSBAndBluetoothFrames() throws {
        let v3XUSBDescriptor = try XCTUnwrap(
            DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00B9, transport: .usb)?.passiveDPIInput
        )
        let v3XUSBObserved800 = PassiveDPIParser.parse(
            report: [0x05, 0x02, 0x03, 0x20, 0x03, 0x20, 0x00, 0x00],
            descriptor: v3XUSBDescriptor
        )
        let descriptor = try XCTUnwrap(
            DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00AB, transport: .usb)?.passiveDPIInput
        )

        let staged800 = PassiveDPIParser.parse(
            report: [0x05, 0x02, 0x03, 0x20, 0x03, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            descriptor: descriptor
        )
        let staged2000 = PassiveDPIParser.parse(
            report: [0x05, 0x02, 0x07, 0xD0, 0x07, 0xD0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            descriptor: descriptor
        )
        let staged1100 = PassiveDPIParser.parse(
            report: [0x02, 0x04, 0x4C, 0x04, 0x4C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            descriptor: descriptor
        )
        let shortObservedFrame = PassiveDPIParser.parse(
            report: [0x05, 0x02, 0x04, 0x4C, 0x04, 0x4C, 0x00, 0x00],
            descriptor: descriptor
        )
        let usb35KDescriptor = try XCTUnwrap(
            DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00CB, transport: .usb)?.passiveDPIInput
        )
        let usb35KObserved1600 = PassiveDPIParser.parse(
            report: [0x05, 0x02, 0x06, 0x40, 0x06, 0x40, 0x00, 0x00],
            descriptor: usb35KDescriptor
        )
        let bluetoothDescriptor = try XCTUnwrap(
            DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00BA, transport: .bluetooth)?.passiveDPIInput
        )
        let bluetoothDuplicatedReportID = PassiveDPIParser.parse(
            report: [0x05, 0x05, 0x02, 0x07, 0xD0, 0x07, 0xD0, 0x00, 0x00],
            descriptor: bluetoothDescriptor
        )
        let bluetoothSingleReportID = PassiveDPIParser.parse(
            report: [0x05, 0x02, 0x03, 0x20, 0x03, 0x20, 0x00, 0x00, 0x00],
            descriptor: bluetoothDescriptor
        )
        let bluetoothV3ProDescriptor = try XCTUnwrap(
            DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00AC, transport: .bluetooth)?.passiveDPIInput
        )
        let bluetoothV3ProObserved900 = PassiveDPIParser.parse(
            report: [0x05, 0x05, 0x02, 0x03, 0x84, 0x03, 0x84, 0x00, 0x00],
            descriptor: bluetoothV3ProDescriptor
        )
        let bluetoothV3ProObserved1100 = PassiveDPIParser.parse(
            report: [0x05, 0x05, 0x02, 0x04, 0x4C, 0x04, 0x4C, 0x00, 0x00],
            descriptor: bluetoothV3ProDescriptor
        )

        XCTAssertEqual(v3XUSBObserved800, PassiveDPIReading(dpiX: 800, dpiY: 800))
        XCTAssertEqual(staged800, PassiveDPIReading(dpiX: 800, dpiY: 800))
        XCTAssertEqual(staged2000, PassiveDPIReading(dpiX: 2000, dpiY: 2000))
        XCTAssertEqual(staged1100, PassiveDPIReading(dpiX: 1100, dpiY: 1100))
        XCTAssertEqual(shortObservedFrame, PassiveDPIReading(dpiX: 1100, dpiY: 1100))
        XCTAssertEqual(usb35KObserved1600, PassiveDPIReading(dpiX: 1600, dpiY: 1600))
        XCTAssertEqual(bluetoothDuplicatedReportID, PassiveDPIReading(dpiX: 2000, dpiY: 2000))
        XCTAssertEqual(bluetoothSingleReportID, PassiveDPIReading(dpiX: 800, dpiY: 800))
        XCTAssertEqual(bluetoothV3ProObserved900, PassiveDPIReading(dpiX: 900, dpiY: 900))
        XCTAssertEqual(bluetoothV3ProObserved1100, PassiveDPIReading(dpiX: 1100, dpiY: 1100))
    }

    func testPassiveUSBParserRejectsInvalidSubtypeAndOutOfRangeValues() throws {
        let descriptor = try XCTUnwrap(
            DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00AB, transport: .usb)?.passiveDPIInput
        )

        let wrongSubtype = PassiveDPIParser.parse(
            report: [0x05, 0x03, 0x03, 0x20, 0x03, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            descriptor: descriptor
        )
        let outOfRange = PassiveDPIParser.parse(
            report: [0x05, 0x02, 0x00, 0x32, 0x00, 0x32, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            descriptor: descriptor
        )

        XCTAssertNil(wrongSubtype)
        XCTAssertNil(outOfRange)
    }

    func testPassiveBluetoothParserClassifiesHeartbeatFramesSeparatelyFromDpiFrames() throws {
        let descriptor = try XCTUnwrap(
            DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00BA, transport: .bluetooth)?.passiveDPIInput
        )

        let heartbeat = PassiveDPIParser.classify(
            report: [0x05, 0x05, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            descriptor: descriptor
        )
        let dpi = PassiveDPIParser.classify(
            report: [0x05, 0x05, 0x02, 0x04, 0x4C, 0x04, 0x4C, 0x00, 0x00],
            descriptor: descriptor
        )
        let other = PassiveDPIParser.classify(
            report: [0x01, 0x00, 0x00, 0x00, 0x00, 0x00],
            descriptor: descriptor
        )

        XCTAssertEqual(heartbeat, .heartbeat)
        XCTAssertEqual(dpi, .dpi(PassiveDPIReading(dpiX: 1100, dpiY: 1100)))
        XCTAssertEqual(other, .other)
    }

    func testPassiveParserClassifiesUSBProfileSwitchReportDirectly() throws {
        let usbDescriptor = try XCTUnwrap(
            DeviceProfiles.resolve(vendorID: 0x1532, productID: 0x00AB, transport: .usb)?.passiveDPIInput
        )

        XCTAssertEqual(
            PassiveDPIParser.classify(
                report: [0x05, 0x39, 0x00, 0x00, 0x00, 0x00],
                descriptor: usbDescriptor
            ),
            .profileSwitch
        )
    }

    func testPassiveParserRequiresBluetoothProfileSwitchPrelude() throws {
        let bluetoothDescriptor = try XCTUnwrap(
            DeviceProfiles.resolve(vendorID: 0x068E, productID: 0x00AC, transport: .bluetooth)?.passiveDPIInput
        )

        XCTAssertTrue(
            PassiveDPIParser.matchesProfileSwitchPrelude(
                report: [0x04, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
                descriptor: bluetoothDescriptor
            )
        )
        XCTAssertEqual(
            PassiveDPIParser.classify(
                report: [0x05, 0x05, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
                descriptor: bluetoothDescriptor
            ),
            .other
        )
        XCTAssertEqual(
            PassiveDPIParser.classify(
                report: [0x05, 0x05, 0x39, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00],
                descriptor: bluetoothDescriptor,
                profileSwitchPreludeSatisfied: true
            ),
            .other
        )
        XCTAssertEqual(
            PassiveDPIParser.classify(
                report: [0x05, 0x05, 0x39, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
                descriptor: bluetoothDescriptor,
                profileSwitchPreludeSatisfied: true
            ),
            .profileSwitch
        )
    }

    func testPassiveUSBMergeUpdatesActiveStageOnlyForUniqueMatch() {
        let device = makePassiveTestDevice(id: "usb-passive-merge", transport: .usb)
        let uniquePrevious = makePassiveTestState(
            device: device,
            dpiValues: [800, 900, 2000, 1100, 1200],
            activeStage: 0,
            dpiValue: 800
        )
        let duplicatePrevious = makePassiveTestState(
            device: device,
            dpiValues: [800, 2000, 2000],
            activeStage: 0,
            dpiValue: 800
        )
        let event = PassiveDPIEvent(deviceID: device.id, dpiX: 2000, dpiY: 2000, observedAt: Date())
        let uniqueMatch = mergedStateFromPassiveDpiEvent(
            previous: uniquePrevious,
            event: event
        )
        let duplicateMatch = mergedStateFromPassiveDpiEvent(
            previous: duplicatePrevious,
            event: event
        )

        XCTAssertFalse(LocalBridgeBackend.passiveDpiEventHasAmbiguousStageMatch(previous: uniquePrevious, event: event))
        XCTAssertTrue(LocalBridgeBackend.passiveDpiEventHasAmbiguousStageMatch(previous: duplicatePrevious, event: event))
        XCTAssertEqual(uniqueMatch?.dpi?.x, 2000)
        XCTAssertEqual(uniqueMatch?.dpi_stages.active_stage, 2)
        XCTAssertEqual(duplicateMatch?.dpi?.x, 2000)
        XCTAssertEqual(duplicateMatch?.dpi_stages.active_stage, 0)
        XCTAssertEqual(duplicateMatch?.dpi_stages.values, [800, 2000, 2000])
        XCTAssertEqual(
            duplicateMatch?.dpi_stages.pairs,
            [800, 2000, 2000].map { DpiPair(x: $0, y: $0) }
        )
    }

    func testPassiveUSBMergeTreatsDuplicateDpiStageMatchAsAmbiguous() {
        let device = makePassiveTestDevice(id: "usb-passive-merge-duplicate", transport: .usb)
        let duplicatePrevious = makePassiveTestState(
            device: device,
            dpiValues: [800, 2000, 2000],
            activeStage: 0,
            dpiValue: 800
        )
        let event = PassiveDPIEvent(deviceID: device.id, dpiX: 2000, dpiY: 2000, observedAt: Date())
        let duplicateMatch = mergedStateFromPassiveDpiEvent(
            previous: duplicatePrevious,
            event: event
        )

        XCTAssertEqual(duplicateMatch?.dpi?.x, 2000)
        XCTAssertEqual(duplicateMatch?.dpi_stages.active_stage, 0)
        XCTAssertTrue(LocalBridgeBackend.passiveDpiEventHasAmbiguousStageMatch(previous: duplicatePrevious, event: event))
        XCTAssertEqual(duplicateMatch?.dpi_stages.values, [800, 2000, 2000])
        XCTAssertEqual(
            duplicateMatch?.dpi_stages.pairs,
            [800, 2000, 2000].map { DpiPair(x: $0, y: $0) }
        )
    }

    func testPassiveUSBMergeDoesNotRewriteStageTableWhenDpiDoesNotMatchAStage() {
        let device = makePassiveTestDevice(id: "usb-passive-merge-unmatched", transport: .usb)
        let previous = makePassiveTestState(
            device: device,
            dpiValues: [800, 900, 1000],
            activeStage: 1,
            dpiValue: 900
        )
        let event = PassiveDPIEvent(deviceID: device.id, dpiX: 1500, dpiY: 1500, observedAt: Date())

        let merged = mergedStateFromPassiveDpiEvent(previous: previous, event: event)

        XCTAssertEqual(merged?.dpi?.x, 1500)
        XCTAssertEqual(merged?.dpi_stages.active_stage, 1)
        XCTAssertEqual(merged?.dpi_stages.values, [800, 900, 1000])
        XCTAssertEqual(
            merged?.dpi_stages.pairs,
            [800, 900, 1000].map { DpiPair(x: $0, y: $0) }
        )
        XCTAssertTrue(LocalBridgeBackend.passiveDpiEventHasAmbiguousStageMatch(previous: previous, event: event))
    }

    func testPassiveUSBMergeDropsEventWithoutSeededState() {
        let merged = mergedStateFromPassiveDpiEvent(
            previous: nil,
            event: PassiveDPIEvent(deviceID: "missing", dpiX: 1100, dpiY: 1100, observedAt: Date())
        )

        XCTAssertNil(merged)
    }

    func testPassiveUSBFallbackSeedStateBootstrapsHidOnlyMonitoring() {
        let device = makePassiveTestDevice(id: "usb-passive-seed", transport: .usb)
        let event = PassiveDPIEvent(deviceID: device.id, dpiX: 1100, dpiY: 1100, observedAt: Date())

        let seeded = LocalBridgeBackend.seededStateForPassiveDpiEvent(device: device, event: event)

        XCTAssertEqual(seeded.device.id, device.id)
        XCTAssertEqual(seeded.connection, "USB")
        XCTAssertEqual(seeded.dpi?.x, 1100)
        XCTAssertEqual(seeded.dpi_stages.active_stage, 0)
        XCTAssertEqual(seeded.dpi_stages.values, [1100])
        XCTAssertEqual(seeded.onboard_profile_count, device.onboard_profile_count)
        XCTAssertTrue(seeded.capabilities.dpi_stages)
        XCTAssertTrue(seeded.capabilities.poll_rate)
    }

    func testPassiveUSBFallbackSeedStateKeepsSingleObservedStageFreshAcrossHidOnlyEvents() {
        let device = makePassiveTestDevice(id: "usb-passive-seed-refresh", transport: .usb)
        let firstEvent = PassiveDPIEvent(deviceID: device.id, dpiX: 1100, dpiY: 1100, observedAt: Date())
        let seeded = LocalBridgeBackend.seededStateForPassiveDpiEvent(device: device, event: firstEvent)

        let merged = mergedStateFromPassiveDpiEvent(
            previous: seeded,
            event: PassiveDPIEvent(deviceID: device.id, dpiX: 1600, dpiY: 1600, observedAt: Date())
        )

        XCTAssertEqual(merged?.dpi?.x, 1600)
        XCTAssertEqual(merged?.dpi_stages.active_stage, 0)
        XCTAssertEqual(merged?.dpi_stages.values, [1600])
    }

    func testBluetoothPassiveDpiExpectationUsesUniqueMatchedStage() {
        let device = makePassiveTestDevice(id: "bt-passive-expected", transport: .bluetooth)
        let event = PassiveDPIEvent(deviceID: device.id, dpiX: 1100, dpiY: 1100, observedAt: Date())
        let expectationFromSnapshot = BridgeClient.bluetoothPassiveDpiExpectation(
            event: event,
            snapshot: BLEVendorProtocol.DpiStageSnapshot(
                active: 0,
                count: 5,
                slots: [800, 900, 1000, 1100, 1500],
                pairs: [800, 900, 1000, 1100, 1500].map { DpiPair(x: $0, y: $0) },
                stageIDs: [1, 2, 3, 4, 5],
                marker: 0x03
            ),
            state: nil
        )
        let expectationFromState = BridgeClient.bluetoothPassiveDpiExpectation(
            event: event,
            snapshot: nil,
            state: makePassiveTestState(
                device: device,
                dpiValues: [800, 900, 1000, 1100, 1500],
                activeStage: 0,
                dpiValue: 800
            )
        )
        let duplicateMatch = BridgeClient.bluetoothPassiveDpiExpectation(
            event: PassiveDPIEvent(deviceID: device.id, dpiX: 2000, dpiY: 2000, observedAt: Date()),
            snapshot: nil,
            state: makePassiveTestState(
                device: device,
                dpiValues: [800, 2000, 2000],
                activeStage: 0,
                dpiValue: 800
            )
        )

        XCTAssertEqual(expectationFromSnapshot?.active, 3)
        XCTAssertEqual(expectationFromSnapshot?.values, [800, 900, 1000, 1100, 1500])
        XCTAssertEqual(expectationFromState?.active, 3)
        XCTAssertNil(duplicateMatch)
    }

}
