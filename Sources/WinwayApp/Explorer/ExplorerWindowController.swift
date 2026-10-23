import AppKit
import SwiftUI
import WinwayCore

@MainActor
final class ExplorerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate {
    private let onAction: (ExplorerAction) -> Void
    private var snapshot = ExplorerSnapshot()
    private var rendering = false
    private let root = ExplorerSurface()
    private let tabBar = TitlebarSurface(color: ExplorerStyle.titlebar)
    private let navigation = ExplorerSurface(color: ExplorerStyle.titlebar)
    private let commands = ExplorerSurface(color: ExplorerStyle.chrome)
    private let content = ExplorerSurface()
    private let statusBar = ExplorerSurface(color: ExplorerStyle.chrome)
    private let sidebar = NSScrollView()
    private let outline = NSOutlineView()
    private let fileScroll = NSScrollView()
    let fileTable = ExplorerFileTable()
    private let details = ExplorerSurface()
    private let detailsScroll = NSScrollView()
    private let detailBody = ExplorerSurface()
    private let tabsScroll = NSScrollView()
    private let tabsBody = ExplorerTabStrip()
    private var newTabButton: ExplorerButton!
    private let breadcrumb = NSPathControl()
    private let pathField = NSTextField()
    private let searchField = NSTextField()
    private let searchSurface = ExplorerSurface()
    private let searchIcon = NSImageView()
    private var clearSearchButton: ExplorerButton!
    private let statusLabel = ExplorerStyle.label("", secondary: true, size: 12)
    private let jobLabel = ExplorerStyle.label("", secondary: true, size: 12)
    private let emptyLabel = ExplorerStyle.label("", secondary: true)
    private var retryButton: ExplorerButton!
    private var homeButton: ExplorerButton!
    private var cancelButton: ExplorerButton!
    private var statusDetailsButton: ExplorerButton!
    private var statusRootButton: ExplorerButton!
    private var buttons: [CommandID: ExplorerButton] = [:]
    private var commandBarButtons: [ExplorerButton] = []
    private var tabButtons: [NSView] = []
    private var activeRenameURL: URL?
    private var renameEditor: NSTextField?
    private weak var renameDisplayLabel: NSTextField?
    private let renameOverlay = ExplorerRenameOverlay()
    private var pendingRename: (url: URL, name: String)?
    private var locationItems: [LocationNode] = []
    private var tabLayoutKey = ""
    private var locationLayoutKey = ""
    private var detailKey = ""
    private var previousTab: UUID?
    
    init(onAction: @escaping (ExplorerAction) -> Void) {
        self.onAction = onAction
        let window = ExplorerWindow(contentRect: NSRect(x: 0, y: 0, width: 1376, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.collectionBehavior = [.fullScreenNone, .fullScreenDisallowsTiling]
        window.title = "Winway"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false; window.minSize = NSSize(width: 960, height: 600)
        window.contentMinSize = NSSize(width: 960, height: 600)
        window.backgroundColor = .white; window.appearance = NSAppearance(named: .aqua)
        super.init(window: window)
        window.onMouseNavigation = { [weak self] command in
            guard let self, self.snapshot.enabledCommands.contains(command) else { return }
            self.emit(command)
        }
        window.contentView = root
        assemble()
        window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: fileScroll.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(resized), name: NSWindow.didResizeNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(layoutWindowButtons), name: NSWindow.didUpdateNotification, object: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func pin(_ view: NSView, to parent: NSView, top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0) {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        NSLayoutConstraint.activate([view.topAnchor.constraint(equalTo: parent.topAnchor, constant: top), view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: left), view.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -bottom), view.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -right)])
    }

