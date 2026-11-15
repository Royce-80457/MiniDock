import AppKit
import ApplicationServices
import ScreenCaptureKit
import ToggleCore

final class DockPreviewController {
    private let panel = PreviewPanel()
    private let activator = PreviewWindowActivator()
    private let windowStore = PreviewWindowStore()
    private let queue = DispatchQueue(label: "local.royce.MiniDock.previewAX", qos: .userInitiated)
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var busy = false
    private var generation = UUID()
    private var candidate: NSRunningApplication?
    private var anchor = CGRect.zero
    private var enteredAt = 0.0
    private var lastInside = 0.0
    private var refreshedAt = 0.0
    private var windows: [PreviewWindow] = []
    private var listTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var suppressedAnchor: CGRect?
    var excluded: Set<String> = [] { didSet { windowStore.excluded = excluded } }
    var record: ((String) -> Void)? { didSet { activator.record = record } }
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    init() {
        panel.selected = { [weak self] index in self?.activate(index) }
        panel.dismissed = { [weak self] in self?.dismiss() }
    }

    func start() {
        stop()
        windowStore.start()
        let timer = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged]) { [weak self] _ in
            self?.dismiss()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 && self.panel.isVisible {
                self.dismiss()
                return nil
            }
            if event.type != .keyDown && event.window !== self.panel { self.dismiss() }
            return event
        }
    }

    func stop() {
        cancelActivation()
        windowStore.stop()
        timer?.invalidate()
        timer = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        dismiss()
    }

    func dismiss(suppressUntilPointerLeaves: Bool = true) {
        if candidate != nil && suppressUntilPointerLeaves { suppressedAnchor = anchor }
        if !suppressUntilPointerLeaves { suppressedAnchor = nil }
        generation = UUID()
        listTask?.cancel()
        listTask = nil
        captureTask?.cancel()
        captureTask = nil
        panel.dismissPreview()
        windows = []
        candidate = nil
    }

    func cancelActivation() { activator.cancel() }

    private func tick() {
        guard AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.screensaver" else {
            dismiss()
            return
        }
        let mouse = NSEvent.mouseLocation
        let pointerInPanel = panel.frame.insetBy(dx: -5, dy: -5).contains(mouse)
        if PreviewInteractionPolicy.preservesClick(mousePressed: NSEvent.pressedMouseButtons != 0,
                                                   pointerInPanel: pointerInPanel, panelVisible: panel.isVisible) {
            lastInside = now
            return
        }
        guard NSEvent.pressedMouseButtons == 0 else { dismiss(); return }
        if let suppressedAnchor {
            if suppressedAnchor.insetBy(dx: -4, dy: -4).contains(mouse) { return }
            self.suppressedAnchor = nil
        }
        if panel.isVisible && panel.frame.insetBy(dx: -5, dy: -5).contains(mouse) {
            lastInside = now
            refreshIfNeeded()
            return
        }
        // Restrict AX hit testing to screen edges where a Dock can appear.
        let nearDock = NSScreen.screens.contains { screen in
            screen.frame.contains(mouse) && (mouse.y < screen.frame.minY + 300
                || mouse.x < screen.frame.minX + 300 || mouse.x > screen.frame.maxX - 300)
        }
        guard nearDock else { leave(); return }
        guard !busy else { return }
        busy = true
        let token = generation
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let point = CGPoint(x: mouse.x, y: top - mouse.y)
        queue.async { [weak self] in
            let target = try? AX.dockTarget(at: point)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard self.timer != nil, self.generation == token else { return }
                guard NSEvent.pressedMouseButtons == 0 else { return }
                // Ignore a delayed hit test after the pointer has already moved.
                guard hypot(NSEvent.mouseLocation.x - mouse.x, NSEvent.mouseLocation.y - mouse.y) < 5 else { return }
                guard let target, target.app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                      !self.excluded.contains(target.app.bundleIdentifier ?? "") else { self.leave(); return }
                let bounds = CGRect(x: target.frame.minX, y: top - target.frame.maxY,
                                    width: target.frame.width, height: target.frame.height)
                self.hover(target.app, anchor: bounds)
            }
        }
    }

    private func leave() {
        if now - lastInside > 0.35 { dismiss() }
    }

    private func hover(_ app: NSRunningApplication, anchor: CGRect) {
        windowStore.watch(app)
        if candidate?.processIdentifier != app.processIdentifier {
            dismiss()
            suppressedAnchor = nil
            candidate = app
            enteredAt = now
            refreshedAt = 0
        }
        self.anchor = anchor
        lastInside = now
        if now - enteredAt >= 0.4 { refreshIfNeeded() }
    }

    private func refreshIfNeeded() {
        guard !busy, now - refreshedAt >= 1, let app = candidate else { return }
        refreshedAt = now
        busy = true
        let token = generation
        let retained = windowStore.elements(for: app.processIdentifier)
        queue.async { [weak self] in
            let updated = PreviewWindow.windows(for: app.processIdentifier, including: retained)
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard self.timer != nil, self.generation == token else { return }
                guard NSEvent.pressedMouseButtons == 0 else { return }
                let mouse = NSEvent.mouseLocation
                guard self.anchor.insetBy(dx: -6, dy: -6).contains(mouse)
                    || (self.panel.isVisible && self.panel.frame.insetBy(dx: -5, dy: -5).contains(mouse)) else {
                    self.dismiss()
                    return
                }
                self.listTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    var resolved = updated
                    var captures: [SCWindow]?
                    if CGPreflightScreenCaptureAccess() {
                        self.busy = true
                        if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) {
                            let available = content.windows.filter {
                                $0.owningApplication?.processID == app.processIdentifier && $0.windowLayer == 0
                            }
                            captures = available
                            let represented = Set(updated.compactMap {
                                $0.captureWindow(in: available, siblings: updated)?.windowID
                            })
                            let fullscreen = PreviewWindow.fullscreenWindows(in: content, pid: app.processIdentifier,
                                                                            displays: NSScreen.screens.map(\.frame))
                            resolved.append(contentsOf: fullscreen.filter { window in
                                guard let id = window.captureID else { return false }
                                return !represented.contains(id)
                            })
                        }
                        self.busy = false
                    }
                    guard !Task.isCancelled, self.timer != nil, self.generation == token else { return }
                    self.present(resolved, app: app, token: token, captures: captures)
                }
            }
        }
    }

    private func present(_ updated: [PreviewWindow], app: NSRunningApplication, token: UUID, captures: [SCWindow]?) {
        guard !app.isTerminated else { dismiss(); return }
        let mouse = NSEvent.mouseLocation
        guard NSEvent.pressedMouseButtons == 0,
              anchor.insetBy(dx: -6, dy: -6).contains(mouse)
                || (panel.isVisible && panel.frame.insetBy(dx: -5, dy: -5).contains(mouse)) else { return }
        guard !updated.isEmpty else {
            panel.dismissPreview()
            windows = []
            return
        }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) else { return }
        let unchanged = windows.count == updated.count && zip(windows, updated).allSatisfy {
            $0.isSameWindow(as: $1) && $0.title == $1.title && $0.minimized == $1.minimized
        }
        windows = updated
        let list: Bool
        if !unchanged || !panel.isVisible {
            list = panel.show(windows: updated, app: app, anchor: anchor, screen: screen)
        } else {
            list = panel.tiles.first?.frame.height == 38
        }
        if !list { capture(app: app, token: token, available: captures) }
    }

    private func capture(app: NSRunningApplication, token: UUID, available: [SCWindow]?) {
        guard captureTask == nil, CGPreflightScreenCaptureAccess() else { return }
        let snapshot = windows
        captureTask = Task { @MainActor [weak self] in
            defer { if self?.generation == token { self?.captureTask = nil } }
            guard let available, !Task.isCancelled else { return }
            for (index, window) in snapshot.enumerated() {
                guard !Task.isCancelled, let self, self.generation == token else { return }
                guard let match = window.captureWindow(in: available, siblings: snapshot) else { continue }
                let image = await WindowThumbnailCapture.image(for: match)
                guard !Task.isCancelled, self.generation == token,
                      self.windows.indices.contains(index), self.windows[index].isSameWindow(as: window),
                      self.panel.tiles.indices.contains(index) else { return }
                self.panel.tiles[index].preview = image.map { NSImage(cgImage: $0, size: .zero) }
            }
        }
    }

    private func activate(_ index: Int) {
        guard windows.indices.contains(index), let app = candidate, AXIsProcessTrusted() else { dismiss(); return }
        let window = windows[index]
        dismiss()
        activator.activate(window, in: app, including: windowStore.elements(for: app.processIdentifier))
    }
}
