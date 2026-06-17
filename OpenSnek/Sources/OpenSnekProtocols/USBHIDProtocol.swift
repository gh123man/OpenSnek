import Foundation
import OpenSnekCore

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

    public struct OnboardProfileInventory: Equatable, Sendable {
        public let maxProfileID: UInt8
        public let assignedProfiles: [UInt8]

        public init(maxProfileID: UInt8, assignedProfiles: [UInt8]) {
            self.maxProfileID = maxProfileID
            self.assignedProfiles = assignedProfiles
        }
    }

    public struct LightingEffectState: Equatable, Sendable {
        public let storageEcho: UInt8
        public let ledID: UInt8
        public let effectID: UInt8
        public let payload: [UInt8]

        public init(storageEcho: UInt8, ledID: UInt8, effectID: UInt8, payload: [UInt8]) {
            self.storageEcho = storageEcho
            self.ledID = ledID
            self.effectID = effectID
            self.payload = payload
        }

        public var staticColor: RGBPatch? {
            guard effectID == 0x01,
                  payload.count >= 9,
                  payload[5] >= 0x01 else {
                return nil
            }
            return RGBPatch(r: Int(payload[6]), g: Int(payload[7]), b: Int(payload[8]))
        }
    }

    public static let onboardProfileMetadataLength = 0xFA
    public static let onboardProfileMetadataReadSize: UInt8 = 0x50
    public static let onboardProfileMetadataChunkDataLength = Int(onboardProfileMetadataReadSize) - 5
    public static let onboardProfileMetadataKnownFieldLength = 0xB4
    public static let onboardProfileMetadataChunkOffsets = Array(
        stride(
            from: 0,
            to: onboardProfileMetadataLength,
            by: onboardProfileMetadataChunkDataLength
        )
    )
    public static let onboardProfileMetadataWritableChunkOffsets = onboardProfileMetadataChunkOffsets.filter {
        $0 < onboardProfileMetadataKnownFieldLength
    }

    public static func activeProfileID(from response: [UInt8]) -> UInt8? {
        guard response.count > 8,
              response[0] == 0x02,
              response[6] == 0x05,
              response[7] == 0x84 else {
            return nil
        }
        return response[8]
    }

    public static func activeProfileSetArgs(profile: UInt8) -> [UInt8] {
        [profile]
    }

    public static func activeProfileSetAccepted(from response: [UInt8], profile: UInt8) -> Bool {
        guard response.count > 8,
              response[0] == 0x02,
              response[6] == 0x05,
              response[7] == 0x04,
              response[5] >= 0x01 else {
            return false
        }
        return response[8] == profile
    }

    public static func onboardProfileCreateArgs(profile: UInt8) -> [UInt8] {
        [profile]
    }

    public static func onboardProfileCreateAccepted(from response: [UInt8], profile: UInt8) -> Bool {
        guard response.count > 8,
              response[0] == 0x02,
              response[6] == 0x05,
              response[7] == 0x02,
              response[5] >= 0x01 else {
            return false
        }
        return response[8] == profile
    }

    public static func onboardProfileDeleteArgs(profile: UInt8) -> [UInt8] {
        [profile]
    }

    public static func onboardProfileDeleteAccepted(from response: [UInt8], profile: UInt8) -> Bool {
        guard response.count > 8,
              response[0] == 0x02,
              response[6] == 0x05,
              response[7] == 0x03,
              response[5] >= 0x01 else {
            return false
        }
        return response[8] == profile
    }

    public static func onboardProfileCount(from response: [UInt8]) -> UInt8? {
        guard response.count > 8,
              response[0] == 0x02,
              response[6] == 0x05,
              response[7] == 0x80 else {
            return nil
        }
        return response[8]
    }

    public static func onboardProfileInventory(from response: [UInt8]) -> OnboardProfileInventory? {
        guard response.count > 8,
              response[0] == 0x02,
              response[6] == 0x05,
              response[7] == 0x81 else {
            return nil
        }
        let argCount = max(0, min(Int(response[5]), min(80, response.count - 8)))
        guard argCount >= 1 else { return nil }
        let payload = Array(response[8..<(8 + argCount)])
        return OnboardProfileInventory(
            maxProfileID: payload[0],
            assignedProfiles: Array(payload.dropFirst()).filter { $0 != 0x00 }
        )
    }

    public static func profileLightingEffectReadArgs(profile: UInt8, ledID: UInt8) -> [UInt8] {
        [profile, ledID] + [UInt8](repeating: 0x00, count: 10)
    }

    public static func profileLightingStaticColorSetArgs(profile: UInt8, ledID: UInt8, color: RGBPatch) -> [UInt8] {
        [
            profile,
            ledID,
            0x01,
            0x00,
            0x00,
            0x01,
            UInt8(max(0, min(255, color.r))),
            UInt8(max(0, min(255, color.g))),
            UInt8(max(0, min(255, color.b))),
        ]
    }

    public static func profileLightingEffectState(
        from response: [UInt8],
        expectedLEDID: UInt8? = nil
    ) -> LightingEffectState? {
        guard response.count > 10,
              response[0] == 0x02,
              response[6] == 0x0F,
              response[7] == 0x82 else {
            return nil
        }
        let argCount = max(0, min(Int(response[5]), min(80, response.count - 8)))
        guard argCount >= 3 else { return nil }
        let payload = Array(response[8..<(8 + argCount)])
        guard expectedLEDID == nil || payload[1] == expectedLEDID else { return nil }
        return LightingEffectState(
            storageEcho: payload[0],
            ledID: payload[1],
            effectID: payload[2],
            payload: payload
        )
    }

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

    public static func buildOnboardProfileMetadata(
        identifier: UUID,
        name: String,
        owner: String
    ) -> [UInt8] {
        var metadata = [UInt8](repeating: 0x00, count: onboardProfileMetadataLength)
        let guid = windowsGUIDBytes(from: identifier)
        for (index, byte) in guid.enumerated() where index < metadata.count {
            metadata[index] = byte
        }
        writeASCII(
            name,
            into: &metadata,
            offset: 0x10,
            maxLength: 0x74 - 0x10
        )
        writeASCII(
            owner,
            into: &metadata,
            offset: 0x74,
            maxLength: 64
        )
        return metadata
    }

    public static func onboardProfileMetadataWriteArgs(
        slot: UInt8,
        offset: Int,
        metadata: [UInt8]
    ) -> [UInt8] {
        let clampedOffset = max(0, min(onboardProfileMetadataLength, offset))
        let end = min(metadata.count, clampedOffset + onboardProfileMetadataChunkDataLength)
        let chunk = clampedOffset < end ? Array(metadata[clampedOffset..<end]) : []
        var args = [
            slot,
            UInt8((clampedOffset >> 8) & 0xFF),
            UInt8(clampedOffset & 0xFF),
            UInt8((onboardProfileMetadataLength >> 8) & 0xFF),
            UInt8(onboardProfileMetadataLength & 0xFF),
        ]
        args.append(contentsOf: chunk)
        if args.count < Int(onboardProfileMetadataReadSize) {
            args.append(contentsOf: repeatElement(0x00, count: Int(onboardProfileMetadataReadSize) - args.count))
        }
        return Array(args.prefix(Int(onboardProfileMetadataReadSize)))
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
        guard raw.contains(where: { $0 != 0xFF }) else { return nil }
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

    public static func windowsGUIDBytes(from uuid: UUID) -> [UInt8] {
        let bytes = [
            uuid.uuid.0, uuid.uuid.1, uuid.uuid.2, uuid.uuid.3,
            uuid.uuid.4, uuid.uuid.5, uuid.uuid.6, uuid.uuid.7,
            uuid.uuid.8, uuid.uuid.9, uuid.uuid.10, uuid.uuid.11,
            uuid.uuid.12, uuid.uuid.13, uuid.uuid.14, uuid.uuid.15,
        ]
        return [
            bytes[3], bytes[2], bytes[1], bytes[0],
            bytes[5], bytes[4],
            bytes[7], bytes[6],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15],
        ]
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

    private static func writeASCII(_ value: String, into metadata: inout [UInt8], offset: Int, maxLength: Int) {
        guard offset >= 0, maxLength > 0, offset < metadata.count else { return }
        let upperBound = min(metadata.count, offset + maxLength)
        for index in offset..<upperBound {
            metadata[index] = 0x00
        }
        let bytes = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .compactMap { scalar -> UInt8? in
                guard scalar.value >= 0x20, scalar.value <= 0x7E else { return nil }
                return UInt8(scalar.value)
            }
            .prefix(maxLength)
        for (index, byte) in bytes.enumerated() {
            metadata[offset + index] = byte
        }
    }
}
