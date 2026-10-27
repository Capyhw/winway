import AppKit
import WinwayCore

struct ExplorerTab {
    var id: UUID
    var title: String
}

struct ExplorerLocation {
    var title: String
    var url: URL
    var icon: String
    var isVolume: Bool = false
}

enum ExplorerPreview {
    case none
    case loading
    case text(String)
    case image(NSImage)
    case unavailable(String)
}

struct ExplorerSnapshot {
    var tabs: [ExplorerTab] = []
    var activeTabID = UUID()
    var directory = FileManager.default.homeDirectoryForCurrentUser
    var entries: [FileEntry] = []
    var selection: Set<URL> = []
    var filter = ""
    var locations: [ExplorerLocation] = []
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    var isSearching = false
    var errorMessage: String?
    var statusMessage: String?
    var showHidden = false
    var showDetails = true
    var preset: KeyboardPreset = .windows
    var enabledCommands: Set<CommandID> = []
    var shortcutLabels: [CommandID: String] = [:]
    var preview: ExplorerPreview = .none
    var scrollOffset: CGFloat = 0
    var sortKey = "name"
    var sortAscending = true
    var canCancelTask = false
    var canMoveFiles = true
}

enum TabCloseScope: Int, CaseIterable {
    case current, others, left, right

    var title: String {
        switch self {
        case .current: "关闭标签页"
        case .others: "关闭其余标签页"
        case .left: "关闭左侧标签页"
        case .right: "关闭右侧标签页"
        }
    }
}

enum ExplorerAction {
    case command(CommandID)
    case navigate(URL)
    case openFolderInNewTab(URL)
    case openWith([URL], application: URL)
    case navigatePath(String)
    case activateTab(UUID)
    case moveTab(UUID, before: UUID?)
    case moveFiles([URL], to: URL)
    case closeTab(UUID)
    case closeTabs(UUID, TabCloseScope)
    case filter(String)
    case select(Set<URL>)
    case sort(String, Bool)
    case rename(URL, String)
    case scroll(CGFloat)
    case cancelTask
}
