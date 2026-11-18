import SwiftUI

/// Stores OpenSnek app data.
struct OpenSnekApp: App {
    static let mainWindowID = "opensnek-editor"
    private static let minimumMainWindowWidth: CGFloat = 900
    private static let minimumMainWindowHeight: CGFloat = 600
    private static let defaultMainWindowWidth: CGFloat = 1250
    private static let defaultMainWindowHeight: CGFloat = 800

    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appLifecycle
    @State private var appState: AppState

    init() {
        let launchRole = OpenSnekProcessRole.current
        let isUITestRun: Bool
        #if DEBUG
            isUITestRun = OpenSnekUITestSupport.isEnabled
            if isUITestRun { OpenSnekUITestSupport.recordLaunch(role: launchRole) }
        #else
            isUITestRun = false
        #endif

        let coordinator = BackgroundServiceCoordinator.shared
        let presentation = launchRole.isService || isUITestRun ? nil : ServiceLaunchPresentation.decode(ProcessInfo.processInfo.environment[ServiceLaunchPresentation.environmentKey], servicePID: coordinator.serviceProcessIdentifier)
        let backend = presentation.flatMap { _ in coordinator.publishedServiceBackend() }
        let initialAppState = AppState(launchRole: launchRole, backend: backend, shouldCheckForReleaseUpdates: isUITestRun ? false : ReleaseUpdateChecker.shouldCheckForUpdates())
        if let presentation, backend != nil {
            initialAppState.runtimeStore.hidAccessStatus = presentation.hidAccessStatus
            initialAppState.deviceController.applyLaunchPresentation(presentation)
        }
        _appState = State(initialValue: initialAppState)

        #if DEBUG
            if isUITestRun, !launchRole.isService {
                Task { @MainActor in
                    await initialAppState.runtimeController.start()
                    await initialAppState.runtimeController.refreshHIDAccessStatus(forceRefresh: false)
                }
            }
        #endif
    }

    var body: some Scene {
        WindowGroup("", id: Self.mainWindowID) {
            Group {
                if appState.runtimeStore.isServiceProcess {
                    ServiceWindowSuppressorView()
                } else {
                    ContentView(deviceStore: appState.deviceStore, editorStore: appState.editorStore, runtimeStore: appState.runtimeStore).frame(minWidth: Self.minimumMainWindowWidth, minHeight: Self.minimumMainWindowHeight).background(
                        WindowChromeConfigurator(keepWindowForReopen: appState.runtimeController.keepLastWindowForReopen).frame(width: 0, height: 0)
                    ).background(SettingsOpenBridgeView(runtimeStore: appState.runtimeStore, runtimeController: appState.runtimeController, lifecycle: appLifecycle).frame(width: 0, height: 0))
                }
            }.openSnekFixedAppearance()
        }.defaultSize(width: Self.defaultMainWindowWidth, height: Self.defaultMainWindowHeight)

        MenuBarExtra(isInserted: .constant(appState.runtimeStore.isServiceProcess)) {
            ServiceMenuBarView(deviceStore: appState.deviceStore, editorStore: appState.editorStore, runtimeStore: appState.runtimeStore).openSnekFixedAppearance()
        } label: {
            ServiceMenuBarStatusItemLabel(deviceStore: appState.deviceStore, editorStore: appState.editorStore, runtimeStore: appState.runtimeStore)
        }.menuBarExtraStyle(.window)

        Settings { SettingsView(deviceStore: appState.deviceStore, runtimeStore: appState.runtimeStore).openSnekFixedAppearance() }
    }
}

/// Stores service window suppressor view data.
private struct ServiceWindowSuppressorView: NSViewRepresentable {
    func makeNSView(context: Context) -> SuppressorView { SuppressorView() }

    func updateNSView(_ nsView: SuppressorView, context: Context) {}

    /// Coordinates suppressor view behavior.
    final class SuppressorView: NSView {
        private weak var suppressedWindow: NSWindow?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            guard let newWindow else { return }
            suppress(window: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            suppress(window: window)
        }

        private func suppress(window: NSWindow) {
            guard suppressedWindow !== window else { return }
            suppressedWindow = window

            // The service process uses a WindowGroup only to satisfy SwiftUI scene
            // requirements. Hide that transient window before AppKit can present it.
            window.alphaValue = 0
            window.hasShadow = false
            window.animationBehavior = .none
            window.ignoresMouseEvents = true
            window.orderOut(nil)

            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                window.orderOut(nil)
                window.close()
            }
        }
    }
}

/// Stores settings open bridge view data.
private struct SettingsOpenBridgeView: View {
    let runtimeStore: RuntimeStore

    let runtimeController: AppStateRuntimeController
    let lifecycle: AppLifecycleDelegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.frame(width: 0, height: 0).onAppear {
            lifecycle.runtimeController = runtimeController
            runtimeController.openEditorWindow = { [openWindow] in openWindow(id: OpenSnekApp.mainWindowID) }
            handleLaunchSettingsRequestIfNeeded()
        }.onChange(of: runtimeStore.openSettingsRequestCount) { _, count in
            guard count > 0 else { return }
            openSettings()
        }
    }

    private func handleLaunchSettingsRequestIfNeeded() {
        guard runtimeStore.openSettingsOnWindowAppearance else { return }
        runtimeStore.openSettingsOnWindowAppearance = false
        DispatchQueue.main.async { openSettings() }
    }
}
