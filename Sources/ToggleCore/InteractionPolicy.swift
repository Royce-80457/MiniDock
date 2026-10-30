/// Experimental handoff after the native mouse-up; never run an old click late.
public enum DeferredClickPolicy {
    public static let handoffDelay = 0.05
    public static func accepts(elapsed: Double, unchangedInput: Bool, stable: Bool) -> Bool {
        elapsed >= 0 && elapsed <= 0.2 && unchangedInput && stable
    }
}

/// Finite read-only confirmation after one minimize request. No decision asks
/// the caller to write again or to operate on another window.
public enum MinimizeReadbackPolicy {
    public enum Observation { case minimized, notMinimized, unknown, communicationFailure, fatalFailure }
    public enum Decision: Equatable { case confirmed, retryRead, pause }
    public static func decide(_ observation: Observation, attempt: Int) -> Decision {
        guard (1...3).contains(attempt) else { return .pause }
        switch observation {
        case .minimized: return .confirmed
        case .notMinimized, .communicationFailure: return attempt < 3 ? .retryRead : .pause
        case .unknown, .fatalFailure: return .pause
        }
    }
}
