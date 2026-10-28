import AppKit
import SwiftUI
import Combine
import WinwayCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case keyboard = "快捷键", permissions = "权限", about = "关于"
    var id: Self { self }
    var icon: String {
        switch self { case .keyboard: "keyboard"; case .permissions: "lock.shield"; case .about: "info.circle" }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsPage = .keyboard
}

struct SettingsView: View {
    @ObservedObject var keyboard: KeyboardSettingsStore
    @ObservedObject var search: SearchSettingsStore
    @ObservedObject var navigation: SettingsNavigation
    @StateObject private var updates = UpdateSettingsStore()

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SettingsPage.allCases) { page in
                    Button { navigation.selection = page } label: {
                        Label(page.rawValue, systemImage: page.icon)
                            .font(.system(size: 14, weight: navigation.selection == page ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(navigation.selection == page ? Color(nsColor: ExplorerStyle.selected) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(navigation.selection == page ? .isSelected : [])
                }
                Spacer()
            }.padding(12).frame(width: 174).frame(maxHeight: .infinity)
                .background(Color(nsColor: ExplorerStyle.sidebar))
            Divider()
            Group {
                switch navigation.selection {
                case .keyboard: KeyboardSettingsView(store: keyboard)
                case .permissions: PermissionsSettingsView(store: search)
                case .about: AboutSettingsView(store: updates)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Color(nsColor: ExplorerStyle.chrome))
            .foregroundStyle(Color(nsColor: ExplorerStyle.text))
            .tint(Color(nsColor: ExplorerStyle.accent))
    }
}

struct PermissionsSettingsView: View {
    @ObservedObject var store: SearchSettingsStore
    @State private var confirmRebuild = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("权限").font(.system(size: 23, weight: .semibold))
                DiskAccessControl(store: store)
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("搜索索引").font(.headline)
                    HStack(alignment: .top, spacing: 12) {
                        if store.isBusy { ProgressView().controlSize(.small) }
                        Text(store.indexMessage).id(store.indexMessage).foregroundStyle(.secondary).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let granted = store.engineAccess {
                        Label(granted ? "搜索服务权限已生效" : "搜索服务权限尚未生效",
                              systemImage: granted ? "checkmark.circle" : "exclamationmark.circle")
                            .font(.callout).foregroundStyle(granted ? Color.secondary : Color.orange)
                    }
                    Button("重新建立索引…") { confirmRebuild = true }
                        .disabled(store.access != .granted || store.isBusy || store.checkingAccess)
                    Text("重新扫描文件与内容，补全此前因权限而遗漏的目录。不会修改或删除你的文件。索引建立期间暂时无法搜索。")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if store.engineAccess == false {
                        Button("在访达中显示搜索辅助程序") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/fsearch")])
                        }
                    }
                }
                Spacer(minLength: 0)
            }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
        }.onAppear { store.refreshAccess() }
            .alert("重新建立搜索索引？", isPresented: $confirmRebuild) {
                Button("取消", role: .cancel) {}
                Button("重新建立") { store.rebuildIndex() }
            } message: { Text("将清理现有搜索缓存并重新扫描。你的文件保持不变，耗时取决于磁盘中的文件数量。") }
    }
}

struct DiskAccessControl: View {
    @ObservedObject var store: SearchSettingsStore
    private var status: String {
        if store.checkingAccess { return "正在检测…" }
        switch store.access {
        case .granted: return "已开启"
        case .denied: return "未开启或尚未生效"
        case .unknown: return "暂时无法确认"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("完全磁盘访问权限").font(.headline)
                    Text(status).id(status).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("完全磁盘访问权限", isOn: Binding(get: { store.access == .granted }, set: { _ in store.openSystemSettings() }))
                    .labelsHidden().toggleStyle(.switch)
                    .help("此开关显示检测结果；点击前往 macOS 系统设置更改权限。")
                    .accessibilityHint("打开系统设置以更改权限")
            }
            Text("用于搜索桌面、文档、下载等受保护目录。权限由 macOS 管理，Winway 无法代你开启或关闭。")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("在「系统设置 → 隐私与安全性 → 完全磁盘访问权限」中开启 Winway；若列表中没有，请点 + 添加此应用。返回 Winway 后会自动检测并开始索引。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("打开系统设置") { store.openSystemSettings() }
                Button("重新检测") { store.refreshAccess() }.disabled(store.checkingAccess)
            }
            if store.access != .granted {
                Text("如果已开启却仍显示未生效，请退出并重新打开 Winway。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
