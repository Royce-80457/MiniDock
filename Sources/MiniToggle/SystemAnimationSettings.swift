import AppKit
import ApplicationServices
import ToggleCore

/// Change the native System Settings control through public Accessibility APIs.
/// No Dock preference keys, shell commands, Apple Events, or Dock restarts.
final class SystemAnimationSettings {
    private let queue = DispatchQueue(label: "local.royce.MiniToggle.animation-settings")
    private(set) var busy = false // Main-thread UI state.
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    @discardableResult static func openSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return false }
        return NSWorkspace.shared.open(url)
    }

    func set(_ style: WindowAnimationStyle, completion: @escaping (Result<WindowAnimationStyle, Error>) -> Void) {
        guard !busy else { return }
        guard AXIsProcessTrusted() else {
            completion(.failure(SettingsError("需要辅助功能权限；也可在系统设置中手动选择动画。")))
            return
        }
        busy = true
        guard Self.openSettings() else {
            busy = false
            completion(.failure(SettingsError("无法打开系统设置。请手动打开“桌面与程序坞”。")))
            return
        }
        let deadline = now + 8
        queue.async { self.locate(style, deadline: deadline, completion: completion) }
    }

    private struct SettingsError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
    private func finish(_ result: Result<WindowAnimationStyle, Error>,
                        _ completion: @escaping (Result<WindowAnimationStyle, Error>) -> Void) {
        DispatchQueue.main.async { self.busy = false; completion(result) }
    }
    private func retry(deadline: Double, completion: @escaping (Result<WindowAnimationStyle, Error>) -> Void,
                       work: @escaping () -> Void) {
        guard AXIsProcessTrusted() else {
            finish(.failure(SettingsError("辅助功能权限已撤销，已停止调整动画。")), completion)
            return
        }
        guard now + 0.25 < deadline else {
            finish(.failure(SettingsError("未能确认动画设置。请在“系统设置 → 桌面与程序坞 → 最小化窗口动画”中手动选择；此系统的界面结构可能不兼容。")), completion)
            return
        }
        // Only a short, bounded readiness check after the user's explicit action.
        queue.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    private func settingsApp() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first else { return nil }
        return AXUIElementCreateApplication(app.processIdentifier)
    }
    private func children(_ element: AXUIElement) throws -> [AXUIElement] {
        try AX.read(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }
    private func search(_ roots: [AXUIElement], limit: Int,
                        matches: (AXUIElement) throws -> Bool) throws -> AXUIElement? {
        var nodes = roots
        var index = 0
        let began = now
        while index < nodes.count && index < limit && now - began < 0.35 {
            let node = nodes[index]
            index += 1
            if try matches(node) { return node }
            nodes.append(contentsOf: try children(node))
        }
        return nil
    }
    private func button(in app: AXUIElement) throws -> AXUIElement? {
        guard let windows = try AX.read(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        return try search(windows, limit: 400) { node in
            try AX.string(node, kAXIdentifierAttribute) == "minimize-windows"
                && AX.string(node, kAXRoleAttribute) == kAXPopUpButtonRole
        }
    }
    private func locate(_ style: WindowAnimationStyle, deadline: Double,
                        completion: @escaping (Result<WindowAnimationStyle, Error>) -> Void) {
        do {
            guard AXIsProcessTrusted(), let app = settingsApp(),
                  try AX.bool(app, kAXFrontmostAttribute) == true,
                  let control = try button(in: app) else {
                retry(deadline: deadline, completion: completion) { self.locate(style, deadline: deadline, completion: completion) }
                return
            }
            guard let label = try AX.string(control, kAXValueAttribute),
                  let current = WindowAnimationStyle(systemLabel: label) else {
                finish(.failure(SettingsError("无法识别当前系统的动画选项；请在系统设置中手动选择。")), completion)
                return
            }
            if current == style { finish(.success(style), completion); return }
            let error = AXUIElementPerformAction(control, kAXPressAction as CFString)
            guard error == .success else { throw AXFailure(error, operation: "animation.openMenu") }
            queue.asyncAfter(deadline: .now() + 0.1) {
                self.choose(style, control: control, deadline: deadline, completion: completion)
            }
        } catch {
            if let failure = error as? AXFailure, failure.code == .cannotComplete || failure.code == .invalidUIElement {
                retry(deadline: deadline, completion: completion) { self.locate(style, deadline: deadline, completion: completion) }
            } else { finish(.failure(error), completion) }
        }
    }
    private func choose(_ style: WindowAnimationStyle, control: AXUIElement, deadline: Double,
                        completion: @escaping (Result<WindowAnimationStyle, Error>) -> Void) {
        do {
            guard AXIsProcessTrusted(), let app = settingsApp(), try AX.bool(app, kAXFrontmostAttribute) == true else {
                finish(.failure(SettingsError("系统设置已失去前台或权限不足，已停止调整动画。")), completion)
                return
            }
            guard let item = try search(children(control), limit: 40, matches: { node in
                guard try AX.string(node, kAXRoleAttribute) == kAXMenuItemRole,
                      let title = try AX.string(node, kAXTitleAttribute) else { return false }
                return WindowAnimationStyle(systemLabel: title) == style
            }) else {
                retry(deadline: deadline, completion: completion) {
                    self.choose(style, control: control, deadline: deadline, completion: completion)
                }
                return
            }
            guard try AX.bool(item, kAXEnabledAttribute) == true else {
                finish(.failure(SettingsError("系统的动画选项当前不可用。")), completion)
                return
            }
            let error = AXUIElementPerformAction(item, kAXPressAction as CFString)
            guard error == .success else { throw AXFailure(error, operation: "animation.chooseEffect") }
            queue.asyncAfter(deadline: .now() + 0.1) {
                self.verify(style, deadline: deadline, completion: completion)
            }
        } catch { finish(.failure(error), completion) }
    }
    private func verify(_ style: WindowAnimationStyle, deadline: Double,
                        completion: @escaping (Result<WindowAnimationStyle, Error>) -> Void) {
        do {
            guard AXIsProcessTrusted(), let app = settingsApp(), let control = try button(in: app),
                  let label = try AX.string(control, kAXValueAttribute),
                  WindowAnimationStyle(systemLabel: label) == style else {
                retry(deadline: deadline, completion: completion) { self.verify(style, deadline: deadline, completion: completion) }
                return
            }
            finish(.success(style), completion)
        } catch {
            retry(deadline: deadline, completion: completion) { self.verify(style, deadline: deadline, completion: completion) }
        }
    }
}
