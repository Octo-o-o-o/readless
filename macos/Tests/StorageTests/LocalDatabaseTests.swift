import XCTest
@testable import Storage
@testable import Core

final class LocalDatabaseTests: XCTestCase {
    var database: LocalDatabase!

    override func setUp() async throws {
        // Use in-memory database for tests
        database = try LocalDatabase(path: ":memory:")
    }

    func testSaveAndFetchContent() async throws {
        let content = Content(
            id: "test-123",
            title: "Test Content",
            sourceType: .text,
            status: .ready
        )

        try await database.saveContent(content)
        let fetched = try await database.fetchContents(limit: 10)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, "test-123")
        XCTAssertEqual(fetched.first?.title, "Test Content")
        XCTAssertEqual(fetched.first?.sourceType, .text)
        XCTAssertEqual(fetched.first?.status, .ready)
    }

    func testFetchContentWithOutline() async throws {
        let outline = [
            OutlinePoint(id: "p1", point: "First point", anchors: ["¶1", "¶2"]),
            OutlinePoint(id: "p2", point: "Second point", anchors: ["¶3"])
        ]

        let content = Content(
            id: "test-456",
            title: "Content with Outline",
            sourceType: .url,
            l0Summary: "Brief summary",
            l1Outline: outline,
            tags: ["ai", "tech"],
            status: .ready
        )

        try await database.saveContent(content)
        let fetched = try await database.fetchContents(limit: 10)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.l0Summary, "Brief summary")
        XCTAssertEqual(fetched.first?.l1Outline?.count, 2)
        XCTAssertEqual(fetched.first?.l1Outline?[0].point, "First point")
        XCTAssertEqual(fetched.first?.l1Outline?[0].anchors, ["¶1", "¶2"])
        XCTAssertEqual(fetched.first?.tags, ["ai", "tech"])
    }

    func testUnsyncedContents() async throws {
        let content1 = Content(id: "sync-1", title: "Unsynced", sourceType: .text, status: .ready)
        let content2 = Content(id: "sync-2", title: "To Sync", sourceType: .text, status: .ready)

        try await database.saveContent(content1)
        try await database.saveContent(content2)

        // Initially all should be unsynced
        var unsynced = try await database.unsyncedContents()
        XCTAssertEqual(unsynced.count, 2)

        // Mark one as synced
        try await database.markAsSynced("sync-1")

        // Now only one should be unsynced
        unsynced = try await database.unsyncedContents()
        XCTAssertEqual(unsynced.count, 1)
        XCTAssertEqual(unsynced.first?.id, "sync-2")
    }

    func testUpdateContent() async throws {
        var content = Content(
            id: "update-1",
            title: "Original Title",
            sourceType: .text,
            status: .pending
        )

        try await database.saveContent(content)

        // Update the content
        content.title = "Updated Title"
        content.status = .ready
        content.l0Summary = "New summary"

        try await database.saveContent(content)

        let fetched = try await database.fetchContents(limit: 10)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Updated Title")
        XCTAssertEqual(fetched.first?.status, .ready)
        XCTAssertEqual(fetched.first?.l0Summary, "New summary")
    }

    func testFetchWithPagination() async throws {
        // Create multiple content items
        for i in 1...15 {
            let content = Content(
                id: "page-\(i)",
                title: "Content \(i)",
                sourceType: .text,
                status: .ready,
                createdAt: Date(timeIntervalSinceNow: TimeInterval(-i))
            )
            try await database.saveContent(content)
        }

        // Fetch first page
        let page1 = try await database.fetchContents(limit: 10, offset: 0)
        XCTAssertEqual(page1.count, 10)

        // Fetch second page
        let page2 = try await database.fetchContents(limit: 10, offset: 10)
        XCTAssertEqual(page2.count, 5)

        // Verify ordering (newest first)
        XCTAssertEqual(page1.first?.id, "page-1")
        XCTAssertEqual(page1.last?.id, "page-10")
    }

    func testDeleteContent() async throws {
        let content = Content(id: "delete-1", title: "To Delete", sourceType: .text, status: .ready)
        try await database.saveContent(content)

        var fetched = try await database.fetchContents(limit: 10)
        XCTAssertEqual(fetched.count, 1)

        try await database.deleteContent("delete-1")

        fetched = try await database.fetchContents(limit: 10)
        XCTAssertEqual(fetched.count, 0)
    }

    func testFetchContentByID() async throws {
        let content = Content(id: "fetch-1", title: "Specific Content", sourceType: .url, status: .ready)
        try await database.saveContent(content)

        let fetched = try await database.fetchContent(id: "fetch-1")
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.title, "Specific Content")

        let missing = try await database.fetchContent(id: "nonexistent")
        XCTAssertNil(missing)
    }

    func testSaveContentPreservesHydratedFieldsWhenMetadataUpdateOmitsThem() async throws {
        let hydrated = Content(
            id: "hydrated-1",
            title: "Hydrated Content",
            sourceType: .text,
            l0Summary: "Detailed summary",
            l1Outline: [
                OutlinePoint(id: "point-1", point: "First point", anchors: ["¶1"])
            ],
            status: .ready,
            fullText: "Full cached text"
        )
        try await database.saveContent(hydrated)

        let metadataOnly = Content(
            id: "hydrated-1",
            title: "Hydrated Content",
            sourceType: .text,
            l0Summary: "Detailed summary",
            l1Outline: nil,
            status: .ready,
            updatedAt: Date().addingTimeInterval(60),
            fullText: nil
        )
        try await database.saveContent(metadataOnly)

        let fetched = try await database.fetchContent(id: "hydrated-1")
        XCTAssertEqual(fetched?.fullText, "Full cached text")
        XCTAssertEqual(fetched?.l1Outline?.first?.point, "First point")
    }
}
