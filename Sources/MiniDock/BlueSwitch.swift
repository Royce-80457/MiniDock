import AppKit

/// Keep native button activation, keyboard handling and accessibility, while
/// drawing a fixed blue on-state independent of accent color or menu vibrancy.
final class BlueSwitch: NSButton {
    init() {
        super.init(frame: .zero)
        setButtonType(.switch)
        isBordered = false
        title = ""
        focusRingType = .default
        setAccessibilityRole(.checkBox)
        setAccessibilitySubrole(.switch)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override var intrinsicContentSize: NSSize { NSSize(width: 40, height: 24) }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let track = bounds.insetBy(dx: 1, dy: 1)
        let on = state == .on
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = on ? NSColor(srgbRed: 0, green: 0.4784, blue: 1, alpha: 1)
                       : NSColor(srgbRed: dark ? 0.38 : 0.76, green: dark ? 0.38 : 0.76, blue: dark ? 0.40 : 0.78, alpha: 1)
        NSGraphicsContext.current?.cgContext.setAlpha(isEnabled ? 1 : 0.45)
        color.setFill()
        NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill()
        let diameter = track.height - 4
        let x = on ? track.maxX - diameter - 2 : track.minX + 2
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: track.minY + 2, width: diameter, height: diameter)).fill()
    }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 11, yRadius: 11).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }
}