    private func assemble() {
        let stack = NSStackView(views: [tabBar, navigation, commands, content, statusBar])
        stack.orientation = .vertical; stack.spacing = 0; stack.alignment = .leading; stack.distribution = .fill
        pin(stack, to: root)
        for row in [tabBar, navigation, commands, content, statusBar] {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        }
        for row in [tabBar, navigation, commands] { row.heightAnchor.constraint(equalToConstant: 44).isActive = true }
        statusBar.heightAnchor.constraint(equalToConstant: 32).isActive = true
        content.setContentHuggingPriority(.defaultLow, for: .vertical)
        // Our full-size content lays out its own 44-point title strip. AppKit's
        // automatic titlebar insets would otherwise clip the 32-point tab scroller.
        // Keep the clip views' independent header/ruler adjustment enabled.
        for scroll in [tabsScroll, sidebar, fileScroll, detailsScroll] {
            scroll.automaticallyAdjustsContentInsets = false
            scroll.contentInsets = NSEdgeInsetsZero
        }
        tabsScroll.drawsBackground = false; tabsScroll.hasHorizontalScroller = false; tabsScroll.hasVerticalScroller = false
        tabsScroll.verticalScrollElasticity = .none
        tabsScroll.horizontalScrollElasticity = .automatic
        tabsScroll.documentView = tabsBody; tabBar.addSubview(tabsScroll)
        tabsBody.onMove = { [weak self] id, next in self?.onAction(.moveTab(id, before: next)) }
        newTabButton = ExplorerButton(icon: "plus", tooltip: "新建标签页", action: { [weak self] in self?.emit(.newTab) })
        tabBar.addSubview(newTabButton)
        buildNavigation(); buildCommandBar(); buildTable(); buildSidebar()
        content.addSubview(sidebar); content.addSubview(fileScroll); content.addSubview(details)
        detailsScroll.documentView = detailBody; detailsScroll.drawsBackground = false; detailsScroll.hasVerticalScroller = true
        detailsScroll.autohidesScrollers = true; details.addSubview(detailsScroll)
        details.wantsLayer = true; details.layer?.borderColor = ExplorerStyle.border.cgColor; details.layer?.borderWidth = 1
        content.addSubview(emptyLabel)
        emptyLabel.alignment = .center; emptyLabel.maximumNumberOfLines = 5; emptyLabel.lineBreakMode = .byWordWrapping
        retryButton = ExplorerButton("重新读取", action: { [weak self] in self?.emit(.refresh) })
        homeButton = ExplorerButton("返回主目录", action: { [weak self] in self?.onAction(.navigate(FileManager.default.homeDirectoryForCurrentUser)) })
        for b in [retryButton!, homeButton!] { content.addSubview(b); b.isHidden = true }
        statusBar.addSubview(statusLabel); statusBar.addSubview(jobLabel)
        statusDetailsButton = ExplorerButton(icon: "view",tooltip: "切换详细信息面板",action: { [weak self] in self?.emit(.toggleDetails) }); statusDetailsButton.iconSize = 18
        statusRootButton = ExplorerButton(icon: "pc",tooltip: "打开根目录",action: { [weak self] in self?.onAction(.navigate(URL(fileURLWithPath: "/"))) }); statusRootButton.iconSize = 18
        statusBar.addSubview(statusDetailsButton); statusBar.addSubview(statusRootButton)
        cancelButton = ExplorerButton("取消任务", action: { [weak self] in self?.onAction(.cancelTask) }); statusBar.addSubview(cancelButton)
        root.layoutSubtreeIfNeeded(); layoutContent()
    }

    private func buildNavigation() {
        for command in [CommandID.back, .forward, .up] {
            let b = makeButton(command, icon: command.rawValue); navigation.addSubview(b)
        }
        breadcrumb.pathStyle = .standard; breadcrumb.isEditable = false; breadcrumb.focusRingType = .none
        breadcrumb.target = self; breadcrumb.action = #selector(pathClicked); breadcrumb.doubleAction = #selector(editPath)
        breadcrumb.font = .systemFont(ofSize: 13); breadcrumb.backgroundColor = .white
        breadcrumb.wantsLayer = true; breadcrumb.layer?.cornerRadius = 4; breadcrumb.layer?.borderWidth = 1; breadcrumb.layer?.borderColor = ExplorerStyle.border.cgColor
        breadcrumb.setAccessibilityLabel("当前位置，双击编辑路径")
        navigation.addSubview(breadcrumb)
        pathField.isHidden = true; pathField.font = .systemFont(ofSize: 13); pathField.delegate = self
        pathField.target = self; pathField.action = #selector(submitPath); pathField.focusRingType = .none
        pathField.placeholderString = "输入绝对路径或 ~/ 路径"; pathField.setAccessibilityLabel("目录路径")
        navigation.addSubview(pathField)
        searchField.isBezeled = false; searchField.isBordered = false; searchField.drawsBackground = false
        searchField.font = .systemFont(ofSize: 13); searchField.placeholderString = "搜索当前目录及子文件夹"
        searchField.focusRingType = .none; searchField.cell?.usesSingleLineMode = true
        searchField.cell?.isScrollable = true
        searchField.setAccessibilitySubrole(.searchField)
        searchField.delegate = self; searchField.setAccessibilityLabel("按名称搜索当前目录及所有子文件夹")
        searchSurface.layer?.cornerRadius = 4; searchSurface.layer?.borderWidth = 1
        searchSurface.layer?.borderColor = ExplorerStyle.border.cgColor
        searchIcon.image = ExplorerStyle.image("search", size: 18)
        searchIcon.setAccessibilityElement(false)
        clearSearchButton = ExplorerButton(icon: "close", tooltip: "清空搜索", action: { [weak self] in self?.clearSearch() })
        clearSearchButton.iconSize = 14; clearSearchButton.isHidden = true
        searchSurface.addSubview(searchIcon); searchSurface.addSubview(clearSearchButton)
        searchSurface.addSubview(searchField); navigation.addSubview(searchSurface)
    }

    private func buildCommandBar() {
        let new = makeButton(.newFolder, icon: "plus", title: "新建")
        new.arrow = true; new.handler = { [weak self, weak new] in guard let self, let new else { return }; self.showMenu(self.commandMenu([.newFolder, .newTab]), from: new) }
        commandBarButtons.append(new)
        for (command, icon) in [(CommandID.cut,"cut"),(.copy,"copy"),(.paste,"paste"),(.rename,"rename"),(.trash,"delete")] { commandBarButtons.append(makeButton(command, icon: icon)) }
        let sort = ExplorerButton("排序", icon: "sort", action: {}); sort.arrow = true; sort.iconSize = 18
        sort.handler = { [weak self, weak sort] in guard let self, let sort else { return }; self.showMenu(self.sortMenu(), from: sort) }
        commandBarButtons.append(sort)
        let view = ExplorerButton("查看", icon: "view", action: {}); view.arrow = true; view.iconSize = 18
        view.handler = { [weak self, weak view] in guard let self, let view else { return }; self.showMenu(self.commandMenu([.toggleDetails,.toggleHidden,.refresh]), from: view) }
        commandBarButtons.append(view)
        let more = ExplorerButton(icon: "more", tooltip: "更多", action: {})
        more.handler = { [weak self, weak more] in guard let self, let more else { return }; self.showMenu(self.commandMenu([.selectAll,.focusAddress,.refresh,.settings]), from: more) }
        commandBarButtons.append(more)
        for button in commandBarButtons { commands.addSubview(button) }
    }

