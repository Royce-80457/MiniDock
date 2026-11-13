import AppKit
import ApplicationServices
import ToggleCore

final class PreviewWindowActivator {
    private enum End: Error { case cancelled, newInput, permissionRevoked, deadlineExceeded }
    // Cancellation is also checked on the AX queue immediately before writes.
    private final class Request: @unchecked Sendable {
        var window: AXUIElement?
        let descriptor: PreviewWindowMatch
        let displays: [CGRect]
        let timeout: Double
        let retained: [AXUIElement]
        let application: AXUIElement
        let pid: pid_t
        let input = InputStamp.capture()
        let began = ProcessInfo.processInfo.systemUptime
        private let lock = NSLock()
        private var cancelled = false

        init(window: PreviewWindow, pid: pid_t, displays: [CGRect], retained: [AXUIElement]) {
            self.window = window.element
            descriptor = PreviewWindowMatch(title: window.title, frame: window.frame)
            self.displays = displays
            self.retained = retained
            let fullscreen = window.frame.map { PreviewWindowMatch.isDisplaySized($0, displays: displays) } ?? false
            timeout = window.element == nil || fullscreen ? 3 : 1.5
            self.pid = pid
            application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.08)
            if let element = window.element { AXUIElementSetMessagingTimeout(element, 0.08) }
        }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        func check() throws {
            lock.lock()
            let cancelled = cancelled
            lock.unlock()
            guard !cancelled else { throw End.cancelled }
            guard AXIsProcessTrusted() else { throw End.permissionRevoked }
            guard input == InputStamp.capture() else { throw End.newInput }
            guard ProcessInfo.processInfo.systemUptime - began < timeout else { throw End.deadlineExceeded }
        }
    }

    private struct Snapshot {
        let minimized: Bool?
        let frontmost: Bool
        let focused: Bool
    }
    private let queue = DispatchQueue(label: "local.royce.MiniToggle.previewFocus", qos: .userInitiated)
    private var request: Request?
    private var task: Task<Void, Never>?
    var record: ((String) -> Void)?

    func cancel() {
        request?.cancel()
        task?.cancel()
        request = nil
        task = nil
    }

    func activate(_ window: PreviewWindow, in app: NSRunningApplication, including retained: [AXUIElement] = []) {
        cancel()
        let request = Request(window: window, pid: app.processIdentifier, displays: NSScreen.screens.map(\.frame), retained: retained)
        self.request = request
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.request === request { self.request = nil; self.task = nil }
            }
            // Let NSButton tracking finish and the nonactivating panel release key focus.
            await Task.yield()
            var focusRequests = 0
            var restoreRequested = false
            var restoreRequests = 0
            var activationRequests = 0
            var confirmedReads = 0
            do {
                try request.check()
                // Resolve the selected window before activation can replace
                // the app's focused/main window with a current-Space window.
                if request.window == nil {
                    _ = try await self.perform(request) { try Self.snapshot(request) }
                }
                if let frame = request.descriptor.frame, PreviewWindowMatch.isDisplaySized(frame, displays: request.displays) {
                    do {
                        let result = try await self.perform(request) { try Self.focus(request) }
                        focusRequests = 1
                        self.record?("preview-focus prime pid=\(request.pid) \(result)")
                    } catch let error as AXFailure where error.code == .cannotComplete {
                        self.record?("preview-focus prime pending pid=\(request.pid) \(error)")
                    }
                }
                app.unhide()
                if #available(macOS 14.0, *), NSApp.isActive { NSApp.yieldActivation(to: app) }
                let accepted = app.activate(options: [])
                activationRequests = 1
                self.record?("preview-activate pid=\(request.pid) accepted=\(accepted) attempt=1")
                while true {
                    try request.check()
                    guard !app.isTerminated else { throw AXFailure(.invalidUIElement, operation: "preview.applicationExited") }
                    if !app.isActive || app.isHidden {
                        if activationRequests < 3 && ProcessInfo.processInfo.systemUptime - request.began >= Double(activationRequests) * 0.1 {
                            app.unhide()
                            if #available(macOS 14.0, *), NSApp.isActive { NSApp.yieldActivation(to: app) }
                            let accepted = app.activate(options: [])
                            activationRequests += 1
                            self.record?("preview-activate pid=\(request.pid) accepted=\(accepted) attempt=\(activationRequests)")
                        }
                        try await Task.sleep(nanoseconds: 100_000_000)
                        continue
                    }
                    let snapshot: Snapshot
                    do {
                        snapshot = try await self.perform(request) { try Self.snapshot(request) }
                    } catch let error as AXFailure where error.code == .cannotComplete {
                        try await Task.sleep(nanoseconds: 100_000_000)
                        continue
                    }
                    try request.check()
                    let frontmost = snapshot.frontmost && app.isActive && !app.isHidden
                        && NSWorkspace.shared.frontmostApplication?.processIdentifier == request.pid
                    let decision = PreviewFocusPolicy.decide(
                        elapsed: ProcessInfo.processInfo.systemUptime - request.began,
                        unchangedInput: true, targetExists: true, minimized: snapshot.minimized,
                        frontmost: frontmost, focused: snapshot.focused, focusRequests: focusRequests, timeout: request.timeout)
                    switch decision {
                    case .confirmed:
                        confirmedReads += 1
                        if confirmedReads >= 2 {
                            self.record?("preview-focus confirmed pid=\(request.pid) focusRequests=\(focusRequests)")
                            return
                        }
                    case .cancelled, .expired:
                        throw CancellationError()
                    case .wait:
                        confirmedReads = 0
                        if snapshot.minimized == true && !restoreRequested && restoreRequests < 3 {
                            let result = try await self.perform(request) {
                                guard let window = request.window else { throw AXFailure(.invalidUIElement, operation: "preview.unresolvedWindow") }
                                return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                            }
                            self.record?("preview-restore pid=\(request.pid) result=\(result.rawValue)")
                            guard result == .success || result == .cannotComplete else {
                                throw AXFailure(result, operation: "preview.restore")
                            }
                            restoreRequests += 1
                            restoreRequested = result == .success
                        }
                        try request.check()
                        if !frontmost && activationRequests < 3 {
                            app.unhide()
                            if #available(macOS 14.0, *), NSApp.isActive {
                                NSApp.yieldActivation(to: app)
                            }
                            let accepted = app.activate(options: [])
                            activationRequests += 1
                            self.record?("preview-activate pid=\(request.pid) accepted=\(accepted) attempt=\(activationRequests)")
                        }
                    case .focus:
                        confirmedReads = 0
                        focusRequests += 1
                        do {
                            let result = try await self.perform(request) { try Self.focus(request) }
                            self.record?("preview-focus request pid=\(request.pid) attempt=\(focusRequests) \(result)")
                        } catch let error as AXFailure where error.code == .cannotComplete {
                            self.record?("preview-focus transient failure pid=\(request.pid) attempt=\(focusRequests) \(error)")
                        }
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            } catch {
                let elapsed = ProcessInfo.processInfo.systemUptime - request.began
                self.record?("preview-focus ended pid=\(request.pid) elapsedMs=\(Int(elapsed * 1000)) error=\(error)")
            }
        }
    }

    private func perform<T>(_ request: Request, operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try request.check()
                    continuation.resume(returning: try operation())
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func snapshot(_ request: Request) throws -> Snapshot {
        if request.window == nil {
            let candidates = PreviewWindow.windows(for: request.pid, including: request.retained)
            guard let index = PreviewWindowMatch.captureIndex(for: 0, windows: [request.descriptor],
                captures: candidates.map { PreviewWindowMatch(title: $0.title, frame: $0.frame) }, displays: request.displays),
                  let window = candidates[index].element else {
                throw AXFailure(.cannotComplete, operation: "preview.resolveCapturedWindow")
            }
            request.window = window
            AXUIElementSetMessagingTimeout(window, 0.08)
        }
        guard let window = request.window else { throw AXFailure(.invalidUIElement, operation: "preview.unresolvedWindow") }
        var owner: pid_t = 0
        guard AXUIElementGetPid(window, &owner) == .success, owner == request.pid else {
            throw AXFailure(.invalidUIElement, operation: "preview.owner")
        }
        let values = try AX.readMany(request.application, [kAXWindowsAttribute, kAXFocusedWindowAttribute, kAXFrontmostAttribute])
        // Space membership does not determine whether an AX window is alive.
        // Keep the exact selected element and validate its owner and role.
        guard try AX.string(window, kAXRoleAttribute) == kAXWindowRole else {
            throw AXFailure(.invalidUIElement, operation: "preview.closedWindow")
        }
        let focused = values[kAXFocusedWindowAttribute].map { CFEqual($0, window) } ?? false
        return Snapshot(minimized: try AX.bool(window, kAXMinimizedAttribute),
                        frontmost: values[kAXFrontmostAttribute] as? Bool == true, focused: focused)
    }

    private static func focus(_ request: Request) throws -> String {
        // Revalidate on the worker immediately before targeting the saved window.
        let snapshot = try snapshot(request)
        guard snapshot.minimized == false, let window = request.window else { return "state-changed" }
        var results: [String] = []
        for (element, key, value) in [
            (window, kAXMainAttribute, kCFBooleanTrue as CFTypeRef),
            (request.application, kAXFocusedWindowAttribute, window as CFTypeRef),
            (window, kAXFocusedAttribute, kCFBooleanTrue as CFTypeRef)
        ] {
            try request.check()
            var settable = DarwinBoolean(false)
            let error = AXUIElementIsAttributeSettable(element, key as CFString, &settable)
            if error == .success && settable.boolValue {
                try request.check()
                let result = AXUIElementSetAttributeValue(element, key as CFString, value)
                results.append("\(key)=\(result.rawValue)")
            } else { results.append("\(key).settable=\(error.rawValue)/\(settable.boolValue)") }
        }
        try request.check()
        let raised = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        results.append("raise=\(raised.rawValue)")
        return results.joined(separator: " ")
    }
}
