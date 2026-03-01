import XCTest
@testable import AIServices

/// Integration tests for Command Bar components working together end-to-end.
/// These tests verify state flow between AICoordinator, search/results, error handling, and preview panel.
@MainActor
final class CommandBarIntegrationTests: XCTestCase {
    var coordinator: AICoordinator!

    override func setUp() async throws {
        coordinator = AICoordinator()
    }

    override func tearDown() async throws {
        coordinator = nil
    }

    // MARK: - Test 1: Command Bar Visibility Integration

    func testCommandBarOpenCloseFlow() {
        // Initially hidden
        XCTAssertFalse(coordinator.isCommandBarVisible)

        // Open command bar
        coordinator.showCommandBar()
        XCTAssertTrue(coordinator.isCommandBarVisible)

        // Verify state reset on open
        XCTAssertEqual(coordinator.commandQuery, "")
        XCTAssertEqual(coordinator.commandResults.count, 0)

        // Close command bar
        coordinator.hideCommandBar()
        XCTAssertFalse(coordinator.isCommandBarVisible)
    }

    func testSelectionResetOnOpen() {
        // Set selection to non-zero
        coordinator.selectedResultIndex = 3

        // Open command bar (should reset selection)
        coordinator.showCommandBar()

        // Reset happens in UI layer (CommandBarWindow onChange)
        // But we can verify resetSelection() method works
        coordinator.resetSelection()
        XCTAssertEqual(coordinator.selectedResultIndex, 0)
    }

    // MARK: - Test 2: Search Results Integration

    func testSearchResultsUpdateFlow() async {
        // Simulate search results being populated (normally done by CommandBarService)
        let mockResults = [
            CommandResult(title: "Result 1", subtitle: "Subtitle 1", icon: "doc.text") {},
            CommandResult(title: "Result 2", subtitle: "Subtitle 2", icon: "link") {},
            CommandResult(title: "Result 3", subtitle: "Subtitle 3", icon: "folder") {}
        ]

        coordinator.commandResults = mockResults

        // Verify results are stored
        XCTAssertEqual(coordinator.commandResults.count, 3)
        XCTAssertEqual(coordinator.commandResults[0].title, "Result 1")
        XCTAssertEqual(coordinator.commandResults[1].title, "Result 2")
        XCTAssertEqual(coordinator.commandResults[2].title, "Result 3")
    }

    func testNavigationThroughResults() {
        // Populate results
        coordinator.commandResults = [
            CommandResult(title: "A", icon: "1.circle") {},
            CommandResult(title: "B", icon: "2.circle") {},
            CommandResult(title: "C", icon: "3.circle") {}
        ]

        // Start at 0
        XCTAssertEqual(coordinator.selectedResultIndex, 0)

        // Navigate down
        coordinator.selectNextResult()
        XCTAssertEqual(coordinator.selectedResultIndex, 1)

        coordinator.selectNextResult()
        XCTAssertEqual(coordinator.selectedResultIndex, 2)

        // Try to go past end (should clamp)
        coordinator.selectNextResult()
        XCTAssertEqual(coordinator.selectedResultIndex, 2)

        // Navigate up
        coordinator.selectPreviousResult()
        XCTAssertEqual(coordinator.selectedResultIndex, 1)

        coordinator.selectPreviousResult()
        XCTAssertEqual(coordinator.selectedResultIndex, 0)

        // Try to go before start (should clamp)
        coordinator.selectPreviousResult()
        XCTAssertEqual(coordinator.selectedResultIndex, 0)
    }

    func testNavigationWithEmptyResults() {
        // No results
        XCTAssertEqual(coordinator.commandResults.count, 0)

        // Navigation should not crash
        coordinator.selectNextResult()
        XCTAssertEqual(coordinator.selectedResultIndex, 0)

        coordinator.selectPreviousResult()
        XCTAssertEqual(coordinator.selectedResultIndex, 0)
    }

    // MARK: - Test 3: Error Handling Integration

    func testErrorMessageFlow() {
        // No error initially
        XCTAssertNil(coordinator.errorMessage)

        // Set error message
        coordinator.errorMessage = "Network request failed"
        XCTAssertEqual(coordinator.errorMessage, "Network request failed")

        // Clear error message
        coordinator.errorMessage = nil
        XCTAssertNil(coordinator.errorMessage)
    }

    func testErrorClearOnNewSearch() {
        // Simulate error state
        coordinator.errorMessage = "Previous error"

        // New search clears error (simulated - normally done by CommandBarWindow)
        coordinator.errorMessage = nil

        XCTAssertNil(coordinator.errorMessage)
    }

    // MARK: - Test 4: Loading State Integration

    func testLoadingStateFlow() {
        // Not loading initially
        XCTAssertFalse(coordinator.isLoading)

        // Start loading
        coordinator.isLoading = true
        XCTAssertTrue(coordinator.isLoading)

        // Finish loading
        coordinator.isLoading = false
        XCTAssertFalse(coordinator.isLoading)
    }

    func testLoadingStateWithSearchFlow() {
        // Simulate search with loading
        coordinator.isLoading = true

        // Populate results
        coordinator.commandResults = [
            CommandResult(title: "Result", icon: "magnifyingglass") {}
        ]

        // Finish loading
        coordinator.isLoading = false

        XCTAssertFalse(coordinator.isLoading)
        XCTAssertEqual(coordinator.commandResults.count, 1)
    }

