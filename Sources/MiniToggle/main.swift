import AppKit
import ApplicationServices
import ServiceManagement
import ToggleCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let engine = Engine()
    let animationSettings = SystemAnimationSettings()
    lazy var settingsWindow = SettingsWindowController(appDelegate: self)
    var item: NSStatusItem!
    let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        engine.excluded = Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [])
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.compress.vertical", accessibilityDescription: "MiniToggle")
        item.menu = menu
        menu.delegate = self
        engine.changed = { [weak self] in
            guard let self else { return }
            self.item.button?.toolTip = "MiniToggle: \(self.engine.status)"
            self.settingsWindow.updateEngineStatus()
        }
        // No launch-time permission requests or automatic enhancement.
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }
    func menuWillOpen(_ menu: NSMenu) {
        engine.checkHealth()
        menu.removeAllItems()
        add("MiniToggle \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · \(engine.status)", nil)
        add(engine.running ? "暂停 MiniToggle" : "启用 MiniToggle / 重试", #selector(toggle))
        menu.addItem(.separator())
        add("设置…", #selector(showSettings))
        menu.addItem(.separator())
        add("复制本次诊断（最多 200 条）", #selector(copyDiagnostics))
        add("清空诊断", #selector(clearDiagnostics))
        add("退出", #selector(quit))
    }
    @discardableResult func add(_ title: String, _ action: Selector?) -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: "")
        value.target = self
        menu.addItem(value)
        return value
    }
    @objc func showSettings() { settingsWindow.present() }
    @objc func toggle() {
        if engine.running { engine.stop() }
        else {
            engine.experimental = true
            engine.start()
        }
    }
    @objc func useGenie() { setAnimation(.genie) }
    @objc func useScale() { setAnimation(.scale) }
    @objc func openAnimationSettings() { SystemAnimationSettings.openSettings() }
    func setAnimation(_ style: WindowAnimationStyle) {
        engine.invalidate("animation-setting-change")
        animationSettings.set(style) { [weak self] result in
            defer { self?.settingsWindow.refreshControls() }
            switch result {
            case .success(let applied):
                self?.engine.record("system animation=\(applied.rawValue) verified via System Settings")
                self?.settingsWindow.showAnimationResult("已切换为\(applied.title)")
            case .failure(let error):
                self?.engine.record("system animation change failed: \(error.localizedDescription)")
                let alert = NSAlert()
                alert.messageText = "窗口动画未确认切换"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
        settingsWindow.refreshControls()
    }
    @objc func requestAX() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    @objc func openAX() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func requestInput() {
        _ = CGRequestListenEventAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "登录项设置未完成"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
    @objc func openLogin() { SMAppService.openSystemSettingsLoginItems() }
    func toggleExclusion(_ id: String) {
        if engine.excluded.contains(id) { engine.excluded.remove(id) } else { engine.excluded.insert(id) }
        UserDefaults.standard.set(engine.excluded.sorted(), forKey: "excludedBundleIDs")
    }
    @objc func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(engine.records.joined(separator: "\n"), forType: .string)
    }
    @objc func clearDiagnostics() { engine.clearRecords() }
    @objc func quit() { engine.stop(); NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--audit-windows") {
    auditWindows()
} else if CommandLine.arguments.contains("--check") {
    print("AX trusted: \(AXIsProcessTrusted())")
    print("Listen preflight (advisory): \(CGPreflightListenEventAccess())")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
