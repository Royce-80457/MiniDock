import AppKit
import ApplicationServices
import ToggleCore

struct AXFailure: Error, CustomStringConvertible {
    let code: AXError
    let operation: String
    init(_ code: AXError, operation: String) {
        self.code = code
        self.operation = operation
    }
    var description: String {
        let name: String
        switch code {
        case .cannotComplete: name = "cannotComplete"
        case .invalidUIElement: name = "invalidUIElement"
        case .apiDisabled: name = "apiDisabled"
        case .attributeUnsupported: name = "attributeUnsupported"
        case .noValue: name = "noValue"
        case .notImplemented: name = "notImplemented"
        case .illegalArgument: name = "illegalArgument"
        default: name = "other"
        }
        return "AXError=\(code.rawValue)(\(name)) operation=\(operation)"
    }
}

enum AX {
    static let system = AXUIElementCreateSystemWide()
    static func read(_ element: AXUIElement, _ key: String) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        switch error {
        case .success: return value
        case .attributeUnsupported, .noValue, .notImplemented: return nil
        default: throw AXFailure(error, operation: "read.\(key)")
        }
    }
    static func element(_ element: AXUIElement, _ key: String) throws -> AXUIElement? {
        guard let value = try read(element, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func string(_ element: AXUIElement, _ key: String) throws -> String? {
        try read(element, key) as? String
    }
    static func bool(_ element: AXUIElement, _ key: String) throws -> Bool? {
        try read(element, key) as? Bool
    }
    static func readMany(_ element: AXUIElement, _ keys: [String]) throws -> [String: CFTypeRef] {
        var result: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, keys as CFArray, [], &result)
        if error == .notImplemented {
            var values: [String: CFTypeRef] = [:]
            for key in keys { values[key] = try read(element, key) }
            return values
        }
        guard error == .success else { throw AXFailure(error, operation: "readMultiple") }
        guard let values = result as? [CFTypeRef], values.count == keys.count else {
            throw AXFailure(.failure, operation: "readMultiple.invalidResult")
        }
        var decoded: [String: CFTypeRef] = [:]
        for (key, value) in zip(keys, values) {
            if CFGetTypeID(value) == CFNullGetTypeID() { continue }
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError {
                var attributeError = AXError.success
                guard AXValueGetValue(value as! AXValue, .axError, &attributeError) else {
                    throw AXFailure(.failure, operation: "readMultiple.decode.\(key)")
                }
                switch attributeError {
                case .attributeUnsupported, .noValue, .notImplemented: continue
                default: throw AXFailure(attributeError, operation: "readMultiple.\(key)")
                }
            }
            decoded[key] = value
        }
        return decoded
    }
    private static func asElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func focusedPID() throws -> pid_t? {
        guard let app = try element(system, kAXFocusedApplicationAttribute) else { return nil }
        var pid: pid_t = 0
        let error = AXUIElementGetPid(app, &pid)
        guard error == .success else { throw AXFailure(error, operation: "getFocusedApplicationPID") }
        return pid
    }
    struct FocusEvidence {
        let systemPID: pid_t?
        let appFrontmost: Bool?
        func allows(target: pid_t, workspace: pid_t?) -> Bool {
            FocusPolicy.allows(target: target, workspace: workspace, system: systemPID, appFrontmost: appFrontmost)
        }
        var details: String {
            "systemPID=\(systemPID.map(String.init) ?? "unavailable") appFrontmost=\(appFrontmost.map(String.init) ?? "not-read")"
        }
    }
    static func focusEvidence(_ pid: pid_t) throws -> FocusEvidence {
        let systemPID = try focusedPID()
        let appFrontmost = try systemPID == nil
            ? bool(AXUIElementCreateApplication(pid), kAXFrontmostAttribute) : nil
        return FocusEvidence(systemPID: systemPID, appFrontmost: appFrontmost)
    }
    static func focusedWindow(_ pid: pid_t) throws -> AXUIElement? {
        guard let window = try element(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
        var owner: pid_t = 0
        let error = AXUIElementGetPid(window, &owner)
        guard error == .success else { throw AXFailure(error, operation: "getFocusedWindowPID") }
        return owner == pid ? window : nil
    }

    struct AppWindowSnapshot {
        let frontmost: Bool?
        let window: AXUIElement?
        func allows(target: pid_t, workspace: pid_t?) -> Bool {
            FocusPolicy.allowsAppSnapshot(target: target, workspace: workspace, appFrontmost: frontmost)
        }
    }
    /// One application request for both active state and focused window. A batch
    /// reduces messaging; it is not a system-wide atomic focus transaction.
    static func appWindowSnapshot(_ pid: pid_t) throws -> AppWindowSnapshot {
        let values = try readMany(AXUIElementCreateApplication(pid),
            [kAXFrontmostAttribute, kAXFocusedWindowAttribute])
        let window = asElement(values[kAXFocusedWindowAttribute])
        if let window {
            var owner: pid_t = 0
            let error = AXUIElementGetPid(window, &owner)
            guard error == .success else { throw AXFailure(error, operation: "getSnapshotWindowPID") }
            guard owner == pid else { throw AXFailure(.invalidUIElement, operation: "snapshotWindowOwnerMismatch") }
        }
        return AppWindowSnapshot(frontmost: values[kAXFrontmostAttribute] as? Bool, window: window)
    }

    /// Hit test in CGEvent's global, top-left coordinate space. Never flip via NSScreen.main.
    static func dockApplication(at point: CGPoint) throws -> NSRunningApplication? {
        try dockTarget(at: point, includeHidden: false, requireFrame: false)?.app
    }

    static func dockTarget(at point: CGPoint, includeHidden: Bool = true, requireFrame: Bool = true) throws -> (app: NSRunningApplication, frame: CGRect)? {
        var hit: AXUIElement?
        var error = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
        // System-wide hit testing can land on an arbitrary application's UI.
        // No AX hit-test implementation there means no confirmed Dock icon;
        // it is not a failure of MiniDock's event listener or authorization.
        if [.failure, .cannotComplete, .noValue, .notImplemented].contains(error) {
            // Some full-screen players make system-wide AX hit testing fail.
            // Only query Dock directly when WindowServer confirms a visible
            // Dock-owned surface under this point, excluding desktop wallpaper.
            guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
                  let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]],
                  windows.contains(where: { window in
                      guard (window[kCGWindowOwnerPID as String] as? Int32) == dock.processIdentifier,
                            (window[kCGWindowLayer as String] as? Int ?? 0) > 0,
                            (window[kCGWindowAlpha as String] as? Double ?? 0) > 0,
                            let bounds = window[kCGWindowBounds as String] as? [String: Any],
                            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
                      return frame.contains(point)
                  }) else { return nil }
            let application = AXUIElementCreateApplication(dock.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.05)
            error = AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &hit)
            if [.failure, .cannotComplete, .noValue, .notImplemented].contains(error) { return nil }
        }
        guard error == .success else { throw AXFailure(error, operation: "hitTest") }
        guard var item = hit else { return nil }
        for _ in 0..<5 {
            var pid: pid_t = 0
            guard AXUIElementGetPid(item, &pid) == .success,
                  NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock" else { return nil }
            if try string(item, kAXSubroleAttribute) == kAXApplicationDockItemSubrole {
                // URL, not localized label or private Dock preferences, identifies the application.
                guard let url = try read(item, kAXURLAttribute) as? URL, url.isFileURL,
                      url.pathExtension.lowercased() == "app" else { return nil }
                let matches = NSWorkspace.shared.runningApplications.filter {
                    $0.activationPolicy == .regular && !$0.isTerminated && (includeHidden || !$0.isHidden)
                    && $0.bundleURL?.resolvingSymlinksInPath() == url.resolvingSymlinksInPath()
                }
                guard matches.count == 1, let app = matches.first else { return nil }
                if !requireFrame { return (app, .zero) }
                guard let bounds = try frame(item) else { return nil }
                return (app, bounds)
            }
            guard let parent = try element(item, kAXParentAttribute) else { return nil }
            item = parent
        }
        return nil
    }

    static func frame(_ window: AXUIElement) throws -> CGRect? {
        let values = try readMany(window, [kAXPositionAttribute, kAXSizeAttribute])
        return frame(values)
    }
    private static func frame(_ values: [String: CFTypeRef]) -> CGRect? {
        guard let p = values[kAXPositionAttribute], CFGetTypeID(p) == AXValueGetTypeID(),
              let s = values[kAXSizeAttribute], CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }

    struct Eligibility {
        let reasons: [String]
        let details: String
        var allowed: Bool { reasons.isEmpty }
    }

    static func eligibility(_ window: AXUIElement) throws -> Eligibility {
        var reasons: [String] = []
        let values = try readMany(window, [kAXRoleAttribute, kAXSubroleAttribute, kAXMinimizedAttribute,
            kAXModalAttribute, kAXMinimizeButtonAttribute, kAXChildrenAttribute, kAXPositionAttribute, kAXSizeAttribute])
        let role = values[kAXRoleAttribute] as? String
        let subrole = values[kAXSubroleAttribute] as? String
        let minimized = values[kAXMinimizedAttribute] as? Bool
        let modal = values[kAXModalAttribute] as? Bool
        let button = asElement(values[kAXMinimizeButtonAttribute])
        let buttonEnabled = try button.flatMap { try bool($0, kAXEnabledAttribute) }
        let children = values[kAXChildrenAttribute] as? [AXUIElement]
        let bounds = frame(values)
        if role != kAXWindowRole { reasons.append("role-not-window") }
        if subrole != kAXStandardWindowSubrole { reasons.append("subrole-not-standard") }
        if minimized != false { reasons.append("minimized-true-or-unknown") }
        if modal != false { reasons.append("modal-true-or-unknown") }
        if button == nil { reasons.append("minimize-button-missing") }
        if buttonEnabled != true { reasons.append("minimize-button-disabled-or-unknown") }
        if children == nil { reasons.append("children-unavailable") }
        if bounds == nil { reasons.append("frame-unavailable") }
        // Sheets are exposed as direct window children by standard AppKit applications.
        for child in children ?? [] {
            if try string(child, kAXRoleAttribute) == kAXSheetRole { reasons.append("sheet-present") }
        }
        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(window, kAXMinimizedAttribute as CFString, &settable)
        if settableError == .cannotComplete || settableError == .apiDisabled {
            throw AXFailure(settableError, operation: "isSettable.AXMinimized")
        }
        if settableError != .success || !settable.boolValue { reasons.append("minimized-not-writable") }
        // Public AX headers offer no generic fullscreen-state constant. Allow
        // work-area edges, but reject full-display or off-work-area windows.
        let screens = NSScreen.screens
        let workAreas = screens.map { screen -> CGRect in
            let visible = screen.visibleFrame
            return CGRect(x: visible.minX, y: (screens.first?.frame.maxY ?? 0) - visible.maxY,
                          width: visible.width, height: visible.height)
        }
        let displayFrames = screens.map { screen in
            CGRect(x: screen.frame.minX, y: (screens.first?.frame.maxY ?? 0) - screen.frame.maxY,
                   width: screen.frame.width, height: screen.frame.height)
        }
        if let bounds, !zip(displayFrames, workAreas).contains(where: {
            WindowGeometry.allows(bounds, display: $0.0, workArea: $0.1)
        }) {
            reasons.append("geometry-outside-safe-work-area")
        }
        if screens.isEmpty { reasons.append("screens-unavailable") }
        func boolText(_ value: Bool?) -> String { value.map(String.init) ?? "unknown" }
        let details = "role=\(role ?? "unknown") subrole=\(subrole ?? "unknown") minimized=\(boolText(minimized)) modal=\(boolText(modal)) minimizeButtonEnabled=\(boolText(buttonEnabled)) children=\(children.map { String($0.count) } ?? "unknown") minimizedWritable=\(settable.boolValue) settableError=\(settableError.rawValue) frame=\(bounds.map { NSStringFromRect($0) } ?? "unknown") workAreas=\(workAreas.map { NSStringFromRect($0) }.joined(separator: ";"))"
        return Eligibility(reasons: reasons, details: details)
    }
}
