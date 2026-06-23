import XCTest
@testable import OpenSnek
import OpenSnekCore

final class BridgeClientUSBWriteSemanticsTests: XCTestCase {
    func testUSBButtonWriteFailsWhenPersistentLayerFails() {
        XCTAssertFalse(
            BridgeClient.usbButtonWriteSucceeded(
                writePersistentLayer: true,
                writeDirectLayer: true,
                wrotePersistent: false,
                wroteDirect: true
            )
        )
    }

    func testUSBButtonWriteFailsWhenDirectLayerFails() {
        XCTAssertFalse(
            BridgeClient.usbButtonWriteSucceeded(
                writePersistentLayer: true,
                writeDirectLayer: true,
                wrotePersistent: true,
                wroteDirect: false
            )
        )
    }

    func testUSBButtonWriteSucceedsWhenOnlyPersistentLayerRequestedAndWritten() {
        XCTAssertTrue(
            BridgeClient.usbButtonWriteSucceeded(
                writePersistentLayer: true,
                writeDirectLayer: false,
                wrotePersistent: true,
                wroteDirect: false
            )
        )
    }

    func testUSBButtonWriteSucceedsWhenOnlyDirectLayerRequestedAndWritten() {
        XCTAssertTrue(
            BridgeClient.usbButtonWriteSucceeded(
                writePersistentLayer: false,
                writeDirectLayer: true,
                wrotePersistent: false,
                wroteDirect: true
            )
        )
    }

    func testOnboardProfileMetadataDefaultsToSynapseCompatibleOwnerHash() {
        let metadata = OnboardProfileMetadata(name: "Slot 2")

        XCTAssertTrue(metadata.hasSynapseCompatibleOwner)
        XCTAssertEqual(metadata.owner.count, 64)
        XCTAssertEqual(
            OnboardProfileMetadata.normalizedOwner("OpenSnek"),
            OnboardProfileMetadata.synapseCompatibleFallbackOwner
        )
    }

    func testPreferredProfileOwnerForWriteUsesExistingHashWhenPreferredIsDefault() {
        let existing = "5ed8944a85a9763fd315852f448cb7de36c5e928e13b3be427f98f7dc455f141"
        let explicit = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

        XCTAssertEqual(
            BridgeClient.preferredProfileOwnerForWrite(
                preferred: OnboardProfileMetadata.synapseCompatibleFallbackOwner,
                existing: existing
            ),
            existing
        )
        XCTAssertEqual(
            BridgeClient.preferredProfileOwnerForWrite(
                preferred: explicit,
                existing: existing
            ),
            explicit
        )
        XCTAssertEqual(
            BridgeClient.preferredProfileOwnerForWrite(
                preferred: "OpenSnek",
                existing: nil
            ),
            OnboardProfileMetadata.synapseCompatibleFallbackOwner
        )
    }

    func testUSBDPIStageWriteArgsCanDeclareLogicalCountWithFixedRows() throws {
        let device = makeRefactorTestDevice(
            id: "usb-dpi-stage-write-args",
            transport: .usb,
            serial: "USB-DPI-STAGE-WRITE-ARGS",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )

        let args = try XCTUnwrap(BridgeClient.usbDPIStageWriteArgs(
            profileID: 0x02,
            activeStage: 0,
            pairs: [
                DpiPair(x: 800, y: 800),
                DpiPair(x: 1600, y: 1600),
                DpiPair(x: 3200, y: 3200)
            ],
            stageIDs: nil,
            device: device
        ))

        XCTAssertEqual(args.count, 38)
        XCTAssertEqual(args[0], 0x02)
        XCTAssertEqual(args[1], 0x00)
        XCTAssertEqual(args[2], 0x03)
        XCTAssertEqual(
            Array(args.dropFirst(3)),
            [
                0x00, 0x03, 0x20, 0x03, 0x20, 0x00, 0x00,
                0x01, 0x06, 0x40, 0x06, 0x40, 0x00, 0x00,
                0x02, 0x0C, 0x80, 0x0C, 0x80, 0x00, 0x00,
                0x03, 0x0C, 0x80, 0x0C, 0x80, 0x00, 0x00,
                0x04, 0x0C, 0x80, 0x0C, 0x80, 0x00, 0x00
            ]
        )
    }

