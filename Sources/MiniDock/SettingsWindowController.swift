import AppKit
import ApplicationServices
import ServiceManagement
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSTabViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private weak var appDelegate: AppDelegate?
    private let tabs = NSTabView()
    private let updater = UpdateController()
    private let updateStatus = NSTextField(wrappingLabelWithString: "")
    private let checkUpdate = NSButton(title: "检查更新", target: nil, action: nil)
    private let installUpdate = NSButton(title: "更新并重启", target: nil, action: nil)
    private var general: NSStackView!
    private let engineStatus = NSTextField(wrappingLabelWithString: "")
    private let permissionStatus = NSTextField(labelWithString: "")
    private let captureStatus = NSTextField(labelWithString: "")
    private let login = NSSwitch()
    private let enableAtLaunch = NSSwitch()
    private let loginLabel = NSTextField(labelWithString: "登录时启动")
    private let table = NSTableView()
    private let remove = NSButton(title: "−", target: nil, action: nil)
    private let empty = NSTextField(labelWithString: "暂无排除应用")
    private var listHeight: NSLayoutConstraint!
    private var apps: [(name: String, id: String, url: URL?)] = []
    private var observers: [NSObjectProtocol] = []

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "MiniDock \(appDelegate.versionDescription) 设置"
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
        general.spacing = 16
        engineStatus.font = .systemFont(ofSize: 13, weight: .medium)
        permissionStatus.font = .systemFont(ofSize: 13, weight: .medium)
        login.target = self
        login.action = #selector(toggleLogin)
        login.setAccessibilityLabel("登录时启动")
        enableAtLaunch.target = self
        enableAtLaunch.action = #selector(toggleEnableAtLaunch)
        enableAtLaunch.setAccessibilityLabel("启动时自动启用")

        let runtime = settingsRow("运行状态", detail: "从菜单栏启用或暂停 MiniDock。", trailing: engineStatus)
        let startup = settingsRow(loginLabel, detail: "登录 macOS 后自动打开 MiniDock。", trailing: login)
        let loginSettings = button("登录项设置…", #selector(openLogin))
        startup.addArrangedSubview(loginSettings)
        let autoEnable = settingsRow("启动时自动启用", detail: "下次启动生效，包含登录后启动。", trailing: enableAtLaunch)
        general.addArrangedSubview(settingsCard("启动与运行", rows: [runtime, startup, autoEnable]))

        let accessibility = settingsRow("辅助功能", detail: "识别 Dock 图标、读取窗口、最小化及切换窗口。", trailing: permissionStatus)
        let permissionActions = row([
            button("申请权限…", #selector(requestAX)),
            button("系统设置…", #selector(openAX)),
            button("刷新状态", #selector(refresh))
        ])
        let permissionContent = NSStackView(views: [accessibility, permissionActions])
        permissionContent.orientation = .vertical
        permissionContent.alignment = .leading
        permissionContent.spacing = 12
        accessibility.widthAnchor.constraint(equalTo: permissionContent.widthAnchor).isActive = true
        let input = settingsRow("输入监控", detail: "仅在监听创建失败且系统要求时申请。", trailing: button("申请…", #selector(requestInput)))
        let capture = settingsRow("屏幕录制", detail: "用于 Dock 悬停窗口缩略图，授权后可能需要重启应用。", trailing: captureStatus)
        let captureContent = NSStackView(views: [capture, button("授权屏幕录制…", #selector(requestCapture))])
        captureContent.orientation = .vertical
        captureContent.alignment = .leading
        captureContent.spacing = 8
        capture.widthAnchor.constraint(equalTo: captureContent.widthAnchor).isActive = true
        general.addArrangedSubview(settingsCard("权限", rows: [permissionContent, captureContent, input]))

        let logs = settingsRow("运行日志", detail: "保留本次运行最近 200 条。", trailing: button("清空日志", #selector(clearLogs)))
        logs.addArrangedSubview(button("复制日志", #selector(copyLogs)))
        logs.toolTip = "退出后清除，不记录窗口标题或按键内容。"
        general.addArrangedSubview(settingsCard("诊断", rows: [logs]))
        for section in general.arrangedSubviews {
            section.widthAnchor.constraint(equalTo: general.widthAnchor).isActive = true
        }
        runtime.toolTip = "无法确认窗口状态时会停止增强，可复制日志查看原因并重试。"
        permissionActions.toolTip = "在系统设置中授权后返回，状态会自动刷新，也可手动刷新。"

        let updates = page("更新")
        checkUpdate.target = self
        checkUpdate.action = #selector(checkForUpdates)
        installUpdate.target = self
        installUpdate.action = #selector(installLatest)
        updateStatus.preferredMaxLayoutWidth = 510
        updates.addArrangedSubview(settingsCard("软件更新", rows: [
            settingsRow("当前版本", detail: appDelegate.versionDescription, trailing: checkUpdate),
            updateStatus,
            row([installUpdate, button("GitHub 令牌…", #selector(configureToken))])
        ]))
        updates.arrangedSubviews.first?.widthAnchor.constraint(equalTo: updates.widthAnchor).isActive = true
        updater.changed = { [weak self] in self?.refreshUpdateControls() }
        refreshUpdateControls()

        let exclusions = page("排除应用")
        exclusions.addArrangedSubview(row([heading("排除应用"),
            help("列表中的应用不执行再次点击最小化和悬停预览。用＋添加应用；选中行后用−移除，可多选。移除不会删除应用文件。")]))
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
        let updateTab = tabs.selectedTabViewItem?.identifier as? String == "更新"
        let height = updateTab ? 320 : (exclusionTab ? listHeight.constant + 94 : max(260, general.fittingSize.height + 72))
        guard abs(window.contentLayoutRect.height - height) > 1 else { return }
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: 600, height: height))
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
    }
    func updateEngineStatus() {
        let text = appDelegate?.engine.running == true ? "运行中" : "已暂停"
        guard engineStatus.stringValue != text else { return }
        engineStatus.stringValue = text
        engineStatus.textColor = appDelegate?.engine.running == true ? .systemGreen : .secondaryLabelColor
        if window?.isVisible == true { resizeWindow() }
    }
    func refreshControls() {
        updateEngineStatus()
        enableAtLaunch.state = appDelegate?.enableAtLaunch == true ? .on : .off
        let trusted = AXIsProcessTrusted()
        permissionStatus.stringValue = trusted ? "✓ 已授权" : "需要授权"
        permissionStatus.textColor = trusted ? .systemGreen : .secondaryLabelColor
        let captureAllowed = CGPreflightScreenCaptureAccess()
        captureStatus.stringValue = captureAllowed ? "✓ 已授权" : "需要授权"
        captureStatus.textColor = captureAllowed ? .systemGreen : .secondaryLabelColor
        let status = SMAppService.mainApp.status
        login.state = status == .enabled ? .on : .off
        loginLabel.stringValue = status == .requiresApproval ? "登录时启动（等待批准）" : "登录时启动"
    }
    private func page(_ title: String) -> NSStackView {
        let item = NSTabViewItem(identifier: title); item.label = title
        let container = NSView(); let stack = NSStackView()
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
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
    private func settingsRow(_ title: String, detail: String, trailing: NSView) -> NSStackView {
        settingsRow(NSTextField(labelWithString: title), detail: detail, trailing: trailing)
    }
    private func settingsRow(_ title: NSTextField, detail: String, trailing: NSView) -> NSStackView {
        title.font = .systemFont(ofSize: 13, weight: .medium)
        let subtitle = NSTextField(wrappingLabelWithString: detail)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.preferredMaxLayoutWidth = 310
        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 5
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        let result = row([labels, trailing])
        result.distribution = .fill
        result.spacing = 16
        return result
    }
    private func settingsCard(_ title: String, rows: [NSView]) -> NSStackView {
        let label = heading(title)
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 12, weight: .medium)
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        for (index, view) in rows.enumerated() {
            if index > 0 {
                let divider = NSBox()
                divider.boxType = .separator
                content.addArrangedSubview(divider)
                divider.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
            }
            content.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        }
        let card = NSBox()
        card.boxType = .custom
        card.titlePosition = .noTitle
        card.borderWidth = 0.5
        card.borderColor = .separatorColor
        card.fillColor = .controlBackgroundColor
        card.cornerRadius = 10
        card.contentViewMargins = NSSize(width: 16, height: 16)
        card.contentView = content
        let section = NSStackView(views: [label, card])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        card.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
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
    private func refreshUpdateControls() {
        updateStatus.stringValue = updater.status
        checkUpdate.isEnabled = !updater.busy
        installUpdate.isEnabled = updater.canInstall
    }
    @objc private func checkForUpdates() { updater.check() }
    @objc private func installLatest() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "安装更新并重启 MiniDock？"
        alert.informativeText = "将覆盖当前运行的应用，完成后清理旧应用和下载临时文件。"
        alert.addButton(withTitle: "更新并重启")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.updater.install() }
        }
    }
    @objc private func configureToken() {
        guard let window, !updater.busy else { return }
        let alert = NSAlert()
        alert.messageText = "GitHub 访问令牌"
        alert.informativeText = "私有仓库需要具有 Royce-80457/MiniDock 的 Contents 读取权限的令牌。令牌保存在 macOS 钥匙串。留空保存可移除已存令牌。"
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "GitHub personal access token"
        alert.accessoryView = field
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do { try self.updater.saveToken(field.stringValue); self.updater.check() }
            catch { self.updateStatus.stringValue = error.localizedDescription }
            field.stringValue = ""
        }
    }
    @objc private func copyLogs() { appDelegate?.copyLogs() }
    @objc private func clearLogs() { appDelegate?.clearLogs() }
    @objc private func refresh() { refreshControls() }
    @objc private func toggleLogin() { appDelegate?.toggleLogin(); refreshControls() }
    @objc private func openLogin() { appDelegate?.openLogin() }
    @objc private func requestAX() { appDelegate?.requestAX(); refreshControls() }
    @objc private func openAX() { appDelegate?.openAX() }
    @objc private func requestInput() { appDelegate?.requestInput() }
    @objc private func toggleEnableAtLaunch() {
        appDelegate?.enableAtLaunch = enableAtLaunch.state == .on
    }
    @objc private func requestCapture() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        refreshControls()
    }
}
