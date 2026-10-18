import AppKit

/// Coordinates app lifecycle delegate behavior.
@MainActor final class AppLifecycleDelegate: NSObject, NSApplicationDelegate {
    /// Defines reopen behavior values.
    enum ReopenBehavior: Equatable {
        case launchFullApp
        case reopenWindows
        case noop
    }

    nonisolated static func reopenBehavior(launchRole: OpenSnekProcessRole, hasVisibleWindows: Bool) -> ReopenBehavior {
        if launchRole.isService { return .launchFullApp }
        return hasVisibleWindows ? .noop : .reopenWindows
    }

    nonisolated static func launchActivationPolicy(launchRole: OpenSnekProcessRole) -> NSApplication.ActivationPolicy { launchRole.isService ? .accessory : .regular }

    func applicationWillFinishLaunching(_ notification: Notification) {
        OpenSnekAppearance.apply()
        NSApp.setActivationPolicy(Self.launchActivationPolicy(launchRole: OpenSnekProcessRole.current))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        AppLog.info("App", "launch version=\(version) build=\(build) logLevel=\(AppLog.currentLevel.shortLabel)")

        if OpenSnekProcessRole.current.isService { return }

        NSApp.setActivationPolicy(Self.launchActivationPolicy(launchRole: .app))
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.windows.forEach {
                WindowChromeConfigurator.configure($0)
                $0.makeKeyAndOrderFront(nil)
            }
            self.acknowledgeDevelopmentLaunch(attemptsRemaining: 100)
        }
    }

    private func acknowledgeDevelopmentLaunch(attemptsRemaining: Int) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--launch-receipt"), arguments.indices.contains(index + 1) else { return }
        let path = arguments[index + 1]
        guard path.hasPrefix("/") else { return }
        let windows = NSApp.windows.filter { $0.canBecomeMain }
        windows.forEach {
            if $0.isMiniaturized { $0.deminiaturize(nil) }
            $0.makeKeyAndOrderFront(nil)
        }
        let visibleCount = windows.filter { $0.isVisible && !$0.isMiniaturized }.count
        if visibleCount > 0 {
            do { _ = try AppLaunchReceipt.write(to: URL(fileURLWithPath: path), role: OpenSnekProcessRole.current, visibleWindowCount: visibleCount) } catch { AppLog.warning("App", "Launch receipt failed: \(error.localizedDescription)") }
            return
        }
        guard attemptsRemaining > 0 else {
            AppLog.warning("App", "Foreground launch did not produce a visible main window")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.acknowledgeDevelopmentLaunch(attemptsRemaining: attemptsRemaining - 1) }
    }

    func applicationDidBecomeActive(_ notification: Notification) { if OpenSnekProcessRole.current.isService { NSApp.setActivationPolicy(.accessory) } }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        switch Self.reopenBehavior(launchRole: OpenSnekProcessRole.current, hasVisibleWindows: flag) {
        case .launchFullApp:
            sender.setActivationPolicy(.accessory)
            BackgroundServiceCoordinator.shared.launchFullAppProcess()
            return false
        case .reopenWindows:
            sender.windows.forEach {
                WindowChromeConfigurator.configure($0)
                $0.makeKeyAndOrderFront(nil)
            }
            return true
        case .noop: return true
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !OpenSnekProcessRole.current.isService }

    func applicationWillTerminate(_ notification: Notification) { BackgroundServiceCoordinator.shared.stopCurrentServiceHostIfNeeded() }
}
