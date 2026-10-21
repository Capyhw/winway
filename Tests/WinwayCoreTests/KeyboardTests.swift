import Testing
import Foundation
@testable import WinwayCore

@MainActor
struct KeyboardTests {
    func memoryStore() -> KeyboardSettingsStore {
        KeyboardSettingsStore(persistence: .init(load: { nil }, save: { _ in }))
    }
    @Test func defaultPresetsAndSwitching() throws {
        let store = memoryStore()
        #expect(store.activePreset == .windows)
        #expect(store.command(for: .init(key: "return")) == .open)
        #expect(store.command(for: .init(key: "f2")) == .rename)
        #expect(store.command(for: .init(key: "backspace")) == .trash)
        #expect(store.command(for: .init(key: "delete")) == nil)
        #expect(store.command(for: .init(key: "c", modifiers: .control)) == .copy)
        store.setPreset(.macOS)
        #expect(store.command(for: .init(key: "return")) == .rename)
        #expect(store.command(for: .init(key: "c", modifiers: .control)) == nil)
        #expect(store.command(for: .init(key: "c", modifiers: .command)) == .copy)
        #expect(store.command(for: .init(key: "v", modifiers: [.command, .option])) == .moveHere)
        try store.configuration.validated()
    }
    @Test func customBindingReplacesAliasesAndSurvivesPresetSwitch() {
        let store = memoryStore()
        let binding = KeyBinding(key: "o", modifiers: [.control, .shift])
        #expect(store.setBinding(binding, for: .open))
        #expect(store.command(for: .init(key: "return")) == nil)
        #expect(store.command(for: .init(key: "enter")) == nil)
        #expect(store.command(for: binding) == .open)
        store.setPreset(.macOS)
        #expect(store.command(for: binding) == nil)
        store.setPreset(.windows)
        #expect(store.command(for: binding) == .open)
    }
    @Test func conflictsAndReservedKeysLeaveOriginalBinding() {
        let store = memoryStore()
        #expect(!store.setBinding(.init(key: "c", modifiers: .control), for: .rename))
        #expect(store.statusMessage?.contains("复制") == true)
        #expect(store.command(for: .init(key: "f2")) == .rename)
        #expect(!store.setBinding(.init(key: "escape"), for: .rename))
        #expect(!store.setBinding(.init(key: "space", modifiers: .command), for: .rename))
        #expect(!store.setBinding(.init(key: "", modifiers: .shift), for: .rename))
    }
    @Test func restoringSingleItemChecksReusedDefault() {
        let store = memoryStore()
        store.clearBinding(for: .copy)
        #expect(store.setBinding(.init(key: "c", modifiers: .control), for: .rename))
        #expect(!store.restoreDefault(for: .copy))
        #expect(store.bindings(for: .copy).isEmpty)
        store.restoreCurrentDefaults()
        #expect(store.command(for: .init(key: "c", modifiers: .control)) == .copy)
    }
    @Test func restoreOnlyCurrentPresetAndSuppressRecordingAndWriteRepeats() {
        let store = memoryStore()
        store.clearBinding(for: .copy)
        store.setPreset(.macOS)
        store.clearBinding(for: .copy)
        store.setPreset(.windows)
        store.restoreCurrentDefaults()
        #expect(!store.bindings(for: .copy).isEmpty)
        #expect(store.command(for: .init(key: "backspace"), isRepeat: true) == nil)
        store.isRecording = true
        #expect(store.command(for: .init(key: "return")) == nil)
        store.isRecording = false
        store.setPreset(.macOS)
        #expect(store.bindings(for: .copy).isEmpty)
    }
    @Test func atomicPersistenceAndReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("keyboard.json")
        let store = KeyboardSettingsStore(configurationURL: url)
        store.setPreset(.macOS)
        store.clearBinding(for: .rename)
        #expect(!store.hasUnsavedChanges)
        let loaded = KeyboardSettingsStore(configurationURL: url)
        #expect(loaded.activePreset == .macOS)
        #expect(loaded.bindings(for: .rename).isEmpty)
        try loaded.configuration.validated()
    }
    @Test func corruptUnknownVersionAndDuplicateConfigurationsRecover() throws {
        let corrupt = KeyboardSettingsStore(persistence: .init(load: { Data("invalid".utf8) }, save: { _ in }))
        #expect(corrupt.activePreset == .windows)
        #expect(corrupt.statusMessage?.contains("恢复") == true)
        var unsupported = KeyboardConfiguration(); unsupported.schemaVersion = 99
        let unsupportedData = try JSONEncoder().encode(unsupported)
        let newer = KeyboardSettingsStore(persistence: .init(load: { unsupportedData }, save: { _ in }))
        #expect(newer.statusMessage?.contains("恢复") == true)
        var duplicate = KeyboardConfiguration()
        duplicate.override(.rename, bindings: [.init(key: "c", modifiers: .control)])
        let duplicateData = try JSONEncoder().encode(duplicate)
        let invalid = KeyboardSettingsStore(persistence: .init(load: { duplicateData }, save: { _ in }))
        #expect(invalid.command(for: .init(key: "f2")) == .rename)
        #expect(invalid.statusMessage?.contains("恢复") == true)
    }
    @Test func saveFailureIsExplicitAndCanRetry() {
        var fail = true
        let store = KeyboardSettingsStore(persistence: .init(load: { nil }, save: { _ in
            if fail { throw CocoaError(.fileWriteNoPermission) }
        }))
        store.setPreset(.macOS)
        #expect(store.activePreset == .macOS)
        #expect(store.hasUnsavedChanges)
        #expect(store.statusMessage?.contains("未保存") == true)
        fail = false
        store.retrySave()
        #expect(!store.hasUnsavedChanges)
        #expect(store.statusMessage == "已保存")
    }
}
