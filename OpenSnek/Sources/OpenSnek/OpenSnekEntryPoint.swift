import AppKit
import SwiftUI

/// Routes documentation rendering before the app or its service lifecycle is created.
@main enum OpenSnekEntryPoint {
    @MainActor static func main() {
        guard let index = CommandLine.arguments.firstIndex(of: "--render-screenshots") else {
            OpenSnekApp.main()
            return
        }
        guard CommandLine.arguments.count == index + 2 else {
            fputs("Usage: OpenSnek --render-screenshots <output-directory>\n", stderr)
            exit(2)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        OpenSnekAppearance.apply(to: application)
        application.finishLaunching()
        do { try ScreenshotRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)) } catch {
            fputs("Screenshot rendering failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
