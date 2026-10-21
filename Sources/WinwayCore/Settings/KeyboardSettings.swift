import Foundation
import Combine

public struct KeyboardConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var activePreset: KeyboardPreset = .windows
    // Empty array explicitly disables a command; absent key inherits its default.
    public var windowsOverrides: [String: [KeyBinding]] = [:]
    public var macOverrides: [String: [KeyBinding]] = [:]
    public init() {}
    public func bindings(for command: CommandID, preset: KeyboardPreset? = nil) -> [KeyBinding] {
        let profile = preset ?? activePreset
        let overrides = profile == .windows ? windowsOverrides : macOverrides
        return overrides[command.rawValue] ?? command.defaultBindings(for: profile)
    }
    public mutating func override(_ command: CommandID, bindings: [KeyBinding]?) {
        if activePreset == .windows { windowsOverrides[command.rawValue] = bindings }
        else { macOverrides[command.rawValue] = bindings }
    }
    public func validated() throws {
        guard schemaVersion == 1 else { throw KeyboardSettingsError.invalidConfiguration }
        for profile in KeyboardPreset.allCases {
            let overrides = profile == .windows ? windowsOverrides : macOverrides
            for (command, bindings) in overrides {
                guard CommandID(rawValue: command) != nil, bindings.count <= 1,
                      bindings.allSatisfy({ $0.isValidLogicalKey && !$0.isReserved && ($0.modifiers.rawValue & ~15) == 0 }) else {
                    throw KeyboardSettingsError.invalidConfiguration
                }
            }
            var seen: [KeyBinding: CommandID] = [:]
            for command in CommandID.allCases {
                for binding in bindings(for: command, preset: profile) {
                    if let existing = seen[binding], existing != command { throw KeyboardSettingsError.conflict(existing) }
                    seen[binding] = command
                }
            }
        }
    }
}

public enum KeyboardSettingsError: LocalizedError, Equatable {
    case invalidConfiguration, invalidBinding, reserved, conflict(CommandID)
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "快捷键配置无法读取，已恢复 Windows 默认设置。"
        case .invalidBinding: "请录入一个按键或组合键，不能只使用修饰键。"
        case .reserved: "该组合键由系统或应用保留，请选择其他按键。"
        case .conflict(let command): "与“\(command.title)”冲突，请先修改或清除该命令的绑定。"
        }
    }
}

public struct KeyboardSettingsPersistence {
    public var load: () throws -> Data?
    public var save: (Data) throws -> Void
    public init(load: @escaping () throws -> Data?, save: @escaping (Data) throws -> Void) {
        self.load = load
        self.save = save
    }
    public static func file(at url: URL) -> Self {
        Self(load: {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        }, save: { data in
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        })
    }
}

@MainActor
public final class KeyboardSettingsStore: ObservableObject {
    @Published public private(set) var configuration: KeyboardConfiguration
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var hasUnsavedChanges = false
    @Published public var isRecording = false
    private let persistence: KeyboardSettingsPersistence
    public var activePreset: KeyboardPreset { configuration.activePreset }
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Winway/keyboard.json")
    }
    public convenience init(configurationURL: URL? = nil) { self.init(persistence: .file(at: configurationURL ?? Self.defaultURL)) }
    public convenience init(url: URL) { self.init(configurationURL: url) }
    public init(persistence: KeyboardSettingsPersistence) {
        self.persistence = persistence
        var configuration = KeyboardConfiguration()
        var warning: String?
        do {
            if let data = try persistence.load() {
                configuration = try JSONDecoder().decode(KeyboardConfiguration.self, from: data)
                try configuration.validated()
            }
        } catch {
            configuration = KeyboardConfiguration()
            warning = "快捷键配置无法读取，已恢复 Windows 默认设置。原文件未覆盖；重新保存设置可修复。"
        }
        self.configuration = configuration
        self.statusMessage = warning
    }
    public func bindings(for command: CommandID) -> [KeyBinding] { configuration.bindings(for: command) }
    public func shortcutLabel(for command: CommandID) -> String { bindings(for: command).map(\.displayName).joined(separator: " / ") }
    public func command(for binding: KeyBinding, isRepeat: Bool = false) -> CommandID? {
        guard !isRecording else { return nil }
        return CommandID.allCases.first { bindings(for: $0).contains(binding) && !(isRepeat && $0.isWriteOperation) }
    }
    public func validationError(for binding: KeyBinding, command: CommandID) -> String? {
        if !binding.isValidLogicalKey || binding.modifiers.rawValue & ~15 != 0 { return KeyboardSettingsError.invalidBinding.localizedDescription }
        if binding.isReserved { return KeyboardSettingsError.reserved.localizedDescription }
        if let conflict = CommandID.allCases.first(where: { $0 != command && bindings(for: $0).contains(binding) }) {
            return KeyboardSettingsError.conflict(conflict).localizedDescription
        }
        return nil
    }
    public func setPreset(_ preset: KeyboardPreset) {
        var next = configuration; next.activePreset = preset; commit(next)
    }
    @discardableResult public func setBinding(_ binding: KeyBinding, for command: CommandID) -> Bool {
        if let error = validationError(for: binding, command: command) { statusMessage = error; return false }
        var next = configuration; next.override(command, bindings: [binding]); commit(next); return true
    }
    public func clearBinding(for command: CommandID) {
        var next = configuration; next.override(command, bindings: []); commit(next)
    }
    @discardableResult public func restoreDefault(for command: CommandID) -> Bool {
        var next = configuration; next.override(command, bindings: nil)
        do { try next.validated(); commit(next); return true }
        catch { statusMessage = error.localizedDescription; return false }
    }
    public func restoreCurrentDefaults() {
        var next = configuration
        if next.activePreset == .windows { next.windowsOverrides = [:] } else { next.macOverrides = [:] }
        commit(next)
    }
    public func retrySave() { commit(configuration) }
    private func commit(_ next: KeyboardConfiguration) {
        configuration = next
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try persistence.save(encoder.encode(next))
            hasUnsavedChanges = false; statusMessage = "已保存"
        } catch {
            hasUnsavedChanges = true
            statusMessage = "未保存：\(error.localizedDescription)。当前窗口已应用，退出后可能丢失；请重试保存。"
        }
    }
}
