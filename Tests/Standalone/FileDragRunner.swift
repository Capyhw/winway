import AppKit
import WinwayCore

@MainActor
final class FileDragProbe: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation = .move
    var draggingLocation: NSPoint = .zero
    var draggedImageLocation: NSPoint { draggingLocation }
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingSequenceNumber = 1
    var formationWrites = 0
    var badgeWrites = 0
    var draggingFormation: NSDraggingFormation = .list { didSet { formationWrites += 1 } }
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1 { didSet { badgeWrites += 1 } }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@main
struct FileDragRunner {
    @MainActor
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("winway-file-drag-\(UUID())")
        let folder = root.appendingPathComponent("资料", isDirectory: true)
        let child = folder.appendingPathComponent("子目录", isDirectory: true)
        let target = root.appendingPathComponent("目标", isDirectory: true)
        let other = root.appendingPathComponent("其他", isDirectory: true)
        for url in [child, target, other] { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        defer { try? fm.removeItem(at: root) }
        let file = root.appendingPathComponent("中文 file.txt")
        let nested = child.appendingPathComponent("nested.txt")
        try Data("file payload".utf8).write(to: file)
        try Data("nested payload".utf8).write(to: nested)
        let alias = root.appendingPathComponent("child-link")
        try fm.createSymbolicLink(at: alias, withDestinationURL: child)
        let broken = root.appendingPathComponent("broken-link")
        try fm.createSymbolicLink(atPath: broken.path, withDestinationPath: "missing")
        let sources = [file, folder, broken]
        func paths(_ urls: [URL]?) -> [String]? { urls?.map(\.path) }
        precondition(paths(ExplorerFileDrop.movableSources(sources, to: target)) == paths(sources))
        precondition(paths(ExplorerFileDrop.movableSources([nested, folder, file, file], to: target)) == paths([folder, file]),
                     "Nested search hits and duplicate URLs must only move once")
        for invalid in [folder, child, alias, root, file] {
            precondition(ExplorerFileDrop.movableSources(sources, to: invalid) == nil, "Reject self, descendant, alias, same parent and file targets")
        }
        precondition(ExplorerFileDrop.movableSources([], to: target) == nil)
        precondition(ExplorerFileDrop.movableSources([root.appendingPathComponent("gone")], to: target) == nil)
        precondition(paths(ExplorerFileDrop.movableSources([alias, nested], to: target)) == paths([alias, nested]),
                     "Moving a link must not absorb files inside its target")
        print("PASS: mixed sources, broken links, nested search hits, duplicates, cycles and invalid destinations")

        let many = (0..<12).map { root.appendingPathComponent("文件 \($0).txt") }
        let previewItems = ExplorerFileDragPreview.items(for: many, at: .zero)
        precondition(previewItems.count == many.count, "A bounded preview must preserve the complete drag payload")
        precondition(previewItems.compactMap { ($0.item as? NSURL)?.path } == many.map(\.path))
        precondition(previewItems.prefix(5).allSatisfy { $0.imageComponents?.map(\.key) == [.icon, .label] },
                     "Visible drag rows need both file icons and readable filename labels")
        precondition(previewItems.dropFirst(5).allSatisfy { $0.imageComponentsProvider == nil },
                     "Large selections must not obscure the entire destination list")
        let longLabel = ExplorerFileDragPreview.labelImage(String(repeating: "很长的名称", count: 50) + ".txt")
        precondition(longLabel.size.width <= 420 && longLabel.size.height == 20)
        print("PASS: filename/icon drag images, bounded long names and complete multi-file payload")

        var actions: [ExplorerAction] = []
        let controller = ExplorerWindowController { actions.append($0) }
        let table = controller.fileTable
        let window = controller.window!
        var snapshot = ExplorerSnapshot()
        snapshot.directory = root
        snapshot.entries = [
            FileEntry(url: file, name: file.lastPathComponent, isDirectory: false),
            FileEntry(url: folder, name: folder.lastPathComponent, isDirectory: true),
            FileEntry(url: target, name: target.lastPathComponent, isDirectory: true),
            FileEntry(url: other, name: other.lastPathComponent, isDirectory: true)
        ]
        snapshot.selection = [file, folder]
        window.contentView!.layoutSubtreeIfNeeded()
        controller.render(snapshot)
        let selected = table.selectedRowIndexes
        table.showDraggedFiles([file, folder])
        let sourceRow = table.rowView(atRow: 0, makeIfNecessary: true) as! ExplorerRowView
        precondition(sourceRow.isFileDragSource)
        let sourceCell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! NSTableCellView
        precondition(sourceCell.alphaValue == 0.5, "Source rows must dim while the drag is active")
        controller.render(snapshot)
        precondition(sourceRow.isFileDragSource && sourceCell.alphaValue == 0.5, "Background renders must preserve source feedback")
        let cancelledDrag = FileDragProbe()
        cancelledDrag.draggingSource = table
        cancelledDrag.draggingDestinationWindow = window
        table.draggingEnded(cancelledDrag)
        cancelledDrag.draggingPasteboard.releaseGlobally()
        precondition(table.draggedFileURLs.isEmpty, "Releasing a cancelled drop must clear the source drag state")
        precondition(!sourceRow.isFileDragSource && sourceCell.alphaValue == 1)
        table.deselectAll(nil)
        table.selectRowIndexes(selected, byExtendingSelection: false)
        precondition(!sourceRow.isFileDragSource && sourceCell.alphaValue == 1,
                     "Reselecting after a cancelled drop must use the normal selection appearance")
        func event(_ type: NSEvent.EventType, row: Int, offset: CGFloat = 0) -> NSEvent {
            let rect = table.rect(ofRow: row)
            let point = table.convert(NSPoint(x: 70 + offset, y: rect.midY), to: nil)
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                     context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        table.showDraggedFiles([file, folder])
        table.fileDropTarget = target
        table.draggingExited(cancelledDrag)
        precondition(table.fileDropTarget == nil && !table.draggedFileURLs.isEmpty,
                     "Leaving the list clears only the target; the drag can still reenter")
        table.mouseUp(with: event(.leftMouseUp, row: 0))
        precondition(table.draggedFileURLs.isEmpty && sourceCell.alphaValue == 1 && table.selectedRowIndexes == selected,
                     "Mouse release on an invalid destination must restore source rows without changing selection")
        table.showDraggedFiles([file, folder])
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                     charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        table.keyDown(with: escape)
        precondition(table.draggedFileURLs.isEmpty && sourceCell.alphaValue == 1 && table.selectedRowIndexes == selected,
                     "Escape cancels the drag appearance and preserves the original selection")
        // The native source callback must also clean up an outside-window drop,
        // where this table never receives a destination draggingEnded callback.
        table.showDraggedFiles([file, folder])
        table.draggingSession(NSDraggingSession(), endedAt: .zero, operation: [])
        precondition(table.draggedFileURLs.isEmpty && sourceCell.alphaValue == 1)
        print("PASS: native destination/source completion, invalid mouse release, Escape and reselect restore source rows")
        table.mouseDown(with: event(.leftMouseDown, row: 0))
        precondition(table.selectedRowIndexes == selected, "Pressing a selected row must preserve the entire drag selection")
        table.mouseDragged(with: event(.leftMouseDragged, row: 0, offset: 2))
        precondition(table.selectedRowIndexes == selected, "Small pointer jitter must not collapse selection")
        table.mouseUp(with: event(.leftMouseUp, row: 0))
        precondition(table.selectedRowIndexes == IndexSet(integer: 0), "A plain click still selects one row on release")
        controller.render(snapshot)
        table.mouseDown(with: event(.leftMouseDown, row: 0))
        snapshot.activeTabID = UUID()
        snapshot.selection = [target]
        controller.render(snapshot)
        table.mouseUp(with: event(.leftMouseUp, row: 0))
        precondition(table.selectedRowIndexes == IndexSet(integer: 2), "A stale mouse release must not change another tab's selection")
        print("PASS: selected-row press preserves multi-selection, click release and tab-switch invalidation")

        let probe = FileDragProbe()
        defer { probe.draggingPasteboard.releaseGlobally() }
        probe.draggingSource = table
        probe.draggingDestinationWindow = window
        func setSources(_ urls: [URL]) {
            probe.draggingPasteboard.clearContents()
            precondition(probe.draggingPasteboard.writeObjects(urls.map { $0 as NSURL }))
        }
        func validate(_ row: Int) -> NSDragOperation {
            probe.draggingLocation = table.convert(NSPoint(x: 70, y: table.rect(ofRow: row).midY), to: nil)
            return controller.tableView(table, validateDrop: probe, proposedRow: row, proposedDropOperation: .above)
        }
        func accept(_ row: Int) -> Bool {
            controller.tableView(table, acceptDrop: probe, row: row, dropOperation: .on)
        }
        for batch in [[file], [folder], [file, folder]] {
            setSources(batch)
            precondition(validate(2) == .move && probe.numberOfValidItemsForDrop == batch.count)
            let initialFormationWrites = probe.formationWrites
            let initialBadgeWrites = probe.badgeWrites
            let hoverStart = ContinuousClock.now
            for _ in 0..<120 {
                precondition(validate(2) == .move)
            }
            FileHandle.standardError.write(Data("Hover benchmark: 120 updates, \(batch.count) sources, \(hoverStart.duration(to: .now)); formation writes \(probe.formationWrites - initialFormationWrites), badge writes \(probe.badgeWrites - initialBadgeWrites)\n".utf8))
            precondition(probe.formationWrites == initialFormationWrites && probe.badgeWrites == initialBadgeWrites,
                         "Moving within one folder row must not repeatedly reset native drag images or the count badge")
            precondition(probe.draggingFormation == .list && table.fileDropTarget == target)
            let targetView = table.rowView(atRow: 2, makeIfNecessary: true) as! ExplorerRowView
            let targetCell = table.view(atColumn: 0, row: 2, makeIfNecessary: true) as! NSTableCellView
            precondition(targetView.isFileDropTarget && targetCell.textField?.textColor == .white,
                         "Valid target folders must use a full-row highlight with white labels")
            actions.removeAll()
            precondition(accept(2))
            precondition(table.fileDropTarget == nil && !targetView.isFileDropTarget && targetCell.textField?.textColor == ExplorerStyle.text)
            guard actions.count == 1, case .moveFiles(let urls, let destination) = actions[0] else { fatalError("One drop must emit one move action") }
            precondition(paths(urls) == paths(batch) && destination == target)
            precondition(!accept(2), "The same accepted drop must not submit twice")
        }
        setSources([file])
        precondition(validate(3) == .move)
        try fm.removeItem(at: other)
        precondition(validate(3) == .move, "Repeated hover reuses the same validation instead of probing the filesystem again")
        actions.removeAll()
        precondition(!accept(3) && actions.isEmpty, "Mouse release must revalidate a destination deleted during the drag")
        precondition(validate(3).isEmpty)
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        probe.draggingSequenceNumber += 1
        precondition(validate(3) == .move, "A new drag must discard the previous session's rejected destination")
        print("PASS: stable hover feedback, session-scoped validation cache and fresh filesystem checks on release")
        setSources([file, folder])
        precondition(validate(0).isEmpty && !accept(0), "A file row in the source directory must not move files into themselves")
        precondition(validate(1).isEmpty && !accept(1), "A selected folder cannot receive itself")
        probe.draggingLocation = table.convert(NSPoint(x: 70, y: table.rect(ofRow: 3).maxY + 40), to: nil)
        precondition(controller.tableView(table, validateDrop: probe, proposedRow: 4, proposedDropOperation: .above).isEmpty)
        probe.draggingSource = nil
        precondition(validate(2).isEmpty && !accept(2), "Only internal file drags are accepted")
        probe.draggingSource = table
        probe.draggingSourceOperationMask = .copy
        precondition(validate(2).isEmpty && !accept(2), "Copy-only drags cannot silently become moves")
        probe.draggingSourceOperationMask = .move
        precondition(validate(2) == .move)
        snapshot.canMoveFiles = false
        controller.render(snapshot)
        precondition(!accept(2) && validate(2).isEmpty && !table.canDragFiles, "Busy state must reject both drag and drop")
        snapshot.canMoveFiles = true
        controller.render(snapshot)
        precondition(validate(2) == .move)
        snapshot.entries.swapAt(2, 3)
        controller.render(snapshot)
        precondition(!accept(2), "A refresh must not redirect a drop into a different folder")
        controller.close()
        print("PASS: folder-only move drops, captured URLs, one submission, invalid targets, busy state and refreshed rows")

        // Dwell is measured across updates, not pointer motion, and resets on exit.
        let strip = ExplorerTabStrip()
        strip.frame = NSRect(x: 0, y: 0, width: 684, height: 32)
        let tabIDs = [UUID(), UUID(), UUID()]
        for (index, id) in tabIDs.enumerated() {
            strip.addSubview(ExplorerTabView(tab: ExplorerTab(id: id, title: "Tab \(index)"),
                isSelected: index == 0, index: index, count: 3, onAction: { _ in }))
        }
        strip.layoutTabs()
        strip.activeTabID = tabIDs[0]
        var activated: [UUID] = []
        strip.onFileHover = { activated.append($0); strip.activeTabID = $0 }
        let second = NSPoint(x: 260, y: 16), third = NSPoint(x: 490, y: 16)
        strip.updateFileHover(at: second, sequence: 1, now: 0)
        strip.updateFileHover(at: second, sequence: 1, now: 0.3)
        precondition(activated.isEmpty, "Passing over a tab must not switch it immediately")
        strip.updateFileHover(at: third, sequence: 1, now: 0.4)
        strip.updateFileHover(at: third, sequence: 1, now: 0.8)
        precondition(activated.isEmpty, "Entering another tab restarts the dwell")
        strip.updateFileHover(at: third, sequence: 1, now: 1.1)
        strip.updateFileHover(at: third, sequence: 1, now: 2)
        precondition(activated == [tabIDs[2]], "A stationary hover activates once")
        strip.updateFileHover(at: second, sequence: 1, now: 3)
        strip.draggingExited(nil)
        strip.updateFileHover(at: second, sequence: 1, now: 4)
        precondition(activated.count == 1, "Reentry starts a fresh dwell")
        strip.updateFileHover(at: second, sequence: 2, now: 5)
        precondition(activated.count == 1, "A new session cannot reuse the previous dwell")
        strip.draggingEnded(probe)
        strip.updateFileHover(at: second, sequence: 2, now: 6)
        precondition(activated.count == 1, "Cancelled drags must not activate a tab later")
        precondition(!strip.performDragOperation(probe), "Dropping on the tab strip itself must not move files")
        print("PASS: delayed tab activation, stationary hover, repeated updates, tab changes, exit, cancellation and new sessions")

        // Exercise the actual controller → action → model → filesystem route.
        let model = AppModel(directory: root, settingsURL: root.appendingPathComponent("settings.json"))
        model.controller = ExplorerWindowController { [weak model] in model?.handle($0) }
        defer { model.controller.close() }
        model.tabs[0].entries = try await model.service.listDirectory(root)
        model.tabs.append(BrowserTabState(directory: target))
        model.clipboard = [other]; model.clipboardKind = .copy
        model.render()
        model.controller.window!.contentView!.layoutSubtreeIfNeeded()
        let originalID = model.activeID
        model.tabs[0].selection = Set(sources)
        model.render()
        let modelTable = model.controller.fileTable
        modelTable.showDraggedFiles(Set(sources))
        setSources(sources)
        probe.draggingSource = modelTable
        probe.draggingDestinationWindow = model.controller.window
        func findStrip(_ view: NSView) -> ExplorerTabStrip? {
            if let strip = view as? ExplorerTabStrip { return strip }
            return view.subviews.lazy.compactMap { findStrip($0) }.first
        }
        let modelStrip = findStrip(model.controller.window!.contentView!)!
        probe.draggingLocation = modelStrip.convert(NSPoint(x: 260, y: 16), to: nil)
        precondition(modelStrip.draggingEntered(probe).isEmpty)
        precondition(model.activeID == originalID)
        try await Task.sleep(for: .milliseconds(650))
        _ = modelStrip.draggingUpdated(probe)
        precondition(model.activeID == model.tabs[1].id, "Hovering must activate the destination tab through the real action route")
        precondition(modelTable.draggedFileURLs == Set(sources) && model.tabs[0].selection == Set(sources),
                     "Switching tabs must preserve the captured sources and original selection")
        // During a native drag, destination/source callbacks must restore hover
        // even when the normal tracking-area mouseExited event is not delivered.
        let activeTab = modelStrip.subviews.compactMap { $0 as? ExplorerTabView }
            .first { $0.tabID == model.activeID }!
        let entered = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: model.controller.window!.windowNumber, context: nil,
            eventNumber: 0, trackingNumber: 0, userData: nil)!
        activeTab.mouseEntered(with: entered)
        modelStrip.draggingExited(probe)
        precondition(activeTab.layer?.backgroundColor == NSColor.white.cgColor,
                     "Leaving the strip must clear drag hover before the mouse is released")
        // Also cover source completion without a destination exit/end callback.
        activeTab.mouseEntered(with: entered)
        modelTable.draggingSession(NSDraggingSession(), endedAt: NSPoint(x: -100, y: -100), operation: [])
        precondition(model.activeID == model.tabs[1].id && modelStrip.activeTabID == model.activeID,
                     "Cancelling outside the window must retain the spring-loaded tab selection")
        precondition(activeTab.layer?.backgroundColor == NSColor.white.cgColor,
                     "Cancelling outside must restore the selected tab background without requiring mouseExited")
        precondition(modelTable.draggedFileURLs.isEmpty && model.tabs[0].selection == Set(sources))
        let tabViews = modelStrip.subviews.compactMap { $0 as? ExplorerTabView }
        precondition(tabViews.allSatisfy {
            $0.layer?.backgroundColor == ($0.tabID == model.activeID ? NSColor.white : ExplorerStyle.chrome).cgColor
        }, "Only the active tab must retain the selected background after cancellation")
        model.render()
        precondition(activeTab.layer?.backgroundColor == NSColor.white.cgColor,
                     "A subsequent render must preserve the restored selected appearance")
        print("PASS: outside-window cancellation preserves the active tab and restores its selected appearance")
        modelTable.showDraggedFiles(Set(sources))
        modelStrip.draggingExited(probe)
        probe.draggingLocation = modelTable.convert(NSPoint(x: 70, y: 100), to: nil)
        precondition(model.controller.tableView(modelTable, validateDrop: probe, proposedRow: 0, proposedDropOperation: .above) == .move)
        precondition(model.controller.tableView(modelTable, acceptDrop: probe, row: -1, dropOperation: .on),
                     "An empty destination list must accept a drop into its current directory")
        precondition(model.busy, "Dropping must start the existing move job")
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while model.busy || model.tabs[1].entries.count != sources.count {
            precondition(ContinuousClock.now < deadline, "Move and tab refresh timed out")
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(!fm.fileExists(atPath: file.path) && !fm.fileExists(atPath: folder.path))
        let movedFile = target.appendingPathComponent(file.lastPathComponent)
        let movedNested = target.appendingPathComponent("资料/子目录/nested.txt")
        let payload = try String(contentsOf: movedFile, encoding: .utf8)
        let nestedPayload = try String(contentsOf: movedNested, encoding: .utf8)
        let linkDestination = try fm.destinationOfSymbolicLink(atPath: target.appendingPathComponent("broken-link").path)
        precondition(payload == "file payload" && nestedPayload == "nested payload" && linkDestination == "missing")
        precondition(!model.tabs[0].entries.contains { sources.map(\.path).contains($0.url.path) })
        precondition(model.clipboard == [other] && model.clipboardKind == .copy, "Dragging must preserve unrelated clipboard contents")
        modelTable.draggingEnded(probe)
        precondition(modelTable.draggedFileURLs.isEmpty)
        print("PASS: cross-tab hover retains mixed file/folder/link payload, moves into empty current directory, refreshes both tabs and preserves clipboard")

        // A second cross-tab drag lands in a child folder, not the tab's root.
        let subtarget = other.appendingPathComponent("child-target", isDirectory: true)
        try fm.createDirectory(at: subtarget, withIntermediateDirectories: true)
        let ordinaryFile = other.appendingPathComponent("ordinary.txt")
        try Data().write(to: ordinaryFile)
        var destinationTab = BrowserTabState(directory: other)
        destinationTab.entries = try await model.service.listDirectory(other)
        model.tabs.append(destinationTab)
        model.render()
        let movedSources = sources.map { target.appendingPathComponent($0.lastPathComponent) }
        setSources(movedSources)
        modelTable.showDraggedFiles(Set(movedSources))
        probe.draggingSequenceNumber += 1
        probe.draggingLocation = modelStrip.convert(NSPoint(x: 490, y: 16), to: nil)
        _ = modelStrip.draggingEntered(probe)
        try await Task.sleep(for: .milliseconds(650))
        _ = modelStrip.draggingUpdated(probe)
        precondition(model.activeID == destinationTab.id && modelTable.draggedFileURLs == Set(movedSources))
        let fileRow = model.active.visibleEntries.firstIndex { !$0.isDirectory }!
        probe.draggingLocation = modelTable.convert(NSPoint(x: 70, y: modelTable.rect(ofRow: fileRow).midY), to: nil)
        precondition(model.controller.tableView(modelTable, validateDrop: probe, proposedRow: fileRow, proposedDropOperation: .on) == .move,
                     "An ordinary file row targets the tab's current directory")
        precondition(modelTable.fileDropTarget == nil)
        let subRow = model.active.visibleEntries.firstIndex { $0.isDirectory }!
        probe.draggingLocation = modelTable.convert(NSPoint(x: 70, y: modelTable.rect(ofRow: subRow).midY), to: nil)
        precondition(model.controller.tableView(modelTable, validateDrop: probe, proposedRow: subRow, proposedDropOperation: .on) == .move)
        precondition(modelTable.fileDropTarget?.resolvingSymlinksInPath() == subtarget.resolvingSymlinksInPath())
        precondition(model.controller.tableView(modelTable, acceptDrop: probe, row: subRow, dropOperation: .on))
        let secondDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        while model.busy || !model.tabs[1].entries.isEmpty {
            precondition(ContinuousClock.now < secondDeadline, "Child-folder move and source refresh timed out")
            try await Task.sleep(for: .milliseconds(20))
        }
        let finalPayload = try String(contentsOf: subtarget.appendingPathComponent(file.lastPathComponent), encoding: .utf8)
        precondition(finalPayload == "file payload")
        let finalNested = try String(contentsOf: subtarget.appendingPathComponent("资料/子目录/nested.txt"), encoding: .utf8)
        precondition(finalNested == "nested payload")
        modelTable.draggingEnded(probe)
        precondition(modelTable.draggedFileURLs.isEmpty && modelTable.fileDropTarget == nil)
        print("PASS: cross-tab child-folder move, ordinary-file fallback to current directory and drag cleanup")
    }
}

