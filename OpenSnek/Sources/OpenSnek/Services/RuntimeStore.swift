import Foundation
import Observation

@MainActor
@Observable
final class RuntimeStore {
    let environment: AppEnvironment
    var backgroundServiceEnabled: Bool
    var launchAtStartupEnabled: Bool
    var serviceStatusMessage: String?

    @ObservationIgnored private weak var runtimeControllerStorage: AppStateRuntimeController?

    init(environment: AppEnvironment, backgroundServiceEnabled: Bool, launchAtStartupEnabled: Bool) {
        self.environment = environment
        self.backgroundServiceEnabled = backgroundServiceEnabled
        self.launchAtStartupEnabled = launchAtStartupEnabled
    }

    func bind(runtimeController: AppStateRuntimeController) {
        self.runtimeControllerStorage = runtimeController
    }

    private var runtimeController: AppStateRuntimeController {
        guard let runtimeControllerStorage else {
            preconditionFailure("RuntimeStore accessed before runtimeController was bound")
        }
        return runtimeControllerStorage
    }

    var isServiceProcess: Bool {
        environment.launchRole.isService
    }

    var compactStatusMessage: String? {
        runtimeController.compactStatusMessage
    }

    var currentPollingProfile: PollingProfile {
        runtimeController.currentPollingProfile
    }

    func start() async {
        await runtimeController.start()
    }

    func setCompactMenuPresented(_ isPresented: Bool) {
        runtimeController.setCompactMenuPresented(isPresented)
    }

    func setBackgroundServiceEnabled(_ enabled: Bool) async {
        await runtimeController.setBackgroundServiceEnabled(enabled)
    }

    func setLaunchAtStartupEnabled(_ enabled: Bool) {
        runtimeController.setLaunchAtStartupEnabled(enabled)
    }

    func sendRemoteClientPresence() {
        runtimeController.sendRemoteClientPresence()
    }

    func recordRemoteClientPresence(_ presence: CrossProcessClientPresence, now: Date = Date()) {
        runtimeController.recordRemoteClientPresence(presence, now: now)
    }

    func pollingProfile(at now: Date) -> PollingProfile {
        runtimeController.pollingProfile(at: now)
    }

    func activeFastPollingDeviceIDs(at now: Date) -> [String] {
        runtimeController.activeFastPollingDeviceIDs(at: now)
    }

    func openFullAppFromService() {
        runtimeController.openFullAppFromService()
    }

    func openSettingsFromService() {
        runtimeController.openSettingsFromService()
    }

    func prepareForCurrentServiceProcessTermination() {
        runtimeController.prepareForCurrentServiceProcessTermination()
    }

    func terminateServiceProcess() {
        runtimeController.terminateServiceProcess()
    }
}
