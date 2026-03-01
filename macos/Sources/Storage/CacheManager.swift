import Foundation
import GRDB

/// Manages local cache size limits and eviction policies
public final class CacheManager {
    // MARK: - Configuration

    /// Cache size limits in bytes
    public struct SizeLimit {
        public static let defaultLimit: Int64 = 4096 * 1024 * 1024  // 4096 MB
        public static let minimumLimit: Int64 = 50 * 1024 * 1024    // 50 MB
        public static let maximumLimit: Int64? = nil                // No limit
        public static let reservedSpace: Int64 = 50 * 1024 * 1024   // 50 MB buffer
    }

    private let database: LocalDatabase
    private let userDefaults: UserDefaults

    /// Singleton instance
    public static let shared = CacheManager(
        database: LocalDatabase.shared,
        userDefaults: .standard
    )

    // MARK: - Initialization

    public init(database: LocalDatabase, userDefaults: UserDefaults = .standard) {
        self.database = database
        self.userDefaults = userDefaults
    }

    private var dbQueue: DatabaseQueue {
        database.dbQueue
    }

    // MARK: - Cache Size Management

    /// Current cache size limit in bytes (from UserDefaults)
    public var sizeLimit: Int64 {
        get {
            let stored = userDefaults.object(forKey: "cacheSizeLimit") as? Int64
            return stored ?? SizeLimit.defaultLimit
        }
        set {
            let clamped = max(SizeLimit.minimumLimit, newValue)
            userDefaults.set(clamped, forKey: "cacheSizeLimit")

            // Trigger eviction if over limit
            Task { try? await evictIfNeeded() }
        }
    }

    /// Current cache size in bytes
    public func currentSize() async throws -> Int64 {
        let dbPath = database.databasePath
        let attributes = try FileManager.default.attributesOfItem(atPath: dbPath)
        return attributes[.size] as? Int64 ?? 0
    }

    /// Available cache space (limit - current - reserved)
    public func availableSpace() async throws -> Int64 {
        let current = try await currentSize()
        return max(0, sizeLimit - current - SizeLimit.reservedSpace)
    }

    /// Whether cache has enough space to save complete content data
    public func hasSpaceForFullData() async throws -> Bool {
        let available = try await availableSpace()
        return available > SizeLimit.reservedSpace
    }

    // MARK: - Cache Eviction (LRU)

    /// Evict least recently used content if cache exceeds limit
    public func evictIfNeeded() async throws {
        let current = try await currentSize()
        let target = sizeLimit - SizeLimit.reservedSpace

        guard current > target else { return }

        let bytesToFree = current - target
        print("[CacheManager] Cache size \(current) exceeds target \(target), freeing \(bytesToFree) bytes")

        try await dbQueue.write { db in
            // Get LRU content IDs (sorted by least recent access)
            let lruIDs = try String.fetchAll(db, sql: """
                SELECT id FROM contents
                ORDER BY
                    COALESCE(last_accessed_at, updated_at, created_at) ASC
            """)

            var freedBytes: Int64 = 0

            for id in lruIDs {
                // Delete content and its associated data
                try db.execute(
                    sql: "DELETE FROM contents WHERE id = ?",
                    arguments: [id]
                )

                // Delete associated paragraphs (if table exists)
                try? db.execute(
                    sql: "DELETE FROM paragraphs WHERE content_id = ?",
                    arguments: [id]
                )

                // Delete expanded details cache (if table exists)
                try? db.execute(
                    sql: "DELETE FROM expanded_details WHERE content_id = ?",
                    arguments: [id]
                )

                // Estimate freed space (rough estimate)
                freedBytes += 100 * 1024  // ~100KB per content

                if freedBytes >= bytesToFree {
                    break
                }
            }

            // Vacuum database to reclaim space
            try db.execute(sql: "VACUUM")

            print("[CacheManager] Evicted \(lruIDs.prefix(10).count) items, freed ~\(freedBytes) bytes")
        }
    }

    /// Update last accessed timestamp for a content
    public func touchContent(_ contentID: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE contents SET last_accessed_at = ? WHERE id = ?",
                arguments: [Date(), contentID]
            )
        }
    }

    // MARK: - Cache Clearing

    /// Clear all cached data
    public func clearAll() async throws {
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM contents")
            try? db.execute(sql: "DELETE FROM paragraphs")
            try? db.execute(sql: "DELETE FROM expanded_details")
            try db.execute(sql: "VACUUM")
        }

        print("[CacheManager] Cleared all cache")
    }

    /// Clear cache older than specified days
    public func clearOlderThan(days: Int) async throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    DELETE FROM contents
                    WHERE COALESCE(last_accessed_at, updated_at, created_at) < ?
                """,
                arguments: [cutoffDate]
            )

            try db.execute(sql: "VACUUM")
        }

        print("[CacheManager] Cleared cache older than \(days) days")
    }

    // MARK: - Statistics

    /// Cache statistics for UI display
    public struct CacheStats: Sendable {
        public let currentSize: Int64
        public let sizeLimit: Int64
        public let availableSpace: Int64
        public let itemCount: Int
        public let usagePercentage: Double

        public var formattedCurrentSize: String {
            ByteCountFormatter.string(fromByteCount: currentSize, countStyle: .file)
        }

        public var formattedSizeLimit: String {
            ByteCountFormatter.string(fromByteCount: sizeLimit, countStyle: .file)
        }

        public var formattedAvailableSpace: String {
            ByteCountFormatter.string(fromByteCount: availableSpace, countStyle: .file)
        }
    }

    public func getStats() async throws -> CacheStats {
        let current = try await currentSize()
        let available = try await availableSpace()
        let itemCount = try await dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM contents") ?? 0
        }

        return CacheStats(
            currentSize: current,
            sizeLimit: sizeLimit,
            availableSpace: available,
            itemCount: itemCount,
            usagePercentage: Double(current) / Double(sizeLimit) * 100.0
        )
    }

}