    private func makeButton(_ command: CommandID, icon: String, title: String = "") -> ExplorerButton {
        let button = ExplorerButton(title, icon: icon, tooltip: command.title, action: { [weak self] in self?.emit(command) })
        buttons[command] = button; return button
    }

    private func buildTable() {
        fileTable.dataSource = self; fileTable.delegate = self; fileTable.rowHeight = 32
        fileTable.intercellSpacing = .zero; fileTable.style = .plain; fileTable.backgroundColor = .white
        fileTable.allowsMultipleSelection = true; fileTable.allowsEmptySelection = true
        fileTable.selectionHighlightStyle = .regular; fileTable.focusRingType = .none
        fileTable.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle; fileTable.usesAlternatingRowBackgroundColors = false
        fileTable.headerView = ExplorerHeaderView(frame: NSRect(x: 0, y: 0, width: 820, height: 36))
        fileTable.cornerView = ExplorerSurface()
        for (key, title, width) in [("name","名称",356.0),("modified","修改日期",180.0),("kind","类型",158.0),("size","大小",110.0),("location","所在位置",220.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key)); column.title = title; column.width = width
            column.minWidth = key == "name" ? 180 : 90
            column.isHidden = key == "location"
            column.headerCell = ExplorerHeaderCell(textCell: title)
            fileTable.addTableColumn(column)
        }
        fileTable.openSelection = { [weak self] in self?.emit(.open) }
        fileTable.contextMenu = { [weak self] in self?.commandMenu([.open,.cut,.copy,.paste,.rename,.trash,.newFolder,.refresh,.settings]) ?? NSMenu() }
        fileTable.setAccessibilityLabel("文件列表")
        fileScroll.documentView = fileTable; fileScroll.hasVerticalScroller = true; fileScroll.hasHorizontalScroller = true
        fileScroll.autohidesScrollers = true; fileScroll.drawsBackground = false; fileScroll.borderType = .noBorder
        fileScroll.contentView.postsBoundsChangedNotifications = true
    }

    private func buildSidebar() {
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("location")); c.width = 208
        outline.addTableColumn(c); outline.outlineTableColumn = c; outline.headerView = nil
        outline.dataSource = self; outline.delegate = self; outline.style = .plain
        outline.rowHeight = 32; outline.intercellSpacing = NSSize(width: 0, height: 2)
        outline.backgroundColor = ExplorerStyle.sidebar; outline.indentationPerLevel = 0
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.focusRingType = .none; outline.selectionHighlightStyle = .regular
        outline.target = self; outline.action = #selector(locationClicked)
        outline.setAccessibilityLabel("常用位置与已挂载卷")
        sidebar.documentView = outline; sidebar.drawsBackground = true; sidebar.backgroundColor = ExplorerStyle.sidebar
        sidebar.hasVerticalScroller = true; sidebar.autohidesScrollers = true
    }

    func render(_ new: ExplorerSnapshot) {
        rendering = true
        defer { rendering = false }
        let entriesChanged = snapshot.entries != new.entries || snapshot.filter.isEmpty != new.filter.isEmpty || snapshot.directory != new.directory
        let newError = new.errorMessage != nil && snapshot.errorMessage != new.errorMessage
        let tabChanged = previousTab != new.activeTabID
        let directoryChanged = snapshot.directory != new.directory
        if let url = activeRenameURL,
           tabChanged || directoryChanged || !new.entries.contains(where: { $0.url == url }) {
            finishRename(commit: false, restoreFocus: false)
        }
        snapshot = new
        window?.title = "\(new.directory.lastPathComponent) — Winway"
        breadcrumb.url = new.directory
        for (index, item) in breadcrumb.pathItems.enumerated() { item.image = index == 0 ? ExplorerStyle.image("pc",size: 18) : nil }
        if pathField.currentEditor() == nil { pathField.stringValue = new.directory.path }
        if searchField.stringValue != new.filter { searchField.stringValue = new.filter }
        clearSearchButton.isHidden = new.filter.isEmpty
        searchField.placeholderString = "搜索 \(new.directory.lastPathComponent) 及子文件夹"
        fileTable.tableColumns.first { $0.identifier.rawValue == "location" }?.isHidden = new.filter.isEmpty
        fileTable.windowsSelection = new.preset == .windows
        fileTable.contextID = new.activeTabID; fileTable.rowURLs = new.entries.map(\.url)
        if entriesChanged { fileTable.reloadData() }
        let indexes = IndexSet(new.entries.indices.filter { new.selection.contains(new.entries[$0].url) })
        if indexes != fileTable.selectedRowIndexes { fileTable.selectRowIndexes(indexes, byExtendingSelection: false) }
        for (command, button) in buttons {
            button.isEnabled = new.enabledCommands.contains(command)
            if command == .back { button.isEnabled = new.canGoBack }
            if command == .forward { button.isEnabled = new.canGoForward }
            button.toolTip = command.title + (new.shortcutLabels[command].map { " (\($0))" } ?? "")
        }
        for column in fileTable.tableColumns {
            if let header = column.headerCell as? ExplorerHeaderCell { header.sorted = column.identifier.rawValue == new.sortKey; header.ascending = new.sortAscending }
        }
        fileTable.headerView?.needsDisplay = true
        updateTabs(); updateLocations(); updateDetails()
        statusLabel.stringValue = "\(new.entries.count) 个项目" + (new.selection.isEmpty ? "" : "    │    已选择 \(new.selection.count) 个项目")
        jobLabel.stringValue = new.statusMessage ?? (new.isSearching ? "正在搜索当前目录及子文件夹…" : new.isLoading ? "正在读取目录…" : "")
        jobLabel.toolTip = new.statusMessage
        cancelButton.isHidden = !new.canCancelTask
        statusDetailsButton.isHidden = new.canCancelTask; statusRootButton.isHidden = new.canCancelTask
        statusDetailsButton.active = new.showDetails
        let message = new.errorMessage ?? (new.isSearching && new.entries.isEmpty ? "正在搜索当前目录及子文件夹…" : new.isLoading && new.entries.isEmpty ? "正在读取目录…" : new.entries.isEmpty ? (new.filter.isEmpty ? "此文件夹为空" : "没有匹配的项目") : "")
        emptyLabel.stringValue = message; emptyLabel.isHidden = message.isEmpty
        emptyLabel.drawsBackground = new.errorMessage != nil; emptyLabel.backgroundColor = .white
        retryButton.isHidden = new.errorMessage == nil; homeButton.isHidden = new.errorMessage == nil
        layoutContent()
        if tabChanged {
            if let index = new.tabs.firstIndex(where: { $0.id == new.activeTabID }), index < tabButtons.count { tabsBody.scrollToVisible(tabButtons[index].frame) }
        }
        if tabChanged || directoryChanged {
            fileScroll.contentView.scroll(to: NSPoint(x: 0, y: max(0,new.scrollOffset) - fileScroll.contentView.contentInsets.top))
            fileScroll.reflectScrolledClipView(fileScroll.contentView)
        }
        previousTab = new.activeTabID
        if let pending = pendingRename {
            if entriesChanged && !new.entries.contains(where: { $0.url == pending.url }) { pendingRename = nil }
            else if newError { beginRename(initialName: pending.name) }
        }
    }

    func focusAddress() { pathField.isHidden = false; breadcrumb.isHidden = true; pathField.stringValue = snapshot.directory.path; window?.makeFirstResponder(pathField); pathField.selectText(nil) }
    func focusSearch() { window?.makeFirstResponder(searchField); searchField.selectText(nil) }
    private func clearSearch() {
        searchField.stringValue = ""; clearSearchButton.isHidden = true
        onAction(.filter("")); focusSearch()
    }
    func focusFiles() { window?.makeFirstResponder(fileTable) }
    func beginRename(initialName: String? = nil) {
        guard snapshot.selection.count == 1, let url = snapshot.selection.first,
              let row = snapshot.entries.firstIndex(where: { $0.url == url }),
              let column = fileTable.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" }) else { return }
        if renameEditor != nil { finishRename(commit: false) }
        fileTable.scrollColumnToVisible(column)
        fileTable.scrollRowToVisible(row)
        // Display labels are intentionally never repurposed as editors. A fresh
        // text-field cell gives AppKit a genuinely editable field editor and AX role.
        let proposedName = initialName ?? snapshot.entries[row].name
        let editor = NSTextField(string: proposedName)
        editor.cell = ExplorerRenameCell(textCell: proposedName)
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = ExplorerStyle.text
        editor.backgroundColor = .white
        editor.isEnabled = true; editor.isEditable = true; editor.isSelectable = true
        editor.isBezeled = true; editor.isBordered = true; editor.drawsBackground = true
        editor.cell?.usesSingleLineMode = true; editor.cell?.isScrollable = true
        editor.focusRingType = .default
        editor.delegate = self; editor.target = self; editor.action = #selector(submitRename)
        editor.setAccessibilityLabel("重命名文件")
        editor.setAccessibilityIdentifier("winway.rename-editor")
        activeRenameURL = url; renameEditor = editor
        renameDisplayLabel = (fileTable.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView)?.textField
        renameDisplayLabel?.isHidden = true
        content.addSubview(renameOverlay, positioned: .above, relativeTo: nil)
        renameOverlay.addSubview(editor)
        positionRenameEditor()
        // selectText establishes the field editor itself. Calling
        // makeFirstResponder first starts then immediately ends an edit session.
        editor.selectText(nil)
        if let fieldEditor = editor.currentEditor() as? NSTextView {
            fieldEditor.isEditable = true; fieldEditor.isSelectable = true
            let name = proposedName
            let stem = snapshot.entries[row].isDirectory ? name : (name as NSString).deletingPathExtension
            fieldEditor.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
        }
    }

    private func positionRenameEditor() {
        guard let editor = renameEditor, let url = activeRenameURL,
              let row = snapshot.entries.firstIndex(where: { $0.url == url }),
              let column = fileTable.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" }) else { return }
        let viewport = fileTable.visibleRect.intersection(fileTable.bounds)
        renameOverlay.frame = content.convert(viewport, from: fileTable)
        var rect = fileTable.frameOfCell(atColumn: column, row: row)
        rect.origin.x += 32; rect.origin.y += 3
        rect.size.width = max(100, rect.width - 36); rect.size.height = 26
        editor.frame = renameOverlay.convert(rect, from: fileTable)
        editor.isHidden = !editor.frame.intersects(renameOverlay.bounds)
    }

    @objc private func submitRename() { finishRename(commit: true) }

    private func finishRename(commit: Bool, restoreFocus: Bool = true) {
        guard let editor = renameEditor, let url = activeRenameURL else { return }
        // The field editor may have uncommitted text, including text set through AX.
        let name = editor.currentEditor()?.string ?? editor.stringValue
        activeRenameURL = nil; renameEditor = nil
        renameDisplayLabel?.isHidden = false; renameDisplayLabel = nil
        if restoreFocus { window?.makeFirstResponder(fileTable) }
        editor.removeFromSuperview()
        renameOverlay.removeFromSuperview()
        if commit && name != url.lastPathComponent {
            pendingRename = (url, name)
            onAction(.rename(url, name))
        } else { pendingRename = nil }
    }

    @objc private func resized() { root.layoutSubtreeIfNeeded(); layoutContent() }
    private func layoutContent() {
        let w = root.bounds.width
        let tabsWidth = max(0, CGFloat(snapshot.tabs.count) * 228 - 8)
        let viewportWidth = min(tabsWidth, max(100, w - 168))
        tabsScroll.frame = NSRect(x: 116,y: 6,width: viewportWidth,height: 32)
        tabsBody.frame.size = NSSize(width: max(viewportWidth, tabsWidth),height: 32)
        newTabButton.frame = NSRect(x: tabsScroll.frame.maxX + 4,y: 6,width: 32,height: 32)
        tabsBody.layoutTabs()
        for (i, command) in [CommandID.back,.forward,.up].enumerated() { buttons[command]?.frame = NSRect(x: 16+CGFloat(i)*40,y: 6,width: 32,height: 32) }
        let searchWidth: CGFloat = w < 1100 ? 250 : 320
        breadcrumb.frame = NSRect(x: 136,y: 6,width: w-136-searchWidth-24,height: 32)
        pathField.frame = breadcrumb.frame; searchSurface.frame = NSRect(x: w-searchWidth-16,y: 6,width: searchWidth,height: 32)
        searchIcon.frame = NSRect(x: 8, y: 7, width: 18, height: 18)
        searchField.frame = NSRect(x: 32, y: 7, width: searchWidth - 64, height: 18)
        clearSearchButton.frame = NSRect(x: searchWidth - 30, y: 2, width: 28, height: 28)
        var x: CGFloat = 16
        for (i,b) in commandBarButtons.enumerated() {
            let width: CGFloat = i == 0 ? 88 : (i == 6 || i == 7 ? 84 : 32)
            b.frame = NSRect(x: x,y: 6,width: width,height: 32); x += width+8
        }
        let h = content.bounds.height
        sidebar.frame = NSRect(x: 0,y: 0,width: 224,height: h)
        sidebar.contentInsets = NSEdgeInsets(top: 12,left: 8,bottom: 12,right: 8)
        let sidebarWidth = max(0, sidebar.contentSize.width - 16)
        outline.frame.size.width = sidebarWidth
        outline.tableColumns.first?.width = sidebarWidth
        let dw: CGFloat = snapshot.showDetails ? 300 : 0
        details.isHidden = !snapshot.showDetails; details.frame = NSRect(x: w-dw,y: 0,width: dw,height: h)
        detailsScroll.frame = details.bounds.insetBy(dx: 1,dy: 1)
        let listWidth = max(200,w-224-dw)
        fileScroll.frame = NSRect(x: 240,y: 12,width: listWidth-32,height: h-12)
        // Let the table derive its document size from its rows and columns.
        // Assigning the frame width here can retain the pre-scroller viewport
        // size and let clip-view autoresizing shorten the last row.
        fileTable.tile()
        let messageWidth = max(140,listWidth-48)
        let messageY: CGFloat = snapshot.errorMessage != nil && !snapshot.entries.isEmpty ? max(105,h-160) : 105
        emptyLabel.frame = NSRect(x: 248,y: messageY,width: messageWidth,height: 110)
        retryButton.frame = NSRect(x: 248,y: messageY+115,width: 110,height: 32)
        homeButton.frame = NSRect(x: 366,y: messageY+115,width: 120,height: 32)
        statusLabel.frame = NSRect(x: 20,y: 7,width: min(340,w/3),height: 18)
        jobLabel.frame = NSRect(x: min(370,w/3+30),y: 7,width: max(100,w-min(370,w/3+30)-130),height: 18)
        cancelButton.frame = NSRect(x: w-112,y: 2,width: 96,height: 28)
        statusDetailsButton.frame = NSRect(x: w-72,y: 2,width: 28,height: 28)
        statusRootButton.frame = NSRect(x: w-40,y: 2,width: 28,height: 28)
        layoutWindowButtons()
        let tabOrigin = tabsScroll.contentView.bounds.origin
        tabsScroll.contentView.scroll(to: NSPoint(x: min(tabOrigin.x, max(0, tabsWidth - viewportWidth)), y: 0))
        positionRenameEditor()
    }

    @objc private func layoutWindowButtons() {
        guard let window, !window.styleMask.contains(.fullScreen), tabBar.bounds.height > 0 else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
        guard let first = buttons.first else { return }
        let firstFrame = first.convert(first.bounds, to: tabBar)
        // Keep native sizes, spacing, ownership and actions. Convert from our
        // flipped tab strip instead of assuming the system titlebar's height.
        let placements = buttons.compactMap { button -> (NSButton, NSPoint)? in
            guard let parent = button.superview else { return nil }
            var frame = button.convert(button.bounds, to: tabBar)
            frame.origin = NSPoint(x: 18 + frame.minX - firstFrame.minX,
                                  y: (tabBar.bounds.height - frame.height) / 2)
            let target = parent.convert(frame, from: tabBar)
            // Do not place a control outside its system-managed hit-test area.
            guard parent.bounds.contains(target) else { return nil }
            return (button, target.origin)
        }
        for (button, origin) in placements where button.frame.origin != origin {
            button.setFrameOrigin(origin)
        }
    }

    private func updateTabs() {
        let key = snapshot.tabs.map { "\($0.id):\($0.title)" }.joined() + snapshot.activeTabID.uuidString
        guard key != tabLayoutKey else { return }; tabLayoutKey = key
        tabsBody.cancelReordering(animated: false)
        tabButtons.forEach { $0.removeFromSuperview() }; tabButtons.removeAll()
        for (index, tab) in snapshot.tabs.enumerated() {
            let view = ExplorerTabView(tab: tab, isSelected: tab.id == snapshot.activeTabID,
                                       index: index, count: snapshot.tabs.count,
                                       onAction: { [weak self] in self?.onAction($0) })
            tabsBody.addSubview(view); tabButtons.append(view)
        }
    }

    private func updateLocations() {
        let key = snapshot.locations.map { $0.url.path+$0.title+$0.icon }.joined()
        if key != locationLayoutKey {
            locationLayoutKey = key; locationItems = snapshot.locations.map(LocationNode.init)
            outline.reloadData()
        }
        if let row = locationItems.firstIndex(where: { $0.location.url.standardizedFileURL == snapshot.directory.standardizedFileURL }) {
            outline.selectRowIndexes(IndexSet(integer: row),byExtendingSelection: false)
        } else { outline.deselectAll(nil) }
    }

    private func emit(_ command: CommandID) {
        guard snapshot.enabledCommands.contains(command) || (command == .back && snapshot.canGoBack) || (command == .forward && snapshot.canGoForward) else { NSSound.beep(); return }
        onAction(.command(command))
    }
    private func showMenu(_ menu: NSMenu, from view: NSView) { menu.popUp(positioning: nil,at: NSPoint(x: 0,y: view.bounds.height+2),in: view) }
    private func commandMenu(_ commands: [CommandID]) -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        for command in commands {
            let shortcut = snapshot.shortcutLabels[command].map { "    \($0)" } ?? ""
            let item = NSMenuItem(title: command.title+shortcut,action: #selector(menuCommand(_:)),keyEquivalent: "")
            item.target = self; item.representedObject = command.rawValue; item.isEnabled = snapshot.enabledCommands.contains(command)
            if command == .toggleHidden { item.state = snapshot.showHidden ? .on : .off }
            if command == .toggleDetails { item.state = snapshot.showDetails ? .on : .off }
            menu.addItem(item)
        }
        return menu
    }
    private func sortMenu() -> NSMenu {
        let menu = NSMenu()
        for (key,title) in [("name","名称"),("modified","修改日期"),("kind","类型"),("size","大小")] {
            let item = NSMenuItem(title: title,action: #selector(sortCommand(_:)),keyEquivalent: ""); item.target = self
            item.representedObject = key; item.state = snapshot.sortKey == key ? .on : .off; menu.addItem(item)
        }
        menu.addItem(.separator())
        for (key,title) in [("ascending","升序"),("descending","降序")] {
            let item = NSMenuItem(title: title,action: #selector(sortCommand(_:)),keyEquivalent: ""); item.target = self
            item.representedObject = key; item.state = (key == "ascending") == snapshot.sortAscending ? .on : .off; menu.addItem(item)
        }
        return menu
    }
    @objc private func menuCommand(_ sender: NSMenuItem) { if let raw = sender.representedObject as? String, let command = CommandID(rawValue: raw) { emit(command) } }
    @objc private func sortCommand(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        if key == "ascending" || key == "descending" { onAction(.sort(snapshot.sortKey,key == "ascending")) }
        else { onAction(.sort(key,true)) }
    }
    @objc private func pathClicked() { if let url = breadcrumb.clickedPathItem?.url { onAction(.navigate(url)) } }
    @objc private func editPath() { focusAddress() }
    @objc private func submitPath() { let path = pathField.stringValue; pathField.isHidden = true; breadcrumb.isHidden = false; focusFiles(); onAction(.navigatePath(path)) }
    @objc private func locationClicked() { let row = outline.clickedRow; guard row >= 0,row < locationItems.count else { return }; onAction(.navigate(locationItems[row].location.url)) }
    @objc private func scrolled() { positionRenameEditor(); if !rendering { onAction(.scroll(max(0,fileScroll.contentView.bounds.origin.y + fileScroll.contentView.contentInsets.top))) } }

    func numberOfRows(in tableView: NSTableView) -> Int { snapshot.entries.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ExplorerRowView() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < snapshot.entries.count,let column = tableColumn else { return nil }
        let entry = snapshot.entries[row]; let key = column.identifier.rawValue
        let cell = (tableView.makeView(withIdentifier: column.identifier,owner: self) as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = column.identifier
        if cell.textField == nil {
            cell.wantsLayer = true; cell.layer?.masksToBounds = true
            let label = ExplorerStyle.label(""); label.delegate = self; cell.textField = label; cell.addSubview(label)
            label.maximumNumberOfLines = 1
            label.cell?.usesSingleLineMode = true; label.cell?.isScrollable = false
            label.lineBreakMode = .byTruncatingMiddle
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: key == "name" ? 36 : 8),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            if key == "name" {
                let image = NSImageView(); cell.imageView = image; cell.addSubview(image)
                image.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    image.widthAnchor.constraint(equalToConstant: 20), image.heightAnchor.constraint(equalToConstant: 20)
                ])
            }
        }
        let label = cell.textField!
        label.isEditable = false; label.isSelectable = false; label.isBezeled = false
        label.isBordered = false; label.drawsBackground = false; label.focusRingType = .none
        label.textColor = key == "name" ? ExplorerStyle.text : ExplorerStyle.secondary
        label.font = .systemFont(ofSize: 13); label.alignment = key == "size" ? .right : .left
        let text: String
        switch key { case "name": text = entry.name; case "location": text = entry.location(relativeTo: snapshot.directory); case "modified": text = ExplorerStyle.dateFormatter.string(from: entry.modified); case "kind": text = entry.isSymbolicLink ? "符号链接 · \(entry.kind)" : entry.kind; default: text = ExplorerStyle.size(entry) }
        label.stringValue = text; label.toolTip = key == "location" || (key == "name" && !snapshot.filter.isEmpty) ? entry.url.path : text
        label.isHidden = key == "name" && entry.url == activeRenameURL
        if label.isHidden { renameDisplayLabel = label }
        cell.imageView?.image = ExplorerStyle.fileImage(entry)
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !rendering else { return }
        onAction(.select(Set(fileTable.selectedRowIndexes.compactMap { snapshot.entries.indices.contains($0) ? snapshot.entries[$0].url : nil })))
    }
    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        let key = tableColumn.identifier.rawValue
        guard FileSort(rawValue: key) != nil else { return }
        onAction(.sort(key,key == snapshot.sortKey ? !snapshot.sortAscending : true))
    }

    func tableViewColumnDidMove(_ notification: Notification) { positionRenameEditor() }
    func tableViewColumnDidResize(_ notification: Notification) { positionRenameEditor() }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField) === searchField && !rendering {
            clearSearchButton.isHidden = searchField.stringValue.isEmpty
            onAction(.filter(searchField.stringValue))
        }
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === renameEditor { finishRename(commit: true, restoreFocus: false) }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if control === searchField, commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            clearSearch(); return true
        }
        if control === renameEditor {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finishRename(commit: false); return true }
            if commandSelector == #selector(NSResponder.insertNewline(_:)) { finishRename(commit: true); return true }
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)), control === pathField {
            pathField.isHidden = true; breadcrumb.isHidden = false; focusFiles(); return true
        }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { item == nil ? locationItems.count : 0 }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { locationItems[index] }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { false }
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? { ExplorerRowView() }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? LocationNode else { return nil }
        let id = NSUserInterfaceItemIdentifier("location-cell")
        let cell = (outlineView.makeView(withIdentifier: id,owner: self) as? NSTableCellView) ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let text = ExplorerStyle.label(""); cell.textField = text; cell.addSubview(text)
            let icon = NSImageView(); cell.imageView = icon; cell.addSubview(icon)
            let pin = NSImageView(); pin.tag = 99; pin.image = ExplorerStyle.image("pinnedShortcut",size: 14); cell.addSubview(pin)
            for view in [text, icon, pin] { view.translatesAutoresizingMaskIntoConstraints = false }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18),
                text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                text.trailingAnchor.constraint(equalTo: pin.leadingAnchor, constant: -8),
                pin.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                pin.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                pin.widthAnchor.constraint(equalToConstant: 14), pin.heightAnchor.constraint(equalToConstant: 14)
            ])
        }
        cell.viewWithTag(99)?.isHidden = node.location.isVolume || ["home","pc","drive"].contains(node.location.icon)
        cell.textField?.stringValue = node.location.title
        cell.imageView?.image = ExplorerStyle.image(node.location.icon,size: 18)
        cell.toolTip = node.location.url.path
        return cell
    }
}

