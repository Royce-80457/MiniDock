import Foundation
import CoreGraphics

public enum WindowGeometry {
    /// Allow ordinary windows touching the work-area edge. A full-display window
    /// remains ambiguous/fullscreen even when menu bar and Dock are auto-hidden.
    public static func allows(_ window: CGRect, display: CGRect, workArea: CGRect) -> Bool {
        guard window.width > 0, window.height > 0,
              window.minX.isFinite, window.minY.isFinite,
              window.width.isFinite, window.height.isFinite,
              workArea.contains(window) else { return false }
        let coversDisplay = abs(window.minX - display.minX) <= 2
            && abs(window.minY - display.minY) <= 2
            && abs(window.maxX - display.maxX) <= 2
            && abs(window.maxY - display.maxY) <= 2
        return !coversDisplay
    }
}
