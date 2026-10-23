import AppKit
import WinwayCore

@MainActor
final class TabDragProbe: NSObject, NSDraggingInfo {
    var draggingDestinationWindow: NSWindow?
    var draggingSourceOperationMask: NSDragOperation { .move }
    var draggingLocation: NSPoint = .zero
    var draggedImageLocation: NSPoint { draggingLocation }
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard = NSPasteboard.withUniqueName()
    var draggingSource: Any?
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(options: NSDraggingItemEnumerationOptions, for view: NSView?, classes: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}

@main
struct TabsRunner {
    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("winway-tabs-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var cases = 0
        for count in [1, 3, 5] {
            for target in 0..<count {
                for active in 0..<count {
                    for scope in TabCloseScope.allCases {
                        let model = AppModel(directory: root, settingsURL: root.appendingPathComponent("keyboard.json"))
                        model.tabs = (0..<count).map { index in
                            var tab = BrowserTabState(directory: root.appendingPathComponent("Tab-\(index)"))
                            let file = tab.navigation.directory.appendingPathComponent("file.txt")
                            tab.entries = [FileEntry(url: file, name: "file.txt", isDirectory: false)]
                            tab.selection = [file]
                            tab.scrollOffset = CGFloat(index * 30)
                            return tab
                        }
                        let original = model.tabs
                        model.activeID = original[active].id
                        let remaining = original.enumerated().filter { index, _ in
                            switch scope {
                            case .current: index != target
                            case .others: index == target
                            case .left: index >= target
                            case .right: index <= target
                            }
                        }.map(\.element)
                        model.handle(.closeTabs(original[target].id, scope))
                        if remaining.isEmpty {
                            precondition(model.tabs.count == 1 && model.activeID == model.tabs[0].id)
                            precondition(model.active.navigation.directory == FileManager.default.homeDirectoryForCurrentUser)
                        } else {
                            precondition(model.tabs.map(\.id) == remaining.map(\.id), "Close must preserve the exact survivors and order")
                            let expectedActive = remaining.contains { $0.id == original[active].id }
                                ? original[active].id
                                : (scope == .current ? remaining[min(target, remaining.count - 1)].id : original[target].id)
                            precondition(model.activeID == expectedActive, "Closing a background tab must preserve the active tab")
                            for (actual, expected) in zip(model.tabs, remaining) {
                                precondition(actual.selection == expected.selection && actual.scrollOffset == expected.scrollOffset)
                                precondition(actual.navigation.history == expected.navigation.history)
                            }
                        }
                        let ids = model.tabs.map(\.id)
                        model.handle(.closeTabs(UUID(), scope))
                        precondition(model.tabs.map(\.id) == ids, "Stale tab IDs must be ignored")
                        cases += 1
                    }
                }
            }
        }
        print("PASS: \(cases) tab close cases: target/active positions, scopes, survivor state, last-tab fallback and stale IDs")
        verifyTabInteraction()
        verifyReordering(root: root)
        verifyDragDestination()
    }

