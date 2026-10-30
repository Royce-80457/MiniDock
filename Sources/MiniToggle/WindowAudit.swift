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
                    print("windowIndex=\(index) allowed=\(result.allowed) reasons=\(result.reasons.joined(separator: ",")) \(result.details)")
                } catch { print("windowIndex=\(index) \(error)") }
            }
        } catch { print(error) }
    }
}
