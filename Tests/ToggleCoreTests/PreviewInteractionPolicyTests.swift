import XCTest
@testable import ToggleCore

final class PreviewInteractionPolicyTests: XCTestCase {
    func testMouseDownInsidePreviewSurvivesEveryTimerTickUntilRelease() {
        for _ in 0..<10 {
            XCTAssertTrue(PreviewInteractionPolicy.preservesClick(mousePressed: true, pointerInPanel: true, panelVisible: true))
        }
        XCTAssertFalse(PreviewInteractionPolicy.preservesClick(mousePressed: false, pointerInPanel: true, panelVisible: true))
        XCTAssertFalse(PreviewInteractionPolicy.preservesClick(mousePressed: true, pointerInPanel: false, panelVisible: true))
        XCTAssertFalse(PreviewInteractionPolicy.preservesClick(mousePressed: true, pointerInPanel: true, panelVisible: false))
    }

    func testFocusWaitsForRestorationAndApplicationActivation() {
        XCTAssertEqual(decide(minimized: true, frontmost: false), .wait)
        XCTAssertEqual(decide(minimized: nil), .wait)
        XCTAssertEqual(decide(frontmost: false), .wait)
        XCTAssertEqual(decide(), .focus)
    }

    func testRaiseSuccessAloneDoesNotConfirmFocus() {
        XCTAssertEqual(decide(focusRequests: 1), .focus)
        XCTAssertEqual(decide(focusRequests: 3), .wait)
        XCTAssertEqual(decide(focused: true, focusRequests: 1), .confirmed)
        XCTAssertEqual(decide(frontmost: false, focused: true, focusRequests: 1), .wait)
        XCTAssertEqual(decide(focused: true), .focus)
    }

    func testNewInputClosedWindowAndDeadlineEndTheRequest() {
        XCTAssertEqual(decide(unchangedInput: false), .cancelled)
        XCTAssertEqual(decide(targetExists: false), .cancelled)
        XCTAssertEqual(decide(elapsed: 1.5), .expired)
    }

    func testCapturedFullscreenWindowCanWaitForItsSpaceToActivate() {
        XCTAssertEqual(PreviewFocusPolicy.decide(elapsed: 2, unchangedInput: true, targetExists: true,
            minimized: false, frontmost: true, focused: false, focusRequests: 0, timeout: 3), .focus)
        XCTAssertEqual(PreviewFocusPolicy.decide(elapsed: 3, unchangedInput: true, targetExists: true,
            minimized: false, frontmost: true, focused: false, focusRequests: 0, timeout: 3), .expired)
    }

    private func decide(elapsed: Double = 0.1, unchangedInput: Bool = true, targetExists: Bool = true,
                        minimized: Bool? = false, frontmost: Bool = true, focused: Bool = false,
                        focusRequests: Int = 0) -> PreviewFocusPolicy.Decision {
        PreviewFocusPolicy.decide(elapsed: elapsed, unchangedInput: unchangedInput, targetExists: targetExists,
            minimized: minimized, frontmost: frontmost, focused: focused, focusRequests: focusRequests)
    }
}
