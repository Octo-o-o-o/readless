import Foundation
import GRDB

/// CommandHistoryRecord is the GRDB persistence layer for command history.
/// Supports full-text search via FTS5 virtual table.
public struct CommandHistoryRecord: Codable, FetchableRecord, PersistableRecord {
    public var id: String
    public var query: String
    public var inputType: String
    public var executedAt: Date
    public var executionCount: Int

    public static var databaseTableName: String { "command_history" }

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let query = Column(CodingKeys.query)
        public static let inputType = Column(CodingKeys.inputType)
        public static let executedAt = Column(CodingKeys.executedAt)
        public static let executionCount = Column(CodingKeys.executionCount)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case query
        case inputType = "input_type"
        case executedAt = "executed_at"
        case executionCount = "execution_count"
    }

    // MARK: - Initialization

    public init(id: String = UUID().uuidString, query: String, inputType: String, executedAt: Date = Date(), executionCount: Int = 1) {
        self.id = id
        self.query = query
        self.inputType = inputType
        self.executedAt = executedAt
        self.executionCount = executionCount
    }
}
