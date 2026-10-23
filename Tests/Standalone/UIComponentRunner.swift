import AppKit
import WinwayCore

@MainActor
final class EditingProbe: NSObject {
    var events: [String] = []
    @objc func changed(_ notification: Notification) {
        let field = notification.object as? NSTextField
        events.append("\(notification.name.rawValue):\(field?.accessibilityIdentifier() ?? "unidentified")")
    }
}

@main
struct UIComponentRunner {
    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let probe = EditingProbe()
        for name in [NSControl.textDidBeginEditingNotification, NSControl.textDidEndEditingNotification] {
            NotificationCenter.default.addObserver(probe, selector: #selector(EditingProbe.changed(_:)), name: name, object: nil)
        }
        var actions: [ExplorerAction] = []
        let controller = ExplorerWindowController { actions.append($0) }
        var snapshot = ExplorerSnapshot()
        let directory = URL(fileURLWithPath: "/tmp/winway-ui-component-test")
        let entry = FileEntry(url: directory.appendingPathComponent("Original.txt"), name: "Original.txt", isDirectory: false)
        snapshot.tabs = [ExplorerTab(id: snapshot.activeTabID, title: "UI component test")]
        snapshot.directory = directory; snapshot.entries = [entry]; snapshot.selection = [entry.url]
        snapshot.enabledCommands = Set(CommandID.allCases)
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        controller.render(snapshot)
        let originalLabel = (controller.fileTable.view(atColumn: 0, row: 0, makeIfNecessary: true) as! NSTableCellView).textField!
        controller.beginRename()
        precondition(originalLabel.isHidden, "Rename must hide the original filename")
        func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
        let fields = allViews(controller.window!.contentView!).compactMap { $0 as? NSTextField }
        let rename = fields.first { $0.accessibilityIdentifier() == "winway.rename-editor" }
        print("Editing notifications:", probe.events)
        print("First responder:", String(describing: controller.window!.firstResponder))
        print("Rename field:", rename.map { "frame=\($0.frame),hidden=\($0.isHidden),editable=\($0.isEditable),editor=\(String(describing:$0.currentEditor()))" } ?? "MISSING")
        guard let rename, !rename.isHidden, rename.isEditable,
              let editor = rename.currentEditor() as? NSTextView, editor.isEditable else {
            fputs("FAIL: rename field must remain visible and own an editable field editor\n", stderr)
            exit(1)
        }
        editor.insertText("Renamed", replacementRange: editor.selectedRange)
        guard editor.string == "Renamed.txt" else { fatalError("Text insertion failed: \(editor.string)") }
        _ = controller.control(rename, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        guard actions.contains(where: { if case .rename(let url,let name) = $0 { return url == entry.url && name == "Renamed.txt" }; return false }) else {
            fatalError("Rename did not emit the expected URL and name")
        }
        guard !allViews(controller.window!.contentView!).contains(where: { $0.accessibilityIdentifier() == "winway.rename-editor" }) else { fatalError("Committed editor remained attached") }
        precondition(!originalLabel.isHidden, "Committing rename must restore the display label")
        func currentRenameEditor() -> (NSTextField, NSTextView) {
            let field = allViews(controller.window!.contentView!).compactMap { $0 as? NSTextField }
                .first { $0.accessibilityIdentifier() == "winway.rename-editor" }
            guard let field, !field.isHidden, let text = field.currentEditor() as? NSTextView, text.isEditable else {
                fatalError("A visible and editable rename field must remain attached")
            }
            return (field,text)
        }
        func renameCount() -> Int { actions.filter { if case .rename = $0 { return true }; return false }.count }
        guard renameCount() == 1 else { fatalError("Duplicate initial rename action") }

        // A failed filesystem rename preserves the proposed name in a new edit
        // session. It must not focus/select twice and remove its own field.
        snapshot.errorMessage = "名称冲突"
        controller.render(snapshot)
        let (retryField,retryText) = currentRenameEditor()
        precondition(originalLabel.isHidden, "Failed rename retry must hide the original filename again")
        guard retryText.string == "Renamed.txt", renameCount() == 1 else { fatalError("Failed rename lost input or submitted twice") }
        _ = controller.control(retryField, textView: retryText, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        guard renameCount() == 1 else { fatalError("Escape submitted a rename") }
        precondition(!originalLabel.isHidden, "Cancelling rename must restore the display label")
        guard !allViews(controller.window!.contentView!).contains(where: { $0.accessibilityIdentifier() == "winway.rename-editor" }) else { fatalError("Cancelled editor remained attached") }

        // Losing focus commits once and does not recursively seize the responder.
        snapshot.errorMessage = nil
        controller.render(snapshot)
        controller.beginRename()
        let (_,unicodeText) = currentRenameEditor()
        unicodeText.insertText("更名", replacementRange: unicodeText.selectedRange)
        controller.focusFiles()
        guard renameCount() == 2 else { fatalError("Focus loss must commit exactly once") }
        guard actions.contains(where: { if case .rename(_,let name) = $0 { return name == "更名.txt" }; return false }) else { fatalError("Unicode rename was not committed") }
        guard controller.window?.firstResponder === controller.fileTable else { fatalError("Focus loss did not preserve the requested table responder") }
        precondition(!originalLabel.isHidden, "Focus-loss commit must restore the display label")
        print("PASS: unshown AppKit rename component: text insertion, one Enter submission, failed-name restoration, Escape cancellation, Unicode input, one focus-loss submission")
        verifyNavigationScroll()
        verifyScrollGeometry()
        verifyRenameLayout()
        verifyFileTextAlignment()
        verifyColumnOverflowAndRenameVisibility()
        verifyWindowButtons()
        verifyMouseNavigation()
        verifyControlClickSelection()
        verifyFileContextMenus()
        verifyOpenWithMenus()
        verifyFileServices()
        verifyRubberBandSelection()
        verifyTabStripLayout()
        verifyBreadcrumbInteraction()
        verifyRowHover()
    }

    @MainActor
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    @MainActor
    static func verifyTabStripLayout() {
        let controller = ExplorerWindowController { _ in }
        let window = controller.window!
        var snapshot = ExplorerSnapshot()
        snapshot.tabs = (0..<12).map { ExplorerTab(id: UUID(), title: "Tab \($0)") }
        snapshot.activeTabID = snapshot.tabs[11].id
        for width: CGFloat in [960, 1376, 1600] {
            window.setContentSize(NSSize(width: width, height: 820))
            window.contentView!.layoutSubtreeIfNeeded()
            controller.render(snapshot)
            let views = descendants(window.contentView!)
            let strip = views.compactMap { $0 as? ExplorerTabStrip }.first!
            let scroll = strip.enclosingScrollView!
            let plus = views.compactMap { $0 as? ExplorerButton }.first { $0.glyph == "plus" }!
            precondition(plus.superview === scroll.superview, "Plus must sit outside the scrolling document")
            precondition(abs(plus.frame.maxX - (width - 16)) < 0.5, "Overflow pins plus to the right")
            let plusFrame = plus.frame
            scroll.contentView.scroll(to: NSPoint(x: 400, y: 0))
            precondition(plus.frame == plusFrame, "Scrolling tabs must not move plus")
            let tabs = strip.subviews.compactMap { $0 as? ExplorerTabView }
            precondition(strip.orderedTabIDs == snapshot.tabs.map(\.id))
            // Clicking the title reaches the gesture view; close remains a button.
            let first = tabs[0]
            precondition(first.hitTest(NSPoint(x: 50, y: 16)) === first)
            precondition(first.hitTest(NSPoint(x: 200, y: 16)) is ExplorerButton)
        }
        snapshot.tabs = Array(snapshot.tabs.prefix(1)); snapshot.activeTabID = snapshot.tabs[0].id
        controller.render(snapshot)
        let strip = descendants(window.contentView!).compactMap { $0 as? ExplorerTabStrip }.first!
        precondition(strip.enclosingScrollView!.contentView.bounds.minX == 0, "Closing overflow tabs must clamp the scroll position")
        print("PASS: tab overflow/resize, fixed plus, visual order, gesture hit regions and scroll clamping")
    }

    @MainActor
    static func verifyBreadcrumbInteraction() {
        var actions: [ExplorerAction] = []
        let controller = ExplorerWindowController { actions.append($0) }
        let window = controller.window!
        var snapshot = ExplorerSnapshot()
        snapshot.directory = URL(fileURLWithPath: "/Users/example/中文 空格/Project #1")
        snapshot.enabledCommands = [.newTab]
        window.contentView!.layoutSubtreeIfNeeded()
        controller.render(snapshot)
        let views = descendants(window.contentView!)
        let breadcrumb = views.compactMap { $0 as? ExplorerBreadcrumbView }.first!
        let field = views.compactMap { $0 as? NSTextField }.first { $0.accessibilityIdentifier() == "winway.path-editor" }!
        let segments = descendants(breadcrumb).compactMap { $0 as? ExplorerButton }.filter { $0.accessibilityIdentifier() == "winway.path-segment" }
        precondition(segments.map(\.title) == ["/", "Users", "example", "中文 空格", "Project #1"])
        for button in segments {
            actions.removeAll()
            button.performClick(nil)
            precondition(field.isHidden && !breadcrumb.isHidden, "A segment click must never edit the path")
            guard actions.count == 1, case .navigate(let url) = actions[0] else { fatalError("Segment must emit one navigation") }
            precondition(url.path == button.toolTip, "Segments must retain their exact ancestor URLs")
        }
        let edit = descendants(breadcrumb).compactMap { $0 as? ExplorerButton }.first { $0.accessibilityIdentifier() == "winway.path-edit-area" }!
        precondition(edit.frame.width >= 40 && edit.frame.maxX <= breadcrumb.bounds.width)
        actions.removeAll()
        edit.performClick(nil)
        precondition(actions.isEmpty && !field.isHidden && breadcrumb.isHidden)
        guard let text = field.currentEditor() as? NSTextView else { fatalError("Blank area must focus the address editor") }
        precondition(text.isEditable, "The native field editor must accept typing and paste")
        precondition(text.string == snapshot.directory.path && text.selectedRange.length == (text.string as NSString).length)
        text.insertText("/tmp", replacementRange: text.selectedRange)
        precondition(text.string == "/tmp", "Address input must replace the selected path")
        controller.focusAddress()
        precondition(!field.isHidden && text.string == "/tmp" && text.selectedRange.length == 4,
                     "Focusing an already editing address must select its input without closing or resetting it")
        let editorRect = text.convert(text.bounds, to: field.superview!)
        precondition(abs(editorRect.midY - field.superview!.bounds.midY) <= 1, "The live address editor must be vertically centered")
        _ = controller.control(field, textView: text, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        precondition(field.isHidden && !breadcrumb.isHidden && actions.isEmpty, "Escape must restore breadcrumbs without navigation")
        controller.focusAddress()
        controller.focusFiles()
        precondition(field.isHidden && !breadcrumb.isHidden, "Losing focus must restore breadcrumbs")
        let explorerWindow = window as! ExplorerWindow
        func pointerDown(at point: NSPoint, type: NSEvent.EventType = .leftMouseDown) {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            explorerWindow.onMouseDown?(event)
        }
        // Input and its padding remain editable; every outside region dismisses
        // without submitting the draft or consuming the target's original action.
        controller.focusAddress()
        let addressSurface = field.superview!
        pointerDown(at: addressSurface.convert(NSPoint(x: 2, y: 16), to: nil))
        precondition(!field.isHidden && field.currentEditor() != nil, "Address padding must not dismiss editing")
        pointerDown(at: field.convert(NSPoint(x: 20, y: 9), to: nil), type: .rightMouseDown)
        precondition(!field.isHidden, "The editor's context menu must remain usable")
        let actionCount = actions.count
        let root = window.contentView!
        for point in [NSPoint(x: 900, y: 22), NSPoint(x: 900, y: 110), NSPoint(x: 900, y: 790)] {
            for type: NSEvent.EventType in [.leftMouseDown, .rightMouseDown, .otherMouseDown] {
                controller.focusAddress()
                let editor = field.currentEditor() as! NSTextView
                editor.insertText("/unsubmitted", replacementRange: editor.selectedRange)
                pointerDown(at: root.convert(point, to: nil), type: type)
                precondition(field.isHidden && !breadcrumb.isHidden && field.currentEditor() == nil)
                precondition(actions.count == actionCount && field.stringValue == snapshot.directory.path,
                             "Outside clicks must discard the draft without navigating")
            }
        }
        controller.focusAddress()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        precondition(field.isHidden && !breadcrumb.isHidden, "Clicking another window or app must also exit editing")
        let plus = descendants(root).compactMap { $0 as? ExplorerButton }.first { $0.glyph == "plus" }!
        controller.focusAddress()
        pointerDown(at: plus.convert(NSPoint(x: 16, y: 16), to: nil))
        plus.performClick(nil)
        guard case .command(.newTab) = actions.last else { fatalError("The outside click's original button action must remain available") }
        controller.focusAddress()
        field.stringValue = "/tmp"
        field.sendAction(field.action, to: field.target)
        precondition(field.isHidden && !breadcrumb.isHidden)
        guard case .navigatePath("/tmp") = actions.last else { fatalError("Enter must submit the edited path") }
        for path in ["/", "/Users/example/" + Array(repeating: "long folder 中文", count: 20).joined(separator: "/")] {
            snapshot.directory = URL(fileURLWithPath: path)
            controller.render(snapshot)
            breadcrumb.layoutSubtreeIfNeeded()
            precondition(edit.frame.width >= 40 && edit.frame.maxX <= breadcrumb.bounds.width)
            let scroll = descendants(breadcrumb).compactMap { $0 as? NSScrollView }.first!
            precondition(scroll.documentVisibleRect.maxX >= scroll.documentView!.bounds.maxX - 1, "The final segment must remain visible")
        }
        print("PASS: breadcrumb navigation/editing, input centering, outside clicks across all buttons/regions, window blur, draft cancellation and target action")
    }

    @MainActor
    static func verifyRowHover() {
        let row = ExplorerRowView(frame: NSRect(x: 0, y: 0, width: 500, height: 36))
        let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        row.mouseEntered(with: event)
        precondition(row.hovered && !row.isSelected)
        row.isSelected = true
        row.mouseExited(with: event)
        precondition(!row.hovered && row.isSelected, "Hover exit must preserve selection")
        row.updateTrackingAreas()
        precondition(!row.hovered, "Detached/reused rows must not retain stale hover")
        print("PASS: list row hover enter/exit, selection independence and tracking reset")
    }

    @MainActor
    static func verifyScrollGeometry() {
        for style: NSScroller.Style in [.legacy, .overlay] {
            let controller = ExplorerWindowController { _ in }
            let window = controller.window!
            let table = controller.fileTable
            let scroll = table.enclosingScrollView!
            scroll.scrollerStyle = style
            var snapshot = ExplorerSnapshot()
            snapshot.directory = URL(fileURLWithPath: "/tmp/winway-scroll-geometry")
            let entries = (0..<103).map { index in
                FileEntry(url: snapshot.directory.appendingPathComponent("File-\(index).txt"), name: "File-\(index).txt", isDirectory: false)
            }
            func verifyBottom() {
                let last = table.rect(ofRow: table.numberOfRows - 1)
                precondition(table.frame.height >= last.maxY, "Document height must include the entire last row")
                table.scrollRowToVisible(table.numberOfRows - 1)
                let visible = table.visibleRect
                precondition(visible.maxY >= last.maxY - 0.5 && visible.minY + scroll.contentView.contentInsets.top <= last.minY,
                             "The last row must scroll fully above the bottom edge and any horizontal scroller")
            }
            // Both scrollbar modes, repeated appearance/disappearance of the
            // vertical scroller, and narrow windows with real column overflow.
            for width: CGFloat in [1376, 960, 1376] {
                window.setContentSize(NSSize(width: width, height: 820))
                window.contentView?.layoutSubtreeIfNeeded()
                for count in [1, 103, 1, 103] {
                    snapshot.entries = Array(entries.prefix(count))
                    controller.render(snapshot)
                    window.contentView?.layoutSubtreeIfNeeded()
                    let overflow = table.frame.width > scroll.contentSize.width + 0.5
                    precondition(overflow == (width == 960), "Only genuinely narrow columns should require horizontal scrolling")
                    if style == .legacy {
                        precondition(scroll.horizontalScroller?.isHidden == !overflow, "Legacy horizontal scroller visibility must match actual overflow")
                    }
                    verifyBottom()
                }
            }
            let kindColumn = table.tableColumns.first { $0.identifier.rawValue == "kind" }!
            let originalWidth = kindColumn.width
            kindColumn.width = 1000
            table.tile()
            precondition(table.frame.width > scroll.contentSize.width, "Widened metadata columns beyond the flexible name column's minimum must remain horizontally scrollable")
            verifyBottom()
            kindColumn.width = originalWidth
            table.tile()
            snapshot.showDetails = false
            controller.render(snapshot)
            precondition(table.frame.width <= scroll.contentSize.width + 0.5, "Closing details must fill the wider viewport without overflow")
            verifyBottom()
            scroll.scrollerStyle = style == .legacy ? .overlay : .legacy
            controller.render(snapshot)
            verifyBottom()
        }
        print("PASS: scroll geometry: 103 complete rows, legacy/overlay scrollers, narrow/wide windows, short/long directories, details and scrollbar-style changes")
    }

    @MainActor
    static func verifyColumnOverflowAndRenameVisibility() {
        let controller = ExplorerWindowController { _ in }
        let window = controller.window!
        let table = controller.fileTable
        var snapshot = ExplorerSnapshot()
        let names = ["文件开头_" + String(repeating: "long-filename-", count: 12) + "_保留末尾.txt", "Short.txt"]
        snapshot.entries = names.map { FileEntry(url: URL(fileURLWithPath: "/tmp/winway-overflow/\($0)"), name: $0, isDirectory: false) }
        let editingURL = snapshot.entries[0].url
        snapshot.selection = [editingURL]; snapshot.enabledCommands = Set(CommandID.allCases)
        window.contentView!.layoutSubtreeIfNeeded()
        controller.render(snapshot)
        func label(_ column: Int, _ row: Int) -> NSTextField {
            let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) as! NSTableCellView
            cell.layoutSubtreeIfNeeded()
            return cell.textField!
        }
        for width: CGFloat in [180, 420, 200] {
            for column in table.tableColumns { column.width = column.identifier.rawValue == "name" ? width : 90 }
            table.layoutSubtreeIfNeeded()
            for column in table.tableColumns.indices where !table.tableColumns[column].isHidden {
                let text = label(column, 0)
                let cell = text.superview!
                precondition(text.frame.minX >= 0 && text.frame.maxX <= cell.bounds.maxX, "Text must remain inside its column after resizing")
                precondition(text.lineBreakMode == .byTruncatingMiddle && text.cell?.isScrollable == false, "Display text must truncate in the middle instead of scrolling beyond the column")
            }
            precondition(label(0, 0).stringValue == names[0] && label(0, 0).toolTip == names[0], "Truncation must preserve the original filename and tooltip")
        }
        controller.beginRename()
        precondition(label(0, 0).isHidden && !label(1, 0).isHidden, "Only the filename being edited should be hidden")
        snapshot.entries.reverse()
        controller.render(snapshot)
        precondition(label(0, 1).isHidden && !label(0, 0).isHidden, "Reloaded cells must follow the editing URL, not the old row index")
        controller.focusFiles()
        precondition(!label(0, 1).isHidden, "The current display cell must be restored after a reload")
        controller.beginRename()
        snapshot.entries.removeAll { $0.url == editingURL }
        snapshot.selection = []
        controller.render(snapshot)
        precondition(!label(0, 0).isHidden, "Removing an edited entry must not leave reused cells hidden")
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        precondition(!views(window.contentView!).contains { $0.accessibilityIdentifier() == "winway.rename-editor" }, "Removing an edited entry must dismiss its editor")
        print("PASS: column resizing contains long text, preserves full names, and rename visibility survives reload, reordering, focus loss and entry removal")
    }

    @MainActor
    static func verifyFileTextAlignment() {
        let controller = ExplorerWindowController { _ in }
        let window = controller.window!
        var snapshot = ExplorerSnapshot()
        snapshot.entries = ["tools", "中文文件.txt", "Report-2026.txt"].map {
            FileEntry(url: URL(fileURLWithPath: "/tmp/winway-alignment/\($0)"), name: $0, isDirectory: false)
        }
        snapshot.enabledCommands = Set(CommandID.allCases)
        let table = controller.fileTable
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        for size in [NSSize(width: 1376, height: 820), NSSize(width: 960, height: 600)] {
            window.setContentSize(size)
            window.contentView!.layoutSubtreeIfNeeded()
            for row in snapshot.entries.indices {
                snapshot.selection = [snapshot.entries[row].url]
                controller.render(snapshot)
                var baselines: [CGFloat] = []
                for column in table.tableColumns.indices where !table.tableColumns[column].isHidden {
                    let cell = table.view(atColumn: column, row: row, makeIfNecessary: true) as! NSTableCellView
                    cell.layoutSubtreeIfNeeded()
                    let label = cell.textField!
                    let frame = cell.convert(label.bounds, from: label)
                    precondition(abs(frame.midY - cell.bounds.midY) < 0.5, "File text line must be centered within the row")
                    precondition(abs(frame.height - label.intrinsicContentSize.height) < 0.5, "Text must use its natural line height")
                    let baseline = label.convert(NSPoint(x: 0, y: label.bounds.height - label.baselineOffsetFromBottom), to: table).y
                    baselines.append(baseline)
                }
                precondition(baselines.allSatisfy { abs($0 - baselines[0]) < 0.5 }, "All columns must share a baseline")
                controller.beginRename()
                let field = views(window.contentView!).compactMap { $0 as? NSTextField }
                    .first { $0.accessibilityIdentifier() == "winway.rename-editor" }!
                let editor = field.currentEditor() as! NSTextView
                let layout = editor.layoutManager!
                layout.ensureLayout(for: editor.textContainer!)
                let glyph = layout.location(forGlyphAt: 0)
                let baseline = editor.convert(NSPoint(x: 0, y: editor.textContainerOrigin.y + glyph.y), to: table).y
                precondition(abs(baseline - baselines[0]) < 0.5, "Entering rename must not shift the text baseline")
                precondition(field.frame.height == 26, "Centering must preserve the rename border height")
                _ = controller.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
            }
        }
        print("PASS: all four file columns and rename share centered text baselines for English, Chinese and numbers at two window sizes")
    }

    @MainActor
    static func verifyMouseNavigation() {
        var commands: [CommandID] = []
        let controller = ExplorerWindowController { action in
            if case .command(let command) = action { commands.append(command) }
        }
        let window = controller.window!
        var snapshot = ExplorerSnapshot()
        snapshot.canGoBack = true; snapshot.canGoForward = true
        snapshot.enabledCommands = [.back, .forward]
        controller.render(snapshot)

        func send(_ type: CGEventType, button: Int64) {
            let cgEvent = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: .zero, mouseButton: .center)!
            cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: button)
            let event = NSEvent(cgEvent: cgEvent)!
            precondition(event.buttonNumber == Int(button))
            window.sendEvent(event)
        }
        for button: Int64 in [3, 4] {
            send(.otherMouseDown, button: button)
            send(.otherMouseUp, button: button)
        }
        precondition(commands == [.back, .forward], "Each side-button click must navigate exactly once")

        for button: Int64 in [2, 5] {
            send(.otherMouseDown, button: button)
            send(.otherMouseUp, button: button)
        }
        precondition(commands == [.back, .forward], "Middle and unrelated buttons must not navigate")

        snapshot.canGoBack = false
        snapshot.enabledCommands.remove(.back)
        controller.render(snapshot)
        send(.otherMouseDown, button: 3)
        precondition(commands == [.back, .forward], "Back must do nothing at the start of history")
        send(.otherMouseDown, button: 4)
        precondition(commands == [.back, .forward, .forward], "Available forward history must remain usable")
        snapshot.canGoForward = false
        snapshot.enabledCommands.remove(.forward)
        controller.render(snapshot)
        send(.otherMouseDown, button: 4)
        precondition(commands.count == 3, "Forward must do nothing at the end of history")
        print("PASS: mouse side buttons navigate once per click, respect history availability, and ignore other buttons")
    }

