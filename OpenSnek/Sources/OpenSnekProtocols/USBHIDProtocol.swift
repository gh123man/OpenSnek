import Foundation

public enum USBHIDProtocol {
    public struct OnboardProfileMetadata: Equatable, Sendable {
        public let identifier: UUID?
        public let name: String?
        public let owner: String?

        public init(identifier: UUID?, name: String?, owner: String?) {
            self.identifier = identifier
            self.name = name
            self.owner = owner
        }
    }

    public struct OnboardProfileMetadataChunk: Equatable, Sendable {
        public let slot: UInt8
        public let offset: Int
        public let totalLength: Int
        public let data: [UInt8]

        public init(slot: UInt8, offset: Int, totalLength: Int, data: [UInt8]) {
            self.slot = slot
            self.offset = offset
            self.totalLength = totalLength
            self.data = data
        }
    }

    public static let onboardProfileMetadataLength = 0xFA
    public static let onboardProfileMetadataReadSize: UInt8 = 0x50

    public static func createReport(txn: UInt8, classID: UInt8, cmdID: UInt8, size: UInt8, args: [UInt8]) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: 90)
        report[0] = 0x00
        report[1] = txn
        report[5] = size
        report[6] = classID
        report[7] = cmdID
        for (idx, value) in args.prefix(80).enumerated() {
            report[8 + idx] = value
        }
        report[88] = crc(for: report)
        return report
    }

    public static func crc(for report: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        guard report.count >= 88 else { return crc }
        for i in 2..<88 {
            crc ^= report[i]
        }
        return crc
    }

    public static func normalizeResponseBytes(_ raw: [UInt8]) -> [UInt8]? {
        if raw.count == 91 {
            return Array(raw.dropFirst())
        }
        if raw.count == 90 {
            return raw
        }
        if raw.count > 90 {
            return Array(raw.suffix(90))
        }
        return nil
    }

    public static func isValidResponse(_ response: [UInt8], txn: UInt8? = nil, classID: UInt8, cmdID: UInt8) -> Bool {
        guard response.count >= 90 else { return false }
        if let txn, response[1] != txn { return false }
        guard response[6] == classID else { return false }
        guard (response[7] & 0x7F) == (cmdID & 0x7F) else { return false }
        return response[88] == crc(for: response)
    }

    public static func onboardProfileMetadataReadArgs(
        slot: UInt8,
        offset: Int,
        totalLength: Int = onboardProfileMetadataLength
    ) -> [UInt8] {
        let clampedOffset = max(0, min(0xFFFF, offset))
        let clampedLength = max(0, min(0xFFFF, totalLength))
        return [
            slot,
            UInt8((clampedOffset >> 8) & 0xFF),
            UInt8(clampedOffset & 0xFF),
            UInt8((clampedLength >> 8) & 0xFF),
            UInt8(clampedLength & 0xFF),
        ]
    }

    public static func onboardProfileMetadataChunk(
        from response: [UInt8],
        expectedSlot: UInt8? = nil,
        expectedOffset: Int? = nil
    ) -> OnboardProfileMetadataChunk? {
        guard response.count >= 13, response[0] == 0x02 else { return nil }
        guard response[6] == 0x05, response[7] == 0x88 else { return nil }
        let argCount = max(0, min(Int(response[5]), min(80, response.count - 8)))
        guard argCount >= 5 else { return nil }

        let slot = response[8]
        let offset = (Int(response[9]) << 8) | Int(response[10])
        let totalLength = (Int(response[11]) << 8) | Int(response[12])
        guard totalLength > 0 else { return nil }
        if let expectedSlot, slot != expectedSlot { return nil }
        if let expectedOffset, offset != expectedOffset { return nil }

        let dataStart = 13
        let dataEnd = 8 + argCount
        let data = dataStart < dataEnd ? Array(response[dataStart..<dataEnd]) : []
        return OnboardProfileMetadataChunk(
            slot: slot,
            offset: offset,
            totalLength: totalLength,
            data: data
        )
    }

    public static func mergeOnboardProfileMetadataChunks(_ chunks: [OnboardProfileMetadataChunk]) -> [UInt8] {
        let totalLength = chunks.map(\.totalLength).filter { $0 > 0 }.max() ?? onboardProfileMetadataLength
        let minimumLength = chunks.map { $0.offset + $0.data.count }.max() ?? totalLength
        var metadata = [UInt8](repeating: 0x00, count: max(totalLength, minimumLength))

        for chunk in chunks.sorted(by: { $0.offset < $1.offset }) {
            guard chunk.offset >= 0 else { continue }
            let end = chunk.offset + chunk.data.count
            if end > metadata.count {
                metadata.append(contentsOf: [UInt8](repeating: 0x00, count: end - metadata.count))
            }
            for (index, byte) in chunk.data.enumerated() {
                metadata[chunk.offset + index] = byte
            }
        }

        return metadata
    }

    public static func parseOnboardProfileMetadata(_ bytes: [UInt8]) -> OnboardProfileMetadata {
        OnboardProfileMetadata(
            identifier: uuidFromWindowsGUIDBytes(bytes),
            name: asciiField(in: bytes, offset: 0x10, maxLength: 0x74 - 0x10),
            owner: asciiField(in: bytes, offset: 0x74, maxLength: 64)
        )
    }

    public static func uuidFromWindowsGUIDBytes(_ bytes: [UInt8]) -> UUID? {
        guard bytes.count >= 16 else { return nil }
        let raw = Array(bytes.prefix(16))
        guard raw.contains(where: { $0 != 0x00 }) else { return nil }
        let uuidBytes = [
            raw[3], raw[2], raw[1], raw[0],
            raw[5], raw[4],
            raw[7], raw[6],
            raw[8], raw[9], raw[10], raw[11],
            raw[12], raw[13], raw[14], raw[15],
        ]
        return UUID(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }

    private static func asciiField(in bytes: [UInt8], offset: Int, maxLength: Int) -> String? {
        guard offset >= 0, maxLength > 0, offset < bytes.count else { return nil }
        let end = min(bytes.count, offset + maxLength)
        let raw = Array(bytes[offset..<end].prefix { $0 != 0x00 })
        guard !raw.isEmpty, raw.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) else {
            return nil
        }
        return String(bytes: raw, encoding: .ascii)
    }
}
