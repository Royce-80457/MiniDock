import AppKit
import ApplicationServices
import ScreenCaptureKit
import ToggleCore

struct PreviewWindow {
    let element: AXUIElement?
    let title: String
    let frame: CGRect?
    let minimized: Bool
    var captureID: CGWindowID? = nil

    func isSameWindow(as other: PreviewWindow) -> Bool {
        if let captureID, let otherID = other.captureID { return captureID == otherID }
        guard let element, let otherElement = other.element else { return false }
        return CFEqual(element, otherElement)
    }

    static func fullscreenWindows(in content: SCShareableContent, pid: pid_t, displays: [CGRect]) -> [PreviewWindow] {
        content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer == 0
                && PreviewWindowMatch.isDisplaySized($0.frame, displays: displays)
        }.map {
            PreviewWindow(element: nil, title: $0.title ?? "", frame: $0.frame, minimized: false, captureID: $0.windowID)
        }
    }

    static func windows(for pid: pid_t, including retained: [AXUIElement] = []) -> [PreviewWindow] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var elements = (try? AX.read(app, kAXWindowsAttribute)) as? [AXUIElement] ?? []
        // AppKit can omit other-Space windows from AXWindows while still
        // exposing the last focused/main window through these attributes.
        for key in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            if let window = try? AX.element(app, key), !elements.contains(where: { CFEqual($0, window) }) {
                elements.append(window)
            }
        }
        for window in retained where !elements.contains(where: { CFEqual($0, window) }) {
            elements.append(window)
        }
        return elements.compactMap { element in
            AXUIElementSetMessagingTimeout(element, 0.25)
            guard (try? AX.string(element, kAXRoleAttribute)) == kAXWindowRole,
                  let subrole = try? AX.string(element, kAXSubroleAttribute),
                  [kAXStandardWindowSubrole, kAXDialogSubrole].contains(subrole) else { return nil }
            return PreviewWindow(element: element, title: (try? AX.string(element, kAXTitleAttribute)) ?? "",
                                 frame: try? AX.frame(element), minimized: (try? AX.bool(element, kAXMinimizedAttribute)) == true)
        }
    }

    // Public AX has no window-ID accessor. Require a unique match in both
    // directions, allowing full-screen Space animation to shift capture origins.
    func captureWindow(in windows: [SCWindow], siblings: [PreviewWindow]) -> SCWindow? {
        if let captureID { return windows.first { $0.windowID == captureID } }
        guard let index = siblings.firstIndex(where: { isSameWindow(as: $0) }),
              let capture = PreviewWindowMatch.captureIndex(for: index,
                  windows: siblings.map { PreviewWindowMatch(title: $0.title, frame: $0.frame) },
                  captures: windows.map { PreviewWindowMatch(title: $0.title ?? "", frame: $0.frame) },
                  displays: NSScreen.screens.map(\.frame)) else { return nil }
        return windows[capture]
    }

}
