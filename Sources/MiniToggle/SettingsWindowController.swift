import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTabViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private weak var appDelegate: AppDelegate?
    private let tabs = NSTabView()
    private var general: NSStackView!
    private let engineStatus = NSTextField(wrappingLabelWithString: "")
    private let permissionStatus = NSTextField(labelWithString: "")
    private let login = NSButton(checkboxWithTitle: "登录时启动", target: nil, action: nil)
    private let table = NSTableView()
    private let remove = NSButton(title: "−", target: nil, action: nil)
    private let empty = NSTextField(labelWithString: "暂无排除应用")
    private var listHeight: NSLayoutConstraint!
    private var apps: [(name: String, id: String, url: URL?)] = []
    private var observers: [NSObjectProtocol] = []

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 280),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MiniToggle 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentView!.addSubview(tabs)
        tabs.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 10),
            tabs.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -10),
            tabs.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 10),
            tabs.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -10)
        ])
        general = page("通用")
        engineStatus.preferredMaxLayoutWidth = 350
        engineStatus.widthAnchor.constraint(lessThanOrEqualToConstant: 350).isActive = true
        general.addArrangedSubview(row([heading("运行状态"), engineStatus,
            help("从菜单栏启用或暂停。无法确认窗口状态时会停止增强，可复制日志查看原因并重试。")]))
        login.target = self; login.action = #selector(toggleLogin)
        general.addArrangedSubview(row([login, help("登录后仍默认暂停，由你从菜单栏启用。"),
            button("登录项设置…", #selector(openLogin))]))
        general.addArrangedSubview(separator())
        general.addArrangedSubview(row([heading("辅助功能"), permissionStatus,
            help("用于识别 Dock 图标、读取活动窗口并执行最小化。授权后从菜单栏启用。")]))
        general.addArrangedSubview(row([button("申请权限…", #selector(requestAX)),
            button("打开系统设置…", #selector(openAX)), button("刷新状态", #selector(refresh)),
            help("在系统设置中授权后返回，状态会自动刷新，也可手动刷新。")]))
        general.addArrangedSubview(row([button("申请输入监控…", #selector(requestInput)),
            help("仅监听创建失败、系统要求输入监控权限时使用，正常运行无需额外申请。")]))
        general.addArrangedSubview(separator())
        general.addArrangedSubview(row([heading("日志"), button("清空日志", #selector(clearLogs)),
            help("最多保留本次运行的 200 条日志；从菜单栏复制。退出后清除，不记录窗口标题或按键内容。")]))

        let exclusions = page("排除应用")
        exclusions.addArrangedSubview(row([heading("排除应用"),
            help("列表中的应用不执行再次点击最小化。用＋添加应用；选中行后用−移除，可多选。移除不会删除应用文件。")]))
        let name = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
        name.title = "应用"; name.width = 330; name.minWidth = 260
        let kind = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("kind"))
        kind.title = "类型"; kind.width = 130; kind.minWidth = 100
        table.addTableColumn(name); table.addTableColumn(kind)
        table.rowHeight = 32
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let card = NSView()
        card.wantsLayer = true
        card.layer?.cornerRadius = 10; card.layer?.masksToBounds = true
        let footer = NSView()
        let add = button("＋", #selector(addApps))
        add.toolTip = "添加排除应用"; add.setAccessibilityLabel("添加排除应用")
        remove.target = self; remove.action = #selector(removeApps)
        remove.toolTip = "移除选中的排除项"; remove.setAccessibilityLabel("移除选中的排除项")
        remove.isEnabled = false
        for control in [add, remove] {
            control.isBordered = false
            control.font = .systemFont(ofSize: 20)
            control.widthAnchor.constraint(equalToConstant: 28).isActive = true
        }
        let actions = row([add, remove])
        footer.addSubview(actions); actions.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scroll); card.addSubview(footer)
        scroll.translatesAutoresizingMaskIntoConstraints = false; footer.translatesAutoresizingMaskIntoConstraints = false
        empty.textColor = .secondaryLabelColor
        empty.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(empty)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: card.topAnchor), scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: card.leadingAnchor), footer.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: card.bottomAnchor), footer.heightAnchor.constraint(equalToConstant: 30),
            actions.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 6), actions.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), empty.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
        exclusions.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: exclusions.widthAnchor).isActive = true
        listHeight = card.heightAnchor.constraint(equalToConstant: 150); listHeight.isActive = true
        tabs.delegate = self
        for event in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in
                if self?.window?.isVisible == true { self?.reloadApps() }
            })
        }
        refreshControls(); reloadApps(); resizeWindow(); window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    deinit { observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }
    func present() {
        refreshControls(); reloadApps(); resizeWindow()
        showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    func windowDidBecomeKey(_ notification: Notification) { refreshControls(); reloadApps() }
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) { resizeWindow() }
    private func resizeWindow() {
        guard let window, general != nil, listHeight != nil else { return }
        let exclusionTab = tabs.selectedTabViewItem?.identifier as? String == "排除应用"
        let height = exclusionTab ? listHeight.constant + 94 : max(260, general.fittingSize.height + 72)
        guard abs(window.contentLayoutRect.height - height) > 1 else { return }
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: 540, height: height))
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
    }
    func updateEngineStatus() {
        let text = appDelegate?.engine.running == true ? "运行中" : "已暂停"
        guard engineStatus.stringValue != text else { return }
        engineStatus.stringValue = text
        if window?.isVisible == true { resizeWindow() }
    }
    func refreshControls() {
        updateEngineStatus()
        permissionStatus.stringValue = AXIsProcessTrusted() ? "已授权" : "未授权"
        let status = SMAppService.mainApp.status
        login.state = status == .enabled ? .on : .off
        login.title = status == .requiresApproval ? "登录时启动（等待批准）" : "登录时启动"
    }
    private func page(_ title: String) -> NSStackView {
        let item = NSTabViewItem(identifier: title); item.label = title
        let container = NSView(); let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -10)
        ])
        item.view = container; tabs.addTabViewItem(item); return stack
    }
    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = .horizontal; stack.alignment = .centerY; stack.spacing = 8
        return stack
    }
    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text); label.font = .boldSystemFont(ofSize: NSFont.systemFontSize); return label
    }
    private func separator() -> NSBox {
        let box = NSBox(); box.boxType = .separator; box.widthAnchor.constraint(equalToConstant: 470).isActive = true; return box
    }
    private func help(_ text: String) -> NSView {
        let help = HoverHelpButton(text)
        help.widthAnchor.constraint(equalToConstant: 20).isActive = true
        help.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return help
    }
    private func button(_ title: String, _ action: Selector) -> NSButton { NSButton(title: title, target: self, action: action) }
    private func reloadApps() {
        guard let appDelegate else { return }
        let selected = Set(table.selectedRowIndexes.compactMap { apps.indices.contains($0) ? apps[$0].id : nil })
        apps = appDelegate.engine.excluded.map { id in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? id
            return (name: name, id: id, url: url)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        table.reloadData()
        table.selectRowIndexes(IndexSet(apps.indices.filter { selected.contains(apps[$0].id) }), byExtendingSelection: false)
        empty.isHidden = !apps.isEmpty
        listHeight.constant = CGFloat(min(max(apps.count, 3), 8) * 32 + 54)
        remove.isEnabled = !table.selectedRowIndexes.isEmpty
        resizeWindow()
    }
    func numberOfRows(in tableView: NSTableView) -> Int { apps.count }
    func tableViewSelectionDidChange(_ notification: Notification) { remove.isEnabled = !table.selectedRowIndexes.isEmpty }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let app = apps[row]
        if tableColumn?.identifier.rawValue == "kind" {
            return NSTextField(labelWithString: app.url == nil ? "未定位" : "应用程序")
        }
        let cell = NSTableCellView()
        let icon = NSImageView(image: app.url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "应用")!)
        let name = NSTextField(labelWithString: app.name); name.lineBreakMode = .byTruncatingTail
        cell.addSubview(icon); cell.addSubview(name); cell.toolTip = app.id
        cell.imageView = icon; cell.textField = name
        icon.translatesAutoresizingMaskIntoConstraints = false; name.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20),
            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8), name.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            name.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8)
        ])
        return cell
    }
    @objc private func addApps() {
        guard let window else { return }
        let panel = NSOpenPanel(); panel.title = "添加排除应用"; panel.prompt = "添加"
        panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            let ids = Set(panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { $0 != Bundle.main.bundleIdentifier })
            self.appDelegate?.addExclusions(ids); self.reloadApps()
        }
    }
    @objc private func removeApps() {
        let ids = Set(table.selectedRowIndexes.compactMap { apps.indices.contains($0) ? apps[$0].id : nil })
        appDelegate?.removeExclusions(ids); reloadApps()
    }
    @objc private func clearLogs() { appDelegate?.clearLogs() }
    @objc private func refresh() { refreshControls() }
    @objc private func toggleLogin() { appDelegate?.toggleLogin(); refreshControls() }
    @objc private func openLogin() { appDelegate?.openLogin() }
    @objc private func requestAX() { appDelegate?.requestAX(); refreshControls() }
    @objc private func openAX() { appDelegate?.openAX() }
    @objc private func requestInput() { appDelegate?.requestInput() }
}