private final class LocationNode: NSObject {
    let location: ExplorerLocation
    init(_ location: ExplorerLocation) { self.location = location }
}

extension ExplorerWindowController {
    private func updateDetails() {
        let previewKey: String
        switch snapshot.preview {
        case .none: previewKey = "none"
        case .loading: previewKey = "loading"
        case .text(let text): previewKey = "text:\(text.hashValue)"
        case .image(let image): previewKey = "image:\(ObjectIdentifier(image))"
        case .unavailable(let reason): previewKey = reason
        }
        let key = snapshot.selection.map(\.path).sorted().joined(separator: "|") + previewKey + snapshot.entries.filter { snapshot.selection.contains($0.url) }.map { "\($0.size):\($0.modified)" }.joined()
        guard key != detailKey else { return }; detailKey = key
        detailBody.subviews.forEach { $0.removeFromSuperview() }
        detailBody.frame = NSRect(x: 0,y: 0,width: 298,height: 620)
        let chosen = snapshot.entries.filter { snapshot.selection.contains($0.url) }
        guard chosen.count == 1,let entry = chosen.first else {
            let title = ExplorerStyle.label(chosen.isEmpty ? "详细信息" : "已选择 \(chosen.count) 个项目",size: 14)
            title.font = .systemFont(ofSize: 14,weight: .medium); title.frame = NSRect(x: 16,y: 20,width: 266,height: 22); detailBody.addSubview(title)
            let info = ExplorerStyle.label(chosen.isEmpty ? "选择文件以查看属性和预览" : "选择单个文件以查看预览",secondary: true)
            info.frame = NSRect(x: 16,y: 52,width: 266,height: 22); detailBody.addSubview(info)
            if chosen.count > 1 {
                let total = chosen.filter { !$0.isDirectory }.reduce(Int64(0)) { $0+$1.size }
                let size = ExplorerStyle.label("文件总大小：\(ByteCountFormatter.string(fromByteCount: total,countStyle: .file))",secondary: true)
                size.frame = NSRect(x: 16,y: 86,width: 266,height: 22); detailBody.addSubview(size)
            }
            return
        }
        let icon = NSImageView(frame: NSRect(x: 16,y: 16,width: 40,height: 40)); icon.image = ExplorerStyle.fileImage(entry,size: 40); detailBody.addSubview(icon)
        let name = ExplorerStyle.label(entry.name); name.font = .systemFont(ofSize: 13,weight: .medium); name.frame = NSRect(x: 68,y: 14,width: 214,height: 22); name.toolTip = entry.name; detailBody.addSubview(name)
        let kind = ExplorerStyle.label(entry.kind,secondary: true); kind.frame = NSRect(x: 68,y: 38,width: 214,height: 20); detailBody.addSubview(kind)
        let divider = ExplorerSurface(color: ExplorerStyle.border); divider.frame = NSRect(x: 16,y: 72,width: 266,height: 1); detailBody.addSubview(divider)
        let preview = ExplorerSurface(color: ExplorerStyle.chrome); preview.frame = NSRect(x: 16,y: 85,width: 266,height: 240); preview.layer?.cornerRadius = 4; detailBody.addSubview(preview)
        switch snapshot.preview {
        case .image(let image):
            let imageView = NSImageView(frame: preview.bounds.insetBy(dx: 12,dy: 12)); imageView.image = image; imageView.imageScaling = .scaleProportionallyDown; preview.addSubview(imageView)
        case .text(let text):
            let scroll = NSScrollView(frame: preview.bounds.insetBy(dx: 12,dy: 12)); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
            let textView = NSTextView(frame: scroll.bounds); textView.isEditable = false; textView.isSelectable = true; textView.string = text
            textView.font = .monospacedSystemFont(ofSize: 11,weight: .regular); textView.textColor = ExplorerStyle.text; textView.backgroundColor = ExplorerStyle.chrome
            textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false; textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true; scroll.documentView = textView; preview.addSubview(scroll)
        default:
            let largeIcon = NSImageView(frame: NSRect(x: 101,y: 38,width: 64,height: 64)); largeIcon.image = ExplorerStyle.fileImage(entry,size: 64); preview.addSubview(largeIcon)
            let message: String
            switch snapshot.preview { case .loading: message = "正在读取预览…"; case .unavailable(let reason): message = reason; default: message = entry.isDirectory ? "文件夹" : "选择文件以读取预览" }
            let info = ExplorerStyle.label(message,secondary: true,size: 12); info.alignment = .center; info.maximumNumberOfLines = 4; info.lineBreakMode = .byWordWrapping; info.frame = NSRect(x: 16,y: 120,width: 234,height: 65); preview.addSubview(info)
            let open = ExplorerButton("用默认应用打开",action: { [weak self] in self?.emit(.open) }); open.frame = NSRect(x: 56,y: 194,width: 158,height: 30); open.isEnabled = snapshot.enabledCommands.contains(.open); preview.addSubview(open)
        }
        let metadata = NSHostingView(rootView: ExplorerMetadataView(entry: entry))
        metadata.frame = NSRect(x: 16,y: 342,width: 266,height: 220)
        detailBody.addSubview(metadata)
    }
}
