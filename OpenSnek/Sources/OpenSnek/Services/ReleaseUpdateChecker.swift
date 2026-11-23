import Foundation
import OpenSnekAppSupport

/// Defines release update check modes.
enum ReleaseUpdateCheckMode: Equatable {
    case newerThanCurrent
    case includingReleaseCandidates
    case latestReleaseDryRun
}

/// Defines the release update checking contract.
protocol ReleaseUpdateChecking: Sendable { func checkForUpdate(currentVersion: String, mode: ReleaseUpdateCheckMode) async throws -> ReleaseAvailability? }

/// Defines app build channel values.
enum AppBuildChannel: String, Equatable {
    case dev
    case release
}

/// Stores release version data.
struct ReleaseVersion: Comparable, Equatable {
    /// Defines pre release identifier values.
    enum PreReleaseIdentifier: Comparable, Equatable {
        case numeric(Int)
        case textual(String)

        static func < (lhs: PreReleaseIdentifier, rhs: PreReleaseIdentifier) -> Bool {
            switch (lhs, rhs) {
            case let (.numeric(left), .numeric(right)): return left < right
            case let (.textual(left), .textual(right)): return left.localizedStandardCompare(right) == .orderedAscending
            case (.numeric, .textual): return true
            case (.textual, .numeric): return false
            }
        }
    }

    let components: [Int]
    let preRelease: [PreReleaseIdentifier]

    var isReleaseCandidate: Bool { preRelease.first == .textual("rc") }

    static func parse(_ rawValue: String) -> ReleaseVersion? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutPrefix = trimmed.replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
        let coreAndSuffix = withoutPrefix.split(separator: "-", maxSplits: 1).map(String.init)
        guard let core = coreAndSuffix.first, !core.isEmpty else { return nil }
        let parts = core.split(separator: ".")
        guard !parts.isEmpty else { return nil }

        var parsed: [Int] = []
        parsed.reserveCapacity(parts.count)
        for part in parts {
            guard let value = Int(part) else { return nil }
            parsed.append(value)
        }

        let preRelease: [PreReleaseIdentifier]
        if coreAndSuffix.count > 1 {
            let suffix = coreAndSuffix[1]
            let identifiers = suffix.split(separator: ".")
            guard !identifiers.isEmpty else { return nil }
            preRelease = identifiers.map { identifier in
                if let numeric = Int(identifier) { return .numeric(numeric) }
                return .textual(String(identifier))
            }
        } else {
            preRelease = []
        }

        return ReleaseVersion(components: parsed, preRelease: preRelease)
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }

        if lhs.preRelease.isEmpty && rhs.preRelease.isEmpty { return false }
        if lhs.preRelease.isEmpty { return false }
        if rhs.preRelease.isEmpty { return true }

        let preReleaseCount = max(lhs.preRelease.count, rhs.preRelease.count)
        for index in 0..<preReleaseCount {
            if index >= lhs.preRelease.count { return true }
            if index >= rhs.preRelease.count { return false }
            let left = lhs.preRelease[index]
            let right = rhs.preRelease[index]
            if left != right { return left < right }
        }

        return false
    }

    static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// Stores release availability data.
struct ReleaseAvailability: Equatable {
    let latestVersion: String
    let releaseURL: URL
    let checkMode: ReleaseUpdateCheckMode

    var isDryRun: Bool { checkMode == .latestReleaseDryRun }

    var appcastURL: URL { ReleaseUpdateChecker.releasesPageURL.appendingPathComponent("download").appendingPathComponent("v\(latestVersion)").appendingPathComponent("appcast.xml") }
}

/// Describes the result of checking for an installable release.
enum ReleaseUpdateCheckState: Equatable {
    case idle, checking, upToDate
    case failed(String)
}

/// Defines software update install lifecycle values.
enum SoftwareUpdateInstallState: Equatable {
    case idle
    case checking
    case downloading(received: UInt64, expected: UInt64?)
    case extracting(progress: Double?)
    case readyToInstall
    case installing
    case installed
    case failed(String)
}

/// Defines software update installer behavior.
@MainActor protocol SoftwareUpdateInstalling: AnyObject { func installLatestRelease(_ release: ReleaseAvailability, statusHandler: @escaping @MainActor (SoftwareUpdateInstallState) -> Void) async throws }

/// Provides a disabled software update installer fallback.
@MainActor final class DisabledSoftwareUpdateInstaller: SoftwareUpdateInstalling {
    static let shared = DisabledSoftwareUpdateInstaller()

