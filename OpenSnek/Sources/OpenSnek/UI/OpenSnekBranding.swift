import AppKit

enum OpenSnekBranding {
    static let titlebarAccessoryIdentifier = NSUserInterfaceItemIdentifier("io.opensnek.OpenSnek.titlebarIcon")

    static let menuIcon = makeRasterizedIcon(canvasSize: NSSize(width: 12, height: 12), imageSize: NSSize(width: 7, height: 7))
    static let titlebarIcon = makeRasterizedIcon(canvasSize: NSSize(width: 13, height: 12), imageSize: NSSize(width: 10, height: 9))

    private static func makeRasterizedIcon(canvasSize: NSSize, imageSize: NSSize) -> NSImage? {
        guard let source = loadSourceIcon() else { return nil }

        let image = NSImage(size: canvasSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.set()
        NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
        NSGraphicsContext.current?.imageInterpolation = .high

        let origin = NSPoint(
            x: (canvasSize.width - imageSize.width) / 2.0,
            y: (canvasSize.height - imageSize.height) / 2.0
        )
        let rect = NSRect(origin: origin, size: imageSize)
        source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        image.isTemplate = false
        return image
    }

    private static func loadSourceIcon() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "snek-menu", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = false
        return image
    }
}
