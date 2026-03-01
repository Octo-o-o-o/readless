import Foundation
import GRDB
import Core

/// LocalDatabase provides CRUD operations for Content with GRDB.
/// Supports local persistence, sync tracking, and bi-directional sync with backend.
public final class LocalDatabase {
    private let dbQueue: DatabaseQueue

    /// Singleton instance using default production database path.
    public static let shared: LocalDatabase = {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dbFolder = appSupport.appendingPathComponent("Readless", isDirectory: true)

        try? fileManager.createDirectory(at: dbFolder, withIntermediateDirectories: true)
        let dbPath = dbFolder.appendingPathComponent("readless.db").path

        return try! LocalDatabase(path: dbPath)
    }()

    /// Initialize with custom database path (useful for testing with ":memory:").
    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }

    // MARK: - Migration

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "contents") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("source_url", .text)
                t.column("source_type", .text).notNull()
                t.column("source_app_name", .text)
                t.column("source_app_bundle_id", .text)
                t.column("l0_summary", .text)
                t.column("l1_outline", .blob)
                t.column("tags", .blob)
                t.column("status", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("synced_at", .datetime)
                t.column("is_favorite", .boolean).notNull().defaults(to: false)
                t.column("podcast_url", .text)
            }

            try db.create(index: "idx_contents_created_at", on: "contents", columns: ["created_at"])
            try db.create(index: "idx_contents_status", on: "contents", columns: ["status"])
            try db.create(index: "idx_contents_synced_at", on: "contents", columns: ["synced_at"])
        }

        return migrator
    }

    // MARK: - CRUD Operations

    /// Save or update a content record. If content with same ID exists, it will be updated.
    public func saveContent(_ content: Content) async throws {
        try await dbQueue.write { db in
            try ContentRecord(from: content).save(db)
        }
    }

    /// Fetch all contents ordered by creation date (newest first).
    public func fetchContents(limit: Int = 100, offset: Int = 0) async throws -> [Content] {
        try await dbQueue.read { db in
            let records = try ContentRecord
                .order(Column("created_at").desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
            return records.map { $0.toContent() }
        }
    }

    /// Fetch a single content by ID.
    public func fetchContent(id: String) async throws -> Content? {
        try await dbQueue.read { db in
            guard let record = try ContentRecord.fetchOne(db, key: id) else {
                return nil
            }
            return record.toContent()
        }
    }

    /// Delete a content by ID.
    public func deleteContent(_ contentID: String) async throws {
        _ = try await dbQueue.write { db in
            try ContentRecord.deleteOne(db, key: contentID)
        }
    }

    // MARK: - Sync Operations

    /// Fetch contents that have not been synced or were modified after last sync.
    public func unsyncedContents() async throws -> [Content] {
        try await dbQueue.read { db in
            let records = try ContentRecord
                .filter(Column("synced_at") == nil || Column("updated_at") > Column("synced_at"))
                .fetchAll(db)
            return records.map { $0.toContent() }
        }
    }

    /// Mark a content as synced by updating synced_at timestamp.
    public func markAsSynced(_ contentID: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE contents SET synced_at = ? WHERE id = ?",
                arguments: [Date(), contentID]
            )
        }
    }

    // MARK: - Utility

    /// Get total count of contents.
    public func contentCount() async throws -> Int {
        try await dbQueue.read { db in
            try ContentRecord.fetchCount(db)
        }
    }

    /// Clear all contents (useful for testing or reset).
    public func clearAllContents() async throws {
        _ = try await dbQueue.write { db in
            try ContentRecord.deleteAll(db)
        }
    }
}