    // MARK: - Test 5: Preview Panel Integration

    func testPreviewPanelToggle() {
        // Initially hidden
        XCTAssertFalse(coordinator.showPreviewPanel)

        // Toggle on
        coordinator.showPreviewPanel = true
        XCTAssertTrue(coordinator.showPreviewPanel)

        // Toggle off
        coordinator.showPreviewPanel = false
        XCTAssertFalse(coordinator.showPreviewPanel)
    }

    func testPreviewPanelWithContent() {
        // No content initially
        XCTAssertNil(coordinator.previewContent)

        // Set preview content (mock content)
        // Note: Can't create Content directly without proper initialization
        // In real usage, this would be set by CommandBarService

        // Show preview panel
        coordinator.showPreviewPanel = true
        XCTAssertTrue(coordinator.showPreviewPanel)
    }

    // MARK: - Test 6: Execute Result Integration

    func testExecuteSelectedResult() async {
        var actionExecuted = false

        // Create results with action
        coordinator.commandResults = [
            CommandResult(title: "Action 1", icon: "1.circle") {
                actionExecuted = true
            }
        ]

        // Execute selected result (index 0)
        await coordinator.executeSelectedResult()

        // Verify action was executed
        XCTAssertTrue(actionExecuted)

        // Verify command bar was hidden
        XCTAssertFalse(coordinator.isCommandBarVisible)
    }

    func testExecuteResultOutOfBounds() async {
        // No results
        coordinator.commandResults = []
        coordinator.selectedResultIndex = 5

        // Should not crash
        await coordinator.executeSelectedResult()
    }

    // MARK: - Test 7: Complex Multi-Step Flow

    func testCompleteUserSearchFlow() async {
        // 1. User opens command bar
        coordinator.showCommandBar()
        XCTAssertTrue(coordinator.isCommandBarVisible)
        XCTAssertEqual(coordinator.selectedResultIndex, 0)

        // 2. Search starts (loading)
        coordinator.isLoading = true
        XCTAssertTrue(coordinator.isLoading)

        // 3. Results arrive
        var result1Executed = false
        var result2Executed = false

        coordinator.commandResults = [
            CommandResult(title: "Import clipboard", subtitle: "⌘V", icon: "doc.text") {
                result1Executed = true
            },
            CommandResult(title: "Search content", subtitle: "⌘F", icon: "magnifyingglass") {
                result2Executed = true
            }
        ]

        coordinator.isLoading = false

        // Verify search completed successfully
        XCTAssertFalse(coordinator.isLoading)
        XCTAssertEqual(coordinator.commandResults.count, 2)

        // 4. User navigates with arrow keys
        coordinator.selectNextResult()
        XCTAssertEqual(coordinator.selectedResultIndex, 1)

        // 5. User toggles preview panel
        coordinator.showPreviewPanel = true
        XCTAssertTrue(coordinator.showPreviewPanel)

        // 6. User executes selected result
        await coordinator.executeSelectedResult()

        // Verify result was executed and command bar closed
        XCTAssertTrue(result2Executed)
        XCTAssertFalse(result1Executed)
        XCTAssertFalse(coordinator.isCommandBarVisible)
    }

    func testErrorRecoveryFlow() {
        // 1. User opens command bar
        coordinator.showCommandBar()

        // 2. Search fails with error
        coordinator.isLoading = true
        coordinator.errorMessage = "Network timeout"
        coordinator.isLoading = false

        XCTAssertEqual(coordinator.errorMessage, "Network timeout")

        // 3. User tries new search (error should clear)
        coordinator.errorMessage = nil
        coordinator.isLoading = true

        XCTAssertNil(coordinator.errorMessage)

        // 4. New search succeeds
        coordinator.commandResults = [
            CommandResult(title: "Result", icon: "checkmark") {}
        ]
        coordinator.isLoading = false

        XCTAssertFalse(coordinator.isLoading)
        XCTAssertEqual(coordinator.commandResults.count, 1)
        XCTAssertNil(coordinator.errorMessage)
    }

    // MARK: - Test 8: State Consistency

    func testStateConsistencyAfterMultipleOperations() {
        // Perform multiple operations
        coordinator.showCommandBar()
        coordinator.commandResults = [
            CommandResult(title: "A", icon: "a") {},
            CommandResult(title: "B", icon: "b") {}
        ]
        coordinator.selectNextResult()
        coordinator.showPreviewPanel = true
        coordinator.errorMessage = "Test error"

        // Verify all state is maintained correctly
        XCTAssertTrue(coordinator.isCommandBarVisible)
        XCTAssertEqual(coordinator.commandResults.count, 2)
        XCTAssertEqual(coordinator.selectedResultIndex, 1)
        XCTAssertTrue(coordinator.showPreviewPanel)
        XCTAssertEqual(coordinator.errorMessage, "Test error")

        // Close and verify state
        coordinator.hideCommandBar()
        XCTAssertFalse(coordinator.isCommandBarVisible)

        // Other state should remain
        XCTAssertEqual(coordinator.commandResults.count, 2)
        XCTAssertEqual(coordinator.selectedResultIndex, 1)
    }
}
