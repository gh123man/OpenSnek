import AppKit

/// Defines OpenSnek branding values.
enum OpenSnekBranding {
    private static let menuTemplateResourceName = "snek-menu-template"
    private static let menuTemplateResourceExtension = "png"

    static var menuBarIconSide: CGFloat { max(16, floor(NSStatusBar.system.thickness)) }

    static var menuIcon: NSImage? { bundledMenuTemplateIcon(size: NSSize(width: menuBarIconSide, height: menuBarIconSide)) }

    static func menuBarDpiBadge(dpi: Int) -> NSImage {
        let badgeHeight = max(18, floor(NSStatusBar.system.thickness - 2))
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .black)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .black)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.black, .paragraphStyle: paragraph]
        let valueAttributes: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: NSColor.black, .paragraphStyle: paragraph]

        let labelText = "DPI" as NSString
        let valueText = "\(dpi)" as NSString
        let labelSize = labelText.size(withAttributes: labelAttributes)
        let valueSize = valueText.size(withAttributes: valueAttributes)
        let badgeWidth = max(24, ceil(max(labelSize.width, valueSize.width)) + 4)
        let totalHeight = labelSize.height + valueSize.height
        let baseY = max(0, floor((badgeHeight - totalHeight) / 2))

        let image = NSImage(size: NSSize(width: badgeWidth, height: badgeHeight))
        image.lockFocus()
        labelText.draw(in: NSRect(x: 0, y: baseY + valueSize.height - 2, width: badgeWidth, height: labelSize.height), withAttributes: labelAttributes)
        valueText.draw(in: NSRect(x: 0, y: baseY, width: badgeWidth, height: valueSize.height), withAttributes: valueAttributes)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func menuBarSymbolIcon(symbolName: String, color: NSColor? = nil) -> NSImage? {
        let side = menuBarIconSide
        let targetHeight = max(10, floor(side * 0.6))
        let config = NSImage.SymbolConfiguration(pointSize: targetHeight, weight: .bold)
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }

        let sourceSize = base.size
        let width = max(targetHeight, ceil(sourceSize.width * (targetHeight / max(sourceSize.height, 1))))
        let image = NSImage(size: NSSize(width: width, height: side))
        image.lockFocus()
        let rect = NSRect(x: 0, y: floor((side - targetHeight) / 2), width: width, height: targetHeight)
        base.draw(in: rect)
        if let color {
            color.set()
            rect.fill(using: .sourceAtop)
        }
        image.unlockFocus()
        image.isTemplate = color == nil
        return image
    }

    static func menuBarSymbolWidth(symbolName: String) -> CGFloat { menuBarSymbolIcon(symbolName: symbolName)?.size.width ?? menuBarIconSide }

    static func menuTemplateIcon(from url: URL, size: NSSize) -> NSImage? {
        guard let source = NSImage(contentsOf: url), let sized = source.copy() as? NSImage else { return nil }

        sized.size = size
        sized.isTemplate = true
        return sized
    }

    private static func bundledMenuTemplateIcon(size: NSSize) -> NSImage? {
        guard let url = Bundle.main.url(forResource: menuTemplateResourceName, withExtension: menuTemplateResourceExtension) else { return nil }
        return menuTemplateIcon(from: url, size: size)
    }
}
