import AppKit

final class ExplorerTabView: ExplorerSurface, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("com.winway.tab")
    let tabID: UUID
    private(set) var dragAnchorX: CGFloat = 110
    private let isSelected: Bool
    private let onAction: (ExplorerAction) -> Void
    private var hoverTracking: NSTrackingArea?
    private var hovered = false { didSet { updateBackground() } }
    private var pressed = false { didSet { updateBackground() } }
    private var pressOrigin: NSPoint?
    private weak var activateButton: ExplorerButton?

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
        activateButton = activate
        activate.frame = NSRect(x: 4, y: 0, width: 184, height: 32)
        activate.font = .systemFont(ofSize: 13, weight: isSelected ? .medium : .regular)
        activate.setAccessibilityValue(isSelected ? "已选中" : "未选中")
        let close = ExplorerButton(icon: "close", tooltip: "关闭 \(tab.title)") {
            onAction(.closeTab(tab.id))
        }
        close.iconSize = 14
        close.showsInteractionBackground = false
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

    // Keep the title button's accessibility action, but route pointer gestures
    // to the tab so a press can become a drag without activating it first.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === activateButton ? self : hit
    }

    override func mouseDown(with event: NSEvent) {
        pressOrigin = convert(event.locationInWindow, from: nil)
        pressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = pressOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - origin.x, point.y - origin.y) >= 5 else { return }
        dragAnchorX = origin.x
        pressOrigin = nil
        pressed = false
        let item = NSPasteboardItem()
        item.setString(tabID.uuidString, forType: Self.pasteboardType)
        let drag = NSDraggingItem(pasteboardWriter: item)
        let image = NSImage(size: bounds.size)
        if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmap)
            image.addRepresentation(bitmap)
        }
        drag.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [drag], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        let shouldActivate = pressOrigin != nil && bounds.contains(convert(event.locationInWindow, from: nil))
        pressOrigin = nil
        pressed = false
        if shouldActivate { onAction(.activateTab(tabID)) }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        pressOrigin = nil
        pressed = false
        (superview as? ExplorerTabStrip)?.cancelReordering()
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
        let color = pressed ? ExplorerStyle.selected : (hovered ? base.blended(withFraction: isSelected ? 0.3 : 0.55, of: ExplorerStyle.border) ?? base : base)
        layer?.backgroundColor = color.cgColor
    }
}
