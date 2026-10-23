import AppKit

/// Preview the order using the existing tab views throughout the native drag.
/// Commit once on drop; cancellation restores the original order and state.
final class ExplorerTabStrip: ExplorerSurface {
    var onMove: ((UUID, UUID?) -> Void)?
    private var previewOrder: [UUID]?
    private weak var draggedTab: ExplorerTabView?
    private let tabWidth: CGFloat = 220
    private let tabStride: CGFloat = 228
    var orderedTabIDs: [UUID] { previewOrder ?? tabs.map(\.tabID) }
    private var tabs: [ExplorerTabView] { subviews.compactMap { $0 as? ExplorerTabView } }

    init() {
        super.init(color: ExplorerStyle.titlebar)
        registerForDraggedTypes([ExplorerTabView.pasteboardType])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func layoutTabs(animated: Bool = false) {
        let views = Dictionary(uniqueKeysWithValues: tabs.map { ($0.tabID, $0) })
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.14 : 0
            for (index, id) in orderedTabIDs.enumerated() {
                guard let view = views[id] else { continue }
                let frame = NSRect(x: CGFloat(index) * tabStride, y: 0, width: tabWidth, height: 32)
                if context.duration > 0 { view.animator().frame = frame }
                else { view.frame = frame }
            }
        }
    }

    func cancelReordering(animated: Bool = true) {
        guard previewOrder != nil else { return }
        draggedTab?.alphaValue = 1
        draggedTab = nil
        previewOrder = nil
        layoutTabs(animated: animated)
    }

    private func previewMove(_ source: ExplorerTabView, at point: NSPoint) {
        if draggedTab !== source {
            cancelReordering(animated: false)
            draggedTab = source
            previewOrder = tabs.map(\.tabID)
            source.alphaValue = 0.25
        }
        guard var order = previewOrder, let current = order.firstIndex(of: source.tabID) else { return }
        // Use the dragged tab's center rather than the pointer's grab position.
        // Slot thresholds stay fixed while views animate, avoiding oscillation
        // when the pointer pauses over a newly moved neighbor.
        let centerX = point.x + tabWidth / 2 - source.dragAnchorX
        var destination = current
        while destination + 1 < order.count && centerX > CGFloat(destination + 1) * tabStride + tabWidth / 2 {
            destination += 1
        }
        while destination > 0 && centerX < CGFloat(destination - 1) * tabStride + tabWidth / 2 {
            destination -= 1
        }
        guard destination != current else { return }
        order.remove(at: current)
        order.insert(source.tabID, at: destination)
        previewOrder = order
        layoutTabs(animated: true)
    }

    private func sourceTab(_ sender: NSDraggingInfo) -> ExplorerTabView? {
        guard let tab = sender.draggingSource as? ExplorerTabView, tab.superview === self,
              sender.draggingPasteboard.string(forType: ExplorerTabView.pasteboardType) == tab.tabID.uuidString else { return nil }
        return tab
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let source = sourceTab(sender) else { cancelReordering(); return [] }
        if let scroll = enclosingScrollView {
            let point = scroll.contentView.convert(sender.draggingLocation, from: nil)
            let visible = scroll.contentView.bounds
            let delta: CGFloat = point.x < visible.minX + 28 ? -18 : (point.x > visible.maxX - 28 ? 18 : 0)
            if delta != 0 {
                let x = min(max(0, visible.minX + delta), max(0, bounds.width - visible.width))
                scroll.contentView.scroll(to: NSPoint(x: x, y: 0))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        previewMove(source, at: convert(sender.draggingLocation, from: nil))
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { cancelReordering() }
    override func draggingEnded(_ sender: NSDraggingInfo) { cancelReordering() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let source = sourceTab(sender) else { return false }
        previewMove(source, at: convert(sender.draggingLocation, from: nil))
        let order = orderedTabIDs
        guard let index = order.firstIndex(of: source.tabID) else { return false }
        let nextID = index + 1 < order.count ? order[index + 1] : nil
        let changed = order != tabs.map(\.tabID)
        cancelReordering(animated: false)
        if changed { onMove?(source.tabID, nextID) }
        return true
    }
}
