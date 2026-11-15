import AppKit
import ApplicationServices

final class PreviewWindowStore {
    private struct Application {
        let observer: AXObserver
        let element: AXUIElement
        var windows: [AXUIElement] = []
    }
    private var applications: [pid_t: Application] = [:]
    private var notifications: [NSObjectProtocol] = []
    private var timer: Timer?
    var excluded: Set<String> = [] {
        didSet {
            for pid in Array(applications.keys) {
                if let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, excluded.contains(id) {
                    remove(pid)
                }
            }
        }
    }

    func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification] {
            notifications.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.watch(app)
                }
            })
        }
        notifications.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                    self?.remove(app.processIdentifier)
                }
            })
        sampleForeground()
        // Some apps omit focus notifications during full-screen transitions.
        // Sample only the foreground app's window references as a fallback.
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in self?.sampleForeground() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        notifications.forEach { center.removeObserver($0) }
        notifications.removeAll()
        for pid in Array(applications.keys) { remove(pid) }
    }

    func watch(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular, !app.isTerminated,
              !excluded.contains(app.bundleIdentifier ?? ""), applications[app.processIdentifier] == nil else { return }
        var observer: AXObserver?
        let error = AXObserverCreate(app.processIdentifier, { _, element, notification, context in
            guard let context else { return }
            Unmanaged<PreviewWindowStore>.fromOpaque(context).takeUnretainedValue()
                .receive(element, notification: notification as String)
        }, &observer)
        guard error == .success, let observer else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.05)
        applications[app.processIdentifier] = Application(observer: observer, element: element)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            _ = AXObserverAddNotification(observer, element, name as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        receive(element, notification: kAXFocusedWindowChangedNotification)
        if let windows = try? AX.read(element, kAXWindowsAttribute) as? [AXUIElement] {
            for window in windows { remember(window) }
        }
    }

    func elements(for pid: pid_t) -> [AXUIElement] {
        applications[pid]?.windows ?? []
    }

    private func sampleForeground() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        watch(app)
        if let element = applications[app.processIdentifier]?.element {
            receive(element, notification: kAXFocusedWindowChangedNotification)
            if let windows = try? AX.read(element, kAXWindowsAttribute) as? [AXUIElement] {
                for window in windows { remember(window) }
            }
        }
    }

    private func receive(_ element: AXUIElement, notification: String) {
        if notification == kAXUIElementDestroyedNotification {
            for pid in Array(applications.keys) {
                applications[pid]?.windows.removeAll { CFEqual($0, element) }
            }
            return
        }
        remember(element)
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let app = applications[pid]?.element else { return }
        for key in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = try? AX.element(app, key) { remember(window) }
        }
    }

    private func remember(_ element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let app = applications[pid],
              !app.windows.contains(where: { CFEqual($0, element) }) else { return }
        applications[pid]?.windows.append(element)
        _ = AXObserverAddNotification(app.observer, element, kAXUIElementDestroyedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
    }

    private func remove(_ pid: pid_t) {
        guard let app = applications.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(app.observer), .commonModes)
    }

    deinit { stop() }
}
