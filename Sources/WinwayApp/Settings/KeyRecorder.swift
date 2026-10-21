import SwiftUI
import WinwayCore

struct KeyRecorder: NSViewRepresentable {
    let isCapturing: Bool
    let onKey: (KeyBinding) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onKey = onKey
        view.isCapturing = isCapturing
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.onKey = onKey
        nsView.isCapturing = isCapturing
    }

    static func dismantleNSView(_ nsView: RecorderView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}
