import XCTest
@testable import AIServices

final class AICoordinatorTests: XCTestCase {
    @MainActor
    func testShowCommandBar() {
        let coordinator = AICoordinator()
        XCTAssertFalse(coordinator.isCommandBarVisible)

        coordinator.showCommandBar()
        XCTAssertTrue(coordinator.isCommandBarVisible)
    }

    @MainActor
    func testHideCommandBar() {
        let coordinator = AICoordinator()
        coordinator.showCommandBar()
        coordinator.hideCommandBar()

        XCTAssertFalse(coordinator.isCommandBarVisible)
    }
}
