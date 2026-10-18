import Foundation
import OpenSnekCore
import OpenSnekProtocols

/// Rejects incomplete or malformed stage tables before either test writes or journal recovery.
enum HardwareDPIBaseline {
    static func validate(_ payload: Data, range: ClosedRange<Int>) throws -> Data {
        guard (36...38).contains(payload.count), (1...DeviceProfiles.maximumDpiStageCount).contains(Int(payload[1])), let parsed = BLEVendorProtocol.parseDpiStageSnapshot(blob: payload), parsed.pairs.prefix(parsed.count).allSatisfy({ range.contains($0.x) && range.contains($0.y) }),
            Set(parsed.stageIDs.prefix(parsed.count)).count == parsed.count, parsed.stageIDs.prefix(parsed.count).contains(payload[0])
        else { throw HardwareValidationSession.failure("A complete, valid DPI baseline is required; no writes sent") }
        return payload
    }
}

/// Requires explicit hardware identity and a named recovery journal before destructive tests.
struct HardwareValidationScope {
    let deviceID: String
    let journalURL: URL
    let isRecovery: Bool

    init(environment: [String: String]) throws {
        guard let deviceID = environment["OPEN_SNEK_HW_DEVICE_ID"], !deviceID.isEmpty else { throw HardwareValidationSession.failure("Set OPEN_SNEK_HW_DEVICE_ID to an exact discovered device ID; choosing the first device is forbidden.") }
        let recovery = environment["OPEN_SNEK_HW_RECOVER_JOURNAL"]
        guard let path = recovery ?? environment["OPEN_SNEK_HW_JOURNAL"], !path.isEmpty else { throw HardwareValidationSession.failure("Set OPEN_SNEK_HW_JOURNAL to a new absolute recovery-journal path.") }
        guard path.hasPrefix("/") else { throw HardwareValidationSession.failure("The hardware journal path must be absolute") }
        self.deviceID = deviceID
        self.journalURL = URL(fileURLWithPath: path)
        self.isRecovery = recovery != nil
    }

    func select(from devices: [MouseDevice], transport: DeviceTransportKind) throws -> MouseDevice {
        let matches = devices.filter { $0.id == deviceID && $0.transport == transport }
        guard matches.count == 1, let selected = matches.first else { throw HardwareValidationSession.failure("The exact requested hardware device is not connected on the expected transport; no writes sent.") }
        return selected
    }
}

/// Durable recovery state written before a hardware test is allowed to mutate a device.
struct HardwareValidationJournal<Snapshot: Codable & Sendable>: Codable, Sendable {
    /// Describes whether restoration still requires operator attention.
    enum Phase: String, Codable, Sendable { case prepared, restoring, restored, restoreFailed }

    let schemaVersion: Int
    let deviceID: String
    let original: Snapshot
    var phase: Phase

    static func load(from url: URL) throws -> Self {
        let journal = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard journal.schemaVersion == 1 else { throw HardwareValidationSession.failure("Unknown journal schema at \(url.path)") }
        return journal
    }

    func save(to url: URL, create: Bool = false) throws {
        let data = try JSONEncoder().encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: create ? .withoutOverwriting : .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.synchronize()
    }
}

/// Runs hardware mutations with a journaled baseline, mandatory restore, and authoritative verification.
@MainActor enum HardwareValidationSession {
    static func run<Snapshot: Codable & Equatable & Sendable>(deviceID: String, journalURL: URL, read: () async throws -> Snapshot, restore: (Snapshot) async throws -> Void, operation: () async throws -> Void) async throws {
        guard !FileManager.default.fileExists(atPath: journalURL.path) else { throw failure("Journal already exists: \(journalURL.path). Recover or archive it before another run.") }
        let original = try await read()
        let journal = HardwareValidationJournal(schemaVersion: 1, deviceID: deviceID, original: original, phase: .prepared)
        try journal.save(to: journalURL, create: true)
        var operationError: Error?
        do { try await operation() } catch { operationError = error }
        do { try await restoreAndVerify(journal, journalURL: journalURL, read: read, restore: restore) } catch { throw failure("Restoration failed; retain \(journalURL.path). Operation: \(operationError?.localizedDescription ?? "passed"). Restore: \(error.localizedDescription)") }
        if let operationError { throw operationError }
    }

    static func recover<Snapshot: Codable & Equatable & Sendable>(deviceID: String, journalURL: URL, read: () async throws -> Snapshot, restore: (Snapshot) async throws -> Void) async throws {
        let journal = try HardwareValidationJournal<Snapshot>.load(from: journalURL)
        guard journal.deviceID == deviceID else { throw failure("Recovery device does not match the journal; no writes sent.") }
        try await restoreAndVerify(journal, journalURL: journalURL, read: read, restore: restore)
    }

    private static func restoreAndVerify<Snapshot: Codable & Equatable & Sendable>(_ originalJournal: HardwareValidationJournal<Snapshot>, journalURL: URL, read: () async throws -> Snapshot, restore: (Snapshot) async throws -> Void) async throws {
        var journal = originalJournal
        // Retain the in-memory baseline during a live run: a journal status write must never
        // prevent cleanup. The prepared journal already exists before hardware mutation begins.
        journal.phase = .restoring
        do {
            try await restore(journal.original)
            guard try await read() == journal.original else { throw failure("Restored state does not match the original snapshot") }
            journal.phase = .restored
            try journal.save(to: journalURL)
        } catch {
            journal.phase = .restoreFailed
            try journal.save(to: journalURL)
            throw error
        }
    }

    nonisolated static func failure(_ message: String) -> NSError { NSError(domain: "HardwareValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
