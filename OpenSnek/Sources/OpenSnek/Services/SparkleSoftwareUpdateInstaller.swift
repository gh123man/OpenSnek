import Foundation
import OpenSnekAppSupport
@preconcurrency import Sparkle

/// Installs release updates through Sparkle.
@MainActor final class SparkleSoftwareUpdateInstaller: NSObject, SoftwareUpdateInstalling {
    static let shared = SparkleSoftwareUpdateInstaller()

    private let serviceCoordinator: BackgroundServiceCoordinator
    private var updaterController: SPUStandardUpdaterController?
    private var updaterDelegate: OpenSnekSparkleUpdaterDelegate?

    init(serviceCoordinator: BackgroundServiceCoordinator = .shared) {
        self.serviceCoordinator = serviceCoordinator
        super.init()
    }

    func installLatestRelease(statusHandler: @escaping @MainActor (SoftwareUpdateInstallState) -> Void) throws {
        guard Self.isConfigured() else { throw NSError(domain: "OpenSnek.Update", code: 1, userInfo: [NSLocalizedDescriptionKey: "Automatic update installation is not configured for this build."]) }

        let updaterController = makeUpdaterControllerIfNeeded(statusHandler: statusHandler)
        updaterDelegate?.statusHandler = statusHandler
        statusHandler(.checking)
        updaterController.checkForUpdates(nil)
    }

    private static func isConfigured(bundle: Bundle = .main) -> Bool {
        guard let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else { return false }
        let trimmed = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(")
    }

    private func makeUpdaterControllerIfNeeded(statusHandler: @escaping @MainActor (SoftwareUpdateInstallState) -> Void) -> SPUStandardUpdaterController {
        if let updaterController { return updaterController }

        let updaterDelegate = OpenSnekSparkleUpdaterDelegate(serviceCoordinator: serviceCoordinator, statusHandler: statusHandler)
        let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: updaterDelegate, userDriverDelegate: nil)
        self.updaterDelegate = updaterDelegate
        self.updaterController = updaterController
        return updaterController
    }
}

/// Coordinates Sparkle lifecycle callbacks with OpenSnek runtime state.
@MainActor private final class OpenSnekSparkleUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    private let serviceCoordinator: BackgroundServiceCoordinator
    var statusHandler: @MainActor (SoftwareUpdateInstallState) -> Void

    init(serviceCoordinator: BackgroundServiceCoordinator, statusHandler: @escaping @MainActor (SoftwareUpdateInstallState) -> Void) {
        self.serviceCoordinator = serviceCoordinator
        self.statusHandler = statusHandler
    }

    func bestValidUpdate(in appcast: SUAppcast, for _: SPUUpdater) -> SUAppcastItem? {
        guard Self.shouldForceLatestUpdateForDryRun else { return nil }
        return appcast.items.first
    }

    func feedURLString(for _: SPUUpdater) -> String? {
        guard Self.shouldForceLatestUpdateForDryRun else { return nil }
        return ReleaseUpdateChecker.dryRunAppcastURL().absoluteString
    }

    func updater(_: SPUUpdater, willDownloadUpdate _: SUAppcastItem, with _: NSMutableURLRequest) { statusHandler(.downloading(received: 0, expected: nil)) }

    func updater(_: SPUUpdater, didDownloadUpdate _: SUAppcastItem) { statusHandler(.extracting(progress: nil)) }

    func updater(_: SPUUpdater, willExtractUpdate _: SUAppcastItem) { statusHandler(.extracting(progress: nil)) }

    func updater(_: SPUUpdater, didExtractUpdate _: SUAppcastItem) { statusHandler(.readyToInstall) }

    func updater(_: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate _: SUAppcastItem, state _: SPUUserUpdateState) { if choice == .install { statusHandler(.installing) } }

    func updater(_: SPUUpdater, willInstallUpdate _: SUAppcastItem) {
        serviceCoordinator.stopServiceProcess()
        serviceCoordinator.terminateOtherRunningApplicationInstances()
        statusHandler(.installing)
    }

    func updaterWillRelaunchApplication(_: SPUUpdater) {
        serviceCoordinator.stopServiceProcess()
        serviceCoordinator.terminateOtherRunningApplicationInstances()
    }

    func updater(_: SPUUpdater, didAbortWithError error: any Error) { statusHandler(.failed(error.localizedDescription)) }

    func updater(_: SPUUpdater, didFinishUpdateCycleFor _: SPUUpdateCheck, error: (any Error)?) { if let error { statusHandler(.failed(error.localizedDescription)) } else { statusHandler(.idle) } }

    private static var shouldForceLatestUpdateForDryRun: Bool { ReleaseUpdateChecker.currentBuildChannel() == .dev && DeveloperRuntimeOptions.releaseUpdateDryRunEnabled() }
}
