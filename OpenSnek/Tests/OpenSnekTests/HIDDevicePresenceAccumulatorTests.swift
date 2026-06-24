import XCTest
import OpenSnekCore
import OpenSnekHardware

/// Exercises HID device presence accumulator behavior.
final class HIDDevicePresenceAccumulatorTests: XCTestCase {
    func testCompositeDeviceDisconnectEmitsOnlyAfterLastInterfaceLeaves() {
        var accumulator = HIDDevicePresenceAccumulator()
        let deviceID = "1532:00ab:00130000:usb"

        let firstConnect = accumulator.reducedEvent(
            deviceID: deviceID,
            interfaceToken: "interface-a",
            event: presenceEvent(deviceID: deviceID, change: .connected)
        )
        let secondConnect = accumulator.reducedEvent(
            deviceID: deviceID,
            interfaceToken: "interface-b",
            event: presenceEvent(deviceID: deviceID, change: .connected)
        )
        let firstDisconnect = accumulator.reducedEvent(
            deviceID: deviceID,
            interfaceToken: "interface-a",
            event: presenceEvent(deviceID: deviceID, change: .disconnected)
        )
        let secondDisconnect = accumulator.reducedEvent(
            deviceID: deviceID,
            interfaceToken: "interface-b",
            event: presenceEvent(deviceID: deviceID, change: .disconnected)
        )

        XCTAssertEqual(firstConnect?.change, .connected)
        XCTAssertNil(secondConnect)
        XCTAssertNil(firstDisconnect)
        XCTAssertEqual(secondDisconnect?.change, .disconnected)
    }

    func testUnknownInterfaceDisconnectIsIgnored() {
        var accumulator = HIDDevicePresenceAccumulator()
        let deviceID = "1532:00ab:00130000:usb"

        let event = accumulator.reducedEvent(
            deviceID: deviceID,
            interfaceToken: "interface-a",
            event: presenceEvent(deviceID: deviceID, change: .disconnected)
        )

        XCTAssertNil(event)
    }

    private func presenceEvent(
        deviceID: String,
        change: HIDDevicePresenceChangeKind
    ) -> HIDDevicePresenceEvent {
        HIDDevicePresenceEvent(
            deviceID: deviceID,
            vendorID: 0x1532,
            productID: 0x00AB,
            locationID: 0x00130000,
            transport: .usb,
            change: change,
            observedAt: Date()
        )
    }
}
