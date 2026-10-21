import Combine
import WinwayCore

@MainActor
final class ShortcutRecordingState: ObservableObject {
    @Published var candidate: KeyBinding?
    @Published var recordingError: String?
    @Published var isCapturing = true
}
