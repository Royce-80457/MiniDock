import AppKit
import CoreFoundation
import ToggleCore

/// Public preference APIs and Apple's documented Dock effect values. Saving a
/// preference is not proof that an already-running Dock has adopted the effect.
final class SystemAnimationSettings {
    private static let domain = "com.apple.dock" as CFString
    private static let key = "mineffect" as CFString
    private let queue = DispatchQueue(label: "local.royce.MiniToggle.animation-settings")
    private(set) var busy = false

    @discardableResult static func openSettings() -> Bool {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") else { return false }
        return NSWorkspace.shared.open(url)
    }
    func currentStyle() -> WindowAnimationStyle? {
        CFPreferencesAppSynchronize(Self.domain)
        guard let value = CFPreferencesCopyAppValue(Self.key, Self.domain) as? String else { return nil }
        return WindowAnimationStyle(rawValue: value)
    }
    private struct SettingsError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    func set(_ style: WindowAnimationStyle, completion: @escaping (Result<WindowAnimationStyle, Error>) -> Void) {
        guard !busy else { return }
        busy = true
        queue.async {
            let result: Result<WindowAnimationStyle, Error>
            if CFPreferencesAppValueIsForced(Self.key, Self.domain) {
                result = .failure(SettingsError(message: "窗口动画由系统管理策略控制，无法更改。"))
            } else {
                let previous = CFPreferencesCopyValue(Self.key, Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                CFPreferencesSetValue(Self.key, style.rawValue as CFString, Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                let saved = CFPreferencesSynchronize(Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                CFPreferencesAppSynchronize(Self.domain)
                let effective = CFPreferencesCopyAppValue(Self.key, Self.domain) as? String
                if saved && effective == style.rawValue {
                    result = .success(style)
                } else {
                    // Restore just this key, including absence of an old value.
                    CFPreferencesSetValue(Self.key, previous, Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                    CFPreferencesSynchronize(Self.domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
                    result = .failure(SettingsError(message: "未能保存动画偏好，已尝试恢复原值。"))
                }
            }
            DispatchQueue.main.async { self.busy = false; completion(result) }
        }
    }
}
