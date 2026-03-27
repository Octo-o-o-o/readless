import XCTest
import GRDB
@testable import Storage
@testable import Core

final class CacheManagerTests: XCTestCase {
    private var databaseURL: URL!
    private var suiteName: String!
    private var database: LocalDatabase!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        suiteName = "CacheManagerTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
        database = try LocalDatabase(path: databaseURL.path)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        for suffix in ["", "-wal", "-shm"] {
            let path = databaseURL.path + suffix
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func makeManager() -> CacheManager {
        CacheManager(database: database, userDefaults: userDefaults)
    }

    private func makeContent(
        id: String,
        userId: String,
        title: String,
        createdAt: Date
    ) -> Content {
        Content(
            id: id,
            title: title,
            sourceType: .text,
            l0Summary: "Summary",
            status: .ready,
            createdAt: createdAt,
            updatedAt: createdAt,
            fullText: "Full text",
            userId: userId
        )
    }

    func testSizeLimitClampsToMinimum() {
        let manager = makeManager()

        manager.sizeLimit = 1

        XCTAssertEqual(manager.sizeLimit, CacheManager.SizeLimit.minimumLimit)
    }

    func testTouchContentUpdatesLastAccessedAt() async throws {
        let manager = makeManager()
        try await database.saveContent(
            makeContent(
                id: "touch-1",
                userId: "user-1",
                title: "Touch Me",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            userId: "user-1"
        )

        try await manager.touchContent("touch-1", userId: "user-1")

        let lastAccessed = try await database.dbQueue.read { db in
            try Date.fetchOne(
                db,
                sql: "SELECT last_accessed_at FROM contents WHERE id = ?",
                arguments: ["touch-1"]
            )
        }
        XCTAssertNotNil(lastAccessed)
    }

    func testClearOlderThanRemovesOnlyScopedUserContent() async throws {
        let manager = makeManager()
        let oldDate = Date(timeIntervalSinceNow: -60 * 60 * 24 * 90)
        let recentDate = Date()

        try await database.saveContents(
            [
                makeContent(id: "old-user-1", userId: "user-1", title: "Old", createdAt: oldDate),
                makeContent(id: "recent-user-1", userId: "user-1", title: "Recent", createdAt: recentDate),
                makeContent(id: "old-user-2", userId: "user-2", title: "Other", createdAt: oldDate),
            ]
        )

        try await manager.clearOlderThan(days: 30, userId: "user-1")

        let userOneContents = try await database.fetchContents(userId: "user-1")
        let userTwoContents = try await database.fetchContents(userId: "user-2")
        XCTAssertEqual(userOneContents.map(\.id), ["recent-user-1"])
        XCTAssertEqual(userTwoContents.map(\.id), ["old-user-2"])
    }

    func testClearAllRemovesOnlyScopedUserData() async throws {
        let manager = makeManager()
        try await database.saveContents(
            [
                makeContent(id: "u1-1", userId: "user-1", title: "One", createdAt: Date()),
                makeContent(id: "u2-1", userId: "user-2", title: "Two", createdAt: Date()),
            ]
        )

        try await manager.clearAll(userId: "user-1")

        let userOneContents = try await database.fetchContents(userId: "user-1")
        let userTwoContents = try await database.fetchContents(userId: "user-2")
        XCTAssertEqual(userOneContents.count, 0)
        XCTAssertEqual(userTwoContents.count, 1)
    }

    func testGetStatsReportsCountsAndSizes() async throws {
        let manager = makeManager()
        try await database.saveContent(
            makeContent(
                id: "stats-1",
                userId: "user-1",
                title: "Stats",
                createdAt: Date()
            ),
            userId: "user-1"
        )

        let stats = try await manager.getStats(userId: "user-1")

        XCTAssertEqual(stats.itemCount, 1)
        XCTAssertEqual(stats.sizeLimit, CacheManager.SizeLimit.defaultLimit)
        XCTAssertGreaterThan(stats.currentSize, 0)
        XCTAssertGreaterThanOrEqual(stats.usagePercentage, 0)
    }
}
