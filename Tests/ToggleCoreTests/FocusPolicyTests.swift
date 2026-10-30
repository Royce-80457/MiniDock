import XCTest
@testable import ToggleCore

final class FocusPolicyTests: XCTestCase {
    func testAppSnapshotRequiresBothForegroundSourcesToAgree() {
        XCTAssertTrue(FocusPolicy.allowsAppSnapshot(target: 42, workspace: 42, appFrontmost: true))
        XCTAssertFalse(FocusPolicy.allowsAppSnapshot(target: 42, workspace: 7, appFrontmost: true))
        XCTAssertFalse(FocusPolicy.allowsAppSnapshot(target: 42, workspace: nil, appFrontmost: true))
        XCTAssertFalse(FocusPolicy.allowsAppSnapshot(target: 42, workspace: 42, appFrontmost: false))
        XCTAssertFalse(FocusPolicy.allowsAppSnapshot(target: 42, workspace: 42, appFrontmost: nil))
    }
    func testMissingSystemFocusRequiresAffirmativeAppEvidence() {
        XCTAssertTrue(FocusPolicy.allows(target: 42, workspace: 42, system: nil, appFrontmost: true))
        XCTAssertFalse(FocusPolicy.allows(target: 42, workspace: 42, system: nil, appFrontmost: false))
        XCTAssertFalse(FocusPolicy.allows(target: 42, workspace: 42, system: nil, appFrontmost: nil))
    }
    func testBackgroundClickCannotBecomeCandidateAfterActivation() {
        XCTAssertFalse(FocusPolicy.allows(target: 42, workspace: 7, system: 42, appFrontmost: true))
        XCTAssertFalse(FocusPolicy.allows(target: 42, workspace: nil, system: nil, appFrontmost: true))
    }
    func testConflictingSystemFocusIsNeverOverridden() {
        XCTAssertFalse(FocusPolicy.allows(target: 42, workspace: 42, system: 7, appFrontmost: true))
        XCTAssertTrue(FocusPolicy.allows(target: 42, workspace: 42, system: 42, appFrontmost: nil))
    }
}
