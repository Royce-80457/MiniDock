import AppKit

let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Design/IconCandidates/dock-bar-v1")
func mark(origin: NSPoint, scale: CGFloat, solid: Bool, color: NSColor) {
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let t = NSAffineTransform(); t.translateX(by: origin.x, yBy: origin.y); t.scale(by: scale); t.concat()
    color.setFill(); color.setStroke()
    let bounds = NSRect(x: 1.5, y: 3, width: 17, height: 4)
    if solid {
        NSBezierPath(roundedRect: bounds, xRadius: 1.6, yRadius: 1.6).fill()
    } else {
        let bar = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.65, dy: 0.65), xRadius: 0.95, yRadius: 0.95)
        bar.lineWidth = 1.3; bar.stroke()
    }
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 10, y: 18)); arrow.line(to: NSPoint(x: 10, y: 9.5))
    arrow.move(to: NSPoint(x: 7.2, y: 12.3)); arrow.line(to: NSPoint(x: 10, y: 9.5)); arrow.line(to: NSPoint(x: 12.8, y: 12.3))
    arrow.lineWidth = 1.6; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
}
func app(origin: NSPoint, size: CGFloat, solid: Bool) {
    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
    let t = NSAffineTransform(); t.translateX(by: origin.x, yBy: origin.y); t.scale(by: size / 1024); t.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(srgbRed: 0.23, green: 0.30, blue: 0.78, alpha: 1), ending: NSColor(srgbRed: 0.37, green: 0.66, blue: 0.99, alpha: 1))!.draw(in: tile, angle: 70)
    mark(origin: NSPoint(x: 192, y: 176), scale: 32, solid: solid, color: .white)
}
func png(width: Int, height: Int, name: String, draw: () -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    draw(); NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
}
func label(_ text: String, centerX: CGFloat, y: CGFloat, size: CGFloat, color: NSColor = .black) {
    let s = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
    s.draw(at: NSPoint(x: centerX - s.size().width / 2, y: y))
}
for solid in [true, false] {
    let name = solid ? "solid" : "outline"
    try png(width: 1024, height: 1024, name: "app-\(name).png") { app(origin: .zero, size: 1024, solid: solid) }
    try png(width: 80, height: 80, name: "menu-\(name).png") { mark(origin: .zero, scale: 4, solid: solid, color: .black) }
}
try png(width: 760, height: 500, name: "comparison.png") {
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 760, height: 500).fill()
    label("A  实心", centerX: 190, y: 455, size: 22)
    label("B  空心", centerX: 570, y: 455, size: 22)
    app(origin: NSPoint(x: 46, y: 170), size: 288, solid: true)
    app(origin: NSPoint(x: 426, y: 170), size: 288, solid: false)
    label("菜单栏标记（放大）", centerX: 190, y: 140, size: 14, color: .darkGray)
    label("菜单栏标记（放大）", centerX: 570, y: 140, size: 14, color: .darkGray)
    mark(origin: NSPoint(x: 150, y: 35), scale: 4, solid: true, color: .black)
    mark(origin: NSPoint(x: 530, y: 35), scale: 4, solid: false, color: .black)
}
