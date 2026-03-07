import Foundation
import GRDB
import Core

/// Local full-text search service using SQLite FTS5
public final class LocalSearchService {
    private let database: LocalDatabase

    public static let shared = LocalSearchService(database: .shared)

    public init(database: LocalDatabase) {
        self.database = database
    }

    // MARK: - Search

    /// Search locally cached content using FTS5
    /// If userId is provided, only searches content for that user
    public func search(query: String, limit: Int = 20, userId: String? = nil) async throws -> SearchResult {
        let results = try await database.dbQueue.read { db -> [SearchResultItem] in
            let ftsQuery = prepareFTSQuery(query)

            // Include snippet() directly in the query to avoid N+1
            var sql = """
                SELECT
                    c.id,
                    c.title,
                    c.l0_summary,
                    c.created_at,
                    c.source_url,
                    bm25(contents_fts) as rank,
                    snippet(contents_fts, 1, '<mark>', '</mark>', '...', 64) as snippet
                FROM contents c
                JOIN contents_fts ON contents_fts.rowid = c.rowid
                WHERE contents_fts MATCH ?
            """

            if userId != nil {
                sql += " AND c.user_id = ?"
            }

            sql += """
                ORDER BY rank
                LIMIT ?
            """

            let rows: [Row]
            if let userId = userId {
                rows = try Row.fetchAll(db, sql: sql, arguments: [ftsQuery, userId, limit])
            } else {
                rows = try Row.fetchAll(db, sql: sql, arguments: [ftsQuery, limit])
            }

            return rows.compactMap { row -> SearchResultItem? in
                guard let id = row["id"] as? String,
                      let title = row["title"] as? String else {
                    return nil
                }

                let summary = row["l0_summary"] as? String
                let sourceURL = row["source_url"] as? String
                let createdAt = row["created_at"] as? Date
                let snippet = row["snippet"] as? String

                return SearchResultItem(
                    id: id,
                    title: title,
                    snippet: snippet ?? summary ?? "",
                    sourceURL: sourceURL,
                    createdAt: createdAt ?? Date(),
                    relevanceScore: 0.0
                )
            }
        }

        return SearchResult(
            query: query,
            results: results,
            totalCount: results.count
        )
    }

    // MARK: - FTS Query Preparation

    /// Convert natural language query to FTS5 query syntax
    private func prepareFTSQuery(_ query: String) -> String {
        // Split query into terms
        let terms = query
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else {
            return query
        }

        // Build FTS5 query with OR operator for better recall
        // Example: "swift async" -> "swift OR async"
        let ftsQuery = terms.map { "\"\($0)\"*" }.joined(separator: " OR ")

        return ftsQuery
    }

    // MARK: - Content Syncing

    /// Sync content from server to local database for offline search
    /// Respects user_id if set on the content
    public func syncContent(_ content: Content, fullText: String?, paragraphs: [(anchorID: String, text: String)]) async throws {
        try await database.dbQueue.write { db in
            // Update content with full_text
            if let fullText = fullText {
                var sql = "UPDATE contents SET full_text = ?, last_accessed_at = ? WHERE id = ?"
                var arguments: [DatabaseValueConvertible] = [fullText, Date(), content.id]

                // Verify user ownership if userId is set on content
                if let userId = content.userId {
                    sql += " AND user_id = ?"
                    arguments.append(userId)
                }

                try db.execute(sql: sql, arguments: StatementArguments(arguments))
            }

            // Save paragraphs: delete-then-insert to avoid unbounded duplicates
            // (UUID().uuidString as id would never trigger ON CONFLICT)
            try db.execute(sql: "DELETE FROM paragraphs WHERE content_id = ?", arguments: [content.id])
            for (index, para) in paragraphs.enumerated() {
                try db.execute(
                    sql: """
                        INSERT INTO paragraphs (id, content_id, anchor_id, text, position)
                        VALUES (?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        UUID().uuidString,
                        content.id,
                        para.anchorID,
                        para.text,
                        index
                    ]
                )
            }

            print("[LocalSearch] Synced content: \(content.title)")
        }
    }

    /// Check if content has full data cached locally
    /// If userId is provided, only returns true if content belongs to that user
    public func hasFullDataCached(contentID: String, userId: String? = nil) async throws -> Bool {
        try await database.dbQueue.read { db in
            var sql = "SELECT full_text IS NOT NULL FROM contents WHERE id = ?"
            var arguments: [DatabaseValueConvertible] = [contentID]

            if let userId = userId {
                sql += " AND user_id = ?"
                arguments.append(userId)
            }

            let hasFullText = try Bool.fetchOne(
                db,
                sql: sql,
                arguments: StatementArguments(arguments)
            ) ?? false

            let hasParagraphs = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM paragraphs WHERE content_id = ?",
                arguments: [contentID]
            ) ?? 0 > 0

            return hasFullText && hasParagraphs
        }
    }
}

// MARK: - Search Result Models

public struct SearchResult: Sendable {
    public let query: String
    public let results: [SearchResultItem]
    public let totalCount: Int
}

public struct SearchResultItem: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let snippet: String
    public let sourceURL: String?
    public let createdAt: Date
    public let relevanceScore: Double
}