    @MainActor
    static func verifyRubberBandSelection() {
        var inspectSelection: (() -> Void)?
        let controller = ExplorerWindowController { action in
            if case .select = action { inspectSelection?() }
        }
        let window = controller.window!
        let table = controller.fileTable
        let viewport = table.enclosingScrollView!.contentView
        var snapshot = ExplorerSnapshot()
        snapshot.entries = (0..<8).map {
            FileEntry(url: URL(fileURLWithPath: "/tmp/band-\($0).txt"), name: "band-\($0).txt", isDirectory: false)
        }
        window.contentView!.layoutSubtreeIfNeeded()
        controller.render(snapshot)
        controller.showWindow(nil)
        defer { window.orderOut(nil) }

        for offset: CGFloat in [0, 48] {
            table.setFrameSize(NSSize(width: table.frame.width, height: viewport.bounds.height + 100))
            viewport.scroll(to: NSPoint(x: 0, y: offset))
            let origin = NSPoint(x: 360, y: 400)
            let end = NSPoint(x: 130, y: 80)
            var inspected = false
            inspectSelection = {
                guard !table.selectedRowIndexes.isEmpty else { return }
                guard let overlay = viewport.subviews.compactMap({ $0 as? ExplorerSelectionOverlay }).first else {
                    fatalError("Dragging must show a selection overlay")
                }
                precondition(overlay.hitTest(.zero) == nil, "The selection overlay must pass mouse events through")
                precondition(table.selectedRowIndexes == IndexSet(2..<8), "Upward blank-space drag must select intersected rows")
                window.contentView!.layoutSubtreeIfNeeded()
                let bitmap = viewport.bitmapImageRepForCachingDisplay(in: viewport.bounds)!
                viewport.cacheDisplay(in: viewport.bounds, to: bitmap)
                @MainActor func color(at point: NSPoint) -> NSColor {
                    let local = viewport.convert(point, from: table)
                    let x = Int((local.x - viewport.bounds.minX) * CGFloat(bitmap.pixelsWide) / viewport.bounds.width)
                    let y = Int((local.y - viewport.bounds.minY) * CGFloat(bitmap.pixelsHigh) / viewport.bounds.height)
                    return bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                }
                // Verify actual compositing over both an opaque selected row and empty space.
                for y: CGFloat in [120, 330] {
                    let outside = color(at: NSPoint(x: end.x - 4, y: y))
                    let border = color(at: NSPoint(x: end.x, y: y))
                    precondition(outside.redComponent - border.redComponent > 0.1,
                                 "The rectangle border must remain visible over rows and blank space")
                }
                if offset == 0, let path = ProcessInfo.processInfo.environment["WINWAY_SELECTION_SNAPSHOT"] {
                    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
                }
                inspected = true
            }
            func event(_ type: NSEvent.EventType, at point: NSPoint) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: table.convert(point, to: nil), modifierFlags: [],
                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            // Queue the tracked events before entering the table's native drag loop.
            NSApp.postEvent(event(.leftMouseUp, at: end), atStart: true)
            NSApp.postEvent(event(.leftMouseDragged, at: end), atStart: true)
            table.mouseDown(with: event(.leftMouseDown, at: origin))
            precondition(inspected, "The drag must update selection before mouse-up")
            precondition(!viewport.subviews.contains { $0 is ExplorerSelectionOverlay }, "Mouse-up must remove the rectangle")
            inspectSelection = nil
            table.deselectAll(nil)
        }
        print("PASS: upward rubber-band selection, border pixels over selected rows and empty space, scroll coordinates, event passthrough and mouse-up cleanup")
    }

