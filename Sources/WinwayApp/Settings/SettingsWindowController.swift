import AppKit
import SwiftUI
import Combine
import WinwayCore

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let store: KeyboardSettingsStore
    init(store: KeyboardSettingsStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.collectionBehavior = [.fullScreenNone, .fullScreenDisallowsTiling]
        window.title = "Winway 设置"
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 620, height: 440)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: KeyboardSettingsView(store: store))
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func showWindow(_ sender: Any?) { super.showWindow(sender); window?.makeKeyAndOrderFront(sender) }
    func windowWillClose(_ notification: Notification) { store.isRecording = false }
}

@MainActor
private final class KeyboardEditorState: ObservableObject {
    @Published var recording: CommandID?
    @Published var confirmingReset = false
}

private struct KeyboardSettingsView: View {
    @ObservedObject var store: KeyboardSettingsStore
    @ObservedObject private var editor = KeyboardEditorState()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("键盘习惯").font(.system(size: 23, weight: .semibold))
            Picker("预设", selection: Binding(get: { store.activePreset }, set: { store.setPreset($0) })) {
                ForEach(KeyboardPreset.allCases) { preset in Text(preset.title).tag(preset) }
            }.pickerStyle(.segmented).frame(maxWidth: 320)
            Text("每套预设独立保存修改。文本输入始终优先；macOS 的 ⌘X 是 Winway 提供的剪切扩展。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(CommandID.allCases) { command in
                        HStack(spacing: 12) {
                            Text(command.title).frame(maxWidth: .infinity, alignment: .leading)
                            Text(store.shortcutLabel(for: command).isEmpty ? "未绑定" : store.shortcutLabel(for: command))
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                            Button("修改") { beginRecording(command) }
                                .accessibilityLabel("修改\(command.title)快捷键")
                            Button("清除") { store.clearBinding(for: command) }
                                .accessibilityLabel("清除\(command.title)快捷键")
                            Button("恢复") { store.restoreDefault(for: command) }
                                .accessibilityLabel("恢复\(command.title)快捷键")
                        }.padding(.vertical, 9).padding(.horizontal, 12)
                        Divider()
                    }
                }.background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text("系统或其他软件可能额外占用快捷键，Winway 无法检测所有占用。保存后请在文件列表中实际试用；部分键盘的 F2 需要同时按 Fn。")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button("恢复当前预设全部默认按键…") { editor.confirmingReset = true }
                Spacer()
                if store.hasUnsavedChanges { Button("重试保存") { store.retrySave() } }
            }
            if let message = store.statusMessage {
                Text(message).font(.system(size: 12)).foregroundStyle(store.hasUnsavedChanges ? Color.red : Color.secondary).textSelection(.enabled)
            }
        }.padding(24).frame(minWidth: 580, minHeight: 400)
            .background(Color(nsColor: ExplorerStyle.chrome))
            .foregroundStyle(Color(nsColor: ExplorerStyle.text))
            .tint(Color(nsColor: ExplorerStyle.accent))
            .alert("恢复 \(store.activePreset.title) 默认按键？", isPresented: $editor.confirmingReset) {
                Button("取消", role: .cancel) {}
                Button("恢复", role: .destructive) { store.restoreCurrentDefaults() }
            } message: { Text("只清除当前预设的自定义设置，另一套预设保持不变。") }
            .sheet(item: $editor.recording, onDismiss: { store.isRecording = false }) { command in
                ShortcutRecordingSheet(store: store, command: command)
            }
    }
    private func beginRecording(_ command: CommandID) {
        store.isRecording = true; editor.recording = command
    }
}
