import AppKit

@MainActor
enum ExplorerFileDragPreview {
    static let rowHeight: CGFloat = 24
    static let visibleLimit = 5

    static func items(for urls: [URL], at origin: NSPoint) -> [NSDraggingItem] {
        urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            // Keep every URL in the native drag, but bound the floating preview
            // so a large selection never covers the destination folders.
            guard index < visibleLimit else {
                item.setDraggingFrame(NSRect(origin: origin, size: NSSize(width: 1, height: rowHeight)), contents: nil)
                item.imageComponentsProvider = nil
                return item
            }
            let label = labelImage(url.lastPathComponent)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            let width = 24 + label.size.width
            item.draggingFrame = NSRect(x: origin.x, y: origin.y + CGFloat(index) * rowHeight,
                                        width: width, height: rowHeight)
            item.imageComponentsProvider = {
                let iconComponent = NSDraggingImageComponent(key: .icon)
                iconComponent.contents = icon
                iconComponent.frame = NSRect(x: 0, y: 2, width: 20, height: 20)
                let labelComponent = NSDraggingImageComponent(key: .label)
                labelComponent.contents = label
                labelComponent.frame = NSRect(x: 24, y: 2, width: label.size.width, height: 20)
                return [iconComponent, labelComponent]
            }
            return item
        }
    }

    static func labelImage(_ name: String) -> NSImage {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let measured = (name as NSString).size(withAttributes: attributes)
        let size = NSSize(width: min(420, ceil(measured.width) + 12), height: 20)
        let color = ExplorerStyle.accent
        return NSImage(size: size, flipped: true) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            (name as NSString).draw(in: NSRect(x: 6, y: (20 - measured.height) / 2,
                                             width: size.width - 12, height: measured.height),
                                   withAttributes: attributes)
            return true
        }
    }
}
