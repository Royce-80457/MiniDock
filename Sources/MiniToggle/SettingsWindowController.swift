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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
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
            tabs.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -12),
            tabs.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 12),
            tabs.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -12)
        ])
        let general = page("通用", in: tabs)
        engineStatus.preferredMaxLayoutWidth = 420
        loginStatus.preferredMaxLayoutWidth = 420
        engineStatus.widthAnchor.constraint(lessThanOrEqualToConstant: 350).isActive = true
        general.addArrangedSubview(row([heading("运行状态"), engineStatus]))
        login.target = self; login.action = #selector(toggleLogin)
        general.addArrangedSubview(row([login, button("登录项设置…", #selector(openLogin))]))
        loginStatus.textColor = .secondaryLabelColor
        general.addArrangedSubview(loginStatus)
        general.addArrangedSubview(separator())
        general.addArrangedSubview(row([heading("辅助功能"), permissionStatus]))
        general.addArrangedSubview(note("用于识别 Dock 图标、读取活动窗口并执行最小化。授权后从菜单栏启用。"))
        general.addArrangedSubview(row([
            button("申请权限…", #selector(requestAX)),
            button("打开系统设置…", #selector(openAX)),
            button("刷新状态", #selector(refresh))
        ]))
        general.addArrangedSubview(row([
            button("申请输入监控…", #selector(requestInput)),
            note("仅监听创建失败时使用")
        ]))
        general.addArrangedSubview(separator())
        general.addArrangedSubview(row([heading("日志"), button("清空日志", #selector(clearLogs))]))
        general.addArrangedSubview(note("最多保留本次运行的 200 条日志；从菜单栏复制。"))

        let exclusions = page("排除应用", in: tabs)
        exclusions.addArrangedSubview(note("勾选后，MiniToggle 不处理该应用的 Dock 点击。列表包含运行中的应用及已保存的排除项。"))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        column.title = "应用"; column.width = 460
        table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 34
        table.dataSource = self; table.delegate = self
        table.style = .inset
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true
        exclusions.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(equalToConstant: 240).isActive = true
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
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -12)
        ])
        item.view = container; tabs.addTabViewItem(item)
        return stack
    }
    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }
    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 470).isActive = true
        return box
    }
    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }
    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 420
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
    @objc private func clearLogs() { appDelegate?.clearLogs() }
    @objc private func refresh() { refreshControls() }
    @objc private func refreshApps() { reloadApps() }
    @objc private func toggleLogin() { appDelegate?.toggleLogin(); refreshControls() }
    @objc private func openLogin() { appDelegate?.openLogin() }
    @objc private func requestAX() { appDelegate?.requestAX(); refreshControls() }
    @objc private func openAX() { appDelegate?.openAX() }
    @objc private func requestInput() { appDelegate?.requestInput() }
}
