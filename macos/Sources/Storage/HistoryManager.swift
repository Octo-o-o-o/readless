import Foundation
import GRDB

/// HistoryManager manages command history with GRDB and FTS5 full-text search.
/// Stores up to 1000 recent commands and provides search/suggestion capabilities.
public final class HistoryManager {
    private let dbQueue: DatabaseQueue

    /// Maximum number of commands to retain in history
    private let maxHistorySize = 1000

    /// Singleton instance using the same database as LocalDatabase.
    public static let shared: HistoryManager = {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dbFolder = appSupport.appendingPathComponent("Readless", isDirectory: true)

        try? fileManager.createDirectory(at: dbFolder, withIntermediateDirectories: true)
        let dbPath = dbFolder.appendingPathComponent("readless.db").path

        return try! HistoryManager(path: dbPath)
    }()

    /// Initialize with custom database path (useful for testing with ":memory:").
    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)

        // Run cleanup on initialization to maintain max history size
        Task {
            try? await cleanup()
        }
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

        // Cleanup after adding to maintain max size
        try await cleanup()
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

            if count > maxHistorySize {
                let excess = count - maxHistorySize

                // Get IDs of oldest records to delete
                let oldestIDs = try String
                    .fetchAll(
                        db,
                        sql: """
                            SELECT id FROM command_history
                            ORDER BY executed_at ASC
                            LIMIT ?
                        """,
                        arguments: [excess]
                    )

                // Delete oldest records
                for id in oldestIDs {
                    try CommandHistoryRecord.deleteOne(db, key: id)
                }
            }
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
