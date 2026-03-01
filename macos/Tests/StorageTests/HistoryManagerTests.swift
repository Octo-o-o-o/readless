import XCTest
@testable import Storage

final class HistoryManagerTests: XCTestCase {
    var historyManager: HistoryManager!

    override func setUp() async throws {
        // Use in-memory database for tests
        historyManager = try HistoryManager(path: ":memory:")
    }

    func testAddCommand() async throws {
        try await historyManager.addCommand("summarize article", inputType: "text")

        let count = try await historyManager.historyCount()
        XCTAssertEqual(count, 1)

        let recent = try await historyManager.getRecentCommands(limit: 1)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.query, "summarize article")
        XCTAssertEqual(recent.first?.inputType, "text")
        XCTAssertEqual(recent.first?.executionCount, 1)
    }

    func testAddDuplicateCommandIncrementsCount() async throws {
        try await historyManager.addCommand("create podcast", inputType: "text")
        try await historyManager.addCommand("create podcast", inputType: "text")
        try await historyManager.addCommand("create podcast", inputType: "text")

        let count = try await historyManager.historyCount()
        XCTAssertEqual(count, 1, "Should only have one unique command")

        let frequent = try await historyManager.getFrequentCommands(limit: 1)
        XCTAssertEqual(frequent.first?.executionCount, 3, "Execution count should be 3")
    }

    func testGetRecentCommands() async throws {
        try await historyManager.addCommand("command 1", inputType: "text")
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
        try await historyManager.addCommand("command 2", inputType: "text")
        try await Task.sleep(nanoseconds: 10_000_000)
        try await historyManager.addCommand("command 3", inputType: "text")

        let recent = try await historyManager.getRecentCommands(limit: 5)
        XCTAssertEqual(recent.count, 3)
        // Most recent should be first
        XCTAssertEqual(recent[0].query, "command 3")
        XCTAssertEqual(recent[1].query, "command 2")
        XCTAssertEqual(recent[2].query, "command 1")
    }

    func testGetFrequentCommands() async throws {
        // Add commands with different execution counts
        try await historyManager.addCommand("frequent command", inputType: "text")
        try await historyManager.addCommand("frequent command", inputType: "text")
        try await historyManager.addCommand("frequent command", inputType: "text")

        try await historyManager.addCommand("rare command", inputType: "text")

        let frequent = try await historyManager.getFrequentCommands(limit: 5)
        XCTAssertEqual(frequent.count, 2)
        // Most frequent should be first
        XCTAssertEqual(frequent[0].query, "frequent command")
        XCTAssertEqual(frequent[0].executionCount, 3)
        XCTAssertEqual(frequent[1].query, "rare command")
        XCTAssertEqual(frequent[1].executionCount, 1)
    }

    func testSearchHistory() async throws {
        try await historyManager.addCommand("summarize article about AI", inputType: "text")
        try await historyManager.addCommand("create podcast from text", inputType: "text")
        try await historyManager.addCommand("search for AI research", inputType: "text")

        // Search for "AI"
        let aiResults = try await historyManager.searchHistory("AI", limit: 10)
        XCTAssertGreaterThanOrEqual(aiResults.count, 2, "Should find commands containing 'AI'")

        // Search for "podcast"
        let podcastResults = try await historyManager.searchHistory("podcast", limit: 10)
        XCTAssertEqual(podcastResults.count, 1)
        XCTAssertEqual(podcastResults.first?.query, "create podcast from text")

        // Empty search should return nothing
        let emptyResults = try await historyManager.searchHistory("", limit: 10)
        XCTAssertEqual(emptyResults.count, 0)
    }

    func testCleanupRemovesOldEntries() async throws {
        // Add multiple commands
        for i in 1...10 {
            try await historyManager.addCommand("command \(i)", inputType: "text")
        }

        let beforeCount = try await historyManager.historyCount()
        XCTAssertEqual(beforeCount, 10)

        // Cleanup won't remove anything since we're under max (1000)
        try await historyManager.cleanup()

        let afterCleanupCount = try await historyManager.historyCount()
        XCTAssertEqual(afterCleanupCount, 10, "No entries should be removed when under max")
    }

    func testClearHistory() async throws {
        try await historyManager.addCommand("command 1", inputType: "text")
        try await historyManager.addCommand("command 2", inputType: "text")
        try await historyManager.addCommand("command 3", inputType: "text")

        var count = try await historyManager.historyCount()
        XCTAssertEqual(count, 3)

        try await historyManager.clearHistory()

        count = try await historyManager.historyCount()
        XCTAssertEqual(count, 0, "All history should be cleared")

        let recent = try await historyManager.getRecentCommands(limit: 10)
        XCTAssertEqual(recent.count, 0)
    }

    func testDifferentInputTypes() async throws {
        try await historyManager.addCommand("same query", inputType: "text")
        try await historyManager.addCommand("same query", inputType: "url")

        let count = try await historyManager.historyCount()
        XCTAssertEqual(count, 2, "Same query with different input types should be separate entries")

        let recent = try await historyManager.getRecentCommands(limit: 5)
        XCTAssertEqual(recent.count, 2)

        let inputTypes = Set(recent.map { $0.inputType })
        XCTAssertTrue(inputTypes.contains("text"))
        XCTAssertTrue(inputTypes.contains("url"))
    }

    func testLimitParameterWorks() async throws {
        for i in 1...20 {
            try await historyManager.addCommand("command \(i)", inputType: "text")
        }

        let recent5 = try await historyManager.getRecentCommands(limit: 5)
        XCTAssertEqual(recent5.count, 5)

        let recent10 = try await historyManager.getRecentCommands(limit: 10)
        XCTAssertEqual(recent10.count, 10)

        let recentAll = try await historyManager.getRecentCommands(limit: 100)
        XCTAssertEqual(recentAll.count, 20)
    }
}
