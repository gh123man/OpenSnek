import AppKit
import Foundation

@MainActor
final class AppStateRuntimeController {
    unowned let appState: AppState

    private var runtimeTask: Task<Void, Never>?
    private var didStartRuntime = false
    private var compactMenuPresented = false
    private var compactInteractionUntil: Date?
    private var lastRefreshStatePollAt: Date = .distantPast
    private var lastDevicePresencePollAt: Date = .distantPast
    private var lastFastDpiPollAt: Date = .distantPast
    private var transientStatusUntil: Date?
    private(set) var isBackendReady = false
    private var clientPresenceObserver: NSObjectProtocol?
    private var backendStateUpdatesTask: Task<Void, Never>?
    private var remoteClientPresenceByProcessID: [Int32: RemoteClientPresenceState] = [:]
    private var lastRemoteClientPresencePingAt: Date = .distantPast

    init(appState: AppState) {
        self.appState = appState
    }

    func tearDown() {
        runtimeTask?.cancel()
        backendStateUpdatesTask?.cancel()
        if let clientPresenceObserver {
            CrossProcessStateSync.removeObserver(clientPresenceObserver)
        }
        clientPresenceObserver = nil
    }

    var compactStatusMessage: String? {
        guard let serviceStatusMessage = appState.serviceStatusMessage,
              let transientStatusUntil,
              Date() < transientStatusUntil else {
            return nil
        }
        return serviceStatusMessage
    }

    func setBackendReady(_ ready: Bool) {
        isBackendReady = ready
    }

    func setCompactInteraction(until date: Date?) {
        compactInteractionUntil = date
    }

    func setTransientStatus(until date: Date?) {
        transientStatusUntil = date
    }

    func pollingProfile(at now: Date) -> PollingProfile {
        if !appState.launchRole.isService {
            return .foreground
        }
        if compactMenuPresented {
            return .serviceInteractive
        }
        if hasActiveRemoteClients(at: now) {
            return .serviceInteractive
        }
        if let compactInteractionUntil, now < compactInteractionUntil {
            return .serviceInteractive
        }
        return .serviceIdle
    }

    func activeFastPollingDeviceIDs(at now: Date) -> [String] {
        let liveIDs = Set(appState.devices.map(\.id))
        var ordered: [String] = []
        var seen: Set<String> = []

        for deviceID in localFastPollingDeviceIDs(at: now) {
            guard liveIDs.contains(deviceID) else { continue }
            guard seen.insert(deviceID).inserted else { continue }
            ordered.append(deviceID)
        }

        let remoteSelectedDeviceIDs = activeRemoteSelectedDeviceIDs(at: now)
        for deviceID in remoteSelectedDeviceIDs {
            guard liveIDs.contains(deviceID) else { continue }
            guard seen.insert(deviceID).inserted else { continue }
            ordered.append(deviceID)
        }

        if appState.launchRole.isService,
           hasActiveRemoteClients(at: now),
           remoteSelectedDeviceIDs.isEmpty,
           let selectedDeviceID = appState.selectedDeviceID,
           liveIDs.contains(selectedDeviceID),
           seen.insert(selectedDeviceID).inserted {
            ordered.append(selectedDeviceID)
        }

        return ordered
    }

    func recordRemoteClientPresence(_ presence: CrossProcessClientPresence, now: Date = Date()) {
        guard appState.launchRole.isService else { return }
        guard presence.sourceProcessID > 0 else { return }
        let hadActiveRemoteClients = hasActiveRemoteClients(at: now)
        pruneExpiredRemoteClientPresence(now: now)
        let previous = remoteClientPresenceByProcessID[presence.sourceProcessID]
        remoteClientPresenceByProcessID[presence.sourceProcessID] = RemoteClientPresenceState(
            expiresAt: now.addingTimeInterval(2.5),
            selectedDeviceID: presence.selectedDeviceID
        )
        let selectedDeviceChanged = previous?.selectedDeviceID != presence.selectedDeviceID
        if !hadActiveRemoteClients || selectedDeviceChanged {
            requestImmediateRuntimePoll(resetPollingDeadlines: true)
        }
    }

    func installCrossProcessObservers() {
        guard clientPresenceObserver == nil else { return }
        clientPresenceObserver = CrossProcessStateSync.observeClientPresence { [weak self] presence in
            Task { [weak self] in
                await self?.handleRemoteClientPresence(presence)
            }
        }
    }

