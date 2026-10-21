import AppKit
import WinwayCore

@MainActor
final class RecorderView: NSView {
    var onKey: ((KeyBinding) -> Void)?
    var isCapturing = false {
        didSet {
            if isCapturing && !oldValue { window?.makeFirstResponder(self) }
        }
    }
    private var monitor: Any?
    private var capturedKeyCode: UInt16?

    override var acceptsFirstResponder: Bool { isCapturing }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard let window else { return }
        if isCapturing { window.makeFirstResponder(self) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, NSApp.isActive, self.window?.isKeyWindow == true,
                      !KeyboardEventAdapter.hasMarkedText(in: self.window) else { return false }
                return self.handleKeyEvent(event) == nil
            }
            return consumed ? nil : event
        }
    }

    func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyUp {
            if event.keyCode == capturedKeyCode {
                capturedKeyCode = nil
                return nil
            }
            return event
        }
        guard event.type == .keyDown else { return event }
        // Holding a recorded Return/Space must not activate a confirmation button.
        if event.isARepeat && (isCapturing || event.keyCode == capturedKeyCode) { return nil }
        guard isCapturing else { return event }
        guard let binding = KeyboardEventAdapter.binding(from: event) else { return nil }
        capturedKeyCode = event.keyCode
        isCapturing = false
        window?.makeFirstResponder(nil)
        onKey?(binding)
        return nil
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        capturedKeyCode = nil
    }
}
