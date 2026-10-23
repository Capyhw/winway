import AppKit

/// Query Launch Services only when the submenu opens, and retain the clicked
/// selection so a later render cannot redirect the chosen application.
final class ExplorerOpenWithMenu: NSMenu, NSMenuDelegate {
    private let urls: [URL]
    private let onOpen: ([URL], URL) -> Void
    var applicationsForURL: (URL) -> [URL] = { NSWorkspace.shared.urlsForApplications(toOpen: $0) }
    var defaultApplicationForURL: (URL) -> URL? = { NSWorkspace.shared.urlForApplication(toOpen: $0) }

    init(urls: [URL], onOpen: @escaping ([URL], URL) -> Void) {
        self.urls = urls
        self.onOpen = onOpen
        super.init(title: "打开方式")
        autoenablesItems = false
        allowsContextMenuPlugIns = false
        delegate = self
        let loading = NSMenuItem(title: "正在读取应用…", action: nil, keyEquivalent: "")
        loading.isEnabled = false
        addItem(loading)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func menuNeedsUpdate(_ menu: NSMenu) {
        removeAllItems()
        guard let first = urls.first else { return }
        var applications = Set(applicationsForURL(first).map(\.standardizedFileURL))
        var defaultApplication = defaultApplicationForURL(first)?.standardizedFileURL
        for url in urls.dropFirst() {
            applications.formIntersection(applicationsForURL(url).map(\.standardizedFileURL))
            if defaultApplicationForURL(url)?.standardizedFileURL != defaultApplication { defaultApplication = nil }
        }
        let names = Dictionary(uniqueKeysWithValues: applications.map { ($0, FileManager.default.displayName(atPath: $0.path)) })
        let sorted = applications.sorted {
            if ($0 == defaultApplication) != ($1 == defaultApplication) { return $0 == defaultApplication }
            let order = names[$0, default: ""].localizedStandardCompare(names[$1, default: ""])
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
        for application in sorted {
            let name = names[application, default: application.lastPathComponent]
            let item = NSMenuItem(title: name + (application == defaultApplication ? "（默认）" : ""),
                                  action: #selector(openWithApplication(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = application
            let icon = NSWorkspace.shared.icon(forFile: application.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            #if compiler(>=6.4)
            // macOS 27 hides menu images by default; retain older SDK build support.
            if #available(macOS 27.0, *) { item.preferredImageVisibility = .visible }
            #endif
            item.toolTip = application.path
            addItem(item)
        }
        if items.isEmpty {
            let item = NSMenuItem(title: "没有可打开所选文件的应用", action: nil, keyEquivalent: "")
            item.isEnabled = false
            addItem(item)
        }
    }

    @objc private func openWithApplication(_ sender: NSMenuItem) {
        guard let application = sender.representedObject as? URL else { return }
        onOpen(urls, application)
    }
}
