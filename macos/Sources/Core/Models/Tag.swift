import Foundation

// MARK: - User Tag

public struct UserTag: Identifiable, Codable, Sendable {
    public let id: Int
    public var tagName: String
    public var contentCount: Int
    public let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case contentCount = "content_count"
        case createdAt = "created_at"
    }

    public init(
        id: Int,
        tagName: String,
        contentCount: Int,
        createdAt: Date
    ) {
        self.id = id
        self.tagName = tagName
        self.contentCount = contentCount
        self.createdAt = createdAt
    }
}
