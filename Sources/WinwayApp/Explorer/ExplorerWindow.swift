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
