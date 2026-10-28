import AppKit
import SwiftUI

@MainActor
final class PermissionOnboardingController: NSWindowController, NSWindowDelegate {
    private let store: SearchSettingsStore
    init(store: SearchSettingsStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 570, height: 490),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "欢迎使用 Winway"
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: PermissionOnboardingView(store: store))
        super.init(window: window)
        window.delegate = self; window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func windowWillClose(_ notification: Notification) { store.dismissOnboarding() }
}

struct PermissionOnboardingView: View {
    @ObservedObject var store: SearchSettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("让 Winway 搜索你的文件", systemImage: "folder.badge.gearshape")
                .font(.system(size: 23, weight: .semibold))
            Text("先允许访问受保护目录，再建立完整的搜索索引。")
                .foregroundStyle(.secondary)
            DiskAccessControl(store: store)
            Spacer(minLength: 0)
            HStack {
                if store.access == .granted {
                    Text(store.indexMessage).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                } else { Text("暂不开启也可以浏览文件。").font(.callout).foregroundStyle(.secondary) }
                Spacer()
                Button(store.access == .granted ? "开始使用" : "稍后设置") { store.dismissOnboarding() }
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 570, height: 490).background(Color(nsColor: ExplorerStyle.chrome))
            .foregroundStyle(Color(nsColor: ExplorerStyle.text)).tint(Color(nsColor: ExplorerStyle.accent))
    }
}
