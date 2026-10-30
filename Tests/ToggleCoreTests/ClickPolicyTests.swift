import XCTest
@testable import ToggleCore

final class ClickPolicyTests: XCTestCase {
    func testShortStationaryClick() {
        XCTAssertTrue(accepts())
    }
    func testLongPressDragModifiersAndMultipleClicksPassThrough() {
        XCTAssertFalse(accepts(duration: 0.26))
        XCTAssertFalse(accepts(distance: 5))
        XCTAssertFalse(accepts(dragged: true))
        XCTAssertFalse(accepts(modified: true))
        XCTAssertFalse(accepts(count: 2))
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
