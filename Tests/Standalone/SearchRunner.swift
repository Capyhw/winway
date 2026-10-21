import AppKit
import WinwayCore

@main
struct SearchRunner {
    @MainActor
    static func waitUntil(_ message: String, _ ready: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !ready() {
            precondition(ContinuousClock.now < deadline, message)
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @MainActor
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("winway-search-integration-\(UUID())")
        let deep = root.appendingPathComponent("资料/2026/十月")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let direct = root.appendingPathComponent("报告.txt")
        let nested = deep.appendingPathComponent("报告.txt")
        try Data("direct".utf8).write(to: direct)
        try Data("nested".utf8).write(to: nested)
        let model = AppModel(directory: root, settingsURL: root.appendingPathComponent("keyboard.json"))
        model.controller = ExplorerWindowController { [weak model] in model?.handle($0) }
        model.refresh()
        try await waitUntil("Initial directory load") { !model.active.isLoading }
        model.handle(.filter("报告"))
        precondition(model.active.isSearching)
        try await waitUntil("Recursive search") { !model.active.isSearching }
        precondition(model.active.visibleEntries.count == 2)
        precondition(model.active.entries.count == 2, "Direct directory listing must stay separate")
        let table = model.controller.fileTable
        let locationIndex = table.column(withIdentifier: NSUserInterfaceItemIdentifier("location"))
        precondition(locationIndex >= 0 && !table.tableColumns[locationIndex].isHidden)
        let nestedRow = model.active.visibleEntries.firstIndex { $0.url.standardizedFileURL == nested.standardizedFileURL }!
        let cell = model.controller.tableView(table, viewFor: table.tableColumns[locationIndex], row: nestedRow) as! NSTableCellView
        precondition(cell.textField?.stringValue == "资料/2026/十月")
        precondition(cell.textField?.toolTip == model.active.visibleEntries[nestedRow].url.path)
        if let path = ProcessInfo.processInfo.environment["WINWAY_SEARCH_SCREENSHOT"],
           let view = model.controller.window?.contentView {
            model.controller.window?.setContentSize(NSSize(width: 1440, height: 800))
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        }
        model.handle(.select([model.active.visibleEntries[nestedRow].url]))
        model.refresh()
        try await waitUntil("Refresh preserves nested selection") { !model.active.isLoading && !model.active.isSearching }
        precondition(model.selected.count == 1 && model.selected[0].url.standardizedFileURL == nested.standardizedFileURL)
        print("PASS: multi-level results and native location column distinguish duplicate names")

        model.handle(.filter("missing"))
        model.handle(.filter("报告"))
        try await waitUntil("Latest query wins") { !model.active.isSearching }
        precondition(model.active.visibleEntries.count == 2)
        model.handle(.filter("missing"))
        model.handle(.filter(""))
        try await Task.sleep(for: .milliseconds(400))
        precondition(!model.active.isSearching && model.active.searchEntries == nil)
        precondition(model.active.visibleEntries.count == 2)
        precondition(table.tableColumns[locationIndex].isHidden)
        print("PASS: rapid query replacement and clearing reject obsolete results")

        model.handle(.filter("报告"))
        model.handle(.cancelTask)
        try await Task.sleep(for: .milliseconds(400))
        precondition(!model.active.isSearching && model.active.searchEntries == nil)
        precondition(model.active.searchMessage?.contains("停止") == true)
        model.refresh()
        try await waitUntil("Refresh restarts search") { !model.active.isLoading && !model.active.isSearching }
        precondition(model.active.visibleEntries.count == 2)
        print("PASS: search cancellation and refresh retry")

        let renamed = try await model.service.rename(nested, to: "新报告.txt")
        await model.reloadAfterWrite(directory: deep, select: renamed)
        try await waitUntil("Nested write refresh") { !model.active.isSearching }
        precondition(model.active.visibleEntries.contains { $0.name == "新报告.txt" })
        precondition(!model.active.visibleEntries.contains { $0.url.standardizedFileURL == nested.standardizedFileURL })
        precondition(model.selected.count == 1 && model.selected.first?.name == "新报告.txt")
        print("PASS: nested rename refreshes ancestor search and selects the renamed result")

        let firstID = model.activeID
        let second = BrowserTabState(directory: deep)
        model.tabs.append(second)
        model.handle(.filter("报告"))
        model.handle(.activateTab(second.id))
        model.refresh()
        try await waitUntil("Tab isolation") { !model.active.isLoading && model.tabs.allSatisfy { !$0.isSearching } }
        precondition(model.active.filter.isEmpty && model.active.visibleEntries.count == 1)
        model.handle(.activateTab(firstID))
        precondition(model.active.filter == "报告" && model.active.visibleEntries.count == 2)
        model.handle(.filter("报告"))
        model.navigate(deep)
        try await waitUntil("Navigation cancels old search") { !model.active.isLoading && !model.active.isSearching }
        try await Task.sleep(for: .milliseconds(350))
        precondition(model.active.filter.isEmpty && model.active.searchEntries == nil)
        precondition(model.active.visibleEntries.count == 1)
        model.handle(.filter("报告"))
        model.closeTab(firstID)
        try await Task.sleep(for: .milliseconds(350))
        precondition(model.tabs.count == 1 && model.activeID == second.id)
        print("PASS: independent tabs, navigation and tab closure reject stale search completion")
        model.controller.close()
    }
}
