import AppKit

final class PreviewTile: NSButton {
    override var isFlipped: Bool { false }
    var preview: NSImage? { didSet { needsDisplay = true } }
    private let appIcon: NSImage?
    private let list: Bool
    private let caption: String
    private let placeholder: String
    private var hovering = false
    private var tracking: NSTrackingArea?

    init(title: String, placeholder: String, icon: NSImage?, list: Bool, size: CGSize) {
        self.caption = title
        self.placeholder = placeholder
        self.appIcon = icon
        self.list = list
        super.init(frame: CGRect(origin: .zero, size: size))
        isBordered = false
        setButtonType(.momentaryPushIn)
        setAccessibilityLabel(title)
        toolTip = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if hovering || isHighlighted || window?.firstResponder === self {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
        }
        let headerY = list ? (bounds.height - 18) / 2 : bounds.height - 26
        appIcon?.draw(in: CGRect(x: 9, y: headerY, width: 18, height: 18))
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        (caption as NSString).draw(in: CGRect(x: 34, y: headerY, width: bounds.width - 42, height: 18),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor, .paragraphStyle: style])
        guard !list else { return }
        let imageRect = CGRect(x: 8, y: 8, width: bounds.width - 16, height: bounds.height - 44)
        NSColor.black.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: imageRect, xRadius: 5, yRadius: 5).fill()
        if let preview {
            let scale = min(imageRect.width / preview.size.width, imageRect.height / preview.size.height)
            let size = CGSize(width: preview.size.width * scale, height: preview.size.height * scale)
            preview.draw(in: CGRect(x: imageRect.midX - size.width / 2, y: imageRect.midY - size.height / 2,
                                    width: size.width, height: size.height))
        } else {
            appIcon?.draw(in: CGRect(x: imageRect.midX - 20, y: imageRect.midY - 8, width: 40, height: 40))
            let centered = NSMutableParagraphStyle()
            centered.alignment = .center
            (placeholder as NSString).draw(in: CGRect(x: imageRect.minX, y: imageRect.minY + 12, width: imageRect.width, height: 18),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: centered])
        }
    }
}
