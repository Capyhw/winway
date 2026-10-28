import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject var store: UpdateSettingsStore
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("关于").font(.system(size: 23, weight: .semibold))
            HStack(spacing: 18) {
                if let url = Bundle.main.url(forResource: "Winway", withExtension: "icns"), let image = NSImage(contentsOf: url) {
                    Image(nsImage: image).resizable().frame(width: 76, height: 76).accessibilityHidden(true)
                } else {
                    Image(systemName: "folder.fill").font(.system(size: 48)).foregroundStyle(.tint).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Winway").font(.system(size: 28, weight: .semibold))
                    Text("版本 \(store.version)（\(store.build)）").foregroundStyle(.secondary).textSelection(.enabled)
                    Text("macOS 原生文件管理器").foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Text("软件更新").font(.headline)
                HStack {
                    if store.state == .checking { ProgressView().controlSize(.small) }
                    Text(store.message).id(store.message).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack {
                    Button("检查更新") { store.check() }.disabled(store.state == .checking)
                    if case .available(_, let url) = store.state {
                        Button("前往下载") { NSWorkspace.shared.open(url) }.buttonStyle(.borderedProminent)
                    }
                }
                Text("下载适合此 Mac 的安装包后替换应用。更新不会自动安装。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Divider()
            Link("项目主页与反馈", destination: URL(string: "https://github.com/Capyhw/winway")!)
            Spacer()
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .contain)
    }
}
