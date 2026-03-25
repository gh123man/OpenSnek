import Foundation

@MainActor
final class AppEnvironment {
    let launchRole: OpenSnekProcessRole
    let serviceCoordinator: BackgroundServiceCoordinator
    let releaseUpdateChecker: any ReleaseUpdateChecking
    let currentAppVersion: String?
    let shouldCheckForReleaseUpdates: Bool
    var backend: any DeviceBackend
    var lastReleaseUpdateCheckAt: Date?

    init(
        launchRole: OpenSnekProcessRole,
        releaseUpdateChecker: any ReleaseUpdateChecking = ReleaseUpdateChecker(),
        currentAppVersion: String? = ReleaseUpdateChecker.currentAppVersion(),
        shouldCheckForReleaseUpdates: Bool = ReleaseUpdateChecker.shouldCheckForUpdates(),
        backend: any DeviceBackend,
        serviceCoordinator: BackgroundServiceCoordinator
    ) {
        self.launchRole = launchRole
        self.releaseUpdateChecker = releaseUpdateChecker
        self.currentAppVersion = currentAppVersion
        self.shouldCheckForReleaseUpdates = shouldCheckForReleaseUpdates
        self.backend = backend
        self.serviceCoordinator = serviceCoordinator
    }

    var usesRemoteServiceTransport: Bool {
        !launchRole.isService && backend.usesRemoteServiceTransport
    }
}
