/// Consecutive communication failures inside a short interval indicate a fault.
/// A complete successful click validation or a gap in failures resets the sequence.
public struct ReadFailureTracker {
    private var count = 0
    private var lastFailure: Double?
    public init() {}
    public mutating func reset() { count = 0; lastFailure = nil }
    public mutating func shouldPause(at time: Double) -> Bool {
        if let lastFailure, time >= lastFailure, time - lastFailure <= 5 {
            count += 1
        } else {
            count = 1
        }
        lastFailure = time
        return count >= 3
    }
}