    func testUSBDPIStageWriteArgsCanDeclareFixedRowsForStoredProfileWrites() throws {
        let device = makeRefactorTestDevice(
            id: "usb-dpi-stage-write-args-fixed-count",
            transport: .usb,
            serial: "USB-DPI-STAGE-WRITE-ARGS-FIXED-COUNT",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )

        let args = try XCTUnwrap(BridgeClient.usbDPIStageWriteArgs(
            profileID: 0x02,
            activeStage: 0,
            pairs: [
                DpiPair(x: 800, y: 800),
                DpiPair(x: 1600, y: 1600),
                DpiPair(x: 3200, y: 3200)
            ],
            stageIDs: nil,
            device: device,
            declaredCountMode: .fixedRowCount
        ))

        XCTAssertEqual(args.count, 38)
        XCTAssertEqual(args[0], 0x02)
        XCTAssertEqual(args[1], 0x00)
        XCTAssertEqual(args[2], 0x05)
        XCTAssertEqual(
            Array(args.dropFirst(3)),
            [
                0x00, 0x03, 0x20, 0x03, 0x20, 0x00, 0x00,
                0x01, 0x06, 0x40, 0x06, 0x40, 0x00, 0x00,
                0x02, 0x0C, 0x80, 0x0C, 0x80, 0x00, 0x00,
                0x03, 0x0C, 0x80, 0x0C, 0x80, 0x00, 0x00,
                0x04, 0x0C, 0x80, 0x0C, 0x80, 0x00, 0x00
            ]
        )
    }

    func testUSBStoredProfileDPIWriteSnapshotKeepsSlotActiveTokenForReducedProfiles() throws {
        let requested = OnboardDPIProfileSnapshot(
            scalar: DpiPair(x: 800, y: 800),
            activeStage: 0,
            pairs: [
                DpiPair(x: 800, y: 800),
                DpiPair(x: 1600, y: 1600),
                DpiPair(x: 3200, y: 3200)
            ]
        )
        let context = OnboardDPIProfileSnapshot(
            scalar: DpiPair(x: 1000, y: 1000),
            activeStage: 2,
            pairs: [
                DpiPair(x: 1200, y: 1200),
                DpiPair(x: 800, y: 800),
                DpiPair(x: 1000, y: 1000),
                DpiPair(x: 1200, y: 1200),
                DpiPair(x: 1400, y: 1400)
            ],
            stageIDs: [0x00, 0x01, 0x02, 0x03, 0x04]
        )
        let device = makeRefactorTestDevice(
            id: "usb-dpi-stage-write-context",
            transport: .usb,
            serial: "USB-DPI-STAGE-WRITE-CONTEXT",
            onboardProfileCount: 5,
            profileID: .basiliskV3Pro
        )

        let adapted = BridgeClient.usbStoredProfileDPIWriteSnapshot(
            requested: requested,
            slotContext: context
        )
        let args = try XCTUnwrap(BridgeClient.usbDPIStageWriteArgs(
            profileID: 0x02,
            activeStage: adapted.activeStage ?? 0,
            pairs: adapted.pairs,
            stageIDs: adapted.stageIDs,
            device: device,
            declaredCountMode: .fixedRowCount
        ))

        XCTAssertEqual(adapted.scalar, DpiPair(x: 800, y: 800))
        XCTAssertEqual(adapted.activeStage, 2)
        XCTAssertEqual(adapted.pairs, [
            DpiPair(x: 800, y: 800),
            DpiPair(x: 1600, y: 1600),
            DpiPair(x: 3200, y: 3200),
            DpiPair(x: 1200, y: 1200),
            DpiPair(x: 1400, y: 1400)
        ])
        XCTAssertEqual(adapted.stageIDs, [0x00, 0x01, 0x02, 0x03, 0x04])
        XCTAssertEqual(Array(args.prefix(3)), [0x02, 0x02, 0x05])
    }
}
