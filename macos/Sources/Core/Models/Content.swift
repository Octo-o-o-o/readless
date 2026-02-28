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
    public var l0Summary: String?
    public var l1Outline: [OutlinePoint]?
    public var tags: [String]
    public var status: ContentStatus
    public let createdAt: Date
    public var podcastURL: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        sourceURL: String? = nil,
        sourceType: SourceType,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        l0Summary: String? = nil,
        l1Outline: [OutlinePoint]? = nil,
        tags: [String] = [],
        status: ContentStatus = .pending,
        createdAt: Date = Date(),
        podcastURL: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sourceURL = sourceURL
        self.sourceType = sourceType
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.l0Summary = l0Summary
        self.l1Outline = l1Outline
        self.tags = tags
        self.status = status
        self.createdAt = createdAt
        self.podcastURL = podcastURL
    }
}
