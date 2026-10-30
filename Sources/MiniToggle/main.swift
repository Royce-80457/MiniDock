import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let engine = Engine()
    var item: NSStatusItem!
    let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        engine.excluded = Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [])
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.compress.vertical", accessibilityDescription: "MiniToggle")
        item.menu = menu
        menu.delegate = self
        engine.changed = { [weak self] in self?.item.button?.toolTip = "MiniToggle：\(self?.engine.status ?? "")" }
        // No launch-time permission requests or automatic enhancement.
    }
    func menuWillOpen(_ menu: NSMenu) {
        engine.checkHealth()
        menu.removeAllItems()
        add("MiniToggle \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · \(engine.status)", nil)
        add(engine.running ? "暂停" : "启用观察 / 重试", #selector(toggle))
        let experimental = add("实验：再次点击最小化", #selector(experiment))
        experimental.state = engine.experimental ? .on : .off
        menu.addItem(.separator())
        add("辅助功能：\(AXIsProcessTrusted() ? "已授权" : "未授权")", nil)
        add("申请辅助功能权限…", #selector(requestAX))
        add("打开辅助功能设置…", #selector(openAX))
        add("监听创建失败时：申请输入监控…", #selector(requestInput))
        menu.addItem(.separator())
        let login = add("登录时启动", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        add("打开登录项设置…", #selector(openLogin))
        let exclusions = add("排除应用", nil)
        let submenu = NSMenu()
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier
        }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        var listed = Set<String>()
        for app in apps {
            guard let id = app.bundleIdentifier, listed.insert(id).inserted else { continue }
            exclusion(app.localizedName ?? id, id, submenu)
        }
        for id in engine.excluded.subtracting(listed).sorted() { exclusion(id, id, submenu) }
        exclusions.submenu = submenu
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
    func exclusion(_ title: String, _ id: String, _ submenu: NSMenu) {
        let entry = NSMenuItem(title: title, action: #selector(exclude(_:)), keyEquivalent: "")
        entry.target = self
        entry.representedObject = id
        entry.state = engine.excluded.contains(id) ? .on : .off
        submenu.addItem(entry)
    }
    @objc func toggle() { if engine.running { engine.stop() } else { engine.start() } }
    @objc func experiment() {
        if !engine.experimental {
            let alert = NSAlert()
            alert.messageText = "启用实验性最小化？"
            alert.informativeText = "尚未完成真实 Dock 交互验收。原始点击会继续交给 Dock，可能出现恢复竞争；全屏识别采用保守检查。建议先在观察模式确认诊断，再使用可随时恢复的测试窗口。此开关不会跨重启保存。"
            alert.addButton(withTitle: "启用实验")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        engine.experimental.toggle()
        engine.record("experimental=\(engine.experimental)")
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
    @objc func exclude(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
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
