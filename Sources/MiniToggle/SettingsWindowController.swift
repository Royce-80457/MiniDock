import AppKit
import ApplicationServices
import ServiceManagement

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private weak var appDelegate: AppDelegate?
    private let engineStatus = NSTextField(wrappingLabelWithString: "")
    private let permissionStatus = NSTextField(labelWithString: "")
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let login = NSButton(checkboxWithTitle: "登录时启动 MiniToggle", target: nil, action: nil)
    private let table = NSTableView()
    private var apps: [(name: String, id: String)] = []
    private var observers: [NSObjectProtocol] = []

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MiniToggle 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.center()
        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            tabs.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            tabs.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            tabs.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -20)
        ])
        let general = page("通用", in: tabs)
        engineStatus.preferredMaxLayoutWidth = 480
        loginStatus.preferredMaxLayoutWidth = 480
        general.addArrangedSubview(heading("运行状态"))
        general.addArrangedSubview(engineStatus)
        general.addArrangedSubview(note("从菜单栏启用或暂停。当前最小化功能仍为实验性，无法确认窗口状态时会停止增强。"))
        general.addArrangedSubview(heading("启动"))
        login.target = self; login.action = #selector(toggleLogin)
        general.addArrangedSubview(login)
        general.addArrangedSubview(loginStatus)
        general.addArrangedSubview(button("打开登录项设置…", #selector(openLogin)))

        let permissions = page("权限", in: tabs)
        permissions.addArrangedSubview(heading("辅助功能"))
        permissions.addArrangedSubview(permissionStatus)
        permissions.addArrangedSubview(note("用于识别 Dock 应用图标、读取活动窗口并将其最小化。授权后，从菜单栏启用 MiniToggle。"))
        permissions.addArrangedSubview(button("申请辅助功能权限…", #selector(requestAX)))
        permissions.addArrangedSubview(button("打开辅助功能设置…", #selector(openAX)))
        permissions.addArrangedSubview(heading("监听故障排查"))
        permissions.addArrangedSubview(note("仅在无法创建鼠标监听、系统要求输入监控权限时使用；正常运行无需额外申请。"))
        permissions.addArrangedSubview(button("申请输入监控…", #selector(requestInput)))
        permissions.addArrangedSubview(button("刷新权限状态", #selector(refresh)))

        let exclusions = page("排除应用", in: tabs)
        exclusions.addArrangedSubview(note("勾选后，MiniToggle 不处理该应用的 Dock 点击。列表包含运行中的应用及已保存的排除项。"))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.title = "应用"; column.width = 490
        table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 34
        table.dataSource = self; table.delegate = self
        table.style = .inset
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true
        exclusions.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(equalToConstant: 380).isActive = true
        scroll.widthAnchor.constraint(equalTo: exclusions.widthAnchor).isActive = true
        exclusions.addArrangedSubview(button("刷新应用列表", #selector(refreshApps)))
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                if self?.window?.isVisible == true { self?.reloadApps() }
            })
        }
        refreshControls()
        reloadApps()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }
    func present() {
        refreshControls(); reloadApps()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func windowDidBecomeKey(_ notification: Notification) { refreshControls(); reloadApps() }
    func updateEngineStatus() { engineStatus.stringValue = appDelegate?.engine.status ?? "已暂停" }
    func refreshControls() {
        updateEngineStatus()
        permissionStatus.stringValue = AXIsProcessTrusted() ? "已授权" : "未授权"
        let status = SMAppService.mainApp.status
        login.state = status == .enabled ? .on : .off
        loginStatus.stringValue = status == .requiresApproval
            ? "等待系统批准，请前往登录项设置完成。"
            : "登录后默认暂停，由你从菜单栏启用。"
    }
    private func page(_ title: String, in tabs: NSTabView) -> NSStackView {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let container = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16)
        ])
        item.view = container; tabs.addTabViewItem(item)
        return stack
    }
    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }
    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 480
        return label
    }
    private func button(_ title: String, _ action: Selector) -> NSButton {
        NSButton(title: title, target: self, action: action)
    }
    private func reloadApps() {
        guard let appDelegate else { return }
        var indexed: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier else { continue }
            indexed[id] = app.localizedName ?? id
        }
        for id in appDelegate.engine.excluded where indexed[id] == nil { indexed[id] = id }
        apps = indexed.map { (name: $0.value, id: $0.key) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        table.reloadData()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { apps.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = apps[row]
        let check = NSButton(checkboxWithTitle: app.name, target: self, action: #selector(exclude(_:)))
        check.identifier = NSUserInterfaceItemIdentifier(app.id)
        check.toolTip = app.id
        check.state = appDelegate?.engine.excluded.contains(app.id) == true ? .on : .off
        return check
    }
    @objc private func exclude(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        appDelegate?.toggleExclusion(id); reloadApps()
    }
    @objc private func refresh() { refreshControls() }
    @objc private func refreshApps() { reloadApps() }
    @objc private func toggleLogin() { appDelegate?.toggleLogin(); refreshControls() }
    @objc private func openLogin() { appDelegate?.openLogin() }
    @objc private func requestAX() { appDelegate?.requestAX(); refreshControls() }
    @objc private func openAX() { appDelegate?.openAX() }
    @objc private func requestInput() { appDelegate?.requestInput() }
}
