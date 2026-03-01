import Foundation
import GRDB
import Core

// MARK: - Database Manager

@available(*, deprecated, message: "Use LocalDatabase instead. This class will be removed in a future version.")
public final class DatabaseManager {
    public static let shared = DatabaseManager()

    private let dbQueue: DatabaseQueue

    /// The path to the database file inside ~/Library/Application Support/Readless/.
    public let databasePath: String

    private init() {
        do {
            let fileManager = FileManager.default
            let appSupportURL = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!

            let readlessDir = appSupportURL.appendingPathComponent("Readless", isDirectory: true)

            if !fileManager.fileExists(atPath: readlessDir.path) {
                try fileManager.createDirectory(at: readlessDir, withIntermediateDirectories: true)
            }

            let dbURL = readlessDir.appendingPathComponent("readless.sqlite")
            databasePath = dbURL.path
            dbQueue = try DatabaseQueue(path: databasePath)

            try runMigrations()
        } catch {
            fatalError("DatabaseManager initialization failed: \(error)")
        }
    }

    /// Provides read-only access to the database.
    public func reader() -> DatabaseReader {
        dbQueue
    }

    /// Provides read-write access to the database.
    public func writer() -> DatabaseWriter {
        dbQueue
    }

    // MARK: - Migrations

    private func runMigrations() throws {
        var migrator = DatabaseMigrator()

        // v1: Create the content table
        migrator.registerMigration("v1") { db in
            try db.create(table: "content") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("sourceURL", .text)
                t.column("sourceType", .text).notNull()
                t.column("sourceAppName", .text)
                t.column("sourceAppBundleID", .text)
                t.column("l0Summary", .text)
                t.column("l1OutlineJSON", .text)
                t.column("tagsJSON", .text)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("createdAt", .datetime).notNull()
                t.column("podcastURL", .text)
            }
        }

        try migrator.migrate(dbQueue)
    }
}
