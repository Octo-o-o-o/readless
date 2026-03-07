import Foundation
import GRDB

/// HistoryManager manages command history with GRDB and FTS5 full-text search.
/// Stores up to 1000 recent commands and provides search/suggestion capabilities.
public final class HistoryManager {
    private let dbQueue: DatabaseQueue

    /// Maximum number of commands to retain in history
    private let maxHistorySize = 1000
    /// Counter to throttle cleanup frequency
    private var insertsSinceCleanup = 0

    /// Singleton instance sharing the same DatabaseQueue as LocalDatabase
    /// to avoid write-lock contention on the same SQLite file.
    public static let shared: HistoryManager = try! HistoryManager(dbQueue: LocalDatabase.shared.dbQueue)

    /// Initialize with a shared DatabaseQueue (production use).
    public init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try migrator.migrate(dbQueue)
        Task { try? await cleanup() }
    }

    /// Initialize with custom database path (useful for testing with ":memory:").
    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
        Task { try? await cleanup() }
    }

    // MARK: - Migration

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v2_command_history") { db in
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

    // MARK: - Command Management

    /// Add a command to history. If the same query exists, increment execution_count and update timestamp.
    public func addCommand(_ query: String, inputType: String) async throws {
        try await dbQueue.write { db in
            // Check if this exact query already exists
            if let existing = try CommandHistoryRecord
                .filter(Column("query") == query && Column("input_type") == inputType)
                .fetchOne(db) {
                // Update existing record: increment count and update timestamp
                var updated = existing
                updated.executionCount = existing.executionCount + 1
                updated.executedAt = Date()
                try updated.update(db)
            } else {
                // Insert new record
                let record = CommandHistoryRecord(
                    query: query,
                    inputType: inputType,
                    executedAt: Date(),
                    executionCount: 1
                )
                try record.insert(db)
            }
        }

        // Cleanup periodically to maintain max size (not on every insert)
        insertsSinceCleanup += 1
        if insertsSinceCleanup >= 100 {
            insertsSinceCleanup = 0
            try await cleanup()
        }
    }

    // MARK: - Search & Retrieval

    /// Search command history using FTS5 full-text search.
    /// Returns matching commands ordered by relevance and execution count.
    public func searchHistory(_ query: String, limit: Int = 10) async throws -> [CommandHistoryRecord] {
        guard !query.isEmpty else {
            return []
        }

        return try await dbQueue.read { db in
            // Use FTS5 for full-text search, joining with main table for full record
            let sql = """
                SELECT ch.*
                FROM command_history ch
                JOIN command_history_fts fts ON ch.rowid = fts.rowid
                WHERE command_history_fts MATCH ?
                ORDER BY ch.execution_count DESC, ch.executed_at DESC
                LIMIT ?
            """

            return try CommandHistoryRecord.fetchAll(db, sql: sql, arguments: [query, limit])
        }
    }

    /// Get recent commands ordered by execution timestamp.
    public func getRecentCommands(limit: Int = 10) async throws -> [CommandHistoryRecord] {
        try await dbQueue.read { db in
            try CommandHistoryRecord
                .order(Column("executed_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Get frequent commands ordered by execution count.
    public func getFrequentCommands(limit: Int = 10) async throws -> [CommandHistoryRecord] {
        try await dbQueue.read { db in
            try CommandHistoryRecord
                .order(Column("execution_count").desc, Column("executed_at").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Cleanup

    /// Remove old entries beyond max history size (1000 commands).
    /// Keeps the most recent commands based on executed_at timestamp.
    public func cleanup() async throws {
        try await dbQueue.write { db in
            let count = try CommandHistoryRecord.fetchCount(db)
            guard count > maxHistorySize else { return }

            let excess = count - maxHistorySize
            // Single batch DELETE instead of per-row deletion
            try db.execute(
                sql: """
                    DELETE FROM command_history
                    WHERE id IN (
                        SELECT id FROM command_history
                        ORDER BY executed_at ASC
                        LIMIT ?
                    )
                """,
                arguments: [excess]
            )
        }
    }

    // MARK: - Utility

    /// Get total count of commands in history.
    public func historyCount() async throws -> Int {
        try await dbQueue.read { db in
            try CommandHistoryRecord.fetchCount(db)
        }
    }

    /// Clear all command history (useful for testing or user-requested reset).
    public func clearHistory() async throws {
        _ = try await dbQueue.write { db in
            try CommandHistoryRecord.deleteAll(db)
        }
    }
}
