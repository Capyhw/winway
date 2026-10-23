import AppKit
import WinwayCore

@MainActor
final class ExplorerWindow: NSWindow {
    var onMouseNavigation: ((CommandID) -> Void)?
    var onMouseDown: ((NSEvent) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
            onMouseDown?(event)
        }
        // AppKit otherwise treats Control-left-click as a context-menu request
        // before the table's Windows selection handler receives mouseDown.
        if event.type == .leftMouseDown, event.modifierFlags.contains(.control),
           attachedSheet == nil, NSApp.modalWindow == nil, let contentView {
            var target = contentView.hitTest(contentView.convert(event.locationInWindow, from: nil))
            while let view = target {
                if let field = view as? NSTextField, field.isEditable { break }
                if view is NSTextView { break }
                if let table = view as? ExplorerFileTable {
                    if table.windowsSelection, table.row(at: table.convert(event.locationInWindow, from: nil)) >= 0 {
                        table.mouseDown(with: event)
                        return
                    }
                    break
                }
                target = view.superview
            }
        }
        guard event.type == .otherMouseDown || event.type == .otherMouseUp,
              event.buttonNumber == 3 || event.buttonNumber == 4,
              attachedSheet == nil, NSApp.modalWindow == nil else {
            super.sendEvent(event)
            return
        }

        // Handle the press only; consuming the release avoids a second action.
        // AppKit numbers the standard back/forward side buttons from zero.
        if event.type == .otherMouseDown {
            onMouseNavigation?(event.buttonNumber == 3 ? .back : .forward)
        }
    }
}
