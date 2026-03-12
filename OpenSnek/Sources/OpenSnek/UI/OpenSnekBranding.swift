import AppKit

enum OpenSnekBranding {
    static let titlebarAccessoryIdentifier = NSUserInterfaceItemIdentifier("io.opensnek.OpenSnek.titlebarIcon")

    static let menuIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "snek-menu", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = false
        return image
    }()
}
