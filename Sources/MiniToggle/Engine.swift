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
    /// Counts only, never key codes or event contents. Unlike the tap callback,
    /// these counters can also notice input waiting while AX is being queried.
    private struct InputStamp: Equatable {
        let counts: [UInt32]
        static func capture() -> InputStamp {
            let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .rightMouseDown,
                .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                .flagsChanged, .keyDown, .scrollWheel]
            return InputStamp(counts: types.map {
                CGEventSource.counterForEventType(.combinedSessionState, eventType: $0)
            })
        }
    }
    private var deferredActionID: UUID?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pending: Pending?
    private var generation = 0
    private var quietUntil = 0.0
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
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                // Activation cancels an in-progress gesture. The next click has
                // its own down-time foreground/window checks; no fixed delay.
                self?.invalidate(note.name.rawValue, settlingDelay: 0)
            })
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] note in self?.invalidate(note.name.rawValue)
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.invalidate("display-change") })
    }
    func invalidate(_ reason: String = "settings-change", settlingDelay: Double = 0.4) {
        if pending != nil { record("cancel candidate reason=\(reason)") }
        pending = nil
        cancelDeferred("state-change: \(reason)")
        verificationID = nil
        generation += 1
        // Activation must not shorten a Space/display transition's quiet time.
        quietUntil = max(quietUntil, now + settlingDelay)
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
        deferredActionID = nil
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
        cancelDeferred("new-input type=\(type.rawValue)")
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
                guard clickCount >= 1 else { record("skip down reason=invalid-click-count count=\(clickCount)"); return }
                guard now >= quietUntil else { record("skip down reason=transition-settling"); return }
                guard let id = target.bundleIdentifier else {
                    record("skip missing-bundle-id pid=\(target.processIdentifier)")
                    return
                }
                guard !excluded.contains(id) else { record("skip excluded pid=\(target.processIdentifier)"); return }
                // Query the target app once. Global AXFocusedApplication often
                // times out or is absent even when this app confirms active.
                phase = "down.snapshot"
                let snapshotBegan = now
                let snapshot = try AX.appWindowSnapshot(target.processIdentifier)
                record("app-snapshot phase=down pid=\(target.processIdentifier) elapsedMs=\(Int((now - snapshotBegan) * 1000)) frontmost=\(String(describing: snapshot.frontmost)) window=\(snapshot.window != nil)")
                guard snapshot.allows(target: target.processIdentifier, workspace: front.processIdentifier) else {
                    readFailures.reset()
                    record("skip down reason=app-frontmost-unconfirmed")
                    return
                }
                guard let window = snapshot.window else {
                    readFailures.reset()
                    record("skip no-focused-window pid=\(target.processIdentifier)")
                    return
                }
                phase = "down.eligibility"
                let eligibility = try AX.eligibility(window)
                readFailures.reset()
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
                scheduleMinimize(candidate, point: event.location, releasedAt: began, input: InputStamp.capture())
            default:
                if pending != nil { record("cancel candidate reason=input-event type=\(type.rawValue)") }
                pending = nil // Any drag, right/other click, or modifier transition cancels.
            }
        } catch {
            handleReadFailure(error, phase: phase)
        }
    }

    private func handleReadFailure(_ error: Error, phase: String) {
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
                record("skip transient AX communication failure; click passed through; pause requires >=3 failures spanning >=2s")
                return
            }
            stop("辅助功能持续通信失败；已暂停")
            return
        }
        stop("辅助功能读取失败 \(error)；已暂停")
    }

    private func cancelDeferred(_ reason: String) {
        if deferredActionID != nil { record("cancel deferred minimize reason=\(reason)") }
        deferredActionID = nil
    }

    private func scheduleMinimize(_ candidate: Pending, point: CGPoint, releasedAt: Double, input: InputStamp) {
        let id = UUID()
        deferredActionID = id
        record("defer minimize pid=\(candidate.pid) handoff=next-main-turn")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.deferredActionID == id else { return }
            defer { if self.deferredActionID == id { self.deferredActionID = nil } }
            let began = self.now
            func stillValid() -> Bool {
                DeferredClickPolicy.accepts(elapsed: self.now - releasedAt,
                    unchangedInput: input == InputStamp.capture(),
                    stable: self.deferredActionID == id && self.generation == candidate.generation
                        && self.now >= self.quietUntil)
            }
            guard stillValid() else { self.record("skip deferred reason=new-input-state-or-expired"); return }
            self.checkHealth()
            guard self.running else { return }
            var phase = "deferred.target"
            do {
                guard let target = try AX.dockApplication(at: point), target.processIdentifier == candidate.pid,
                      let bundleID = target.bundleIdentifier, !self.excluded.contains(bundleID),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == candidate.pid else {
                    self.record("skip deferred reason=target-or-workspace-changed")
                    return
                }
                phase = "deferred.snapshot"
                let snapshotBegan = self.now
                let snapshot = try AX.appWindowSnapshot(candidate.pid)
                self.record("app-snapshot phase=deferred pid=\(candidate.pid) elapsedMs=\(Int((self.now - snapshotBegan) * 1000)) frontmost=\(String(describing: snapshot.frontmost)) window=\(snapshot.window != nil)")
                guard snapshot.allows(target: candidate.pid,
                    workspace: NSWorkspace.shared.frontmostApplication?.processIdentifier) else {
                    self.record("skip deferred reason=app-frontmost-unconfirmed")
                    return
                }
                guard let current = snapshot.window, CFEqual(current, candidate.window) else {
                    self.record("skip deferred reason=focused-window-changed")
                    return
                }
                phase = "deferred.eligibility"
                let eligibility = try AX.eligibility(current)
                let elapsed = self.now - began
                guard eligibility.allowed, elapsed < 0.12 else {
                    self.record("skip deferred pid=\(candidate.pid) reasons=\(eligibility.reasons.joined(separator: ",")) budgetExceeded=\(elapsed >= 0.12) elapsedMs=\(Int(elapsed * 1000)) \(eligibility.details)")
                    return
                }
                self.readFailures.reset()
                // Recheck after synchronous AX queries: newer input may already
                // exist in WindowServer before the tap can deliver its callback.
                guard stillValid(), NSWorkspace.shared.frontmostApplication?.processIdentifier == candidate.pid else {
                    self.record("skip deferred reason=new-input-state-or-expired-after-query")
                    return
                }
                guard self.experimental else { self.record("would-minimize pid=\(candidate.pid) (observe only)"); return }
                guard AXIsProcessTrusted() else { self.stop("辅助功能权限已撤销；已暂停"); return }
                let error = AXUIElementSetAttributeValue(current, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                guard error == .success else { self.stop("最小化失败 \(error.rawValue)；已暂停"); return }
                self.record("minimize-request accepted pid=\(candidate.pid) handoffElapsedMs=\(Int((self.now - releasedAt) * 1000)); not proof of final Dock state")
                let verification = UUID()
                self.verificationID = verification
                self.scheduleReadback(current, id: verification, attempt: 1, actionTime: self.now, input: input)
            } catch {
                self.handleReadFailure(error, phase: phase)
            }
        }
    }

    /// At most three reads after one write. Never re-minimize to mask a restore.
    /// False may be transitional; confirm it within the same finite read budget.
    /// Only false and cannotComplete are retried. AX objects
    /// that become invalid are not replaced with a different application window.
    private func scheduleReadback(_ window: AXUIElement, id: UUID, attempt: Int, actionTime: Double, input: InputStamp) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.running, self.verificationID == id else { return }
            guard input == InputStamp.capture() else {
                self.verificationID = nil
                self.record("readback cancelled by newer input counter; earlier final state unknown")
                return
            }
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
                    guard input == InputStamp.capture() else {
                        self.verificationID = nil
                        self.record("readback result discarded after newer input; earlier final state unknown")
                        return
                    }
                    guard AXIsProcessTrusted() else { self.stop("辅助功能权限已撤销；已暂停"); return }
                    let elapsed = Int((self.now - actionTime) * 1000)
                    let decision: MinimizeReadbackPolicy.Decision
                    let pauseReason: String
                    switch result {
                    case .success(let minimized):
                        self.record("readback attempt=\(attempt) elapsedMs=\(elapsed) minimized=\(String(describing: minimized))")
                        let observation: MinimizeReadbackPolicy.Observation = minimized == true
                            ? .minimized : (minimized == false ? .notMinimized : .unknown)
                        decision = MinimizeReadbackPolicy.decide(observation, attempt: attempt)
                        pauseReason = minimized == false
                            ? "三次读取后仍未确认最小化：可能存在 Dock 竞争或应用未执行；已暂停"
                            : "最小化状态未知；已暂停"
                    case .failure(let error):
                        self.record("readback failure attempt=\(attempt) elapsedMs=\(elapsed) error=\(error)")
                        let retryable = (error as? AXFailure)?.code == .cannotComplete
                        decision = MinimizeReadbackPolicy.decide(retryable ? .communicationFailure : .fatalFailure, attempt: attempt)
                        pauseReason = "回读失败 \(error)；已暂停"
                    }
                    switch decision {
                    case .confirmed:
                        self.verificationID = nil
                    case .retryRead:
                        self.scheduleReadback(window, id: id, attempt: attempt + 1, actionTime: actionTime, input: input)
                    case .pause:
                        self.verificationID = nil
                        self.stop(pauseReason)
                    }
                }
            }
        }
    }
}
