import AppKit
import ApplicationServices

/// Explicit, read-only diagnostic mode. Does not activate apps or change windows.
func auditWindows() {
    NSApplication.shared.setActivationPolicy(.accessory)
    let trusted = AXIsProcessTrusted()
    print("AX trusted: \(trusted)")
    guard trusted else { return }
    AXUIElementSetMessagingTimeout(AX.system, 0.05)
    let workspacePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    print("workspaceFrontmostPID=\(workspacePID ?? -1)")
    let apps = NSWorkspace.shared.runningApplications.filter {
        $0.bundleIdentifier == "com.apple.Safari"
            || ["ChatGPT", "QQ", "TextEdit", "文本编辑"].contains($0.localizedName ?? "")
    }
    for app in apps {
        print("app=\(app.bundleIdentifier ?? "unknown") pid=\(app.processIdentifier)")
        // Explicit finite, read-only comparison. Timings are per call; no
        // activation, polling, window titles, keyboard contents, or mutations.
        func measure(_ label: String, _ body: () throws -> String) {
            let began = ProcessInfo.processInfo.systemUptime
            do {
                let result = try body()
                print("probe=\(label) elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - began) * 1000)) \(result)")
            } catch {
                print("probe=\(label) elapsedMs=\(Int((ProcessInfo.processInfo.systemUptime - began) * 1000)) \(error)")
            }
        }
        measure("batch-app-window") {
            let snapshot = try AX.appWindowSnapshot(app.processIdentifier)
            return "frontmost=\(String(describing: snapshot.frontmost)) window=\(snapshot.window != nil)"
        }
        measure("focused-window") {
            "window=\(try AX.focusedWindow(app.processIdentifier) != nil)"
        }
        measure("global-focus") {
            "systemPID=\(String(describing: try AX.focusedPID()))"
        }
        do {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            let appFrontmost = try AX.bool(element, kAXFrontmostAttribute)
            print("perAppAXFrontmost=\(appFrontmost.map(String.init) ?? "unavailable")")
            let focus = try AX.focusEvidence(app.processIdentifier)
            print("focusAllowed=\(focus.allows(target: app.processIdentifier, workspace: workspacePID)) \(focus.details)")
            let focusedWindow = try AX.focusedWindow(app.processIdentifier)
            print("focusedWindowWithMatchingOwner=\(focusedWindow != nil)")
            guard let windows = try AX.read(element, kAXWindowsAttribute) as? [AXUIElement] else {
                print("windows unavailable")
                continue
            }
            print("windowCount=\(windows.count)")
            for (index, window) in windows.prefix(3).enumerated() {
                do {
                    let result = try AX.eligibility(window)
                    let focused = try AX.bool(window, kAXFocusedAttribute)
                    print("windowIndex=\(index) perWindowAXFocused=\(String(describing: focused))")
                    print("windowIndex=\(index) allowed=\(result.allowed) reasons=\(result.reasons.joined(separator: ",")) \(result.details)")
                } catch { print("windowIndex=\(index) \(error)") }
            }
        } catch { print(error) }
    }
}
