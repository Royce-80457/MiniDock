import AppKit
import ApplicationServices
import ToggleCore

final class Engine {
    struct Pending {
        let pid: pid_t
        let window: AXUIElement
        let point: CGPoint
        let timestamp: UInt64
        let generation: Int
    }
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: Pending?
    private var generation = 0
    private var quietUntil = 0.0
    private var lastAction = 0.0
    private var observers: [NSObjectProtocol] = []
    private var healthTimer: Timer?
    private let verificationQueue = DispatchQueue(label: "local.royce.MiniToggle.verification")
    private var verificationID: UUID?
    private var readFailures = ReadFailureTracker()
    var experimental = false {
        didSet {
            invalidate()
            if running { status = experimental ? "实验运行中" : "观察中"; changed?() }
        }
    }
    var excluded: Set<String> = [] { didSet { invalidate() } }
    private(set) var running = false
    private(set) var status = "已暂停"
    private(set) var records: [String] = []
    var changed: (() -> Void)?
    private var now: Double { ProcessInfo.processInfo.systemUptime }

    init() {
        AXUIElementSetMessagingTimeout(AX.system, 0.05)
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] note in self?.invalidate(note.name.rawValue)
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.invalidate("display-change") })
    }
    func invalidate(_ reason: String = "settings-change") {
        if pending != nil { record("cancel candidate reason=\(reason)") }
        pending = nil
        generation += 1
        quietUntil = now + 0.4
    }
    func record(_ message: String) {
        records.append(String(format: "%.3f %@", now, message))
        if records.count > 200 { records.removeFirst(records.count - 200) }
        changed?()
    }
    func clearRecords() { records.removeAll(); changed?() }
    func start() {
        stop()
        readFailures.reset()
        guard AXIsProcessTrusted() else { stop("缺少辅助功能权限"); return }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                   .rightMouseDown, .otherMouseDown, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                if let context {
                    Unmanaged<Engine>.fromOpaque(context).takeUnretainedValue().receive(type, event)
                }
                // Passive tap: never modifies, suppresses, replays, or synthesizes input.
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            stop("无法监听鼠标；检查权限后手动重试"); return
        }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        guard let source else { stop("无法创建事件源"); return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        running = true
        status = experimental ? "实验运行中" : "观察中"
        invalidate()
        healthTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
        record("started; experimental=\(experimental)")
    }
    func stop(_ reason: String = "已暂停") {
        pending = nil
        verificationID = nil
        running = false
        healthTimer?.invalidate()
        healthTimer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        status = reason
        record("stopped reason=\(reason)")
    }
    func checkHealth() {
        guard running else { return }
        guard AXIsProcessTrusted() else { stop("辅助功能权限已撤销；已暂停"); return }
        guard let tap, CGEvent.tapIsEnabled(tap: tap) else { stop("事件监听已失效；已暂停"); return }
    }

    private func receive(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stop("事件监听被系统停用 type=\(type.rawValue)；已暂停")
            return
        }
        guard running else { return }
        guard AXIsProcessTrusted() else { stop("辅助功能权限已撤销；已暂停"); return }
        let began = now
        defer {
            let elapsed = now - began
            if elapsed >= 0.12 {
                record("event processing slow type=\(type.rawValue) elapsedMs=\(Int(elapsed * 1000))")
            }
        }
        let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn, .maskAlphaShift]
        var phase = "input"
        do {
            switch type {
            case .leftMouseDown:
                pending = nil
                // A later native click may restore the window. Its state must not
                // be mistaken for a restore race caused by the earlier click.
                if verificationID != nil {
                    verificationID = nil
                    record("readback cancelled by subsequent click; earlier final state unknown")
                }
                guard let front = NSWorkspace.shared.frontmostApplication else { return }
                // Freeze the down-time frontmost PID before hit testing. Do not
                // query an unrelated app's focused window on every desktop click.
                phase = "down.hitTest"
                guard let target = try AX.dockApplication(at: event.location) else { return }
                let clickCount = event.getIntegerValueField(.mouseEventClickState)
                record("dock-down app=\(target.bundleIdentifier ?? "unknown") target=\(target.processIdentifier) front=\(front.processIdentifier) clickCount=\(clickCount)")
                guard target.processIdentifier == front.processIdentifier else {
                    record("pass background-click target=\(target.processIdentifier) front=\(front.processIdentifier)")
                    return
                }
                guard event.flags.intersection(modifiers).isEmpty else { record("skip down reason=modifier"); return }
                guard clickCount == 1 else { record("skip down reason=multi-click count=\(clickCount)"); return }
                guard now >= quietUntil else { record("skip down reason=activation-or-space-settling"); return }
                guard now - lastAction > 0.5 else { record("skip down reason=post-minimize-cooldown"); return }
                guard let id = target.bundleIdentifier else {
                    record("skip missing-bundle-id pid=\(target.processIdentifier)")
                    return
                }
                guard !excluded.contains(id) else { record("skip excluded pid=\(target.processIdentifier)"); return }
                phase = "down.focus"
                let focus = try AX.focusEvidence(target.processIdentifier)
                guard focus.allows(target: target.processIdentifier, workspace: front.processIdentifier) else {
                    record("skip down reason=focus-unconfirmed workspace=\(front.processIdentifier) \(focus.details)")
                    return
                }
                if focus.systemPID == nil { record("focus confirmed via AXFrontmost pid=\(target.processIdentifier) \(focus.details)") }
                let window = try AX.focusedWindow(front.processIdentifier)
                guard let window else { record("skip no-focused-window pid=\(target.processIdentifier)"); return }
                phase = "down.eligibility"
                let eligibility = try AX.eligibility(window)
                let elapsed = now - began
                guard eligibility.allowed, elapsed < 0.12 else {
                    record("skip down pid=\(target.processIdentifier) reasons=\(eligibility.reasons.joined(separator: ",")) budgetExceeded=\(elapsed >= 0.12) elapsedMs=\(Int(elapsed * 1000)) \(eligibility.details)")
                    return
                }
                pending = Pending(pid: target.processIdentifier, window: window, point: event.location,
                                  timestamp: event.timestamp, generation: generation)
                record("candidate pid=\(target.processIdentifier) window-snapshot=down")
            case .leftMouseUp:
                guard let candidate = pending else { return }
                pending = nil
                phase = "up.revalidate"
                let duration = event.timestamp >= candidate.timestamp
                    ? Double(event.timestamp - candidate.timestamp) / 1_000_000_000 : -1
                let distance = hypot(event.location.x - candidate.point.x, event.location.y - candidate.point.y)
                guard ClickPolicy.accepts(duration: duration, distance: distance,
                    clickCount: event.getIntegerValueField(.mouseEventClickState),
                    modified: !event.flags.intersection(modifiers).isEmpty, dragged: false,
                    stable: generation == candidate.generation && now >= quietUntil) else {
                    record("skip up reason=gesture durationMs=\(Int(duration * 1000)) distance=\(distance) clickCount=\(event.getIntegerValueField(.mouseEventClickState)) modified=\(!event.flags.intersection(modifiers).isEmpty) stable=\(generation == candidate.generation && now >= quietUntil)")
                    return
                }
                guard let target = try AX.dockApplication(at: event.location), target.processIdentifier == candidate.pid,
                    NSWorkspace.shared.frontmostApplication?.processIdentifier == candidate.pid else {
                    record("skip up reason=target-or-workspace-changed")
                    return
                }
                let focus = try AX.focusEvidence(candidate.pid)
                guard focus.allows(target: candidate.pid, workspace: NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
                    record("skip up reason=focus-unconfirmed \(focus.details)")
                    return
                }
                guard
                    let current = try AX.focusedWindow(candidate.pid), CFEqual(current, candidate.window) else {
                    record("skip changed gesture/window/app/space")
                    return
                }
                phase = "up.eligibility"
                let eligibility = try AX.eligibility(current)
                let elapsed = now - began
                guard eligibility.allowed, elapsed < 0.12 else {
                    record("skip up pid=\(candidate.pid) reasons=\(eligibility.reasons.joined(separator: ",")) budgetExceeded=\(elapsed >= 0.12) elapsedMs=\(Int(elapsed * 1000)) \(eligibility.details)")
                    return
                }
                readFailures.reset()
                guard experimental else { record("would-minimize pid=\(candidate.pid) (observe only)"); return }
                guard AXIsProcessTrusted() else { stop("辅助功能权限已撤销；已暂停"); return }
                let error = AXUIElementSetAttributeValue(current, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                guard error == .success else { stop("最小化失败 \(error.rawValue)；已暂停"); return }
                lastAction = now
                record("minimize-request accepted pid=\(candidate.pid); not proof of final Dock state")
                let verification = UUID()
                verificationID = verification
                scheduleReadback(current, id: verification, attempt: 1, actionTime: now)
            default:
                if pending != nil { record("cancel candidate reason=input-event type=\(type.rawValue)") }
                pending = nil // Any drag, right/other click, or modifier transition cancels.
            }
        } catch {
            pending = nil
            record("AX read failure phase=\(phase) \(error)")
            guard AXIsProcessTrusted() else { stop("辅助功能权限已撤销；已暂停"); return }
            if let failure = error as? AXFailure, failure.code == .invalidUIElement {
                // A closed/replaced window is no longer a candidate. Never retry
                // this click against a newly focused window.
                record("skip stale AX element; click passed through")
                return
            }
            if let failure = error as? AXFailure, failure.code == .cannotComplete {
                if !readFailures.shouldPause(at: now) {
                    record("skip transient AX communication failure; click passed through")
                    return
                }
                stop("辅助功能持续通信失败；已暂停")
                return
            }
            stop("辅助功能读取失败 \(error)；已暂停")
        }
    }

    /// At most three reads after one write. Never re-minimize to mask a restore.
    /// Only cannotComplete (communication failure/timeout) is retried. AX objects
    /// that become invalid are not replaced with a different application window.
    private func scheduleReadback(_ window: AXUIElement, id: UUID, attempt: Int, actionTime: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.running, self.verificationID == id else { return }
            guard AXIsProcessTrusted() else { self.stop("辅助功能权限已撤销；已暂停"); return }
            self.verificationQueue.async {
                let timeoutError = AXUIElementSetMessagingTimeout(window, 0.1)
                let result: Result<Bool?, Error>
                if timeoutError != .success {
                    result = .failure(AXFailure(timeoutError, operation: "setReadbackTimeout"))
                } else {
                    result = Result { try AX.bool(window, kAXMinimizedAttribute) }
                }
                // Do not let a verification timeout leak into later event checks.
                AXUIElementSetMessagingTimeout(window, 0)
                DispatchQueue.main.async {
                    guard self.running, self.verificationID == id else { return }
                    guard AXIsProcessTrusted() else { self.stop("辅助功能权限已撤销；已暂停"); return }
                    let elapsed = Int((self.now - actionTime) * 1000)
                    switch result {
                    case .success(let minimized):
                        self.verificationID = nil
                        self.record("readback attempt=\(attempt) elapsedMs=\(elapsed) minimized=\(String(describing: minimized))")
                        if minimized != true { self.stop("检测到恢复竞争或最小化状态未知；已暂停") }
                    case .failure(let error):
                        self.record("readback failure attempt=\(attempt) elapsedMs=\(elapsed) error=\(error)")
                        if let failure = error as? AXFailure,
                           failure.code == .cannotComplete, attempt < 3 {
                            self.scheduleReadback(window, id: id, attempt: attempt + 1, actionTime: actionTime)
                        } else {
                            self.stop("回读失败 \(error)；已暂停")
                        }
                    }
                }
            }
        }
    }
}
