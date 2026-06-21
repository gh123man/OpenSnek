import AppKit
import SwiftUI

enum OpenSnekAppearance {
    static let appKitName = NSAppearance.Name.darkAqua
    static let colorScheme = ColorScheme.dark

    @MainActor
    static func apply(to application: NSApplication = .shared) {
        application.appearance = NSAppearance(named: appKitName)
    }

    @MainActor
    static func apply(to window: NSWindow) {
        window.appearance = NSAppearance(named: appKitName)
    }
}

extension View {
    func openSnekFixedAppearance() -> some View {
        preferredColorScheme(OpenSnekAppearance.colorScheme)
            .environment(\.colorScheme, OpenSnekAppearance.colorScheme)
    }
}
