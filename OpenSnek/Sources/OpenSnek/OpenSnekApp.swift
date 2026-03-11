import SwiftUI

@main
struct OpenSnekApp: App {
    @NSApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appLifecycle
    @State private var appState: AppState

    init() {
        let launchRole = OpenSnekProcessRole.current
        _appState = State(initialValue: AppState(launchRole: launchRole))
    }

    var body: some Scene {
        WindowGroup("") {
            if appState.isServiceProcess {
                ServiceWindowSuppressorView()
            } else {
                ContentView(appState: appState)
                    .frame(minWidth: 900, minHeight: 600)
                    .background(WindowChromeConfigurator().frame(width: 0, height: 0))
            }
        }

        MenuBarExtra("Open Snek", systemImage: "dial.medium", isInserted: .constant(appState.isServiceProcess)) {
            ServiceMenuBarView(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }
    }
}

private struct ServiceWindowSuppressorView: View {
    @State private var didCloseStartupWindow = false

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                guard !didCloseStartupWindow else { return }
                didCloseStartupWindow = true
                DispatchQueue.main.async {
                    NSApp.windows
                        .filter { !($0 is NSPanel) && $0.standardWindowButton(.closeButton) != nil }
                        .forEach { $0.close() }
                }
            }
    }
}
