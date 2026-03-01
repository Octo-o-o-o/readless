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

    @MainActor
    func testSelectedResultIndexState() {
        let coordinator = AICoordinator()
        XCTAssertEqual(coordinator.selectedResultIndex, 0)

        coordinator.selectedResultIndex = 2
        XCTAssertEqual(coordinator.selectedResultIndex, 2)
    }

    @MainActor
    func testLoadingState() {
        let coordinator = AICoordinator()
        XCTAssertFalse(coordinator.isLoading)

        coordinator.isLoading = true
        XCTAssertTrue(coordinator.isLoading)
    }

    @MainActor
    func testErrorMessageState() {
        let coordinator = AICoordinator()
        XCTAssertNil(coordinator.errorMessage)

        coordinator.errorMessage = "Test error"
        XCTAssertEqual(coordinator.errorMessage, "Test error")
    }
}
