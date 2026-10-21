import AppKit
import WinwayCore

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
                    precondition(buttons.count == 2 && !buttons[0].showsInteractionBackground && buttons[1].showsInteractionBackground)
                    let menu = view.menu!
                    precondition(buttons.allSatisfy { $0.menu === menu }, "All tab regions must expose the same context menu")
                    let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
                    let idleColor = view.layer!.backgroundColor!
                    view.mouseEntered(with: event)
                    precondition(view.layer!.backgroundColor != idleColor, "Hover must change the whole tab surface")
                    view.mouseExited(with: event)
                    precondition(view.layer!.backgroundColor == idleColor, "Exit must restore selected/unselected appearance")
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
        print("PASS: AppKit tab surface hover, independent close feedback, menu routing/disabled states and button actions")
    }
}
