import AppKit
import Combine
import WinwayCore

@MainActor
final class AppModel {
    let service = LocalFileService()
    let keyboard: KeyboardSettingsStore
    var tabs: [BrowserTabState]
    var activeID: UUID
    var showHidden = false
    var showDetails = true
    var preview: ExplorerPreview = .none
    var previewGeneration = UUID()
    var clipboard: [URL] = []
    var clipboardKind: FileTransferKind = .copy
    var cancellation: FileOperationCancellation?
    var busy = false
    var status: String?
    var controller: ExplorerWindowController!
    var settingsController: SettingsWindowController?
    var subscriptions = Set<AnyCancellable>()
    var keyMonitor: Any?
    var locations: [ExplorerLocation] = []
    var onRender: (() -> Void)?
    private var searchJobs: [UUID: (cancellation: FileOperationCancellation, task: Task<Void, Never>)] = [:]
    private var settingsURL: URL?

    init(directory: URL, settingsURL: URL? = nil) {
        self.settingsURL = settingsURL
        keyboard = KeyboardSettingsStore(configurationURL: settingsURL)
        let tab = BrowserTabState(directory: directory)
        tabs = [tab]; activeID = tab.id
    }
    var activeIndex: Int { tabs.firstIndex { $0.id == activeID } ?? 0 }
    var active: BrowserTabState { tabs[activeIndex] }
    var selected: [FileEntry] {
        let tab = active
        guard !tab.selection.isEmpty else { return [] }
        return tab.visibleEntries.filter { tab.selection.contains($0.url) }
    }

