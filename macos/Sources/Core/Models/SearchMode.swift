import Foundation

/// Search mode configuration for content search
public enum SearchMode: String, Codable, Sendable {
    /// AI-powered cloud search using PostgreSQL FTS + OpenAI
    /// - Pros: Semantic understanding, accurate ranking
    /// - Cons: Requires network, API cost
    case cloud

    /// Local SQLite FTS5 search
    /// - Pros: Offline, fast, private
    /// - Cons: Requires cached data, less accurate
    case local

    public var displayName: String {
        switch self {
        case .cloud: return "Cloud Search"
        case .local: return "Local Search"
        }
    }

    public var icon: String {
        switch self {
        case .cloud: return "cloud.fill"
        case .local: return "internaldrive.fill"
        }
    }

    public var description: String {
        switch self {
        case .cloud:
            return "Using AI-powered cloud search with semantic understanding. Requires internet connection."
        case .local:
            return "Using local full-text search. Works offline but requires cached content data."
        }
    }
}
