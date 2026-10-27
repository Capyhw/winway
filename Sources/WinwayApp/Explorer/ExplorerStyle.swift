import AppKit
import WinwayCore

@MainActor
enum ExplorerStyle {
    // SwiftPM backends generate different Bundle.module lookup paths. Prefer
    // the standard macOS app location so packaged apps never need the checkout.
    static let resourceBundle: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("Winway_WinwayApp.bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
    static let text = NSColor(hex: 0x1b2434)
    static let secondary = NSColor(hex: 0x68758a)
    static let border = NSColor(hex: 0xdfe6ef)
    static let chrome = NSColor(hex: 0xf5f8fc)
    static let titlebar = NSColor(hex: 0xf1f3f6)
    static let sidebar = NSColor(hex: 0xf7f9fc)
    static let selected = NSColor(hex: 0xdcebfe)
    static let accent = NSColor(hex: 0x0067c0)
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd HH:mm"; return f
    }()
    static func label(_ text: String, secondary: Bool = false, size: CGFloat = 13) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = secondary ? Self.secondary : Self.text
        label.lineBreakMode = .byTruncatingTail
        return label
    }
    private static var imageCache: [String: NSImage] = [:]
    static func sortImage(ascending: Bool) -> NSImage? {
        let name = ascending ? "chevron-up" : "chevron-down"
        if let cached = imageCache[name] { return cached }
        guard let url = resourceBundle.url(forResource: name, withExtension: "svg", subdirectory: "Resources/Lucide"),
              let source = NSImage(contentsOf: url) else { return nil }
        let color = accent
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            source.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        imageCache[name] = image
        return image
    }
    static func image(_ name: String, size: CGFloat = 20) -> NSImage? {
        let key = "\(name):\(size)"
        if let cached = imageCache[key] { return cached }
        guard let url = resourceBundle.url(forResource: name+"@2x", withExtension: "png", subdirectory: "Resources/Figma"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: size, height: size)
        imageCache[key] = image
        return image
    }
    static func fileImage(_ entry: FileEntry, size: CGFloat = 20) -> NSImage? {
        if entry.isDirectory && !entry.isSymbolicLink { return image("folder", size: size) }
        if entry.isSymbolicLink { let i = NSWorkspace.shared.icon(forFile: entry.url.path); i.size = NSSize(width: size, height: size); return i }
        let icon: String
        switch entry.url.pathExtension.lowercased() {
        case "doc", "docx": icon = size == 40 ? "word1" : "word"
        case "xls", "xlsx", "csv": icon = "excel"
        case "pdf": icon = "pdf"
        case "png", "jpg", "jpeg", "gif", "heic", "webp": icon = "gallery"
        case "mp3", "wav", "m4a", "flac": icon = "music"
        case "mp4", "mov", "mkv": icon = "video"
        default: icon = "document"
        }
        return image(icon, size: size)
    }
    static func size(_ entry: FileEntry) -> String {
        entry.isDirectory ? "—" : size(bytes: entry.size)
    }
    static func size(bytes: Int64) -> String {
        bytes == 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

class ExplorerSurface: NSView {
    override var isFlipped: Bool { true }
    init(color: NSColor = .white) { super.init(frame: .zero); wantsLayer = true; layer?.backgroundColor = color.cgColor }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class TitlebarSurface: ExplorerSurface {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            window?.performZoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }
}

final class ExplorerButton: NSButton {
    var handler: (() -> Void)?
    var glyph: String?
    var iconSize: CGFloat = 20
    var arrow = false
    var showsInteractionBackground = true
    var active = false { didSet { needsDisplay = true } }
    private var hovered = false
    private var hoverTracking: NSTrackingArea?
    init(_ title: String = "", icon: String? = nil, tooltip: String? = nil, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title; glyph = icon; handler = action
        isBordered = false; bezelStyle = .regularSquare
        font = .systemFont(ofSize: 13); toolTip = tooltip ?? title
        setAccessibilityLabel(tooltip ?? title)
        target = self; self.action = #selector(invoke)
        setButtonType(.momentaryPushIn)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverTracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if showsInteractionBackground && (active || (isEnabled && (hovered || isHighlighted))) {
            (active ? ExplorerStyle.selected : ExplorerStyle.border.withAlphaComponent(isHighlighted ? 0.8 : 0.45)).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        }
        let alpha: CGFloat = isEnabled ? 1 : 0.35
        var x: CGFloat = title.isEmpty ? (bounds.width - iconSize) / 2 : 8
        if let glyph, let image = ExplorerStyle.image(glyph, size: iconSize) {
            image.draw(in: NSRect(x: x, y: (bounds.height - iconSize) / 2, width: iconSize, height: iconSize), from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
            x += iconSize + 8
        }
        if !title.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: ExplorerStyle.text.withAlphaComponent(alpha)]
            let height = (title as NSString).size(withAttributes: attrs).height
            (title as NSString).draw(in: NSRect(x: x, y: (bounds.height - height) / 2, width: bounds.width - x - (arrow ? 24 : 6), height: height), withAttributes: attrs)
        }
        if arrow { ExplorerStyle.image("down", size: 14)?.draw(in: NSRect(x: bounds.width - 20, y: (bounds.height - 14) / 2, width: 14, height: 14), from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil) }
    }
}

