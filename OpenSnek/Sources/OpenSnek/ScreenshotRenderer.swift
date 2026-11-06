import AppKit
import QuartzCore
import SwiftUI

/// Renders the real UI at 2× with fixed fixtures, following qeq's offscreen capture workflow.
@MainActor enum ScreenshotRenderer {
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "io.opensnek.screenshots." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw captureError("Could not isolate screenshot preferences") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = ScreenshotFixtures.makeState(defaults: defaults)
        try capture(DesktopScreenshot(app: app), size: DesktopScreenshot.size, name: "desktop", directory: directory)
    }

    private static func capture(_ view: some View, size: CGSize, name: String, directory: URL) throws {
        let root = view.frame(width: size.width, height: size.height, alignment: .topLeading).background(Color(hex: 0x10161D)).openSnekFixedAppearance().environment(\.isDocumentationPreview, true).environment(\.controlActiveState, .active)
        let host = NSHostingController(rootView: root)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -10000, y: 0), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        OpenSnekAppearance.apply(to: window)
        window.contentViewController = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<20 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.035))
            host.view.layoutSubtreeIfNeeded()
            host.view.displayIfNeeded()
            CATransaction.flush()
        }
        let size = host.view.bounds.size
        guard size.width > 0, size.height > 100, size.height <= 1400 else { throw captureError("Unexpected \(name) size: \(size)") }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw captureError("Could not allocate \(name) bitmap")
        }
        bitmap.size = size
        ScreenshotControls.prepare(in: host.view)
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw captureError("Could not encode \(name)") }
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        print("\(name): \(Int(size.width * 2)) × \(Int(size.height * 2)) pixels")
    }

    private static func captureError(_ message: String) -> NSError { NSError(domain: "OpenSnek screenshots", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
