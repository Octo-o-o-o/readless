import Foundation
import GRDB

/// ExpandedDetailRecord is the GRDB persistence layer for cached L2 expansion details.
struct ExpandedDetailRecord: Codable, FetchableRecord, PersistableRecord {
    var contentId: String
    var pointIndex: Int
    var detailText: String
    var cachedAt: Date

    static var databaseTableName: String { "expanded_details" }

    private enum CodingKeys: String, CodingKey {
        case contentId = "content_id"
        case pointIndex = "point_index"
        case detailText = "detail_text"
        case cachedAt = "cached_at"
    }
}
