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

        migrator.registerMigration("v2") { db in
            // Create command history table
            try db.create(table: "command_history") { t in
                t.column("id", .text).primaryKey()
                t.column("query", .text).notNull()
                t.column("input_type", .text).notNull()
                t.column("executed_at", .datetime).notNull()
                t.column("execution_count", .integer).notNull().defaults(to: 1)
            }

            // Create index for timestamp-based queries (recent commands)
            try db.create(index: "idx_command_history_executed_at", on: "command_history", columns: ["executed_at"])

            // Create FTS5 virtual table for full-text search
            try db.create(virtualTable: "command_history_fts", using: FTS5()) { t in
                t.column("query")
                t.content = "command_history"
                t.contentRowID = "rowid"
            }

            // Create triggers to keep FTS5 in sync with command_history
            try db.execute(sql: """
                CREATE TRIGGER command_history_ai AFTER INSERT ON command_history BEGIN
                    INSERT INTO command_history_fts(rowid, query) VALUES (new.rowid, new.query);
                END;
            """)

            try db.execute(sql: """
                CREATE TRIGGER command_history_ad AFTER DELETE ON command_history BEGIN
                    INSERT INTO command_history_fts(command_history_fts, rowid, query) VALUES('delete', old.rowid, old.query);
                END;
            """)

            try db.execute(sql: """
                CREATE TRIGGER command_history_au AFTER UPDATE ON command_history BEGIN
                    INSERT INTO command_history_fts(command_history_fts, rowid, query) VALUES('delete', old.rowid, old.query);
                    INSERT INTO command_history_fts(rowid, query) VALUES (new.rowid, new.query);
                END;
            """)
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
