import AppKit

final class ExplorerTabView: ExplorerSurface {
    private let tabID: UUID
    private let isSelected: Bool
    private let onAction: (ExplorerAction) -> Void
    private var hoverTracking: NSTrackingArea?
    private var hovered = false { didSet { updateBackground() } }

    init(tab: ExplorerTab, isSelected: Bool, index: Int, count: Int,
         onAction: @escaping (ExplorerAction) -> Void) {
        tabID = tab.id
        self.isSelected = isSelected
        self.onAction = onAction
        super.init(color: isSelected ? .white : ExplorerStyle.chrome)
        layer?.cornerRadius = 6
        toolTip = tab.title

        let activate = ExplorerButton(tab.title, icon: "folder", tooltip: tab.title) {
            onAction(.activateTab(tab.id))
        }
        activate.showsInteractionBackground = false
        activate.frame = NSRect(x: 4, y: 0, width: 184, height: 32)
        activate.font = .systemFont(ofSize: 13, weight: isSelected ? .medium : .regular)
        activate.setAccessibilityValue(isSelected ? "已选中" : "未选中")
        let close = ExplorerButton(icon: "close", tooltip: "关闭 \(tab.title)") {
            onAction(.closeTab(tab.id))
        }
        close.iconSize = 14
        close.frame = NSRect(x: 188, y: 2, width: 28, height: 28)
        addSubview(activate)
        addSubview(close)

        let contextMenu = NSMenu()
        contextMenu.autoenablesItems = false
        for scope in TabCloseScope.allCases {
            if scope == .others { contextMenu.addItem(.separator()) }
            let item = NSMenuItem(title: scope.title, action: #selector(closeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = scope.rawValue
            switch scope {
            case .current: item.isEnabled = true
            case .others: item.isEnabled = count > 1
            case .left: item.isEnabled = index > 0
            case .right: item.isEnabled = index < count - 1
            }
            contextMenu.addItem(item)
        }
        menu = contextMenu
        activate.menu = contextMenu
        close.menu = contextMenu
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onAction(.activateTab(tabID))
    }

    @objc private func closeFromMenu(_ sender: NSMenuItem) {
        guard sender.isEnabled, let scope = TabCloseScope(rawValue: sender.tag) else { return }
        onAction(.closeTabs(tabID, scope))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTracking = area
        if let window {
            hovered = window.isKeyWindow && visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else {
            hovered = false
        }
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    private func updateBackground() {
        let base: NSColor = isSelected ? .white : ExplorerStyle.chrome
        let color = hovered ? base.blended(withFraction: isSelected ? 0.3 : 0.55, of: ExplorerStyle.border) ?? base : base
        layer?.backgroundColor = color.cgColor
    }
}