    @MainActor
    static func verifyFileContextMenus() {
        var snapshot = ExplorerSnapshot()
        snapshot.entries = [
            FileEntry(url: URL(fileURLWithPath: "/tmp/menu-folder"), name: "menu-folder", isDirectory: true),
            FileEntry(url: URL(fileURLWithPath: "/tmp/menu-file.txt"), name: "menu-file.txt", isDirectory: false),
            FileEntry(url: URL(fileURLWithPath: "/tmp/menu-other.txt"), name: "menu-other.txt", isDirectory: false)
        ]
        snapshot.enabledCommands = Set(CommandID.allCases).subtracting([.paste])
        var actions: [ExplorerAction] = []
        let controller = ExplorerWindowController { actions.append($0) }
        controller.window!.contentView!.layoutSubtreeIfNeeded()
        controller.render(snapshot)
        let table = controller.fileTable
        func menu(at row: Int?) -> NSMenu {
            let y = row.map { table.rect(ofRow: $0).midY } ?? (table.rect(ofRow: 2).maxY + 30)
            let event = NSEvent.mouseEvent(with: .rightMouseDown,
                                          location: table.convert(NSPoint(x: 70, y: y), to: nil), modifierFlags: [],
                                          timestamp: 0, windowNumber: controller.window!.windowNumber,
                                          context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            return table.menu(for: event)!
        }
        func commands(_ menu: NSMenu) -> [CommandID] {
            menu.items.compactMap { ($0.representedObject as? String).flatMap(CommandID.init(rawValue:)) }
        }
        func checkSeparators(_ menu: NSMenu) {
            precondition(menu.items.first?.isSeparatorItem == false && menu.items.last?.isSeparatorItem == false)
            precondition(!zip(menu.items, menu.items.dropFirst()).contains { $0.isSeparatorItem && $1.isSeparatorItem })
        }
        let file = menu(at: 1)
        precondition(commands(file) == [.open, .cut, .copy, .rename, .trash])
        precondition(!file.items.contains { $0.title == "在新标签页中打开" })
        let folder = menu(at: 0)
        precondition(table.selectedRowIndexes == IndexSet(integer: 0), "Right-click must target the clicked folder")
        let openInTab = folder.items.first { $0.title == "在新标签页中打开" }!
        precondition(openInTab.isEnabled)
        _ = NSApp.sendAction(openInTab.action!, to: openInTab.target, from: openInTab)
        precondition(actions.contains { if case .openFolderInNewTab(let url) = $0 { return url == snapshot.entries[0].url }; return false })
        table.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        let mixed = menu(at: 0)
        precondition(table.selectedRowIndexes == IndexSet([0, 1]), "Right-click within a selection must preserve the batch")
        precondition(commands(mixed) == [.open, .cut, .copy, .trash])
        precondition(!mixed.items.contains { $0.title == "在新标签页中打开" })
        let other = menu(at: 2)
        precondition(table.selectedRowIndexes == IndexSet(integer: 2), "Right-click outside a selection must replace it")
        precondition(commands(other).contains(.rename))
        let blank = menu(at: nil)
        precondition(table.selectedRowIndexes.isEmpty, "Blank-space menus must clear the previous target")
        precondition(commands(blank) == [.newFolder, .paste, .refresh])
        precondition(blank.items.first { $0.representedObject as? String == CommandID.paste.rawValue }?.isEnabled == false)
        precondition(blank.items.first { $0.title == "排序方式" }?.submenu != nil)
        precondition(commands(blank.items.first { $0.title == "显示" }!.submenu!) == [.toggleDetails, .toggleHidden])
        for menu in [file, folder, mixed, other, blank] { checkSeparators(menu) }
        snapshot.entries = []
        snapshot.enabledCommands.insert(.paste)
        controller.render(snapshot)
        let empty = table.contextMenu!()
        precondition(commands(empty) == [.newFolder, .paste, .refresh])
        precondition(empty.items.first { $0.representedObject as? String == CommandID.paste.rawValue }?.isEnabled == true)
        print("PASS: distinct blank/file/folder/multiple-selection menus, clicked target, folder action, empty directory, paste availability and separators")
    }

    @MainActor
    static func verifyOpenWithMenus() {
        let first = URL(fileURLWithPath: "/tmp/中文 压缩包.zip")
        let second = URL(fileURLWithPath: "/tmp/另一个.rar")
        let universal = URL(fileURLWithPath: "/Applications/Archive.app")
        let zipOnly = URL(fileURLWithPath: "/Applications/ZIP.app")
        var received: ([URL], URL)?
        let menu = ExplorerOpenWithMenu(urls: [first, second]) { received = ($0, $1) }
        menu.applicationsForURL = { $0 == first ? [zipOnly, universal, universal] : [universal] }
        menu.defaultApplicationForURL = { _ in universal }
        menu.menuNeedsUpdate(menu)
        precondition(menu.items.count == 1 && menu.items[0].title.hasSuffix("（默认）"))
        precondition(menu.items[0].representedObject as? URL == universal)
        _ = NSApp.sendAction(menu.items[0].action!, to: menu.items[0].target, from: menu.items[0])
        precondition(received?.0 == [first, second] && received?.1 == universal, "Opening must preserve all captured URLs")
        menu.defaultApplicationForURL = { $0 == first ? zipOnly : universal }
        menu.menuNeedsUpdate(menu)
        precondition(!menu.items[0].title.contains("默认"), "Mixed defaults must not be labeled as a common default")
        menu.applicationsForURL = { $0 == first ? [zipOnly] : [universal] }
        menu.menuNeedsUpdate(menu)
        precondition(menu.items.count == 1 && !menu.items[0].isEnabled && menu.items[0].action == nil)

        let single = ExplorerOpenWithMenu(urls: [first]) { _, _ in }
        single.applicationsForURL = { _ in [universal, zipOnly, universal] }
        single.defaultApplicationForURL = { _ in zipOnly }
        single.menuNeedsUpdate(single)
        precondition(single.items.count == 2 && single.items[0].representedObject as? URL == zipOnly)
        print("PASS: Open With common-app intersection, deduplication, default-first ordering, mixed defaults, empty results and captured multi-file handoff")
    }

    @MainActor
    static func verifyFileServices() {
        var snapshot = ExplorerSnapshot()
        snapshot.entries = [
            FileEntry(url: URL(fileURLWithPath: "/tmp/服务测试/中文 空格.zip"), name: "中文 空格.zip", isDirectory: false),
            FileEntry(url: URL(fileURLWithPath: "/tmp/服务测试/文件夹", isDirectory: true), name: "文件夹", isDirectory: true)
        ]
        snapshot.selection = Set(snapshot.entries.map(\.url))
        let controller = ExplorerWindowController { _ in }
        controller.window!.contentView!.layoutSubtreeIfNeeded()
        controller.render(snapshot)
        let table = controller.fileTable
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let generalChange = NSPasteboard.general.changeCount
        let legacy = ExplorerFileTable.filenamesType
        for type in ExplorerFileTable.serviceTypes {
            precondition(table.validRequestor(forSendType: type, returnType: nil) as? ExplorerFileTable === table)
        }
        precondition(table.validRequestor(forSendType: .string, returnType: nil) == nil)
        precondition(table.validRequestor(forSendType: .fileURL, returnType: .string) == nil, "File services must not promise to replace a selection with returned text")
        let expected = snapshot.entries.map(\.url)
        precondition(table.writeSelection(to: board, types: [.fileURL]))
        precondition(board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] == expected)
        precondition(table.writeSelection(to: board, types: [.fileURL, legacy]))
        let actual = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        // AppKit's legacy conversion removes the directory's trailing slash.
        precondition(actual?.map(\.path) == expected.map(\.path), "The service pasteboard must retain every file path, including Unicode and spaces")
        precondition(board.propertyList(forType: legacy) as? [String] == expected.map(\.path))
        precondition(table.writeSelection(to: board, types: [legacy]))
        precondition(board.propertyList(forType: legacy) as? [String] == expected.map(\.path))
        precondition(NSPasteboard.general.changeCount == generalChange, "Services must not overwrite the user's clipboard")
        let previousChange = board.changeCount
        precondition(!table.writeSelection(to: board, types: [.string]) && board.changeCount == previousChange)
        table.deselectAll(nil)
        precondition(table.validRequestor(forSendType: .fileURL, returnType: nil) == nil)
        precondition(!table.writeSelection(to: board, types: [.fileURL]))
        print("PASS: Services requestor validation, multi-file URLs and legacy paths, Unicode, folders, empty selection and clipboard isolation")
    }

