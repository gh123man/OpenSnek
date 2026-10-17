import XCTest
import OpenSnekCore

/// Verifies the root README's supported-device table stays in sync with the shipped device profiles.
///
/// The table is the first thing a prospective user reads, and it has gone stale before: the Naga and
/// Mouse Dock families shipped without being listed. This checks one direction only, that every
/// shipped profile has a row, because a row may legitimately name a device whose other transport is
/// still `Not yet` or `No`.
final class SupportedDevicesReadmeTests: XCTestCase {
    func testReadmeSupportedDevicesTableCoversEveryShippedProfile() throws {
        let readme = try String(contentsOf: repoRoot.appendingPathComponent("README.md"), encoding: .utf8)
        let listedNames = Self.supportedDeviceNames(in: readme)

        XCTAssertFalse(listedNames.isEmpty, "Could not find the Supported Devices table in README.md")
        for productName in Set(DeviceProfiles.all.map(\.productName)).sorted() {
            // The table disambiguates the 2017 Basilisk from the V3 family as "Basilisk (2017)".
            let isListed = listedNames.contains { $0 == productName || $0.hasPrefix("\(productName) (") }
            XCTAssertTrue(isListed, "README.md supported-device table has no row for \"\(productName)\"")
        }
    }

    /// Returns the device column of the `## Supported Devices` table, excluding its header row.
    private static func supportedDeviceNames(in readme: String) -> [String] {
        var names: [String] = []
        var insideTable = false
        for line in readme.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "## Supported Devices" {
                insideTable = true
                continue
            }
            guard insideTable else { continue }
            guard trimmed.hasPrefix("|") else {
                if !names.isEmpty { break }
                continue
            }
            let cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count > 1 else { continue }
            let device = cells[1]
            guard !device.isEmpty, device != "Device", !device.allSatisfy({ $0 == "-" || $0 == ":" }) else { continue }
            names.append(device)
        }
        return names
    }

    private var repoRoot: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
}
