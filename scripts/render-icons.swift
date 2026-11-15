import AppKit

// Compile with Sources/MiniDock/IconArtwork.swift to regenerate the assets.
@main struct RenderIcons {
    static func png(_ size: Int, draw: () -> Void) throws -> Data {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])!
    }
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let directory = root.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset")
        var images: [[String: String]] = []
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = "icon_\(points)x\(points)@\(scale)x.png"
                try png(points * scale, draw: IconArtwork.drawAppIcon).write(to: directory.appendingPathComponent(name))
                images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
            }
        }
        let json: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("Contents.json"))
        // Inspect both menu-bar states without changing the running app.
        for enabled in [true, false] {
            let name = enabled ? "enabled" : "paused"
            try png(256) {
                NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
                IconArtwork.drawMark(origin: NSPoint(x: 112, y: 112), scale: 40, color: .black, solid: enabled)
            }.write(to: root.appendingPathComponent("build/menu-icon-\(name).png"))
        }
    }
}
