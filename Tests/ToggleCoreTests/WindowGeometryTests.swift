import XCTest
import CoreGraphics
@testable import ToggleCore

final class WindowGeometryTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1200)
    let work = CGRect(x: 0, y: 38, width: 1920, height: 1116)

    func testTopAlignedAndMaximizedOrdinaryWindowsAreAllowed() {
        XCTAssertTrue(WindowGeometry.allows(CGRect(x: 200, y: 38, width: 900, height: 700), display: screen, workArea: work))
        XCTAssertTrue(WindowGeometry.allows(work, display: screen, workArea: work))
    }
    func testFullDisplayWindowsAreSkippedEvenWithAutoHiddenSystemUI() {
        XCTAssertFalse(WindowGeometry.allows(screen, display: screen, workArea: work))
        XCTAssertFalse(WindowGeometry.allows(screen, display: screen, workArea: screen))
        XCTAssertFalse(WindowGeometry.allows(screen.insetBy(dx: 1, dy: 1), display: screen, workArea: screen))
    }
    func testPartiallyOffscreenAndSpanningWindowsAreSkipped() {
        XCTAssertFalse(WindowGeometry.allows(CGRect(x: -10, y: 50, width: 900, height: 700), display: screen, workArea: work))
        XCTAssertFalse(WindowGeometry.allows(CGRect(x: 1500, y: 50, width: 900, height: 700), display: screen, workArea: work))
    }
    func testNegativeCoordinateDisplay() {
        let display = CGRect(x: -1920, y: -1200, width: 1920, height: 1200)
        let area = CGRect(x: -1920, y: -1162, width: 1920, height: 1116)
        XCTAssertTrue(WindowGeometry.allows(CGRect(x: -1700, y: -1162, width: 900, height: 700), display: display, workArea: area))
        XCTAssertFalse(WindowGeometry.allows(display, display: display, workArea: area))
    }
}
