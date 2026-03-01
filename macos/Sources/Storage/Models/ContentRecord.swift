import Foundation
import GRDB
import Core

/// ContentRecord is the GRDB persistence layer for Content.
/// It handles serialization of complex fields (outline, tags) to JSON/Data.
struct ContentRecord: Codable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var sourceURL: String?
    var sourceType: String
    var sourceAppName: String?
    var sourceAppBundleID: String?
    var l0Summary: String?
    var l1OutlineData: Data?
    var tagsData: Data?
    var status: String
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var isFavorite: Bool
    var podcastURL: String?

    static var databaseTableName: String { "contents" }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let sourceURL = Column(CodingKeys.sourceURL)
        static let sourceType = Column(CodingKeys.sourceType)
        static let sourceAppName = Column(CodingKeys.sourceAppName)
        static let sourceAppBundleID = Column(CodingKeys.sourceAppBundleID)
        static let l0Summary = Column(CodingKeys.l0Summary)
        static let l1OutlineData = Column(CodingKeys.l1OutlineData)
        static let tagsData = Column(CodingKeys.tagsData)
        static let status = Column(CodingKeys.status)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
        static let syncedAt = Column(CodingKeys.syncedAt)
        static let isFavorite = Column(CodingKeys.isFavorite)
        static let podcastURL = Column(CodingKeys.podcastURL)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case sourceURL = "source_url"
        case sourceType = "source_type"
        case sourceAppName = "source_app_name"
        case sourceAppBundleID = "source_app_bundle_id"
        case l0Summary = "l0_summary"
        case l1OutlineData = "l1_outline"
        case tagsData = "tags"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case syncedAt = "synced_at"
        case isFavorite = "is_favorite"
        case podcastURL = "podcast_url"
    }

    // MARK: - Initialization from Content

    init(from content: Content) {
        self.id = content.id
        self.title = content.title
        self.sourceURL = content.sourceURL
        self.sourceType = content.sourceType.rawValue
        self.sourceAppName = content.sourceAppName
        self.sourceAppBundleID = content.sourceAppBundleID
        self.l0Summary = content.l0Summary
        self.l1OutlineData = content.l1Outline.flatMap { try? JSONEncoder().encode($0) }
        self.tagsData = try? JSONEncoder().encode(content.tags)
        self.status = content.status.rawValue
        self.createdAt = content.createdAt
        self.updatedAt = Date()
        self.syncedAt = nil
        self.isFavorite = false
        self.podcastURL = content.podcastURL
    }

    // MARK: - Conversion to Content

    func toContent() -> Content {
        let l1Outline: [OutlinePoint]? = l1OutlineData.flatMap { data in
            try? JSONDecoder().decode([OutlinePoint].self, from: data)
        }

        let tags: [String] = (tagsData.flatMap { data in
            try? JSONDecoder().decode([String].self, from: data)
        }) ?? []

        return Content(
            id: id,
            title: title,
            sourceURL: sourceURL,
            sourceType: SourceType(rawValue: sourceType) ?? .text,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID,
            l0Summary: l0Summary,
            l1Outline: l1Outline,
            tags: tags,
            status: ContentStatus(rawValue: status) ?? .pending,
            createdAt: createdAt,
            podcastURL: podcastURL
        )
    }
}
