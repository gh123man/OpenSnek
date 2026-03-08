import SwiftUI

@main
struct OpenSnekMacApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .frame(minWidth: 1100, minHeight: 700)
        }
    }
}