final class ExplorerRowView: NSTableRowView {
    var isFileDragSource = false { didSet { if oldValue != isFileDragSource { updateFileDragAppearance() } } }
    var isFileDropTarget = false { didSet { if oldValue != isFileDropTarget { updateFileDragAppearance() } } }
    private var hoverTracking: NSTrackingArea?
    private(set) var hovered = false { didSet { if oldValue != hovered { needsDisplay = true } } }
    override var isEmphasized: Bool { get { false } set {} }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverTracking = area
        if let window {
            hovered = window.isKeyWindow && visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else { hovered = false }
    }
    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        if isFileDropTarget {
            ExplorerStyle.accent.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        } else if hovered && !isSelected {
            ExplorerStyle.chrome.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }
    override func drawSelection(in dirtyRect: NSRect) {
        (isFileDropTarget ? ExplorerStyle.accent : isFileDragSource ? ExplorerStyle.border : ExplorerStyle.selected).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 0), xRadius: 4, yRadius: 4).fill()
    }

    override func drawDraggingDestinationFeedback(in dirtyRect: NSRect) {
        if !isFileDropTarget { super.drawDraggingDestinationFeedback(in: dirtyRect) }
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        updateFileDragAppearance()
    }

    private func updateFileDragAppearance() {
        needsDisplay = true
        for cell in subviews.compactMap({ $0 as? NSTableCellView }) {
            cell.alphaValue = isFileDragSource && !isFileDropTarget ? 0.5 : 1
            cell.textField?.textColor = isFileDropTarget ? .white :
                (cell.identifier?.rawValue == "name" ? ExplorerStyle.text : ExplorerStyle.secondary)
        }
    }
}

final class ExplorerHeaderCell: NSTableHeaderCell {
    var sorted = false
    var ascending = true
    var showsTrailingSeparator = true
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSColor.white.setFill(); cellFrame.fill()
        if sorted {
            ExplorerStyle.selected.setFill()
            NSBezierPath(roundedRect: cellFrame.insetBy(dx: 3, dy: 4), xRadius: 3, yRadius: 3).fill()
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: sorted ? ExplorerStyle.accent : ExplorerStyle.secondary]
        (stringValue as NSString).draw(in: NSRect(x: cellFrame.minX + 8, y: cellFrame.minY + 14, width: cellFrame.width - 16, height: 18), withAttributes: attrs)
        if showsTrailingSeparator {
            ExplorerStyle.border.setFill()
            NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY + 8, width: 1, height: 16).fill()
        }
        if sorted {
            ExplorerStyle.sortImage(ascending: ascending)?.draw(in: NSRect(x: cellFrame.midX - 6, y: cellFrame.minY + 1, width: 12, height: 12), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
    override func highlight(_ flag: Bool, withFrame cellFrame: NSRect, in controlView: NSView) { draw(withFrame: cellFrame, in: controlView) }
}

/// Draw only real columns; AppKit's filler header otherwise repeats the last
/// custom cell in the blank area and beside the vertical scroller.
final class ExplorerHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        dirtyRect.fill()
        guard let tableView else { return }
        for (index, column) in tableView.tableColumns.enumerated() {
            let rect = headerRect(ofColumn: index)
            guard rect.intersects(dirtyRect) else { continue }
            if let cell = column.headerCell as? ExplorerHeaderCell {
                cell.showsTrailingSeparator = index < tableView.numberOfColumns - 1
            }
            column.headerCell.draw(withFrame: rect, in: self)
        }
    }
}

