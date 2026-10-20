import Foundation
import OpenSnekCore
import OpenSnekHardware

/// Persists the physical Bluetooth identity separately from the process-local discovery ID.
struct HardwareBluetoothTarget: Codable, Equatable, Sendable {
    let peripheralIdentifier: UUID
    let device: MouseDevice

    static func capture(device: MouseDevice, peripherals: [BLEVendorTransportClient.ConnectedPeripheralSummary]) throws -> Self {
        let matches = peripherals.filter { BluetoothNameMatcher.looselyMatches($0.name, device.product_name) }
        guard device.transport == .bluetooth, matches.count == 1, let peripheral = matches.first else { throw HardwareValidationSession.failure("Disconnect other matching Bluetooth models before selecting the validation target; no writes sent") }
        return Self(peripheralIdentifier: peripheral.identifier, device: device)
    }

    static func recover(from url: URL) throws -> Self {
        // Old Data-only journals cannot prove physical identity. Never guess from their device ID.
        let journal = try HardwareValidationJournal<HardwareBluetoothSnapshot>.load(from: url)
        let target = journal.original.target
        guard target.device.transport == .bluetooth, journal.deviceID == target.peripheralIdentifier.uuidString else { throw HardwareValidationSession.failure("Recovery journal has no matching Bluetooth UUID; no writes sent") }
        _ = try HardwareDPIBaseline.validate(journal.original.payload, range: DeviceProfiles.dpiRange(for: target.device))
        return target
    }
}

/// Keeps recovery metadata and the exact original stage bytes in one durable snapshot.
struct HardwareBluetoothSnapshot: Codable, Equatable, Sendable {
    let target: HardwareBluetoothTarget
    let payload: Data
}
