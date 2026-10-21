import XCTest
@testable import Storage
@testable import Core

final class LocalSearchServiceTests: XCTestCase {
    private var database: LocalDatabase!
    private var searchService: LocalSearchService!

    override func setUp() async throws {
        database = try LocalDatabase(path: ":memory:")
        searchService = LocalSearchService(database: database)
    }

    private func makeContent(
        id: String,
        userId: String,
        title: String
    ) -> Content {
        Content(
            id: id,
            title: title,
            sourceType: .text,
            l0Summary: "Summary for \(title)",
            status: .ready,
            userId: userId
        )
    }

    func testSearchReturnsResultsFromSyncedContent() async throws {
        let content = makeContent(id: "search-1", userId: "user-1", title: "Async Swift")
        try await database.saveContent(content, userId: "user-1")
        try await searchService.syncContent(
            content,
            fullText: "Swift async await makes concurrency easier",
            paragraphs: [("¶1", "Swift async await makes concurrency easier")]
        )

        let result = try await searchService.search(query: "async", userId: "user-1")

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.results.first?.id, "search-1")
        XCTAssertEqual(result.results.first?.title, "Async Swift")
        XCTAssertTrue(result.results.first?.snippet.lowercased().contains("async") ?? false)
    }

    func testSearchHonorsUserScope() async throws {
        let first = makeContent(id: "scope-1", userId: "user-1", title: "One")
        let second = makeContent(id: "scope-2", userId: "user-2", title: "Two")
        try await database.saveContents([first, second])
        try await searchService.syncContent(
            first,
            fullText: "shared keyword",
            paragraphs: [("¶1", "shared keyword")]
        )
        try await searchService.syncContent(
            second,
            fullText: "shared keyword",
            paragraphs: [("¶1", "shared keyword")]
        )

        let result = try await searchService.search(query: "shared", userId: "user-1")

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.results.first?.id, "scope-1")
    }

    func testHasFullDataCachedRequiresFullTextAndParagraphs() async throws {
        let content = makeContent(id: "cache-1", userId: "user-1", title: "Cached")
        try await database.saveContent(content, userId: "user-1")

        let initiallyCached = try await searchService.hasFullDataCached(
            contentID: "cache-1",
            userId: "user-1"
        )
        XCTAssertFalse(initiallyCached)

        try await searchService.syncContent(
            content,
            fullText: "Full body",
            paragraphs: [("¶1", "Full body")]
        )

        let userOneCached = try await searchService.hasFullDataCached(
            contentID: "cache-1",
            userId: "user-1"
        )
        let userTwoCached = try await searchService.hasFullDataCached(
            contentID: "cache-1",
            userId: "user-2"
        )
        XCTAssertTrue(userOneCached)
        XCTAssertFalse(userTwoCached)
    }
}
