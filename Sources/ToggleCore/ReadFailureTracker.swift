/// Distinguish a burst of animation-time failures from a sustained fault.
/// Pause only after at least three failures spanning two seconds. Successful
/// validation or a gap longer than five seconds resets the sequence.
public struct ReadFailureTracker {
    private var count = 0
    private var firstFailure: Double?
    private var lastFailure: Double?
    public init() {}
    public mutating func reset() { count = 0; firstFailure = nil; lastFailure = nil }
    public mutating func shouldPause(at time: Double) -> Bool {
        if let lastFailure, time >= lastFailure, time - lastFailure <= 5 {
            count += 1
        } else {
            count = 1
            firstFailure = time
        }
        lastFailure = time
        return count >= 3 && time - (firstFailure ?? time) >= 2
    }
}
