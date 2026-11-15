import AppKit
import ToggleCore

final class PreviewPanel: NSPanel {
    private(set) var tiles: [PreviewTile] = []
    var selected: ((Int) -> Void)?
    var dismissed: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .transient, .ignoresCycle]
        setAccessibilityLabel("应用窗口预览")
    }

    func show(windows: [PreviewWindow], app: NSRunningApplication, anchor: CGRect, screen: NSScreen) -> Bool {
        let layout = PreviewLayout(count: windows.count, available: screen.visibleFrame.size)
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: layout.size))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        let scroll = NSScrollView(frame: background.bounds.insetBy(dx: 8, dy: 8))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = layout.usesList
        scroll.autohidesScrollers = true
        let document = NSView(frame: CGRect(x: 0, y: 0,
            width: scroll.bounds.width, height: layout.usesList ? CGFloat(windows.count) * layout.itemHeight : layout.itemHeight))
        tiles = windows.enumerated().map { index, window in
            let title = window.title.isEmpty ? (app.localizedName ?? "未命名窗口") : window.title
            let placeholder = CGPreflightScreenCaptureAccess() ? (window.minimized ? "窗口已最小化" : "预览不可用") : "需要屏幕录制权限"
            let tile = PreviewTile(title: title, placeholder: placeholder, icon: app.icon, list: layout.usesList,
                                   size: CGSize(width: layout.itemWidth, height: layout.itemHeight))
            tile.frame.origin = layout.usesList
                ? CGPoint(x: 0, y: document.bounds.height - CGFloat(index + 1) * layout.itemHeight)
                : CGPoint(x: CGFloat(index) * 224, y: 0)
            tile.tag = index
            tile.target = self
            tile.action = #selector(choose(_:))
            document.addSubview(tile)
            return tile
        }
        scroll.documentView = document
        if layout.usesList { document.scroll(CGPoint(x: 0, y: document.bounds.height)) }
        background.addSubview(scroll)
        contentView = background
        setFrame(PreviewLayout.frame(size: layout.size, anchor: anchor, screen: screen.frame, visible: screen.visibleFrame), display: true)
        orderFrontRegardless()
        return layout.usesList
    }

    @objc private func choose(_ sender: NSButton) { selected?(sender.tag) }
    override func cancelOperation(_ sender: Any?) { dismissed?() }

    func dismissPreview() {
        orderOut(nil)
        contentView = nil
        tiles.removeAll()
    }
}
