import Foundation
import Core

// MARK: - API Client Errors

public enum APIError: Error, Sendable {
    case invalidURL
    case unauthorized
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)
}

// Keep legacy name so existing test references still compile.
public typealias APIClientError = APIError

// MARK: - API Client

public final class APIClient: @unchecked Sendable {
    public static let shared = APIClient()

    public let baseURL: URL
    // Mutable so the token can be updated after authentication.
    public var authToken: String?
    private let session: URLSession

    /// Get the configured API base URL from UserDefaults or use default localhost
    private static func getConfiguredBaseURL() -> URL {
        // Try to read from UserDefaults first
        if let urlString = UserDefaults.standard.string(forKey: "apiBaseURL"),
           let url = URL(string: urlString) {
            print("[Readless] Using configured API base URL: \(urlString)")
            return url
        }

        // Fallback to localhost for development
        let defaultURL = URL(string: "http://localhost:8000")!
        print("[Readless] Using default API base URL: \(defaultURL.absoluteString)")
        return defaultURL
    }

    public init(
        baseURL: URL? = nil,
        authToken: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL ?? Self.getConfiguredBaseURL()
        self.authToken = authToken
        self.session = session
    }

    // MARK: - Generic Request

    private func request(_ path: String, method: String = "GET", body: Data? = nil, isRetry: Bool = false) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            print("[APIClient] ❌ Invalid URL: \(path) relative to \(baseURL)")
            throw APIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            print("[APIClient] 🔐 Request to \(url) with auth token (length: \(token.count))")
        } else {
            print("[APIClient] ⚠️ Request to \(url) WITHOUT auth token")
        }

        req.httpBody = body

        do {
            let (data, response) = try await session.data(for: req)

            guard let http = response as? HTTPURLResponse else {
                print("[APIClient] ❌ Response is not HTTPURLResponse: \(response)")
                throw APIError.serverError(0)
            }

            print("[APIClient] 📡 Response status: \(http.statusCode)")

            guard 200..<300 ~= http.statusCode else {
                print("[APIClient] ❌ Server error: \(http.statusCode)")

                // Try to decode error message from response
                if let errorMessage = String(data: data, encoding: .utf8) {
                    print("[APIClient] Error response: \(errorMessage)")

                    // Auto-refresh token on 401 if token expired
                    if http.statusCode == 401 && errorMessage.contains("Token expired") && !isRetry {
                        print("[APIClient] 🔄 Token expired, attempting refresh and retry...")

                        // Import AuthManager to refresh token
                        // Note: This creates a dependency cycle that should be resolved by using a protocol
                        // For now, we'll add the refresh logic here
                        do {
                            // Try to refresh token via notification
                            await MainActor.run {
                                NotificationCenter.default.post(name: .refreshAuthToken, object: nil)
                            }

                            // Wait a bit for token refresh
                            try await Task.sleep(for: .milliseconds(500))

                            // Retry the request once
                            return try await request(path, method: method, body: body, isRetry: true)
                        } catch {
                            print("[APIClient] ❌ Token refresh failed: \(error)")
                        }
                    }
                }

                throw APIError.serverError(http.statusCode)
            }

            return data
        } catch let error as APIError {
            throw error
        } catch {
            print("[APIClient] ❌ Network error: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }

    // MARK: - Content Endpoints

    /// Create a new content item by sending text or a URL to the backend.
    public func createContent(
        sourceType: String,
        body: String,
        appName: String?,
        bundleID: String?
    ) async throws -> Content {
        struct Req: Encodable {
            let source_type: String
            let body: String
            let source_app_name: String?
            let source_app_bundle_id: String?
        }
        let payload = try JSONEncoder().encode(Req(
            source_type: sourceType,
            body: body,
            source_app_name: appName,
            source_app_bundle_id: bundleID
        ))
        let data = try await request("/api/v1/content/", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(Content.self, from: data)
    }

    /// List content items with pagination.
    public func listContents(skip: Int = 0, limit: Int = 50) async throws -> [Content] {
        let data = try await request("/api/v1/content/?skip=\(skip)&limit=\(limit)")
        return try JSONDecoder.apiDecoder.decode([Content].self, from: data)
    }

    /// Expand a specific outline point for a given content item.
    public func expandPoint(contentID: String, pointIndex: Int) async throws -> String {
        struct Req: Encodable { let point_index: Int }
        struct Resp: Decodable { let text: String }
        let payload = try JSONEncoder().encode(Req(point_index: pointIndex))
        let data = try await request("/api/v1/content/\(contentID)/expand", method: "POST", body: payload)
        return try JSONDecoder().decode(Resp.self, from: data).text
    }

    /// Get a single content item by ID.
    public func getContent(id: String) async throws -> Content {
        let data = try await request("/api/v1/content/\(id)")
        return try JSONDecoder.apiDecoder.decode(Content.self, from: data)
    }

    /// Get all paragraphs for a content item, ordered by position.
    public func getParagraphs(contentID: String) async throws -> [ParagraphResponse] {
        let data = try await request("/api/v1/content/\(contentID)/paragraphs")
        return try JSONDecoder.apiDecoder.decode([ParagraphResponse].self, from: data)
    }

    /// Ask a follow-up question about a content item.
    public func askFollowUp(contentID: String, question: String) async throws -> String {
        struct Req: Encodable { let question: String }
        struct Resp: Decodable { let text: String }
        let payload = try JSONEncoder().encode(Req(question: question))
        let data = try await request("/api/v1/content/\(contentID)/ask", method: "POST", body: payload)
        return try JSONDecoder().decode(Resp.self, from: data).text
    }

    /// Translate content summaries to a target language.
    /// - Parameters:
    ///   - contentID: The content ID to translate
    ///   - targetLanguage: ISO 639-1 language code (e.g., "en", "zh", "ja")
    /// - Returns: Content with translated L0 summary and L1 outline
    public func translateContent(contentID: String, targetLanguage: String) async throws -> Content {
        let data = try await request(
            "/api/v1/content/\(contentID)/translate?target_language=\(targetLanguage)",
            method: "POST"
        )
        return try JSONDecoder.apiDecoder.decode(Content.self, from: data)
    }

    /// Search across all content using a natural-language query.
    public func search(query: String) async throws -> SearchResult {
        struct Req: Encodable { let query: String }
        let payload = try JSONEncoder().encode(Req(query: query))
        let data = try await request("/api/v1/search/", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(SearchResult.self, from: data)
    }

    // MARK: - Tag Endpoints

    /// Fetch user's tag library with content counts.
    public func fetchUserTags() async throws -> [UserTag] {
        let data = try await request("/api/v1/tags")
        return try JSONDecoder.apiDecoder.decode([UserTag].self, from: data)
    }

    /// Create a new tag.
    /// - Parameter name: The name of the tag to create
    /// - Returns: The newly created tag
    public func createTag(name: String) async throws -> UserTag {
        struct Req: Encodable { let tag_name: String }
        let payload = try JSONEncoder().encode(Req(tag_name: name))
        let data = try await request("/api/v1/tags", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(UserTag.self, from: data)
    }

    /// Delete a tag (soft delete on backend).
    /// - Parameter id: The tag ID to delete
    public func deleteTag(id: Int) async throws {
        _ = try await request("/api/v1/tags/\(id)", method: "DELETE")
    }

    /// Update tags for a content item.
    /// Auto-creates tags that don't exist yet. Replaces all existing tags.
    /// - Parameters:
    ///   - contentId: The content ID to update
    ///   - tags: Array of tag names to assign to the content
    /// - Returns: The updated list of tags for the content
    public func updateContentTags(contentId: String, tags: [String]) async throws -> [UserTag] {
        struct Req: Encodable { let tag_names: [String] }
        let payload = try JSONEncoder().encode(Req(tag_names: tags))
        let data = try await request("/api/v1/tags/content/\(contentId)/tags", method: "PUT", body: payload)
        return try JSONDecoder.apiDecoder.decode([UserTag].self, from: data)
    }

    /// Fetch content items by tag.
    /// - Parameter tagId: The tag ID to filter by
    /// - Returns: Array of content items with the specified tag
    public func fetchContentsByTag(tagId: Int) async throws -> [Content] {
        let data = try await request("/api/v1/tags/\(tagId)/contents")
        return try JSONDecoder.apiDecoder.decode([Content].self, from: data)
    }

    // MARK: - Health

    /// Perform a health check against the backend API.
    /// - Returns: `true` if the server responds with a 2xx status.
    public func healthCheck() async throws -> Bool {
        _ = try await request("/health")
        return true
    }
}

// MARK: - Search Models

public struct SearchResult: Codable, Sendable {
    public let answer: String
    public let sources: [SearchSource]
}

public struct SearchSource: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let l0Summary: String?
    public let sourceURL: String?

    private enum CodingKeys: String, CodingKey {
        case id, title
        case l0Summary = "l0_summary"
        case sourceURL = "source_url"
    }
}

// MARK: - Paragraph Response

public struct ParagraphResponse: Codable, Sendable {
    public let anchorID: String
    public let text: String
    public let position: Int

    private enum CodingKeys: String, CodingKey {
        case anchorID = "anchor_id"
        case text, position
    }
}

// MARK: - Notification Names

extension Notification.Name {
    public static let refreshAuthToken = Notification.Name("refreshAuthToken")
}

// MARK: - JSON Decoder Extension

extension JSONDecoder {
    /// A shared decoder configured for the Readless API conventions.
    /// Models provide their own CodingKeys for snake_case mapping so
    /// we do NOT use `.convertFromSnakeCase` here (it would double-convert).
    public static let apiDecoder: JSONDecoder = {
        let d = JSONDecoder()
        let iso = ISO8601DateFormatter()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let str = try decoder.singleValueContainer().decode(String.self)
            if let date = isoFrac.date(from: str) { return date }
            if let date = iso.date(from: str) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Invalid date: \(str)"))
        }
        return d
    }()
}
