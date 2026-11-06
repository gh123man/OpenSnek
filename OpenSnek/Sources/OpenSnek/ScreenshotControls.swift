import AppKit

/// Native rounded text-field bezels depend on the window compositor. Offscreen
/// bitmap rendering can leave bright fragments around their edges. Give only
/// documentation captures a flat, appearance-matched bezel instead.
@MainActor enum ScreenshotControls {
    /// Draws editable text without compositor-dependent bezel fragments.
    private final class CaptureTextFieldCell: NSTextFieldCell {
        override func drawingRect(forBounds rect: NSRect) -> NSRect {
            var drawing = super.drawingRect(forBounds: rect)
            let textHeight = cellSize(forBounds: rect).height
            drawing.origin.y += max(0, (drawing.height - textHeight) / 2)
            drawing.size.height = min(drawing.height, textHeight)
            return drawing.insetBy(dx: 4, dy: 0)
        }
    }

    static func prepare(in view: NSView) {
        if let field = view as? NSTextField, field.isEditable {
            let cell = CaptureTextFieldCell(textCell: field.stringValue)
            cell.font = field.font
            cell.textColor = field.textColor
            cell.alignment = field.alignment
            cell.isEditable = true
            cell.isSelectable = true
            cell.isScrollable = true
            field.cell = cell
            field.isBezeled = false
            field.drawsBackground = false
            field.backgroundColor = .textBackgroundColor
            field.wantsLayer = true
            field.layer?.cornerRadius = 5
            field.layer?.borderWidth = 0.5
            field.effectiveAppearance.performAsCurrentDrawingAppearance {
                field.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
                field.layer?.borderColor = NSColor.separatorColor.cgColor
            }
            field.layer?.masksToBounds = true
        }
        for child in view.subviews { prepare(in: child) }
    }
}
