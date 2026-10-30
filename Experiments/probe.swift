import AppKit
import ApplicationServices

// Read-only: never requests permission, clicks, or changes windows.
func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var result: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, key as CFString, &result)
    return error == .success ? result : nil
}
print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
print("AX trusted: \(AXIsProcessTrusted())")
print("Listen preflight: \(CGPreflightListenEventAccess())")
print("Frontmost PID: \(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1)")
let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)
let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
    options: .listenOnly, eventsOfInterest: CGEventMask(mask),
    callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil)
print("Passive mouse tap created: \(tap != nil)")
if let tap { CFMachPortInvalidate(tap) }
if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
    let element = AXUIElementCreateApplication(dock.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 0.1)
    var names: CFArray?
    let error = AXUIElementCopyAttributeNames(element, &names)
    print("Dock AX attribute query: \(error.rawValue)")
    print("Dock AX attributes: \(names as? [String] ?? [])")
}
