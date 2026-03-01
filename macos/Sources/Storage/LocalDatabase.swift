import Foundation
import GRDB
import Core

/// LocalDatabase provides CRUD operations for Content with GRDB.
/// Supports local persistence, sync tracking, and bi-directional sync with backend.
public final class LocalDatabase {
    internal let dbQueue: DatabaseQueue  // Changed to internal for CacheManager access

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

    /// Get database file path (for cache size calculation)
    public var databasePath: String {
        dbQueue.path
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

        // v3: Add cache management columns and tables
        migrator.registerMigration("v3") { db in
            // Add last_accessed_at for LRU eviction
            try db.alter(table: "contents") { t in
                t.add(column: "last_accessed_at", .datetime)
            }

            // Add full_text for local search
            try db.alter(table: "contents") { t in
                t.add(column: "full_text", .text)
            }

            // Create paragraphs table for complete local data
            try db.create(table: "paragraphs") { t in
                t.column("id", .text).primaryKey()
                t.column("content_id", .text).notNull()
                    .references("contents", onDelete: .cascade)
                t.column("anchor_id", .text).notNull()
                t.column("text", .text).notNull()
                t.column("position", .integer).notNull()
            }

            try db.create(index: "idx_paragraphs_content_id", on: "paragraphs", columns: ["content_id"])

            // Create expanded_details cache table
            try db.create(table: "expanded_details") { t in
                t.column("content_id", .text).notNull()
                    .references("contents", onDelete: .cascade)
                t.column("point_index", .integer).notNull()
                t.column("detail_text", .text).notNull()
                t.column("cached_at", .datetime).notNull()

                t.primaryKey(["content_id", "point_index"])
            }

            try db.create(index: "idx_expanded_details_content_id", on: "expanded_details", columns: ["content_id"])

            // Create FTS5 virtual table for full-text content search
            try db.create(virtualTable: "contents_fts", using: FTS5()) { t in
                t.column("title")
                t.column("full_text")
                t.column("l0_summary")
                t.content = "contents"
                t.contentRowID = "rowid"
            }

            // Create triggers to keep FTS5 in sync
            try db.execute(sql: """
                CREATE TRIGGER contents_ai AFTER INSERT ON contents BEGIN
                    INSERT INTO contents_fts(rowid, title, full_text, l0_summary)
                    VALUES (new.rowid, new.title, new.full_text, new.l0_summary);
                END;
            """)

            try db.execute(sql: """
                CREATE TRIGGER contents_ad AFTER DELETE ON contents BEGIN
                    INSERT INTO contents_fts(contents_fts, rowid, title, full_text, l0_summary)
                    VALUES('delete', old.rowid, old.title, old.full_text, old.l0_summary);
                END;
            """)

            try db.execute(sql: """
                CREATE TRIGGER contents_au AFTER UPDATE ON contents BEGIN
                    INSERT INTO contents_fts(contents_fts, rowid, title, full_text, l0_summary)
                    VALUES('delete', old.rowid, old.title, old.full_text, old.l0_summary);
                    INSERT INTO contents_fts(rowid, title, full_text, l0_summary)
                    VALUES (new.rowid, new.title, new.full_text, new.l0_summary);
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
