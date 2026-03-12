import AppKit

@MainActor
final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    private var openSettingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        AppLog.info("App", "launch version=\(version) build=\(build) logLevel=\(AppLog.currentLevel.shortLabel)")

        if OpenSnekProcessRole.current.isService {
            NSApp.setActivationPolicy(.accessory)
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installOpenSettingsObserver()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
            if ProcessInfo.processInfo.arguments.contains("--open-settings") {
                self.showSettingsWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if OpenSnekProcessRole.current.isService {
            return false
        }
        if !flag {
            sender.windows.forEach { $0.makeKeyAndOrderFront(nil) }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !OpenSnekProcessRole.current.isService
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let openSettingsObserver {
            DistributedNotificationCenter.default().removeObserver(openSettingsObserver)
        }
        BackgroundServiceCoordinator.shared.stopCurrentServiceHostIfNeeded()
    }

    private func installOpenSettingsObserver() {
        guard openSettingsObserver == nil else { return }
        openSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: BackgroundServiceCoordinator.openSettingsNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.showSettingsWindow()
            }
        }
    }

    private func showSettingsWindow() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.windows.forEach { $0.makeKeyAndOrderFront(nil) }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
