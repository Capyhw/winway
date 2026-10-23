import AppKit

/// Draws above file rows without intercepting table or scroll interactions.
final class ExplorerSelectionOverlay: NSView {
    var selectionRect: NSRect = .zero { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        bounds.clip()
        ExplorerStyle.accent.withAlphaComponent(0.12).setFill()
        selectionRect.fill()
        ExplorerStyle.accent.withAlphaComponent(0.6).setStroke()
        NSBezierPath(rect: selectionRect).stroke()
    }
}
