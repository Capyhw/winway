import Foundation

public enum CommandID: String, CaseIterable, Codable, Sendable, Identifiable {
    case open, rename, copy, cut, paste, moveHere, trash, selectAll, newFolder
    case newTab, closeTab, back, forward, up, focusAddress, focusSearch, refresh, settings, toggleHidden, toggleDetails
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .open: "打开"; case .rename: "重命名"; case .copy: "复制"; case .cut: "剪切"
        case .paste: "粘贴"; case .moveHere: "移动到此处"; case .trash: "移到废纸篓"
        case .selectAll: "全选"; case .newFolder: "新建文件夹"; case .newTab: "新建标签页"
        case .closeTab: "关闭标签页"; case .back: "后退"; case .forward: "前进"; case .up: "上级目录"
        case .focusAddress: "输入路径"; case .focusSearch: "搜索当前目录"; case .refresh: "刷新"
        case .settings: "设置"; case .toggleHidden: "显示隐藏文件"; case .toggleDetails: "显示详情"
        }
    }
    public var isWriteOperation: Bool { [.rename, .paste, .moveHere, .trash, .newFolder].contains(self) }
    public var requiresSelection: Bool { [.open, .rename, .copy, .cut, .trash].contains(self) }
}

public enum KeyboardPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case windows, macOS
    public var id: String { rawValue }
    public var title: String { self == .windows ? "Windows" : "macOS" }
    public var selectionModifier: KeyModifiers { self == .windows ? .control : .command }
}

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1)
    public static let command = Self(rawValue: 2)
    public static let option = Self(rawValue: 4)
    public static let shift = Self(rawValue: 8)
}

public struct KeyBinding: Codable, Hashable, Sendable {
    public let key: String
    public let modifiers: KeyModifiers
    public init(key: String, modifiers: KeyModifiers = []) {
        self.key = key.lowercased()
        self.modifiers = modifiers
    }
    public var displayName: String {
        var parts = [String]()
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        let names = ["return": "Return", "enter": "Enter", "backspace": "⌫", "delete": "⌦", "left": "←", "right": "→", "up": "↑", "down": "↓", "space": "Space", "tab": "Tab", "escape": "Esc"]
        parts.append(names[key] ?? key.uppercased())
        return parts.joined(separator: "+")
    }
    public var isValidLogicalKey: Bool {
        let named = ["return", "enter", "backspace", "delete", "left", "right", "up", "down", "space", "tab", "escape", "home", "end", "pageup", "pagedown"]
        return key.count == 1 || named.contains(key) || (1...20).contains(where: { key == "f\($0)" })
    }
    public var isReserved: Bool {
        if key == "escape" { return true }
        if modifiers == .command && ["space", "tab", "q", "h", "m"].contains(key) { return true }
        if modifiers == [.command, .option] && ["escape", "h", "m"].contains(key) { return true }
        if modifiers == [.command, .control] && key == "q" { return true }
        if modifiers == [.command, .shift] && ["3", "4", "5", "q"].contains(key) { return true }
        return false
    }
}

public extension CommandID {
    func defaultBindings(for preset: KeyboardPreset) -> [KeyBinding] {
        let primary: KeyModifiers = preset == .windows ? .control : .command
        func b(_ key: String, _ modifiers: KeyModifiers? = nil) -> [KeyBinding] { [KeyBinding(key: key, modifiers: modifiers ?? primary)] }
        switch self {
        case .open: return preset == .windows ? b("return", []) + b("enter", []) : b("down")
        case .rename: return preset == .windows ? b("f2", []) : b("return", []) + b("enter", [])
        case .copy: return b("c")
        case .cut: return b("x")
        case .paste: return b("v")
        case .moveHere: return preset == .macOS ? b("v", [.command, .option]) : []
        case .trash: return preset == .windows ? b("backspace", []) : b("backspace")
        case .selectAll: return b("a")
        case .newFolder: return b("n", [primary, .shift])
        case .newTab: return b("t")
        case .closeTab: return b("w")
        case .back: return preset == .windows ? b("left", .option) : b("[")
        case .forward: return preset == .windows ? b("right", .option) : b("]")
        case .up: return preset == .windows ? b("up", .option) : b("up")
        case .focusAddress: return b("l")
        case .focusSearch: return b("f")
        case .refresh: return preset == .windows ? b("f5", []) : b("r")
        case .settings: return b(",")
        case .toggleHidden: return b(".", [primary, .shift])
        case .toggleDetails: return preset == .windows ? b("p", .option) : b("p", [.command, .option])
        }
    }
}
