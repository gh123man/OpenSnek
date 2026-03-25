import Foundation

public enum DevicePersistenceKeys {
    public static func normalizedStableSerial(_ rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let lowered = trimmed.lowercased()
        let alphanumeric = lowered.unicodeScalars.filter(CharacterSet.alphanumerics.contains)
        guard !alphanumeric.isEmpty else { return nil }

        if alphanumeric.allSatisfy({ $0 == "0" }) || alphanumeric.allSatisfy({ $0 == "f" }) {
            return nil
        }

        return lowered
    }

    public static func key(for device: MouseDevice) -> String {
        if let serial = normalizedStableSerial(device.serial) {
            return "serial:\(serial)"
        }
        return String(
            format: "vp:%04x:%04x:%@",
            device.vendor_id,
            device.product_id,
            device.transport.rawValue
        )
    }

    public static func legacyKey(for device: MouseDevice) -> String {
        device.id
    }
}