    func restartBackendStateUpdates() async {
        backendStateUpdatesTask?.cancel()
        let stream = await appState.backend.stateUpdates()
        backendStateUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await update in stream {
                await self.handleBackendStateUpdate(update)
            }
        }
    }

    private func handleBackendStateUpdate(_ update: BackendStateUpdate) async {
        guard isBackendReady else { return }
        switch update {
        case .deviceList(let devices, _):
            await appState.deviceController.handleBackendDeviceListUpdate(devices)
        case .snapshot(let snapshot):
            guard appState.usesRemoteServiceUpdates else { return }
            appState.deviceController.applyRemoteServiceSnapshot(snapshot)
        case .deviceState(let deviceID, let updatedState, let updatedAt):
            appState.deviceController.applyBackendDeviceStateUpdate(deviceID: deviceID, state: updatedState, updatedAt: updatedAt)
        }
    }

    private func handleRemoteClientPresence(_ presence: CrossProcessClientPresence) async {
        recordRemoteClientPresence(presence)
    }

    func start() async {
        guard !didStartRuntime else { return }
        didStartRuntime = true

        if appState.launchRole.isService {
            do {
                try await appState.serviceCoordinator.registerServiceHostIfNeeded(backend: LocalBridgeBackend.shared)
            } catch {
                appState.serviceStatusMessage = "Service host failed: \(error.localizedDescription)"
            }
            isBackendReady = true
        } else {
            await configureBackendForCurrentPreferences()
        }

        if appState.usesRemoteServiceUpdates {
            sendRemoteClientPresence()
        } else {
            await appState.deviceController.refreshDevices()
        }
        if !appState.launchRole.isService {
            await appState.checkForUpdates()
        }

        runtimeTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.pollRuntimeOnce()
                let sleepInterval = self.runtimeSleepInterval(after: Date())
                let sleepNanos = UInt64((sleepInterval * 1_000_000_000).rounded())
                try? await Task.sleep(nanoseconds: sleepNanos)
            }
        }
    }

    func setCompactMenuPresented(_ isPresented: Bool) {
        let presentationChanged = compactMenuPresented != isPresented
        compactMenuPresented = isPresented
        if isPresented {
            compactInteractionUntil = Date().addingTimeInterval(3.0)
            if presentationChanged {
                requestImmediateRuntimePoll(resetPollingDeadlines: true)
            }
        }
    }

    func setBackgroundServiceEnabled(_ enabled: Bool) async {
        appState.backgroundServiceEnabled = enabled
        appState.serviceCoordinator.setBackgroundServiceEnabled(enabled)
        if !enabled, appState.launchAtStartupEnabled {
            setLaunchAtStartupEnabled(false)
        }

        if enabled {
            do {
                appState.backend = try await appState.serviceCoordinator.connectOrLaunchService()
                await restartBackendStateUpdates()
                isBackendReady = true
                appState.serviceStatusMessage = "Menu bar service connected"
                transientStatusUntil = Date().addingTimeInterval(3.0)
                appState.errorMessage = nil
            } catch {
                appState.backend = LocalBridgeBackend.shared
                await restartBackendStateUpdates()
                isBackendReady = true
                appState.backgroundServiceEnabled = false
                appState.serviceCoordinator.setBackgroundServiceEnabled(false)
                appState.errorMessage = "Background service unavailable: \(error.localizedDescription)"
            }
        } else {
            appState.backend = LocalBridgeBackend.shared
            await restartBackendStateUpdates()
            isBackendReady = true
            if appState.launchRole.isService {
                appState.serviceCoordinator.stopCurrentServiceHostIfNeeded()
                NSApp.terminate(nil)
                return
            } else {
                appState.serviceCoordinator.stopServiceProcess()
            }
            appState.serviceStatusMessage = "Menu bar service stopped"
            transientStatusUntil = Date().addingTimeInterval(3.0)
        }

        if appState.usesRemoteServiceUpdates {
            sendRemoteClientPresence()
        } else {
            await appState.deviceController.refreshDevices()
        }
    }

    func setLaunchAtStartupEnabled(_ enabled: Bool) {
        do {
            try appState.serviceCoordinator.setLaunchAtStartupEnabled(enabled)
            appState.launchAtStartupEnabled = enabled
            appState.serviceStatusMessage = enabled
                ? "Launch at startup enabled for next login"
                : "Launch at startup disabled"
            transientStatusUntil = Date().addingTimeInterval(3.0)
        } catch {
            appState.errorMessage = "Launch at startup failed: \(error.localizedDescription)"
            appState.launchAtStartupEnabled = appState.serviceCoordinator.launchAtStartupEnabled
        }
    }

    func openFullAppFromService() {
        appState.serviceCoordinator.launchFullAppProcess()
    }

    func openSettingsFromService() {
        appState.serviceCoordinator.launchFullAppProcess(arguments: ["--open-settings"])
    }

    func prepareForCurrentServiceProcessTermination() {
        appState.serviceCoordinator.stopCurrentServiceHostIfNeeded()
    }

    func terminateServiceProcess() {
        appState.serviceCoordinator.terminateOtherRunningApplicationInstances()
        prepareForCurrentServiceProcessTermination()
        NSApp.terminate(nil)
    }

    func refreshNow() async {
        if appState.usesRemoteServiceUpdates {
            sendRemoteClientPresence()
        } else {
            await appState.deviceController.refreshDevices()
        }
        compactInteractionUntil = Date().addingTimeInterval(3.0)
    }

    func sendRemoteClientPresence() {
        guard appState.usesRemoteServiceUpdates else { return }
        lastRemoteClientPresencePingAt = Date()
        CrossProcessStateSync.postClientPresence(selectedDeviceID: appState.selectedDeviceID)
    }

    private func configureBackendForCurrentPreferences() async {
        do {
            appState.backend = try await appState.serviceCoordinator.makeBackendForCurrentMode()
            await restartBackendStateUpdates()
            isBackendReady = true
            if appState.backgroundServiceEnabled {
                appState.serviceStatusMessage = "Menu bar service connected"
                transientStatusUntil = Date().addingTimeInterval(2.0)
            }
        } catch {
            appState.backend = LocalBridgeBackend.shared
            await restartBackendStateUpdates()
            isBackendReady = true
            appState.errorMessage = "Background service unavailable: \(error.localizedDescription)"
        }
    }

    func runtimeSleepInterval(after now: Date) -> TimeInterval {
        RuntimeWakeSchedule.nextSleepInterval(
            now: now,
            profile: pollingProfile(at: now),
            usesRemoteServiceUpdates: appState.usesRemoteServiceUpdates,
            lastDevicePresencePollAt: lastDevicePresencePollAt,
            lastRefreshStatePollAt: lastRefreshStatePollAt,
            lastFastDpiPollAt: lastFastDpiPollAt,
            lastRemoteClientPresencePingAt: lastRemoteClientPresencePingAt,
            transientStatusUntil: transientStatusUntil,
            nextRemoteClientPresenceExpiry: remoteClientPresenceByProcessID
                .values
                .map(\.expiresAt)
                .filter { $0 > now }
                .min()
        )
    }

    private func pollRuntimeOnce() async {
        let now = Date()
        let profile = pollingProfile(at: now)
        pruneExpiredRemoteClientPresence(now: now)

        if appState.usesRemoteServiceUpdates {
            if now.timeIntervalSince(lastRemoteClientPresencePingAt) >= 1.0 {
                lastRemoteClientPresencePingAt = now
                CrossProcessStateSync.postClientPresence(selectedDeviceID: appState.selectedDeviceID)
            }
            clearTransientStatusIfExpired(now: now)
            return
        }

        if now.timeIntervalSince(lastDevicePresencePollAt) >= profile.devicePresenceInterval {
            lastDevicePresencePollAt = now
            await appState.deviceController.pollDevicePresence()
        }

        if now.timeIntervalSince(lastRefreshStatePollAt) >= profile.refreshStateInterval {
            lastRefreshStatePollAt = now
            await appState.deviceController.refreshAllDeviceStates()
        }

        if let fastInterval = profile.fastDpiInterval,
           now.timeIntervalSince(lastFastDpiPollAt) >= fastInterval {
            lastFastDpiPollAt = now
            await appState.deviceController.refreshDpiFast()
        }

        clearTransientStatusIfExpired(now: now)
    }

    private func clearTransientStatusIfExpired(now: Date) {
        if let transientStatusUntil, now >= transientStatusUntil {
            self.transientStatusUntil = nil
            if compactStatusMessage == nil {
                appState.serviceStatusMessage = nil
            }
        }
    }

    private func requestImmediateRuntimePoll(resetPollingDeadlines: Bool) {
        guard didStartRuntime else { return }
        if resetPollingDeadlines {
            lastDevicePresencePollAt = .distantPast
            lastRefreshStatePollAt = .distantPast
            lastFastDpiPollAt = .distantPast
        }
        Task { [weak self] in
            await self?.pollRuntimeOnce()
        }
    }

    private func hasActiveRemoteClients(at now: Date) -> Bool {
        remoteClientPresenceByProcessID.values.contains { $0.expiresAt > now }
    }

    private func activeRemoteSelectedDeviceIDs(at now: Date) -> [String] {
        remoteClientPresenceByProcessID
            .values
            .filter { $0.expiresAt > now }
            .compactMap(\.selectedDeviceID)
    }

    private func localFastPollingDeviceIDs(at now: Date) -> [String] {
        guard let selectedDeviceID = appState.selectedDeviceID else { return [] }
        if appState.launchRole.isService {
            let localInteractive = compactMenuPresented || (compactInteractionUntil.map { now < $0 } ?? false)
            return localInteractive ? [selectedDeviceID] : []
        }
        return appState.usesRemoteServiceUpdates ? [] : [selectedDeviceID]
    }

    private func pruneExpiredRemoteClientPresence(now: Date) {
        guard !remoteClientPresenceByProcessID.isEmpty else { return }
        let expiredProcessIDs = remoteClientPresenceByProcessID.compactMap { processID, state in
            state.expiresAt <= now ? processID : nil
        }
        guard !expiredProcessIDs.isEmpty else { return }
        for processID in expiredProcessIDs {
            remoteClientPresenceByProcessID.removeValue(forKey: processID)
        }
    }
}
