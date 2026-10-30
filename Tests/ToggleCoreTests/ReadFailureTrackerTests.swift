import XCTest
@testable import ToggleCore

final class ReadFailureTrackerTests: XCTestCase {
    func testRepeatedFailuresPauseButSingleFailureDoesNot() {
        var tracker = ReadFailureTracker()
        XCTAssertFalse(tracker.shouldPause(at: 10))
        XCTAssertFalse(tracker.shouldPause(at: 11))
        XCTAssertTrue(tracker.shouldPause(at: 12))
    }
    func testSuccessfulValidationBreaksFailureSequence() {
        var tracker = ReadFailureTracker()
        XCTAssertFalse(tracker.shouldPause(at: 10))
        XCTAssertFalse(tracker.shouldPause(at: 11))
        tracker.reset()
        XCTAssertFalse(tracker.shouldPause(at: 12))
        XCTAssertFalse(tracker.shouldPause(at: 13))
        XCTAssertTrue(tracker.shouldPause(at: 14))
    }
    func testIsolatedFailuresAndClockResetDoNotAccumulate() {
        var tracker = ReadFailureTracker()
        for time in [10.0, 16, 22, 1, 7] {
            XCTAssertFalse(tracker.shouldPause(at: time))
        }
    }
}
