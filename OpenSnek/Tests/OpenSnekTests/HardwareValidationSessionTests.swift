import XCTest

/// Proves journal-before-write and restoration behavior without physical hardware.
@MainActor final class HardwareValidationSessionTests: XCTestCase {
    func testOperationFailureStillRestoresOriginalState() async throws {
        let url = journalURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var hardware = 1600
        do {
            try await HardwareValidationSession.run(
                deviceID: "test-device", journalURL: url, read: { hardware }, restore: { hardware = $0 },
                operation: {
                    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
                    hardware = 900
                    throw TestFailure.operation
                })
            XCTFail("Expected the operation failure")
        } catch TestFailure.operation {
            XCTAssertEqual(hardware, 1600)
            let journal = try HardwareValidationJournal<Int>.load(from: url)
            XCTAssertEqual(journal.phase, .restored)
            XCTAssertEqual(journal.original, 1600)
        }
    }

    func testRestoreMismatchRetainsRecoveryJournal() async throws {
        let url = journalURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var hardware = 1600
        do {
            try await HardwareValidationSession.run(deviceID: "test-device", journalURL: url, read: { hardware }, restore: { _ in }, operation: { hardware = 900 })
            XCTFail("Expected restoration failure")
        } catch {
            let journal = try HardwareValidationJournal<Int>.load(from: url)
            XCTAssertEqual(journal.phase, .restoreFailed)
            XCTAssertEqual(journal.original, 1600)
        }
    }

    func testExistingJournalPreventsAnyMutation() async throws {
        let url = journalURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("unrecovered".utf8).write(to: url)
        var mutated = false
        do {
            try await HardwareValidationSession.run(deviceID: "test-device", journalURL: url, read: { 1600 }, restore: { _ in }, operation: { mutated = true })
            XCTFail("Existing journals must not be overwritten")
        } catch { XCTAssertFalse(mutated) }
    }

    func testRecoveryRejectsWrongDeviceBeforeRestoring() async throws {
        let url = journalURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try await HardwareValidationSession.run(deviceID: "original-device", journalURL: url, read: { 1600 }, restore: { _ in }, operation: {})
        var mutated = false
        do {
            try await HardwareValidationSession.recover(deviceID: "different-device", journalURL: url, read: { 1600 }, restore: { (_: Int) in mutated = true })
            XCTFail("Wrong-device recovery must fail")
        } catch { XCTAssertFalse(mutated) }
    }

    func testLostJournalDuringOperationDoesNotPreventInMemoryRestore() async throws {
        let url = journalURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var hardware = 1600
        try await HardwareValidationSession.run(
            deviceID: "original", journalURL: url, read: { hardware }, restore: { hardware = $0 },
            operation: {
                hardware = 900
                try FileManager.default.removeItem(at: url)
            })
        XCTAssertEqual(hardware, 1600)
        XCTAssertEqual(try HardwareValidationJournal<Int>.load(from: url).phase, .restored)
    }

    func testDPIBaselineHonorsCeilingAndRejectsMalformedStages() throws {
        let captured = Data([3, 5, 1, 0x90, 1, 0x90, 1, 0, 0, 2, 0x20, 3, 0x20, 3, 0, 0, 3, 0x40, 6, 0x40, 6, 0, 0, 4, 0x80, 12, 0x80, 12, 0, 0, 5, 0x50, 0xC3, 0x50, 0xC3, 0])
        XCTAssertEqual(try HardwareDPIBaseline.validate(captured, range: 100...50_000), captured)
        XCTAssertThrowsError(try HardwareDPIBaseline.validate(captured, range: 100...30_000))
        var unknownActive = captured
        unknownActive[0] = 99
        var invalidCount = captured
        invalidCount[1] = 0
        var duplicateIDs = captured
        duplicateIDs[9] = 1
        var zeroDPI = captured
        zeroDPI[3] = 0
        zeroDPI[4] = 0
        for malformed in [unknownActive, invalidCount, duplicateIDs, zeroDPI] { XCTAssertThrowsError(try HardwareDPIBaseline.validate(malformed, range: 100...50_000)) }
        XCTAssertThrowsError(try HardwareDPIBaseline.validate(Data(), range: 100...50_000))
    }

    func testScopeRequiresIdentityAndAbsoluteJournal() throws {
        XCTAssertThrowsError(try HardwareValidationScope(environment: [:]))
        XCTAssertThrowsError(try HardwareValidationScope(environment: ["OPEN_SNEK_HW_DEVICE_ID": "wanted", "OPEN_SNEK_HW_JOURNAL": "relative.json"]))
        let scope = try HardwareValidationScope(environment: ["OPEN_SNEK_HW_DEVICE_ID": "wanted", "OPEN_SNEK_HW_JOURNAL": journalURL().path])
        XCTAssertThrowsError(try scope.select(from: [], transport: .bluetooth))
    }

    func testInterruptedRunCanRecoverFromItsOriginalJournal() async throws {
        let url = journalURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var hardware = 900
        try HardwareValidationJournal(schemaVersion: 1, deviceID: "original", original: 1600, phase: .prepared).save(to: url, create: true)
        try await HardwareValidationSession.recover(deviceID: "original", journalURL: url, read: { hardware }, restore: { hardware = $0 })
        XCTAssertEqual(hardware, 1600)
        XCTAssertEqual(try HardwareValidationJournal<Int>.load(from: url).phase, .restored)
    }

    private func journalURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("hardware-validation-\(UUID().uuidString).json") }

    /// Models an operation error distinct from a restore error.
    private enum TestFailure: Error { case operation }
}
