import AppKit
import WinwayCore

@MainActor
enum KeyboardEventAdapter {
    static func menuEquivalent(for binding: KeyBinding) -> (key: String, modifiers: NSEvent.ModifierFlags) {
        var modifiers: NSEvent.ModifierFlags = []
        if binding.modifiers.contains(.control) { modifiers.insert(.control) }
        if binding.modifiers.contains(.command) { modifiers.insert(.command) }
        if binding.modifiers.contains(.option) { modifiers.insert(.option) }
        if binding.modifiers.contains(.shift) { modifiers.insert(.shift) }
        let special: [String: UInt32] = [
            "return": 0x0d, "enter": 0x03, "backspace": 0x08, "delete": UInt32(NSDeleteFunctionKey),
            "tab": 0x09, "space": 0x20, "escape": 0x1b,
            "left": UInt32(NSLeftArrowFunctionKey), "right": UInt32(NSRightArrowFunctionKey),
            "up": UInt32(NSUpArrowFunctionKey), "down": UInt32(NSDownArrowFunctionKey),
            "home": UInt32(NSHomeFunctionKey), "end": UInt32(NSEndFunctionKey),
            "pageup": UInt32(NSPageUpFunctionKey), "pagedown": UInt32(NSPageDownFunctionKey)
        ]
        if let value = special[binding.key], let scalar = UnicodeScalar(value) {
            return (String(scalar), modifiers)
        }
        if binding.key.hasPrefix("f"), let number = Int(binding.key.dropFirst()), (1...20).contains(number),
           let scalar = UnicodeScalar(UInt32(NSF1FunctionKey) + UInt32(number - 1)) {
            return (String(scalar), modifiers)
        }
        return (binding.key.count == 1 ? binding.key : "", modifiers)
    }
    static func binding(from event: NSEvent) -> KeyBinding? {
        guard event.type == .keyDown else { return nil }
        var modifiers: KeyModifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        let special: [UInt16: String] = [36: "return", 76: "enter", 51: "backspace", 117: "delete", 53: "escape", 48: "tab", 49: "space", 123: "left", 124: "right", 125: "down", 126: "up", 115: "home", 119: "end", 116: "pageup", 121: "pagedown", 122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12", 105: "f13", 107: "f14", 113: "f15", 106: "f16", 64: "f17", 79: "f18", 80: "f19", 90: "f20"]
        guard let key = special[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.lowercased(), !key.isEmpty else { return nil }
        return KeyBinding(key: key, modifiers: modifiers)
    }
    static func hasMarkedText(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        return (responder as? NSTextInputClient)?.hasMarkedText() ?? false
    }
    static func isTextEditing(in window: NSWindow?) -> Bool {
        guard let responder = window?.firstResponder else { return false }
        return responder is NSTextView || responder is NSTextField || (responder as? NSTextInputClient)?.hasMarkedText() == true
    }
    static func shouldAllowCommands(in window: NSWindow?) -> Bool {
        NSApp.isActive && window?.isKeyWindow == true && NSApp.modalWindow == nil && window?.attachedSheet == nil && !isTextEditing(in: window)
    }
}
