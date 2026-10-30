import XCTest
@testable import ToggleCore

final class InteractionPolicyTests: XCTestCase {
    func testNewInputCancelsDeferredClickEvenInsideHandoffInterval() {
        XCTAssertTrue(DeferredClickPolicy.accepts(elapsed: 0.05, unchangedInput: true, stable: true))
        XCTAssertFalse(DeferredClickPolicy.accepts(elapsed: 0.05, unchangedInput: false, stable: true))
    }
    func testSpaceOrSettingsChangeAndLateCallbacksCannotApplyOldClick() {
        XCTAssertFalse(DeferredClickPolicy.accepts(elapsed: 0.05, unchangedInput: true, stable: false))
        XCTAssertFalse(DeferredClickPolicy.accepts(elapsed: 0.201, unchangedInput: true, stable: true))
        XCTAssertFalse(DeferredClickPolicy.accepts(elapsed: -0.1, unchangedInput: true, stable: true))
    }
    func testTransientFalseCanBeConfirmedWithoutAnotherWrite() {
        XCTAssertEqual(MinimizeReadbackPolicy.decide(.notMinimized, attempt: 1), .retryRead)
        XCTAssertEqual(MinimizeReadbackPolicy.decide(.notMinimized, attempt: 2), .retryRead)
        XCTAssertEqual(MinimizeReadbackPolicy.decide(.minimized, attempt: 3), .confirmed)
    }
    func testPersistentlyVisibleWindowStillPauses() {
        XCTAssertEqual(MinimizeReadbackPolicy.decide(.notMinimized, attempt: 3), .pause)
    }
    func testMixedTimeoutsAndFalseShareOneThreeReadBudget() {
        XCTAssertEqual(MinimizeReadbackPolicy.decide(.communicationFailure, attempt: 1), .retryRead)
        XCTAssertEqual(MinimizeReadbackPolicy.decide(.notMinimized, attempt: 2), .retryRead)
        XCTAssertEqual(MinimizeReadbackPolicy.decide(.communicationFailure, attempt: 3), .pause)
    }
    func testUnknownFatalAndInvalidAttemptsNeverExtendConfirmation() {
        for attempt in 1...3 {
            XCTAssertEqual(MinimizeReadbackPolicy.decide(.unknown, attempt: attempt), .pause)
            XCTAssertEqual(MinimizeReadbackPolicy.decide(.fatalFailure, attempt: attempt), .pause)
        }
        XCTAssertEqual(MinimizeReadbackPolicy.decide(.notMinimized, attempt: 0), .pause)
        XCTAssertEqual(MinimizeReadbackPolicy.decide(.minimized, attempt: 4), .pause)
    }
}
