import AppKit

/// One downward arrow above a window. Shared geometry keeps the app icon and
/// the monochrome menu-bar template consistent; there is no lower arrow.
enum IconArtwork {
    static func drawMark(origin: NSPoint, scale: CGFloat, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: origin.x, yBy: origin.y)
        transform.scale(by: scale)
        transform.concat()
        color.setStroke()
        let frame = NSBezierPath()
        frame.move(to: NSPoint(x: 6, y: 12))
        frame.line(to: NSPoint(x: 4.5, y: 12))
        frame.curve(to: NSPoint(x: 3, y: 10.5), controlPoint1: NSPoint(x: 3.67, y: 12), controlPoint2: NSPoint(x: 3, y: 11.33))
        frame.line(to: NSPoint(x: 3, y: 4.5))
        frame.curve(to: NSPoint(x: 4.5, y: 3), controlPoint1: NSPoint(x: 3, y: 3.67), controlPoint2: NSPoint(x: 3.67, y: 3))
        frame.line(to: NSPoint(x: 15.5, y: 3))
        frame.curve(to: NSPoint(x: 17, y: 4.5), controlPoint1: NSPoint(x: 16.33, y: 3), controlPoint2: NSPoint(x: 17, y: 3.67))
        frame.line(to: NSPoint(x: 17, y: 10.5))
        frame.curve(to: NSPoint(x: 15.5, y: 12), controlPoint1: NSPoint(x: 17, y: 11.33), controlPoint2: NSPoint(x: 16.33, y: 12))
        frame.line(to: NSPoint(x: 14, y: 12))
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 10, y: 18))
        arrow.line(to: NSPoint(x: 10, y: 10))
        arrow.move(to: NSPoint(x: 7.2, y: 12.8))
        arrow.line(to: NSPoint(x: 10, y: 10))
        arrow.line(to: NSPoint(x: 12.8, y: 12.8))
        for path in [frame, arrow] {
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
        }
    }
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20), flipped: false) { _ in
            drawMark(origin: .zero, scale: 1, color: .black)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MiniToggle"
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
