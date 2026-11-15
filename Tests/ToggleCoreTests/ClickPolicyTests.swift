import XCTest
@testable import ToggleCore

final class ClickPolicyTests: XCTestCase {
    func testShortStationaryClick() {
        XCTAssertTrue(accepts())
    }
    func testRapidClickSequenceRemainsEligible() {
        // macOS increments clickCount during rapid restore/minimize cycles.
        // Each short physical click must remain eligible without waiting for
        // the system double-click interval to expire.
        for count in 1...8 {
            XCTAssertTrue(accepts(duration: 0.04, count: Int64(count)))
        }
    }
    func testRapidClicksStillRequireSafeGestureAndStableState() {
        XCTAssertFalse(accepts(count: 3, modified: true))
        XCTAssertFalse(accepts(count: 3, dragged: true))
        XCTAssertFalse(accepts(count: 3, stable: false))
        XCTAssertFalse(accepts(duration: 0.3, count: 3))
        XCTAssertFalse(accepts(count: 0))
        XCTAssertFalse(accepts(count: -1))
    }
    func testLongPressDragModifiersAndUnstableStatePassThrough() {
        XCTAssertFalse(accepts(duration: 0.26))
        XCTAssertFalse(accepts(distance: 5))
        XCTAssertFalse(accepts(dragged: true))
        XCTAssertFalse(accepts(modified: true))
        XCTAssertFalse(accepts(stable: false))
        XCTAssertFalse(accepts(duration: -0.1))
    }
    private func accepts(duration: Double = 0.1, distance: Double = 0,
                         count: Int64 = 1, modified: Bool = false,
                         dragged: Bool = false, stable: Bool = true) -> Bool {
        ClickPolicy.accepts(duration: duration, distance: distance, clickCount: count,
                            modified: modified, dragged: dragged, stable: stable)
    }
}

final class ReleaseVersionTests: XCTestCase {
    func testNumericOrdering() {
        XCTAssertLessThan(ReleaseVersion("1.9")!, ReleaseVersion("v1.10.0")!)
        XCTAssertEqual(ReleaseVersion("v1.1.5"), ReleaseVersion("1.1.5.0"))
        XCTAssertLessThan(ReleaseVersion("1.1.5")!, ReleaseVersion("1.1.6")!)
    }
    func testRejectsMalformedAndPrereleaseVersions() {
        for text in ["", "v", "1..2", "1.2-beta", "-1.2", "1.2.3.4.5", "999999999999999999999999"] {
            XCTAssertNil(ReleaseVersion(text), text)
        }
    }
}
