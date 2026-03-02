import Foundation

// MARK: - Source Type

public enum SourceType: String, Codable, Sendable, CaseIterable {
    case url
    case pdf
    case text
    case image
    case clipboard
    case folderWatch
    case email
    case rss
}

// MARK: - Content Status

public enum ContentStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case processing
    case ready
    case failed
}

// MARK: - Content

public struct Content: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var sourceURL: String?
    public var sourceType: SourceType
    public var sourceAppName: String?
    public var sourceAppBundleID: String?
    public var sourceLanguage: String?
    public var l0Summary: String?
    public var l1Outline: [OutlinePoint]?
    public var tags: [String]
    public var status: ContentStatus
    public let createdAt: Date
    public var updatedAt: Date
    public var podcastURL: String?
    public var fullText: String?  // Full text for local search
    public var userId: String?  // User ID for multi-user cache isolation

    // Explicit CodingKeys because .convertFromSnakeCase maps
    // "source_url" → "sourceUrl" (not "sourceURL") and
    // "source_app_bundle_id" → "sourceAppBundleId" (not "sourceAppBundleID").
    private enum CodingKeys: String, CodingKey {
        case id, title
        case sourceURL = "source_url"
        case sourceType = "source_type"
        case sourceAppName = "source_app_name"
        case sourceAppBundleID = "source_app_bundle_id"
        case sourceLanguage = "source_language"
        case l0Summary = "l0_summary"
        case l1Outline = "l1_outline"
        case tags, status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case podcastURL = "podcast_url"
        case fullText = "full_text"
        case userId = "user_id"
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        sourceURL: String? = nil,
        sourceType: SourceType,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        sourceLanguage: String? = nil,
        l0Summary: String? = nil,
        l1Outline: [OutlinePoint]? = nil,
        tags: [String] = [],
        status: ContentStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        podcastURL: String? = nil,
        fullText: String? = nil,
        userId: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.sourceType = sourceType
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceLanguage = sourceLanguage
        self.l0Summary = l0Summary
        self.l1Outline = l1Outline
        self.tags = tags
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.podcastURL = podcastURL
        self.fullText = fullText
        self.userId = userId
    }
}
