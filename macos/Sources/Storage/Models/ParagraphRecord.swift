import Foundation
import GRDB

/// ParagraphRecord is the GRDB persistence layer for cached paragraphs.
struct ParagraphRecord: Codable, FetchableRecord, PersistableRecord {
    var id: String
    var contentId: String
    var anchorId: String
    var text: String
    var position: Int

    static var databaseTableName: String { "paragraphs" }

    private enum CodingKeys: String, CodingKey {
        case id
        case contentId = "content_id"
        case anchorId = "anchor_id"
        case text
        case position
    }
}
