import AppKit

/// Native circular help button, with an immediate hover explanation rather than
/// relying on the system's delayed tooltip timing.
final class HoverHelpButton: NSButton {
    private let explanation: String
    private var hoverArea: NSTrackingArea?
    private let explanationPopover = NSPopover()

    init(_ explanation: String) {
        self.explanation = explanation
        super.init(frame: .zero)
        bezelStyle = .helpButton
        title = ""
        target = self; action = #selector(showExplanation)
        setAccessibilityLabel("说明")
        setAccessibilityHelp(explanation)
        let font = NSFont.systemFont(ofSize: 12)
        let textSize = (explanation as NSString).boundingRect(with: NSSize(width: 256, height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).size
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: ceil(textSize.height) + 24))
        let label = NSTextField(wrappingLabelWithString: explanation)
        label.font = font
        label.frame = content.bounds.insetBy(dx: 12, dy: 12)
        content.addSubview(label)
        let controller = NSViewController(); controller.view = content
        explanationPopover.contentViewController = controller
        explanationPopover.contentSize = content.frame.size
        explanationPopover.behavior = .applicationDefined
        explanationPopover.animates = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); hoverArea = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { showExplanation() }
    override func mouseExited(with event: NSEvent) { explanationPopover.close() }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { explanationPopover.close() }
    }
    @objc private func showExplanation() {
        guard window != nil, !isHiddenOrHasHiddenAncestor, !explanationPopover.isShown else { return }
        explanationPopover.show(relativeTo: bounds, of: self, preferredEdge: .maxX)
    }
}
