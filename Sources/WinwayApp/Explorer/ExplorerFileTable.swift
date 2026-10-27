import AppKit

/// Keep the native field editor and the nonediting text on the same centered
/// line, without shrinking the rename border or focus ring.
final class ExplorerRenameCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var textRect = super.drawingRect(forBounds: rect)
        guard let font else { return textRect }
        let lineHeight = min(textRect.height, ceil(font.ascender - font.descender + font.leading))
        textRect.origin.y = rect.midY - lineHeight / 2
        textRect.size.height = lineHeight
        return textRect
    }
}

/// A transparent editor layer clipped to the file viewport. Empty space must
/// keep forwarding mouse and scroll events to the table underneath it.
final class ExplorerRenameOverlay: NSView {
    override var isFlipped: Bool { true }
    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// AppKit provides row reuse; selection is over row indexes, including offscreen rows.
final class ExplorerFileTable: NSTableView, @MainActor NSServicesMenuRequestor {
    // Some existing file services still request a single legacy path array.
    static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    static let serviceTypes: [NSPasteboard.PasteboardType] = [.fileURL, filenamesType]
    var windowsSelection = true
    var openSelection: (() -> Void)?
    var contextMenu: (() -> NSMenu)?
    var contextID = UUID()
    var rowURLs: [URL] = []
    var canDragFiles = true
    var onFileDragEnded: (() -> Void)?
    private(set) var draggedFileURLs: Set<URL> = []
    var fileDropTarget: URL? { didSet { if oldValue != fileDropTarget { refreshFileDragAppearance() } } }
    private var anchors: [UUID: URL] = [:]
    private var filePress: (origin: NSPoint, urls: [URL], collapseTo: URL?, context: UUID)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            let wasDragging = !draggedFileURLs.isEmpty
            finishFileDrag()
            if !wasDragging { deselectAll(nil) }
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        finishFileDrag()
        window?.makeFirstResponder(self)
        let origin = convert(event.locationInWindow, from: nil)
        let hitRow = row(at: origin)
        let additive = event.modifierFlags.contains(windowsSelection ? .control : .command)
        let range = event.modifierFlags.contains(.shift)
        if hitRow >= 0 {
            let preserveSelection = !range && !additive && selectedRowIndexes.contains(hitRow)
            if range, let anchorURL = anchors[contextID], let selectionAnchor = rowURLs.firstIndex(of: anchorURL) {
                selectRowIndexes(IndexSet(integersIn: min(selectionAnchor, hitRow)...max(selectionAnchor, hitRow)), byExtendingSelection: additive)
            } else if additive {
                var selected = selectedRowIndexes
                if selected.contains(hitRow) { selected.remove(hitRow) } else { selected.insert(hitRow) }
                selectRowIndexes(selected, byExtendingSelection: false)
                if rowURLs.indices.contains(hitRow) { anchors[contextID] = rowURLs[hitRow] }
            } else if !preserveSelection {
                selectRowIndexes(IndexSet(integer: hitRow), byExtendingSelection: false)
                if rowURLs.indices.contains(hitRow) { anchors[contextID] = rowURLs[hitRow] }
            }
            if event.clickCount == 2 {
                selectRowIndexes(IndexSet(integer: hitRow), byExtendingSelection: false)
                openSelection?()
            } else if selectedRowIndexes.contains(hitRow), rowURLs.indices.contains(hitRow) {
                filePress = (origin, serviceURLs, preserveSelection ? rowURLs[hitRow] : nil, contextID)
            }
            return
        }
        let initial = additive ? selectedRowIndexes : IndexSet()
        if !additive { deselectAll(nil) }
        guard let window, let viewport = enclosingScrollView?.contentView else { return }
        let overlay = ExplorerSelectionOverlay(frame: viewport.bounds)
        // A sibling above the document keeps the band above reused row views.
        viewport.addSubview(overlay, positioned: .above, relativeTo: self)
        defer { overlay.removeFromSuperview() }
        while let drag = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if drag.type == .leftMouseUp { break }
            autoscroll(with: drag)
            let p = convert(drag.locationInWindow, from: nil)
            let box = NSRect(x: min(origin.x, p.x), y: min(origin.y, p.y), width: abs(p.x-origin.x), height: abs(p.y-origin.y))
            overlay.frame = viewport.bounds
            overlay.selectionRect = overlay.convert(box, from: self)
            let intersected = rows(in: box)
            var selected = initial
            if intersected.location != NSNotFound && intersected.length > 0 {
                let end = min(numberOfRows, intersected.location + intersected.length)
                if intersected.location < end { selected.formUnion(IndexSet(integersIn: intersected.location..<end)) }
            }
            selectRowIndexes(selected, byExtendingSelection: false)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard canDragFiles, let press = filePress, press.context == contextID else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - press.origin.x, point.y - press.origin.y) >= 5 else { return }
        filePress = nil
        let currentURLs = Set(rowURLs)
        guard !press.urls.isEmpty, press.urls.allSatisfy({ currentURLs.contains($0) }) else { return }
        let items = ExplorerFileDragPreview.items(for: press.urls, at: NSPoint(x: point.x + 12, y: point.y + 10))
        showDraggedFiles(Set(press.urls))
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = .list
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { finishFileDrag() }
        guard let press = filePress, press.context == contextID,
              let url = press.collapseTo, let row = rowURLs.firstIndex(of: url) else { return }
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        anchors[contextID] = url
    }

    override func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    override func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    override func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finishFileDrag()
    }

    private func finishFileDrag() {
        filePress = nil
        if !draggedFileURLs.isEmpty {
            showDraggedFiles([])
            onFileDragEnded?()
        }
        fileDropTarget = nil
    }

    func showDraggedFiles(_ urls: Set<URL>) {
        draggedFileURLs = urls
        refreshFileDragAppearance()
    }

    func refreshFileDragAppearance() {
        enumerateAvailableRowViews { view, row in
            guard let view = view as? ExplorerRowView else { return }
            let url = self.rowURLs.indices.contains(row) ? self.rowURLs[row] : nil
            view.isFileDragSource = url.map { self.draggedFileURLs.contains($0) } ?? false
            view.isFileDropTarget = url != nil && url == self.fileDropTarget
        }
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        fileDropTarget = nil
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        // NSDraggingDestination declares this optional callback, but NSTableView
        // does not implement it. Calling super raises an Objective-C exception
        // and prevents AppKit from finishing the drag's remaining callbacks.
        (sender.draggingSource as? ExplorerFileTable)?.finishFileDrag()
        fileDropTarget = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        finishFileDrag()
        window?.makeFirstResponder(self)
        let hit = row(at: convert(event.locationInWindow, from: nil))
        if hit >= 0 && !selectedRowIndexes.contains(hit) { selectRowIndexes(IndexSet(integer: hit), byExtendingSelection: false) }
        if hit < 0 { deselectAll(nil) }
        return contextMenu?()
    }

    private var serviceURLs: [URL] {
        selectedRowIndexes.compactMap { rowURLs.indices.contains($0) ? rowURLs[$0] : nil }
    }

    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if let sendType, Self.serviceTypes.contains(sendType),
           returnType == nil || returnType?.rawValue.isEmpty == true, !serviceURLs.isEmpty {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    func writeSelection(to pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let urls = serviceURLs
        let fileURLs = types.contains(.fileURL)
        let filenames = types.contains(Self.filenamesType)
        guard !urls.isEmpty, fileURLs || filenames else { return false }
        pasteboard.clearContents()
        if fileURLs {
            let items = urls.map { url in
                let item = NSPasteboardItem()
                item.setString(url.absoluteString, forType: .fileURL)
                return item
            }
            guard pasteboard.writeObjects(items) else { return false }
        }
        if filenames {
            // NSPasteboard translates legacy names; NSPasteboardItem only accepts UTIs.
            pasteboard.addTypes([Self.filenamesType], owner: nil)
            return pasteboard.setPropertyList(urls.map(\.path), forType: Self.filenamesType)
        }
        return true
    }

}
