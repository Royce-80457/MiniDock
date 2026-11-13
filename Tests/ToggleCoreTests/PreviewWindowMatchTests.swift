import XCTest
@testable import ToggleCore

final class PreviewWindowMatchTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1243)
    private let fullScreen = CGRect(x: 0, y: 38, width: 1920, height: 1205)

    func testUntitledFullscreenWindowMatchesAcrossSpaceAnimation() {
        let source = PreviewWindowMatch(title: "", frame: fullScreen)
        let shifted = PreviewWindowMatch(title: "", frame: fullScreen.offsetBy(dx: -1037, dy: 0))
        let titlebar = PreviewWindowMatch(title: "", frame: CGRect(x: -1037, y: 38, width: 1920, height: 32))
        XCTAssertEqual(match(source, captures: [titlebar, shifted]), 1)
    }

    func testFullscreenSupplementRejectsPlayerControlsAndOrdinaryWindows() {
        XCTAssertTrue(PreviewWindowMatch.isDisplaySized(fullScreen, displays: [display]))
        XCTAssertTrue(PreviewWindowMatch.isDisplaySized(fullScreen.offsetBy(dx: -1920, dy: 0), displays: [display]))
        XCTAssertFalse(PreviewWindowMatch.isDisplaySized(CGRect(x: 0, y: 38, width: 1920, height: 32), displays: [display]))
        XCTAssertFalse(PreviewWindowMatch.isDisplaySized(CGRect(x: 500, y: 140, width: 1000, height: 800), displays: [display]))
    }

    func testUniqueTitleHandlesAWindowChangingGeometry() {
        let source = PreviewWindowMatch(title: "Player", frame: fullScreen)
        let capture = PreviewWindowMatch(title: "Player", frame: CGRect(x: -1700, y: 0, width: 960, height: 600))
        XCTAssertEqual(match(source, captures: [capture]), 0)
    }

    func testDuplicateFullscreenWindowsStayAmbiguousInBothDirections() {
        let source = PreviewWindowMatch(title: "", frame: fullScreen)
        let shifted = PreviewWindowMatch(title: "", frame: fullScreen.offsetBy(dx: -1000, dy: 0))
        XCTAssertNil(match(source, captures: [shifted, shifted]))
        XCTAssertNil(PreviewWindowMatch.captureIndex(for: 0, windows: [source, source], captures: [shifted], displays: [display]))
    }

    func testOrdinaryUntitledWindowsRequireGeometry() {
        let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
        let source = PreviewWindowMatch(title: "", frame: frame)
        XCTAssertEqual(match(source, captures: [source]), 0)
        XCTAssertNil(match(source, captures: [PreviewWindowMatch(title: "", frame: frame.offsetBy(dx: 300, dy: 0))]))
    }

    func testConflictingTitlesAndDuplicateTitlesDoNotSelectAnotherWindow() {
        let source = PreviewWindowMatch(title: "Player", frame: fullScreen)
        XCTAssertNil(match(source, captures: [PreviewWindowMatch(title: "Other", frame: fullScreen)]))
        let changed = PreviewWindowMatch(title: "Player", frame: CGRect(x: -2000, y: 0, width: 500, height: 500))
        XCTAssertNil(match(source, captures: [changed, changed]))
    }

    private func match(_ source: PreviewWindowMatch, captures: [PreviewWindowMatch]) -> Int? {
        PreviewWindowMatch.captureIndex(for: 0, windows: [source], captures: captures, displays: [display])
    }
}
