import AppKit

/// Each segment owns its ancestor URL. Only the trailing blank area enters
/// editing; long paths scroll independently and never cover that hit target.
final class ExplorerBreadcrumbView: ExplorerSurface {
    var onNavigate: ((URL) -> Void)?
    var onEdit: (() -> Void)?
    private let scroll = NSScrollView()
    private let body = ExplorerSurface()
    private let editArea = ExplorerButton(tooltip: "编辑路径") {}
    private var pathURL: URL?
    private var contentWidth: CGFloat = 0
    private var revealLastSegment = true

    init() {
        super.init(color: .white)
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = ExplorerStyle.border.cgColor
        setAccessibilityLabel("当前位置")
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.documentView = body
        addSubview(scroll)
        editArea.showsInteractionBackground = false
        editArea.setAccessibilityIdentifier("winway.path-edit-area")
        editArea.handler = { [weak self] in self?.onEdit?() }
        addSubview(editArea)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDirectory(_ directory: URL) {
        let url = directory.standardizedFileURL
        guard pathURL != url else { return }
        pathURL = url
        body.subviews.forEach { $0.removeFromSuperview() }
        var ancestors = [url]
        var parent = url
        while parent.path != "/" {
            parent.deleteLastPathComponent()
            ancestors.append(parent)
        }
        var x: CGFloat = 0
        for ancestor in ancestors.reversed() {
            if x > 0 {
                let separator = NSImageView(frame: NSRect(x: x, y: 7, width: 14, height: 14))
                separator.image = ExplorerStyle.image("right", size: 14)
                separator.setAccessibilityElement(false)
                body.addSubview(separator)
                x += 18
            }
            let title = ancestor.path == "/" ? "/" : ancestor.lastPathComponent
            let button = ExplorerButton(title, icon: ancestor.path == "/" ? "pc" : nil, tooltip: ancestor.path) { [weak self] in
                self?.onNavigate?(ancestor)
            }
            button.setAccessibilityIdentifier("winway.path-segment")
            let textWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
            let width = min(240, max(30, ceil(textWidth) + (ancestor.path == "/" ? 46 : 16)))
            button.frame = NSRect(x: x, y: 0, width: width, height: 28)
            body.addSubview(button)
            x += width
        }
        contentWidth = x
        revealLastSegment = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = min(contentWidth, max(0, bounds.width - 52))
        let resized = scroll.frame.width != width
        scroll.frame = NSRect(x: 4, y: 2, width: width, height: 28)
        body.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 28)
        editArea.frame = NSRect(x: scroll.frame.maxX, y: 2, width: max(0, bounds.width - scroll.frame.maxX - 2), height: 28)
        if revealLastSegment || resized {
            scroll.contentView.scroll(to: NSPoint(x: max(0, contentWidth - width), y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            revealLastSegment = false
        }
    }
}
