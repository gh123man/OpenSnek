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
}
