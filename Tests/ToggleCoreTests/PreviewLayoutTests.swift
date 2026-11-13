import XCTest
@testable import ToggleCore

final class PreviewLayoutTests: XCTestCase {
    func testOverflowUsesScrollableListWithoutDroppingWindows() {
        let available = CGSize(width: 1440, height: 900)
        XCTAssertFalse(PreviewLayout(count: 6, available: available).usesList)
        let overflow = PreviewLayout(count: 7, available: available)
        XCTAssertTrue(overflow.usesList)
        let many = PreviewLayout(count: 100, available: available)
        XCTAssertLessThanOrEqual(many.size.height, available.height - 16)
        XCTAssertEqual(many.itemHeight, 38)
    }

    func testPreviewStaysOnNegativeCoordinateDisplay() {
        let screen = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let visible = screen.insetBy(dx: 0, dy: 30)
        for x in [-1900.0, -960, -40] {
            let frame = PreviewLayout.frame(size: CGSize(width: 700, height: 182),
                anchor: CGRect(x: x, y: -290, width: 40, height: 50), screen: screen, visible: visible)
            XCTAssertTrue(visible.contains(frame))
            XCTAssertGreaterThan(frame.minY, -240)
        }
    }

    func testVerticalDocksPlacePreviewInward() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let left = PreviewLayout.frame(size: CGSize(width: 464, height: 182),
            anchor: CGRect(x: 0, y: 400, width: 60, height: 60), screen: screen,
            visible: CGRect(x: 70, y: 0, width: 1370, height: 870))
        XCTAssertGreaterThanOrEqual(left.minX, 70)
        let right = PreviewLayout.frame(size: CGSize(width: 464, height: 182),
            anchor: CGRect(x: 1380, y: 400, width: 60, height: 60), screen: screen,
            visible: CGRect(x: 0, y: 0, width: 1370, height: 870))
        XCTAssertLessThanOrEqual(right.maxX, 1370)
    }

    func testAutoHiddenVerticalDockStillPlacesPreviewBesideIcon() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = PreviewLayout.frame(size: CGSize(width: 464, height: 182),
            anchor: CGRect(x: 0, y: 400, width: 60, height: 60), screen: screen, visible: screen)
        XCTAssertEqual(frame.minX, 70)
        XCTAssertEqual(frame.midY, 430)
    }
}