    @MainActor
    static func verifyControlClickSelection() {
        var selections: [Set<URL>] = []
        let controller = ExplorerWindowController { action in
            if case .select(let urls) = action { selections.append(urls) }
        }
        let window = controller.window!
        let table = controller.fileTable
        var snapshot = ExplorerSnapshot()
        snapshot.preset = .windows
        snapshot.entries = (0..<5).map {
            FileEntry(url: URL(fileURLWithPath: "/tmp/selection-\($0).txt"), name: "selection-\($0).txt", isDirectory: false)
        }
        window.contentView!.layoutSubtreeIfNeeded()
        controller.render(snapshot)
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        var menus = 0
        table.contextMenu = {
            menus += 1
            let menu = NSMenu()
            // This routing probe must not enter a native Services popup loop.
            menu.allowsContextMenuPlugIns = false
            return menu
        }
        func click(_ row: Int, modifiers: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .leftMouseDown) {
            let rect = table.rect(ofRow: row)
            let point = table.convert(NSPoint(x: 70, y: rect.midY), to: nil)
            let upType: NSEvent.EventType = type == .rightMouseDown ? .rightMouseUp : .leftMouseUp
            for eventType in [type, upType] {
                let event = NSEvent.mouseEvent(with: eventType, location: point, modifierFlags: modifiers,
                                              timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                              context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                window.sendEvent(event)
            }
        }
        click(0)
        click(2, modifiers: .control)
        precondition(table.selectedRowIndexes == IndexSet([0, 2]), "Ctrl-click must add a nonadjacent file")
        click(0, modifiers: .control)
        precondition(table.selectedRowIndexes == IndexSet([2]), "Ctrl-click must deselect an already selected file")
        click(4, modifiers: [.control, .shift])
        precondition(table.selectedRowIndexes == IndexSet(0...4), "Ctrl-Shift-click must extend from the selection anchor")
        precondition(menus == 0, "Windows Ctrl-click must not open a context menu")
        precondition(selections.last == Set(snapshot.entries.map(\.url)), "Selection must reach the application model")
        click(1)
        precondition(table.selectedRowIndexes == IndexSet([1]), "Plain click must replace the selection")
        click(1, type: .rightMouseDown)
        precondition(menus == 1, "Right-click must still open a context menu")
        table.windowsSelection = false
        click(3, modifiers: .command)
        precondition(table.selectedRowIndexes == IndexSet([1, 3]), "macOS Command-click must preserve additive selection")
        print("PASS: window-dispatched Ctrl-click add/remove, Ctrl-Shift range, plain click, model selection, right-click and macOS Command-click")
    }

    @MainActor
    static func verifyWindowButtons() {
        let controller = ExplorerWindowController { _ in }
        let window = controller.window!
        let root = window.contentView!
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons = kinds.map { window.standardWindowButton($0)! }
        let sizes = buttons.map(\.frame.size)
        let originalOrigins = buttons.map(\.frame.origin)
        for size in [NSSize(width: 1376, height: 820), NSSize(width: 960, height: 600), NSSize(width: 1600, height: 900)] {
            window.setContentSize(size)
            root.layoutSubtreeIfNeeded()
            controller.render(ExplorerSnapshot())
            window.update()
            let firstFrame = buttons[0].convert(buttons[0].bounds, to: root)
            for (index, button) in buttons.enumerated() {
                let frame = button.convert(button.bounds, to: root)
                let parent = button.superview!
                let desired = NSRect(x: 18 + frame.minX - firstFrame.minX,
                                     y: 22 - frame.height / 2, width: frame.width, height: frame.height)
                // Older macOS titlebar containers cannot fit the shifted
                // buttons. Production intentionally preserves their native
                // position instead of moving them outside the hit-test area.
                if parent.bounds.contains(parent.convert(desired, from: root)) {
                    precondition(abs(frame.midY - 22) < 0.5, "Window buttons must align when their container permits it")
                    if index == 0 { precondition(abs(frame.minX - 18) < 0.5, "Left inset must be 18 pt") }
                } else {
                    precondition(button.frame.origin == originalOrigins[index], "Constrained titlebars must preserve native positions")
                }
                precondition(button.frame.size == sizes[index], "Native button sizes must be preserved")
                var ancestor = button.superview
                while let view = ancestor {
                    let rect = button.convert(button.bounds, to: view)
                    precondition(view.bounds.contains(rect), "Window button is clipped by an ancestor")
                    ancestor = view.superview
                }
                let point = NSPoint(x: button.frame.midX, y: button.frame.midY)
                precondition(parent.hitTest(point) === button, "Native button must remain clickable")
            }
        }
        print("PASS: window buttons retain size, align when supported or preserve native positions, remain unclipped and hit-testable across three window sizes")
    }

    @MainActor
    static func verifyNavigationScroll() {
        let controller = ExplorerWindowController { _ in }
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        var snapshot = ExplorerSnapshot()
        func entries(_ directory: URL) -> [FileEntry] {
            (0..<200).map { FileEntry(url: directory.appendingPathComponent("File-\($0).txt"), name: "File-\($0).txt", isDirectory: false) }
        }
        snapshot.directory = URL(fileURLWithPath: "/tmp/winway-scroll-A")
        snapshot.entries = entries(snapshot.directory)
        controller.render(snapshot)
        let scroll = controller.fileTable.enclosingScrollView!
        let clip = scroll.contentView
        func offset() -> CGFloat { clip.bounds.minY + clip.contentInsets.top }
        clip.scroll(to: NSPoint(x: 0, y: 1500))
        let retained = offset()
        snapshot.scrollOffset = retained
        snapshot.statusMessage = "刷新完成"
        controller.render(snapshot)
        precondition(abs(offset() - retained) < 1, "Refresh must preserve scroll position")
        snapshot.directory = URL(fileURLWithPath: "/tmp/winway-scroll-B")
        snapshot.entries = entries(snapshot.directory)
        snapshot.scrollOffset = 0
        controller.render(snapshot)
        precondition(abs(offset()) < 1, "Navigation within one tab must reset to the first row")
        snapshot.activeTabID = UUID()
        snapshot.scrollOffset = 480
        controller.render(snapshot)
        precondition(abs(offset() - 480) < 1, "Switching tabs must restore that tab's offset")
        print("PASS: navigation resets scroll; refresh preserves it; tab switch restores it")
    }

    @MainActor
    static func verifyRenameLayout() {
        let controller = ExplorerWindowController { _ in }
        controller.window?.setContentSize(NSSize(width: 960, height: 600))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        var snapshot = ExplorerSnapshot()
        snapshot.entries = (0..<200).map { FileEntry(url: URL(fileURLWithPath: "/tmp/winway-layout/File-\($0).txt"), name: "File-\($0).txt", isDirectory: false) }
        snapshot.selection = [snapshot.entries[0].url]
        snapshot.enabledCommands = Set(CommandID.allCases)
        controller.render(snapshot)
        let table = controller.fileTable
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func editor() -> NSTextField {
            guard let field = views(controller.window!.contentView!).compactMap({ $0 as? NSTextField }).first(where: { $0.accessibilityIdentifier() == "winway.rename-editor" }) else {
                fatalError("Missing rename editor")
            }
            return field
        }
        func checkNameAlignment() {
            let field = editor()
            let column = table.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
            let cell = table.frameOfCell(atColumn: column, row: 0)
            let frame = table.convert(field.bounds, from: field)
            precondition(abs(frame.minX - cell.minX - 32) < 1, "Editor must follow the name column")
            precondition(abs(frame.width - (cell.width - 36)) < 1, "Editor must follow the name column width")
        }
        table.moveColumn(0, toColumn: 3)
        controller.beginRename()
        checkNameAlignment()
        precondition(!editor().isHidden, "Reordered name column must scroll into view for editing")
        table.tableColumns[3].width = 260
        checkNameAlignment()
        let movedField = editor()
        _ = controller.control(movedField, textView: movedField.currentEditor() as! NSTextView, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        table.moveColumn(3, toColumn: 0)
        controller.beginRename()
        checkNameAlignment()
        let scroll = table.enclosingScrollView!
        scroll.contentView.scroll(to: NSPoint(x: 200, y: 10))
        scroll.reflectScrolledClipView(scroll.contentView)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        let field = editor()
        let overlay = field.superview!
        precondition(overlay.layer?.masksToBounds == true, "Rename viewport must clip its editor and field editor")
        let viewport = table.visibleRect.intersection(table.bounds)
        let overlayRect = table.convert(overlay.bounds, from: overlay)
        precondition(overlayRect.equalTo(viewport), "Clip container must exactly follow the file viewport")
        precondition(field.frame.minX < 0 && field.frame.minY < 0, "Fixture must exercise partial clipping on both axes")
        let exposed = overlay.convert(field.bounds, from: field).intersection(overlay.bounds)
        precondition(!exposed.isEmpty, "Partially visible editor must stay usable")
        precondition(overlay.hitTest(NSPoint(x: overlay.frame.maxX - 1, y: overlay.frame.maxY - 1)) == nil, "Empty overlay must pass pointer events to the list")
        guard let text = field.currentEditor() as? NSTextView else { fatalError("Clipping must preserve editing focus") }
        _ = controller.control(field, textView: text, doCommandBy: #selector(NSResponder.cancelOperation(_:)))
        precondition(overlay.superview == nil, "Closing the editor must detach its overlay")
        print("PASS: 960x600 rename follows column reorder/resize, clips both axes, preserves focus and passes pointer events")
    }
}
