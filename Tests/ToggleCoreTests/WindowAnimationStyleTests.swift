import XCTest
@testable import ToggleCore

final class WindowAnimationStyleTests: XCTestCase {
    func testNativeChineseAndEnglishLabelsMatchOnlyTheirOwnEffect() {
        XCTAssertEqual(WindowAnimationStyle(systemLabel: "神奇效果"), .genie)
        XCTAssertEqual(WindowAnimationStyle(systemLabel: "缩放效果"), .scale)
        XCTAssertEqual(WindowAnimationStyle(systemLabel: " Genie Effect\n"), .genie)
        XCTAssertEqual(WindowAnimationStyle(systemLabel: "Scale effect"), .scale)
    }
    func testUnknownOptionsNeverBecomeADifferentEffectOrDisableAnimations() {
        for label in ["", "无动画", "None", "suck", "神奇", "Default", "Genie Effect…"] {
            XCTAssertNil(WindowAnimationStyle(systemLabel: label))
        }
    }
}