    func installLatestRelease(_: ReleaseAvailability, statusHandler _: @escaping @MainActor (SoftwareUpdateInstallState) -> Void) async throws {
        throw NSError(domain: "OpenSnek.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: "Automatic update installation is not configured for this build."])
    }
}

/// Stores release update checker data.
struct ReleaseUpdateChecker: ReleaseUpdateChecking, Sendable {
    /// Carries latest release response data.
    struct LatestReleaseResponse: Decodable {
        let tag_name: String
        let html_url: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [ReleaseAsset]
    }

    /// Identifies a published release artifact.
    struct ReleaseAsset: Decodable { let name: String }

    static let periodicCheckInterval: TimeInterval = 60 * 60 * 24
    static let includeReleaseCandidatesDefaultsKey = "updates.includeReleaseCandidates"
    static let releasesPageURL = URL(string: "https://github.com/gh123man/OpenSnek/releases")!
    static let defaultDryRunAppcastURL = URL(string: "https://github.com/gh123man/OpenSnek/releases/download/sparkle-dryrun/dryrun-appcast.xml")!

    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func checkForUpdate(currentVersion: String, mode: ReleaseUpdateCheckMode = .newerThanCurrent) async throws -> ReleaseAvailability? {
        let endpoint = mode == .includingReleaseCandidates ? "releases?per_page=100" : "releases/latest"
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/gh123man/OpenSnek/\(endpoint)")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("OpenSnek/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else { throw URLError(.badServerResponse) }

        let releases = mode == .includingReleaseCandidates ? try JSONDecoder().decode([LatestReleaseResponse].self, from: data) : [try JSONDecoder().decode(LatestReleaseResponse.self, from: data)]
        return Self.selectUpdate(releases: releases, currentVersion: currentVersion, mode: mode)
    }

    static func selectUpdate(releases: [LatestReleaseResponse], currentVersion: String, mode: ReleaseUpdateCheckMode) -> ReleaseAvailability? {
        let current = ReleaseVersion.parse(currentVersion)
        let candidates = releases.compactMap { release -> (LatestReleaseResponse, ReleaseVersion)? in
            guard !release.draft, let version = ReleaseVersion.parse(release.tag_name) else { return nil }
            let isStable = !release.prerelease && version.preRelease.isEmpty
            guard isStable || (mode == .includingReleaseCandidates && version.isReleaseCandidate) else { return nil }
            let assetNames = Set(release.assets.map(\.name))
            let bareVersion = release.tag_name.replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
            guard assetNames.contains("appcast.xml"), assetNames.contains("OpenSnek-\(bareVersion).zip") else { return nil }
            if mode != .latestReleaseDryRun { guard let current, version > current else { return nil } }
            return (release, version)
        }
        guard let selected = candidates.max(by: { $0.1 < $1.1 })?.0 else { return nil }
        let latestVersion = selected.tag_name.replacingOccurrences(of: #"^[vV]"#, with: "", options: .regularExpression)
        return ReleaseAvailability(latestVersion: latestVersion, releaseURL: selected.html_url.flatMap(URL.init(string:)) ?? releasesPageURL, checkMode: mode)
    }

    static func includesReleaseCandidates(defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: includeReleaseCandidatesDefaultsKey) }

    static func checkMode(currentVersion: String, includeReleaseCandidates: Bool, usesDryRun: Bool) -> ReleaseUpdateCheckMode {
        if usesDryRun { return .latestReleaseDryRun }
        return includeReleaseCandidates || ReleaseVersion.parse(currentVersion)?.isReleaseCandidate == true ? .includingReleaseCandidates : .newerThanCurrent
    }

    static func currentAppVersion(bundle: Bundle = .main) -> String? { bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String }

    static func currentBuildChannel(bundle: Bundle = .main) -> AppBuildChannel {
        let rawValue = bundle.object(forInfoDictionaryKey: "OpenSnekBuildChannel") as? String
        return rawValue.flatMap(AppBuildChannel.init(rawValue:)) ?? .release
    }

    static func shouldCheckForUpdates(bundle: Bundle = .main) -> Bool { currentBuildChannel(bundle: bundle) == .release }

    static func dryRunAppcastURL(defaults: UserDefaults = .standard) -> URL { DeveloperRuntimeOptions.releaseUpdateDryRunAppcastURL(defaults: defaults) ?? defaultDryRunAppcastURL }

    static func isPeriodicCheckDue(lastCheckedAt: Date?, now: Date = Date()) -> Bool {
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= periodicCheckInterval
    }
}