    func start() {
        controller = ExplorerWindowController { [weak self] action in self?.handle(action) }
        keyboard.$configuration.sink { [weak self] _ in
            Task { @MainActor in self?.render() }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification).sink { [weak self] _ in
            Task { @MainActor in self?.loadLocations() }
        }.store(in: &subscriptions)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification).sink { [weak self] _ in
            Task { @MainActor in self?.loadLocations(); self?.refresh() }
        }.store(in: &subscriptions)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.routeKey(event) == nil }
            return consumed ? nil : event
        }
        loadLocations()
        render()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        refresh()
    }

    func loadLocations() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        locations = [ExplorerLocation(title: "主目录", url: home, icon: "home")]
        for (title, directory, icon): (String, FileManager.SearchPathDirectory, String) in [
            ("桌面", .desktopDirectory, "pc"), ("下载", .downloadsDirectory, "download"),
            ("文档", .documentDirectory, "document"), ("图片", .picturesDirectory, "gallery"),
            ("音乐", .musicDirectory, "music"), ("影片", .moviesDirectory, "video")
        ] {
            if let url = FileManager.default.urls(for: directory, in: .userDomainMask).first, FileManager.default.fileExists(atPath: url.path) {
                locations.append(ExplorerLocation(title: title, url: url, icon: icon))
            }
        }
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
        for url in volumes {
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent
            locations.append(ExplorerLocation(title: name.isEmpty ? "Macintosh HD" : name, url: url, icon: "drive", isVolume: true))
        }
        render()
    }

    var enabledCommands: Set<CommandID> {
        var commands = Set(CommandID.allCases)
        let selected = selected
        if selected.isEmpty { commands.subtract([.open, .rename, .copy, .cut, .trash]) }
        if selected.count != 1 { commands.remove(.rename) }
        if clipboard.isEmpty { commands.subtract([.paste, .moveHere]) }
        if !active.navigation.canGoBack { commands.remove(.back) }
        if !active.navigation.canGoForward { commands.remove(.forward) }
        if active.navigation.directory.path == "/" { commands.remove(.up) }
        if busy { commands.subtract([.rename, .newFolder, .paste, .moveHere, .trash]) }
        if !FileManager.default.isWritableFile(atPath: active.navigation.directory.path) {
            commands.subtract([.rename, .newFolder, .paste, .moveHere, .trash])
        }
        return commands
    }

    func render() {
        guard controller != nil else { return }
        var snapshot = ExplorerSnapshot()
        snapshot.tabs = tabs.map { ExplorerTab(id: $0.id, title: $0.navigation.directory.lastPathComponent.isEmpty ? "此电脑" : $0.navigation.directory.lastPathComponent) }
        snapshot.activeTabID = activeID
        snapshot.directory = active.navigation.directory
        snapshot.entries = active.visibleEntries
        snapshot.selection = active.selection
        snapshot.filter = active.filter
        snapshot.locations = locations
        snapshot.canGoBack = active.navigation.canGoBack
        snapshot.canGoForward = active.navigation.canGoForward
        snapshot.isLoading = active.isLoading
        snapshot.isSearching = active.isSearching
        snapshot.errorMessage = active.error
        if busy { snapshot.statusMessage = status }
        else if active.isSearching { snapshot.statusMessage = "正在搜索当前目录及子文件夹…" }
        else if let message = active.searchMessage {
            snapshot.statusMessage = [status, message].compactMap { $0 }.joined(separator: " · ")
        } else { snapshot.statusMessage = status }
        snapshot.showHidden = showHidden
        snapshot.showDetails = showDetails
        snapshot.preset = keyboard.activePreset
        snapshot.enabledCommands = enabledCommands
        snapshot.shortcutLabels = Dictionary(uniqueKeysWithValues: CommandID.allCases.map { ($0, keyboard.shortcutLabel(for: $0)) })
        snapshot.preview = preview
        snapshot.scrollOffset = active.scrollOffset
        snapshot.sortKey = active.sort.rawValue
        snapshot.sortAscending = active.ascending
        snapshot.canCancelTask = cancellation != nil || active.isSearching
        controller.render(snapshot)
        onRender?()
    }

    func handle(_ action: ExplorerAction) {
        switch action {
        case .command(let command): execute(command)
        case .navigate(let url): navigate(url)
        case .navigatePath(let path):
            let expanded = (path as NSString).expandingTildeInPath
            guard expanded.hasPrefix("/") else { showError("请输入绝对路径或以 ~ 开头的路径。"); return }
            navigate(URL(fileURLWithPath: expanded))
        case .activateTab(let id):
            guard tabs.contains(where: { $0.id == id }) else { return }
            activeID = id; updatePreview()
        case .closeTab(let id): closeTab(id)
        case .closeTabs(let id, let scope): closeTabs(id, scope: scope)
        case .filter(let text): setSearch(text)
        case .select(let urls): tabs[activeIndex].selection = urls; tabs[activeIndex].reconcileSelection(); updatePreview()
        case .sort(let key, let ascending):
            tabs[activeIndex].sort = FileSort(rawValue: key) ?? .name
            tabs[activeIndex].ascending = ascending; render()
        case .rename(let url, let name): rename(url, to: name)
        case .scroll(let offset): tabs[activeIndex].scrollOffset = offset
        case .cancelTask:
            if let cancellation { cancellation.cancel(); status = "正在取消剩余项目…" }
            else { cancelSearch(activeID); tabs[activeIndex].searchMessage = "搜索已停止，可刷新重试" }
            render()
        }
    }

    func cancelSearch(_ id: UUID) {
        if let job = searchJobs.removeValue(forKey: id) { job.cancellation.cancel(); job.task.cancel() }
        if let index = tabs.firstIndex(where: { $0.id == id }) { tabs[index].isSearching = false }
    }

    func setSearch(_ text: String) {
        let index = activeIndex
        cancelSearch(activeID)
        tabs[index].searchEntries = nil
        tabs[index].searchMessage = nil
        tabs[index].filter = text
        tabs[index].reconcileSelection()
        if !tabs[index].isLoading { startSearch(activeID) }
        updatePreview()
    }

    func startSearch(_ id: UUID, select: URL? = nil) {
        cancelSearch(id)
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let query = tabs[index].filter
        guard !query.isEmpty else {
            tabs[index].searchEntries = nil; tabs[index].searchMessage = nil
            return
        }
        let directory = tabs[index].navigation.directory
        let hidden = showHidden
        let cancellation = FileOperationCancellation()
        tabs[index].isSearching = true; tabs[index].searchMessage = nil
        let task = Task { [weak self] in
            do {
                // Debounce typing without blocking the main actor or the file queue.
                try await Task.sleep(for: .milliseconds(250))
                guard let self else { return }
                let result = try await service.searchDirectory(directory, query: query, includeHidden: hidden, cancellation: cancellation)
                guard !cancellation.isCancelled,
                      let current = tabs.firstIndex(where: { $0.id == id }),
                      searchJobs[id]?.cancellation === cancellation else { return }
                searchJobs.removeValue(forKey: id)
                tabs[current].isSearching = false
                tabs[current].searchEntries = result.entries
                tabs[current].searchMessage = result.skippedCount > 0
                    ? "搜索完成，已跳过 \(result.skippedCount) 个无法读取的项目"
                    : "搜索完成（含子文件夹）"
                if let select, let entry = result.entries.first(where: { $0.url.standardizedFileURL == select.standardizedFileURL }) {
                    tabs[current].selection = [entry.url]
                }
                tabs[current].reconcileSelection()
                if activeID == id { updatePreview() }
            } catch {
                guard let self, !cancellation.isCancelled,
                      let current = tabs.firstIndex(where: { $0.id == id }),
                      searchJobs[id]?.cancellation === cancellation else { return }
                searchJobs.removeValue(forKey: id)
                tabs[current].isSearching = false
                tabs[current].searchEntries = []
                tabs[current].searchMessage = "搜索失败：\(error.localizedDescription)"
                tabs[current].reconcileSelection()
                if activeID == id { updatePreview() }
            }
        }
        searchJobs[id] = (cancellation, task)
    }

    func refresh() { navigate(active.navigation.directory, refresh: true) }
    func navigate(_ url: URL, historyIndex: Int? = nil, refresh: Bool = false, tabID: UUID? = nil) {
        let targetID = tabID ?? activeID
        guard let index = tabs.firstIndex(where: { $0.id == targetID }) else { return }
        cancelSearch(targetID)
        let token = tabs[index].navigation.beginRequest()
        tabs[index].isLoading = true; tabs[index].error = nil
        let hidden = showHidden
        render()
        Task { [weak self] in
            guard let self else { return }
            do {
                let entries = try await service.listDirectory(url, includeHidden: hidden)
                guard let current = tabs.firstIndex(where: { $0.id == targetID }), tabs[current].navigation.generation == token else { return }
                guard tabs[current].navigation.commit(url, generation: token, historyIndex: historyIndex) else { return }
                tabs[current].entries = entries; tabs[current].isLoading = false
                tabs[current].searchMessage = nil
                if !refresh {
                    tabs[current].searchEntries = nil; tabs[current].selection = []
                    tabs[current].scrollOffset = 0; tabs[current].filter = ""
                }
                tabs[current].reconcileSelection()
                startSearch(targetID)
                if activeID == targetID { updatePreview() }
            } catch {
                guard let current = tabs.firstIndex(where: { $0.id == targetID }), tabs[current].navigation.generation == token else { return }
                tabs[current].isLoading = false; tabs[current].error = error.localizedDescription
                if refresh { tabs[current].entries = []; tabs[current].searchEntries = nil; tabs[current].selection = [] }
                if activeID == targetID { updatePreview() }
                render()
            }
        }
    }

    func execute(_ command: CommandID) {
        guard enabledCommands.contains(command) else { return }
        switch command {
        case .open: selected.forEach { open($0.url) }
        case .rename: controller.beginRename()
        case .copy, .cut:
            clipboard = selected.map(\.url); clipboardKind = command == .cut ? .move : .copy
            status = "已\(command == .cut ? "剪切" : "复制") \(clipboard.count) 个项目"; render()
        case .paste, .moveHere: transfer(sources: clipboard, destination: active.navigation.directory, kind: command == .moveHere ? .move : clipboardKind)
        case .trash: trash(selected.map(\.url))
        case .selectAll: tabs[activeIndex].selection = Set(active.visibleEntries.map(\.url)); updatePreview()
        case .newFolder: promptNewFolder()
        case .newTab:
            let tab = BrowserTabState(directory: FileManager.default.homeDirectoryForCurrentUser)
            tabs.append(tab); activeID = tab.id; preview = .none; refresh()
        case .closeTab: closeTab(activeID)
        case .back: let target = active.navigation.index - 1; navigate(active.navigation.history[target], historyIndex: target)
        case .forward: let target = active.navigation.index + 1; navigate(active.navigation.history[target], historyIndex: target)
        case .up: navigate(active.navigation.directory.deletingLastPathComponent())
        case .focusAddress: controller.focusAddress()
        case .focusSearch: controller.focusSearch()
        case .refresh: refresh(); loadLocations()
        case .settings:
            if settingsController == nil { settingsController = SettingsWindowController(store: keyboard) }
            settingsController?.showWindow(nil); settingsController?.window?.makeKeyAndOrderFront(nil)
        case .toggleHidden:
            showHidden.toggle()
            for tab in tabs { navigate(tab.navigation.directory, refresh: true, tabID: tab.id) }
        case .toggleDetails: showDetails.toggle(); render()
        }
    }

    func closeTab(_ id: UUID) {
        closeTabs(id, scope: .current)
    }

    func closeTabs(_ id: UUID, scope: TabCloseScope) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing: Set<UUID>
        switch scope {
        case .current: closing = [id]
        case .others: closing = Set(tabs.filter { $0.id != id }.map(\.id))
        case .left: closing = Set(tabs.prefix(index).map(\.id))
        case .right: closing = Set(tabs.dropFirst(index + 1).map(\.id))
        }
        guard !closing.isEmpty else { return }
        for closingID in closing { cancelSearch(closingID) }
        tabs.removeAll { closing.contains($0.id) }
        if tabs.isEmpty { tabs = [BrowserTabState(directory: FileManager.default.homeDirectoryForCurrentUser)] }
        if closing.contains(activeID) {
            activeID = scope == .current ? tabs[min(index, tabs.count - 1)].id : id
        }
        updatePreview()
        if active.entries.isEmpty { refresh() }
    }

    func open(_ url: URL) {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { showError("文件已不存在：\(url.lastPathComponent)"); refresh(); return }
        if directory.boolValue { navigate(url); return }
        NSWorkspace.shared.open(url, configuration: .init()) { [weak self] _, error in
            if let error { Task { @MainActor in self?.showError(error.localizedDescription) } }
        }
    }

    func updatePreview() {
        let generation = UUID(); previewGeneration = generation
        let selected = selected
        guard selected.count == 1, let entry = selected.first else { preview = .none; render(); return }
        if entry.isDirectory { preview = .unavailable("文件夹"); render(); return }
        preview = .loading; render()
        Task { [weak self] in
            let result = await PreviewService.load(entry.url)
            guard let self, self.previewGeneration == generation else { return }
            switch result {
            case .text(let text): preview = .text(text)
            case .image(let data): preview = NSImage(data: data).map(ExplorerPreview.image) ?? .unavailable("无法解码图片")
            case .unavailable(let reason): preview = .unavailable(reason)
            }
            render()
        }
    }

    func promptNewFolder(in target: URL? = nil, name: String = "新建文件夹", error: String? = nil) {
        let directory = target ?? active.navigation.directory
        let alert = NSAlert(); alert.messageText = "新建文件夹"; alert.informativeText = error ?? "输入文件夹名称"
        let field = NSTextField(string: name); field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field; alert.addButton(withTitle: "创建"); alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: controller.window!) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            self.busy = true; self.render()
            Task {
                do {
                    let created = try await self.service.createDirectory(in: directory, name: field.stringValue)
                    self.status = "已创建 \(created.lastPathComponent)"
                    await self.reloadAfterWrite(directory: directory, select: created)
                } catch {
                    self.busy = false
                    self.promptNewFolder(in: directory, name: field.stringValue, error: error.localizedDescription)
                }
                self.busy = false; self.render()
            }
        }
    }

    func rename(_ url: URL, to name: String) {
        guard !busy else { return }
        tabs[activeIndex].error = nil
        busy = true; render()
        Task {
            do {
                let renamed = try await service.rename(url, to: name)
                status = "已重命名为 \(renamed.lastPathComponent)"
                await reloadAfterWrite(directory: url.deletingLastPathComponent(), select: renamed)
            } catch {
                showError(error.localizedDescription)
            }
            busy = false; render()
        }
    }

    func reloadAfterWrite(directory: URL? = nil, select: URL? = nil) async {
        for id in tabs.filter({ directory == nil || !$0.filter.isEmpty || $0.navigation.directory.resolvingSymlinksInPath().standardizedFileURL == directory?.resolvingSymlinksInPath().standardizedFileURL }).map(\.id) {
            guard let index = tabs.firstIndex(where: { $0.id == id }) else { continue }
            cancelSearch(id)
            let path = tabs[index].navigation.directory
            let token = tabs[index].navigation.beginRequest()
            do {
                let entries = try await service.listDirectory(path, includeHidden: showHidden)
                guard let current = tabs.firstIndex(where: { $0.id == id }), tabs[current].navigation.generation == token else { continue }
                tabs[current].entries = entries; tabs[current].isLoading = false; tabs[current].error = nil
                if let select, let entry = entries.first(where: { $0.url.standardizedFileURL == select.standardizedFileURL }) { tabs[current].selection = [entry.url] }
                tabs[current].reconcileSelection()
                startSearch(id, select: select)
            } catch {
                if let current = tabs.firstIndex(where: { $0.id == id }), tabs[current].navigation.generation == token {
                    tabs[current].isLoading = false
                    tabs[current].error = error.localizedDescription
                }
            }
        }
        updatePreview()
    }

    func transfer(sources: [URL], destination: URL, kind: FileTransferKind) {
        guard !busy, !sources.isEmpty else { return }
        let token = FileOperationCancellation()
        cancellation = token; busy = true; status = "准备处理 \(sources.count) 个项目…"; render()
        let request = FileTransferRequest(sources: sources, destination: destination, kind: kind)
        Task { [self] in
            let report = await service.transfer(request, cancellation: token, onProgress: { [weak self] progress in
                Task { @MainActor in
                    guard let self, self.cancellation === token else { return }
                    self.status = "已处理 \(progress.processed)/\(progress.total)，成功 \(progress.succeeded)，失败 \(progress.failed) · \(progress.currentSource?.lastPathComponent ?? "")"
                    self.render()
                }
            }, resolveConflict: { [weak self] conflict in
                guard let self else { return .cancel }
                return await self.askConflict(conflict)
            })
            cancellation = nil; busy = false
            if kind == .move {
                let moved = Set(report.results.filter { $0.outcome == .succeeded }.map(\.source))
                clipboard.removeAll { moved.contains($0) }
            }
            let unfinished = report.results.filter { $0.outcome != .succeeded }
            status = "成功 \(report.succeeded)，失败 \(report.failed)，跳过/取消 \(unfinished.count - report.failed)"
            await reloadAfterWrite()
            if !unfinished.isEmpty { showReport(report, destination: destination) }
        }
    }

    func askConflict(_ conflict: FileConflict) async -> FileConflictChoice {
        await withCheckedContinuation { continuation in
            let alert = NSAlert(); alert.messageText = "目标已有同名项目"
            alert.informativeText = "\(conflict.destination.lastPathComponent)\n选择保留两者会生成新名称，不覆盖已有内容。"
            alert.addButton(withTitle: "保留两者"); alert.addButton(withTitle: "跳过"); alert.addButton(withTitle: "取消剩余任务")
            alert.beginSheetModal(for: controller.window!) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn ? .keepBoth : response == .alertSecondButtonReturn ? .skip : .cancel)
            }
        }
    }

    func showReport(_ report: FileOperationReport, destination: URL) {
        let failed = report.results.filter { $0.outcome == .failed }
        let alert = NSAlert(); alert.messageText = "文件操作结果"
        alert.informativeText = report.results.map { item in
            let residual = item.residualURLs.isEmpty ? "" : "\n残留目标：" + item.residualURLs.map(\.path).joined(separator: "、")
            let label: String = switch item.outcome { case .succeeded: "成功"; case .failed: "失败"; case .skipped: "跳过"; case .cancelled: "取消" }
            return "\(item.source.lastPathComponent)：\(label) \(item.error?.message ?? "")\(residual)"
        }.joined(separator: "\n")
        alert.addButton(withTitle: "关闭")
        if !failed.isEmpty { alert.addButton(withTitle: "仅重试失败项目") }
        alert.beginSheetModal(for: controller.window!) { [weak self] response in
            if response == .alertSecondButtonReturn { self?.transfer(sources: failed.map(\.source), destination: destination, kind: report.kind) }
        }
    }

    func trash(_ urls: [URL]) {
        guard !busy else { return }
        let token = FileOperationCancellation()
        cancellation = token; busy = true; render()
        Task {
            var failed: [String] = []
            var count = 0
            for url in urls {
                if token.isCancelled { break }
                let error: String? = await withCheckedContinuation { continuation in
                    NSWorkspace.shared.recycle([url]) { _, error in continuation.resume(returning: error?.localizedDescription) }
                }
                if let error { failed.append("\(url.lastPathComponent)：\(error)") } else { count += 1 }
                status = "移到废纸篓：成功 \(count)，失败 \(failed.count)"; render()
            }
            let remaining = urls.count - count - failed.count
            status = "移到废纸篓：成功 \(count)，失败 \(failed.count)，取消 \(remaining)"
            cancellation = nil; busy = false; await reloadAfterWrite()
            if !failed.isEmpty { showError(failed.joined(separator: "\n")) }
        }
    }

    func showError(_ message: String) { tabs[activeIndex].error = message; render() }

    func routeKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === controller.window, !keyboard.isRecording,
              controller.window?.attachedSheet == nil else { return event }
        if let editor = controller.window?.firstResponder as? NSTextView {
            if editor.hasMarkedText() { return event }
            let modifiers = event.modifierFlags.intersection([.control, .command, .option, .shift])
            if keyboard.activePreset == .windows, modifiers == .control {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c": editor.copy(nil); return nil
                case "x": editor.cut(nil); return nil
                case "v": editor.paste(nil); return nil
                case "a": editor.selectAll(nil); return nil
                default: return event
                }
            }
            return event
        }
        guard let binding = KeyboardEventAdapter.binding(from: event), let command = keyboard.command(for: binding) else { return event }
        // Consume rejected repeats so the same event cannot fall through to a menu equivalent.
        if event.isARepeat && command.isWriteOperation { return nil }
        execute(command); return nil
    }
}
