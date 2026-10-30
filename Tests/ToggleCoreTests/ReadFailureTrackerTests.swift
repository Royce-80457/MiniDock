import XCTest
@testable import ToggleCore

final class ReadFailureTrackerTests: XCTestCase {
    func testReportedAnimationBurstDoesNotPause() {
        var tracker = ReadFailureTracker()
        for time in [344069.740, 344069.963, 344070.132] {
            XCTAssertFalse(tracker.shouldPause(at: time))
        }
    }
    func testFailureDurationMattersRegardlessOfClickSpeed() {
        var tracker = ReadFailureTracker()
        for step in 0..<20 {
            XCTAssertFalse(tracker.shouldPause(at: 10 + Double(step) * 0.1))
        }
        XCTAssertTrue(tracker.shouldPause(at: 12))
    }
    func testRecoveryAfterBurstStartsNewFailureWindow() {
        var tracker = ReadFailureTracker()
        for time in [10.0, 10.2, 10.4] {
            XCTAssertFalse(tracker.shouldPause(at: time))
        }
        tracker.reset()
        for time in [12.0, 12.2, 12.4] {
            XCTAssertFalse(tracker.shouldPause(at: time))
        }
        XCTAssertTrue(tracker.shouldPause(at: 14))
    }
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
