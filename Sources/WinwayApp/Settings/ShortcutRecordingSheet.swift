import SwiftUI
import WinwayCore

struct ShortcutRecordingSheet: View {
    @ObservedObject var store: KeyboardSettingsStore
    let command: CommandID
    @Environment(\.dismiss) private var dismiss
    @StateObject private var capture = ShortcutRecordingState()
    @FocusState private var saveFocused: Bool
    @FocusState private var retryFocused: Bool

    var body: some View {
        VStack(spacing: 18) {
            Text("修改“\(command.title)”快捷键").font(.headline)
            Text(capture.candidate?.displayName ?? "请按下组合键…")
                .font(.system(size: 22, design: .monospaced)).frame(height: 44)
            Text(capture.isCapturing ? "请按下组合键；Escape 取消，纯修饰键与自动重复不会被录入。" : "Return 保存，⌘R 重新录入，Escape 取消。")
                .font(.caption).foregroundStyle(.secondary)
            if let recordingError = capture.recordingError { Text(recordingError).foregroundStyle(.red).font(.caption) }
            HStack {
                Button("重新录入", action: restartCapture)
                    .disabled(capture.isCapturing)
                    .keyboardShortcut("r", modifiers: .command)
                    .focused($retryFocused)
                Button("取消", action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: save)
                    .disabled(capture.isCapturing || capture.candidate == nil || capture.recordingError != nil)
                    .keyboardShortcut(.defaultAction)
                    .focused($saveFocused)
            }
            KeyRecorder(isCapturing: capture.isCapturing, onKey: receive)
                .frame(width: 1, height: 1)
        }.padding(28).frame(width: 410)
    }

    private func receive(_ binding: KeyBinding) {
        if binding.key == "escape" { cancel(); return }
        capture.candidate = binding
        capture.recordingError = store.validationError(for: binding, command: command)
        capture.isCapturing = false
        saveFocused = capture.recordingError == nil
        retryFocused = capture.recordingError != nil
    }

    private func restartCapture() {
        saveFocused = false; retryFocused = false
        capture.candidate = nil; capture.recordingError = nil; capture.isCapturing = true
    }

    private func cancel() { dismiss() }

    private func save() {
        guard let candidate = capture.candidate, store.setBinding(candidate, for: command) else { return }
        dismiss()
    }
}
