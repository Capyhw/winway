import AppKit
import WinwayCore

@main
struct KeyRecorderRunner {
    @MainActor
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let recorder = RecorderView()
        var captured: [KeyBinding] = []
        recorder.onKey = { captured.append($0) }
        func event(_ code: UInt16, _ text: String, type: NSEvent.EventType = .keyDown,
                   modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers, timestamp: 0,
                            windowNumber: 0, context: nil, characters: text,
                            charactersIgnoringModifiers: text, isARepeat: repeatKey, keyCode: code)!
        }

        recorder.isCapturing = true
        precondition(recorder.handleKeyEvent(event(15, "r", modifiers: [.command, .shift])) == nil)
        precondition(captured == [KeyBinding(key: "r", modifiers: [.command, .shift])])
        precondition(!recorder.isCapturing)
        for (code, text): (UInt16, String) in [(48, "\t"), (36, "\r"), (49, " "), (53, "\u{1b}")] {
            let next = event(code, text)
            precondition(recorder.handleKeyEvent(next) === next, "Confirmation keys must reach the sheet")
        }
        precondition(captured.count == 1, "Confirmation keys must not replace the candidate")
        print("PASS: capture once, then release Tab/Return/Space/Escape to sheet controls")

        for (code, text): (UInt16, String) in [(36, "\r"), (49, " ")] {
            recorder.isCapturing = true
            precondition(recorder.handleKeyEvent(event(code, text)) == nil)
            let count = captured.count
            precondition(recorder.handleKeyEvent(event(code, text, repeatKey: true)) == nil,
                         "Holding the candidate key must not accidentally confirm")
            precondition(captured.count == count)
            precondition(recorder.handleKeyEvent(event(code, text, type: .keyUp)) == nil)
            precondition(recorder.handleKeyEvent(event(code, text)) != nil)
        }
        print("PASS: recorded Return/Space repeats are consumed; a fresh press reaches confirmation")

        recorder.isCapturing = true
        let count = captured.count
        precondition(recorder.handleKeyEvent(event(15, "r", repeatKey: true)) == nil)
        precondition(recorder.isCapturing && captured.count == count)
        precondition(recorder.handleKeyEvent(event(48, "\t")) == nil)
        precondition(captured.last == KeyBinding(key: "tab"))
        recorder.isCapturing = true
        precondition(recorder.handleKeyEvent(event(53, "\u{1b}")) == nil)
        precondition(captured.last == KeyBinding(key: "escape"))
        print("PASS: retry captures again, ignores repeats, allows Tab binding and reports Escape for cancellation")

        let store = KeyboardSettingsStore(persistence: .init(load: { nil }, save: { _ in }))
        recorder.isCapturing = true
        precondition(recorder.handleKeyEvent(event(8, "c", modifiers: .control)) == nil)
        precondition(store.validationError(for: captured.last!, command: .rename) != nil)
        precondition(!recorder.isCapturing)
        let tab = event(48, "\t")
        precondition(recorder.handleKeyEvent(tab) === tab, "Conflict must still allow keyboard navigation")
        print("PASS: conflicting candidate exits capture so retry/cancel remain keyboard-accessible")
        recorder.stopMonitoring()
    }
}
