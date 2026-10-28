import AppKit
import SwiftUI
import WinwayCore

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let store: KeyboardSettingsStore
    private let navigation = SettingsNavigation()
    init(store: KeyboardSettingsStore, search: SearchSettingsStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.collectionBehavior = [.fullScreenNone, .fullScreenDisallowsTiling]
        window.title = "Winway 设置"
        window.appearance = NSAppearance(named: .aqua)
        window.minSize = NSSize(width: 800, height: 520)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(keyboard: store, search: search, navigation: navigation))
        super.init(window: window)
        window.delegate = self
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func showPage(_ page: SettingsPage) { navigation.selection = page; showWindow(nil) }
    override func showWindow(_ sender: Any?) { super.showWindow(sender); window?.makeKeyAndOrderFront(sender) }
    func windowWillClose(_ notification: Notification) { store.isRecording = false }
}
