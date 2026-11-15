import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let engine = Engine()
    lazy var settingsWindow = SettingsWindowController(appDelegate: self)
    var item: NSStatusItem!
    let menu = NSMenu()
    private let enableSwitch = BlueSwitch()
    private var statusEntry: NSMenuItem?
    private var statusTitle: String { engine.running ? "运行中" : "已暂停" }
    var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
        return "\(version) (\(build))"
    }
    var enableAtLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: "enableAtLaunch") }
        set { UserDefaults.standard.set(newValue, forKey: "enableAtLaunch") }
    }
    private lazy var enabledIcon = IconArtwork.menuBarImage(enabled: true)
    private lazy var pausedIcon = IconArtwork.menuBarImage(enabled: false)

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["enableAtLaunch": true])
        NSApp.setActivationPolicy(.accessory)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
        engine.excluded = Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [])
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusItem()
        menu.autoenablesItems = false
        menu.font = .menuFont(ofSize: 0)
        item.menu = menu
        menu.delegate = self
        engine.changed = { [weak self] in
            guard let self else { return }
            self.updateStatusItem()
            self.settingsWindow.updateEngineStatus()
        }
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--update-ready"), arguments.indices.contains(index + 1) {
            let marker = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
            let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
            if marker.lastPathComponent == "ready", marker.path.hasPrefix(temporary),
               marker.deletingLastPathComponent().lastPathComponent.hasPrefix("MiniDock-update-") {
                try? Data().write(to: marker)
            }
        }
        if arguments.contains("--update-failed") {
            let alert = NSAlert()
            alert.messageText = "更新未完成，已恢复旧版本"
            alert.informativeText = "新版本未能正常启动。请从设置重新检查更新，或从 GitHub 下载安装。"
            alert.runModal()
        }
        if enableAtLaunch { enable() }
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }
    private func updateStatusItem() {
        guard let button = item?.button else { return }
        let image = engine.running && engine.experimental ? enabledIcon : pausedIcon
        if button.image !== image { button.image = image }
        button.toolTip = "MiniDock \(versionDescription) · \(statusTitle)"
        enableSwitch.state = engine.running ? .on : .off
        statusEntry?.title = statusTitle
    }
    func menuWillOpen(_ menu: NSMenu) {
        engine.checkHealth()
        menu.removeAllItems()
        statusEntry = add(statusTitle, nil)
        let control = NSMenuItem()
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
        row.autoresizingMask = [.width]
        let label = NSTextField(labelWithString: "启用")
        label.font = menu.font
        label.translatesAutoresizingMaskIntoConstraints = false
        enableSwitch.removeFromSuperview()
        enableSwitch.target = self
        enableSwitch.action = #selector(toggle)
        enableSwitch.state = engine.running ? .on : .off
        enableSwitch.setAccessibilityLabel("启用或暂停")
        enableSwitch.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label); row.addSubview(enableSwitch)
        NSLayoutConstraint.activate([
            enableSwitch.widthAnchor.constraint(equalToConstant: 34),
            enableSwitch.heightAnchor.constraint(equalToConstant: 20),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            enableSwitch.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            enableSwitch.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        control.view = row
        menu.addItem(control)
        menu.addItem(.separator())
        add("设置", #selector(showSettings))
        add("关于", #selector(showAbout))
        add("退出", #selector(quit))
    }
    @discardableResult func add(_ title: String, _ action: Selector?) -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: "")
        value.target = self
        value.isEnabled = action != nil
        menu.addItem(value)
        return value
    }
    @objc func showSettings() { settingsWindow.present() }
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "运行位置\n\(Bundle.main.bundlePath)")
        ])
    }
    @objc func toggle() {
        menu.cancelTracking()
        // Permission UI must open after the menu's tracking loop has ended.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.engine.running {
                self.engine.stop()
                return
            }
            self.enable()
        }
    }
    private func enable() {
        engine.experimental = true
        engine.start()
        guard !engine.running else { return }

        showSettings()
        guard let window = settingsWindow.window else { return }
        let needsAccessibility = !AXIsProcessTrusted()
        let alert = NSAlert()
        alert.messageText = "无法启用 MiniDock"
        alert.informativeText = needsAccessibility
            ? "请在系统设置的“隐私与安全性 → 辅助功能”中允许 MiniDock，然后返回菜单重新启用。重新构建后可能需要重新授权。"
            : "\(engine.status)。请检查系统权限后重新启用，详细原因可从设置复制日志查看。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            if needsAccessibility {
                self?.openAX()
            } else {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            }
        }
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
    func addExclusions(_ ids: Set<String>) {
        engine.excluded.formUnion(ids)
        UserDefaults.standard.set(engine.excluded.sorted(), forKey: "excludedBundleIDs")
    }
    func removeExclusions(_ ids: Set<String>) {
        engine.excluded.subtract(ids)
        UserDefaults.standard.set(engine.excluded.sorted(), forKey: "excludedBundleIDs")
    }
    @objc func copyLogs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(engine.records.joined(separator: "\n"), forType: .string)
    }
    @objc func clearLogs() { engine.clearRecords() }
    @objc func quit() { engine.stop(); NSApp.terminate(nil) }
}

if CommandLine.arguments.contains("--audit-windows") {
    auditWindows()
} else if CommandLine.arguments.contains("--check") {
    print("AX trusted: \(AXIsProcessTrusted())")
    print("Listen preflight (advisory): \(CGPreflightListenEventAccess())")
    print("Screen capture authorized: \(CGPreflightScreenCaptureAccess())")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
