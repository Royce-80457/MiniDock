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
    private var statusTitle: String {
        "MiniToggle \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · \(engine.status)"
    }
    private lazy var enabledIcon = IconArtwork.menuBarImage(enabled: true)
    private lazy var pausedIcon = IconArtwork.menuBarImage(enabled: false)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
        engine.excluded = Set(UserDefaults.standard.stringArray(forKey: "excludedBundleIDs") ?? [])
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusItem()
        menu.autoenablesItems = false
        item.menu = menu
        menu.delegate = self
        engine.changed = { [weak self] in
            guard let self else { return }
            self.updateStatusItem()
            self.settingsWindow.updateEngineStatus()
        }
        // No launch-time permission requests or automatic enhancement.
        if CommandLine.arguments.contains("--settings") { showSettings() }
    }
    private func updateStatusItem() {
        guard let button = item?.button else { return }
        let image = engine.running && engine.experimental ? enabledIcon : pausedIcon
        if button.image !== image { button.image = image }
        button.toolTip = "MiniToggle: \(engine.status)"
        enableSwitch.state = engine.running ? .on : .off
        statusEntry?.title = statusTitle
    }
    func menuWillOpen(_ menu: NSMenu) {
        engine.checkHealth()
        menu.removeAllItems()
        statusEntry = add(statusTitle, nil)
        let control = NSMenuItem()
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 38))
        row.autoresizingMask = [.width]
        let label = NSTextField(labelWithString: "启用")
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        enableSwitch.removeFromSuperview()
        enableSwitch.target = self
        enableSwitch.action = #selector(toggle)
        enableSwitch.state = engine.running ? .on : .off
        enableSwitch.setAccessibilityLabel("启用或暂停")
        enableSwitch.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label); row.addSubview(enableSwitch)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            enableSwitch.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            enableSwitch.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        control.view = row
        menu.addItem(control)
        menu.addItem(.separator())
        add("设置…", #selector(showSettings))
        menu.addItem(.separator())
        add("复制日志", #selector(copyLogs))
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
    @objc func toggle() {
        if engine.running { engine.stop() }
        else {
            engine.experimental = true
            engine.start()
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
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
