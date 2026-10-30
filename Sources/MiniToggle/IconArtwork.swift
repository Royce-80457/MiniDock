import AppKit

/// One downward arrow above a Dock-shaped bar. Shared geometry keeps the app icon and
/// the monochrome menu-bar template consistent; there is no lower arrow.
enum IconArtwork {
    static func drawMark(origin: NSPoint, scale: CGFloat, color: NSColor, solid: Bool = true) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: origin.x, yBy: origin.y)
        transform.scale(by: scale)
        transform.concat()
        color.setStroke()
        color.setFill()
        let bounds = NSRect(x: 1.5, y: 3, width: 17, height: 4)
        if solid {
            NSBezierPath(roundedRect: bounds, xRadius: 1.6, yRadius: 1.6).fill()
        } else {
            let bar = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.65, dy: 0.65), xRadius: 0.95, yRadius: 0.95)
            bar.lineWidth = 1.3
            bar.stroke()
        }
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 10, y: 18))
        arrow.line(to: NSPoint(x: 10, y: 9.5))
        arrow.move(to: NSPoint(x: 7.2, y: 12.3))
        arrow.line(to: NSPoint(x: 10, y: 9.5))
        arrow.line(to: NSPoint(x: 12.8, y: 12.3))
        for path in [arrow] {
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
    static func menuBarImage(enabled: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            drawMark(origin: .zero, scale: 1, color: .black, solid: enabled)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = enabled ? "MiniToggle enabled" : "MiniToggle paused"
        return image
    }
    static func drawAppIcon() {
        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
        let gradient = NSGradient(starting: NSColor(srgbRed: 0.23, green: 0.30, blue: 0.78, alpha: 1),
                                  ending: NSColor(srgbRed: 0.37, green: 0.66, blue: 0.99, alpha: 1))!
        gradient.draw(in: tile, angle: 70)
        drawMark(origin: NSPoint(x: 192, y: 176), scale: 32, color: .white)
    }
}
