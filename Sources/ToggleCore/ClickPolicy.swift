import Foundation

/// Conservative gesture gate; all times are monotonic, in seconds.
public struct ClickPolicy {
    public static func accepts(duration: Double, distance: Double, clickCount: Int64,
                               modified: Bool, dragged: Bool, stable: Bool) -> Bool {
        duration >= 0 && duration <= 0.25 && distance <= 4 && clickCount == 1
            && !modified && !dragged && stable
    }
}