    @MainActor
    static func verifyTabInteraction() {
        for count in [1, 3] {
            for index in 0..<count {
                for selected in [false, true] {
                    var actions: [ExplorerAction] = []
                    let tab = ExplorerTab(id: UUID(), title: "Tab \(index)")
                    let view = ExplorerTabView(tab: tab, isSelected: selected, index: index, count: count) { actions.append($0) }
                    view.frame = NSRect(x: 0, y: 0, width: 220, height: 32)
                    let buttons = view.subviews.compactMap { $0 as? ExplorerButton }
                    precondition(buttons.count == 2 && buttons.allSatisfy { !$0.showsInteractionBackground })
                    let menu = view.menu!
                    precondition(buttons.allSatisfy { $0.menu === menu }, "All tab regions must expose the same context menu")
                    let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
                    let idleColor = view.layer!.backgroundColor!
                    view.mouseEntered(with: event)
                    precondition(view.layer!.backgroundColor != idleColor, "Hover must change the whole tab surface")
                    view.mouseExited(with: event)
                    precondition(view.layer!.backgroundColor == idleColor, "Exit must restore selected/unselected appearance")
                    let down = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 60, y: 16), modifierFlags: [], timestamp: 0,
                                                  windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                    view.mouseDown(with: down)
                    precondition(view.layer!.backgroundColor != idleColor && actions.isEmpty, "Press feedback must appear before activation")
                    let up = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: 60, y: 16), modifierFlags: [], timestamp: 0.1,
                                                windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
                    view.mouseUp(with: up)
                    precondition(view.layer!.backgroundColor == idleColor && actions.count == 1, "Release activates once and clears press feedback")
                    for (position, item) in menu.items.enumerated() where !item.isSeparatorItem {
                        let scope = TabCloseScope(rawValue: item.tag)!
                        let enabled: Bool
                        switch scope {
                        case .current: enabled = true
                        case .others: enabled = count > 1
                        case .left: enabled = index > 0
                        case .right: enabled = index < count - 1
                        }
                        precondition(item.isEnabled == enabled)
                        actions.removeAll()
                        if enabled {
                            menu.performActionForItem(at: position)
                            precondition(actions.count == 1)
                            guard case .closeTabs(let id, let actualScope) = actions[0] else { fatalError("Menu must emit tab close action") }
                            precondition(id == tab.id && actualScope == scope, "Context menu must target the clicked tab without activation")
                        }
                    }
                    actions.removeAll()
                    buttons[1].performClick(nil)
                    precondition(actions.count == 1)
                    guard case .closeTab(let id) = actions[0], id == tab.id else { fatalError("Close button must only close its tab") }
                    actions.removeAll()
                    buttons[0].performClick(nil)
                    guard case .activateTab(let id) = actions.first, id == tab.id else { fatalError("Title button must activate its tab") }
                }
            }
        }
        print("PASS: AppKit tab hover/press, close without hover background, menu routing/disabled states and button actions")
    }

    @MainActor
    static func verifyReordering(root: URL) {
        var cases = 0
        for count in [1, 3, 8] {
            for source in 0..<count {
                for destination in 0...count {
                    for active in 0..<count {
                        let model = AppModel(directory: root, settingsURL: root.appendingPathComponent("keyboard.json"))
                        model.tabs = (0..<count).map { index in
                            var tab = BrowserTabState(directory: root.appendingPathComponent("Tab-\(index)"))
                            let child = tab.navigation.directory.appendingPathComponent("child")
                            let generation = tab.navigation.beginRequest()
                            precondition(tab.navigation.commit(child, generation: generation))
                            let file = tab.navigation.directory.appendingPathComponent("file.txt")
                            tab.entries = [FileEntry(url: file, name: "file.txt", isDirectory: false)]
                            tab.selection = [file]; tab.scrollOffset = Double(index * 30)
                            tab.filter = "file"; tab.isSearching = true
                            return tab
                        }
                        let original = model.tabs
                        model.activeID = original[active].id
                        let before = destination < count ? original[destination].id : nil
                        var expected = original.map(\.id)
                        if before != original[source].id {
                            expected.remove(at: source)
                            let index = before.flatMap { expected.firstIndex(of: $0) } ?? expected.count
                            expected.insert(original[source].id, at: index)
                        }
                        model.handle(.moveTab(original[source].id, before: before))
                        precondition(model.tabs.map(\.id) == expected, "Reordering must honor the insertion boundary")
                        precondition(model.activeID == original[active].id, "Dragging must preserve the active tab")
                        for tab in model.tabs {
                            let old = original.first { $0.id == tab.id }!
                            precondition(tab.navigation == old.navigation && tab.selection == old.selection && tab.entries == old.entries)
                            precondition(tab.scrollOffset == old.scrollOffset && tab.filter == old.filter && tab.isSearching)
                        }
                        model.handle(.moveTab(UUID(), before: nil))
                        model.handle(.moveTab(original[source].id, before: UUID()))
                        precondition(model.tabs.map(\.id) == expected, "Stale source or destination IDs must be ignored")
                        cases += 1
                    }
                }
            }
        }
        print("PASS: \(cases) reorder cases preserving active tab, history, selection, scroll and search state")
    }

    @MainActor
    static func verifyDragDestination() {
        var actions: [ExplorerAction] = []
        let controller = ExplorerWindowController { actions.append($0) }
        var snapshot = ExplorerSnapshot()
        snapshot.tabs = (0..<12).map { ExplorerTab(id: UUID(), title: "Tab \($0)") }
        snapshot.activeTabID = snapshot.tabs[0].id
        let window = controller.window!
        window.contentView!.layoutSubtreeIfNeeded()
        controller.render(snapshot)
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let strip = descendants(window.contentView!).compactMap { $0 as? ExplorerTabStrip }.first!
        let tabs = strip.subviews.compactMap { $0 as? ExplorerTabView }
        let probe = TabDragProbe()
        defer { probe.draggingPasteboard.releaseGlobally() }
        probe.draggingDestinationWindow = window
        probe.draggingSource = tabs[1]
        probe.draggingPasteboard.setString(tabs[1].tabID.uuidString, forType: ExplorerTabView.pasteboardType)
        probe.draggingLocation = strip.convert(NSPoint(x: 40, y: 16), to: nil)
        precondition(strip.draggingEntered(probe) == .move)
        let originalOrder = tabs.map(\.tabID)
        let movedOrder = [originalOrder[1], originalOrder[0]] + originalOrder.dropFirst(2)
        precondition(strip.orderedTabIDs == movedOrder && tabs[1].alphaValue < 1,
                     "Tabs must visibly reorder during the drag, before mouse release")
        precondition(actions.isEmpty, "Previewing must not rebuild the drag source or commit application state")
        for _ in 0..<4 { precondition(strip.draggingUpdated(probe) == .move) }
        precondition(strip.orderedTabIDs == movedOrder, "Stationary drags must not oscillate between positions")
        controller.render(snapshot)
        precondition(strip.orderedTabIDs == movedOrder && tabs[0].frame.minX == 228 && tabs[1].frame.minX == 0,
                     "Background renders must lay out the live preview rather than snap back")
        probe.draggingLocation = strip.convert(NSPoint(x: 590, y: 16), to: nil)
        precondition(strip.draggingUpdated(probe) == .move)
        precondition(strip.orderedTabIDs.prefix(3) == [originalOrder[0], originalOrder[2], originalOrder[1]],
                     "Changing direction must move the dragged tab across neighboring slots")
        probe.draggingLocation = strip.convert(NSPoint(x: 40, y: 16), to: nil)
        precondition(strip.draggingUpdated(probe) == .move && strip.orderedTabIDs == movedOrder)
        precondition(strip.prepareForDragOperation(probe), "AppKit must be allowed to perform the accepted drop")
        precondition(strip.performDragOperation(probe))
        guard actions.count == 1, case .moveTab(let source, let next) = actions[0] else { fatalError("Drop must emit one reorder action") }
        precondition(source == tabs[1].tabID && next == tabs[0].tabID)
        precondition(tabs[1].alphaValue == 1, "Dropping must restore normal opacity")
        actions.removeAll()
        let scroll = strip.enclosingScrollView!
        probe.draggingLocation = scroll.contentView.convert(NSPoint(x: scroll.contentView.bounds.maxX - 5, y: 16), to: nil)
        precondition(strip.draggingUpdated(probe) == .move)
        precondition(scroll.contentView.bounds.minX > 0, "A drag at the right edge must scroll to hidden tabs")
        precondition(strip.wantsPeriodicDraggingUpdates(), "Holding a drag near an edge must continue scrolling")
        strip.draggingExited(probe)
        strip.draggingEnded(probe)
        precondition(actions.isEmpty, "An exited or cancelled drag must preserve order")
        precondition(strip.orderedTabIDs == originalOrder && tabs.allSatisfy { $0.alphaValue == 1 })
        strip.layoutTabs()
        precondition(tabs.enumerated().allSatisfy { $0.element.frame.minX == CGFloat($0.offset) * 228 },
                     "Cancellation must restore the original visual positions")
        scroll.contentView.scroll(to: .zero)
        probe.draggingLocation = strip.convert(NSPoint(x: 40, y: 16), to: nil)
        precondition(strip.draggingEntered(probe) == .move && strip.orderedTabIDs == movedOrder,
                     "Reentering the strip must resume live sorting")
        // A genuine tab-set change invalidates the in-flight preview safely.
        snapshot.tabs.remove(at: 1)
        controller.render(snapshot)
        precondition(strip.orderedTabIDs == snapshot.tabs.map(\.id))
        precondition(!strip.performDragOperation(probe), "A removed drag source must not commit a stale order")
        probe.draggingSource = nil
        precondition(strip.draggingEntered(probe).isEmpty && !strip.performDragOperation(probe), "External and forged tab drags must be rejected")
        print("PASS: live tab reordering, stable hover, direction reversal, render preservation, one drop commit, edge scroll, cancellation/reentry and source invalidation")
    }
}
