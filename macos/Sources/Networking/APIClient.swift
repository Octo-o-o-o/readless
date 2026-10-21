import Foundation
import Core

// MARK: - API Client Errors

public enum APIError: Error, Sendable, LocalizedError {
    case invalidURL
    case unauthorized(String?)
    case serverError(Int, String?)
    case networkError(Error)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .unauthorized(let message):
            return message ?? "Your session has expired. Please log in again."
        case .serverError(let code, let message):
            if let message = message {
                return message
            }
            switch code {
            case 400:
                return "Invalid request. Please try again."
            case 401:
                return "Your session has expired. Please log in again."
            case 403:
                return "Access denied. Please check your subscription status."
            case 404:
                return "Content not found."
            case 500...599:
                return "Server error. Please try again later."
            default:
                return "An error occurred. Please try again."
            }
        case .networkError:
            return "Could not connect to server. Please check your internet connection."
        case .decodingError:
            return "Received invalid data from server. Please try again."
        }
    }
}

// Keep legacy name so existing test references still compile.
public typealias APIClientError = APIError

// MARK: - API Client

public final class APIClient: @unchecked Sendable {
    public static let shared = APIClient()

    public let baseURL: URL
    /// Thread-safe auth token storage.
    /// Written from `@MainActor` (AuthService), read from any async context.
    private let _tokenLock = NSLock()
    private var _authToken: String?
    public var authToken: String? {
        get { _tokenLock.withLock { _authToken } }
        set { _tokenLock.withLock { _authToken = newValue } }
    }
    private let transport: HTTPTransport
    private let refreshCoordinator: AuthRefreshCoordinator

    /// Get configured API base URL from UserDefaults or use production by default.
    private static func getConfiguredBaseURL() -> URL {
        // Read configured URL from app defaults first.
        // Also check the explicit domain to support builds launched outside the
        // standard app defaults search path without using suiteName.
        if let urlString = (
            UserDefaults.standard.string(forKey: "apiBaseURL")
                ?? UserDefaults.standard
                    .persistentDomain(forName: "com.readless.app")?["apiBaseURL"] as? String
        ),
           let url = URL(string: urlString) {
            print("[Readless] Using configured API base URL: \(urlString)")
            return url
        }

        // Fallback to production backend.
        let defaultURL = URL(string: "https://readless.cc")!
        print("[Readless] Using default API base URL: \(defaultURL.absoluteString)")
        return defaultURL
    }

    public init(
        baseURL: URL? = nil,
        authToken: String? = nil,
        session: URLSession = .shared,
        transport: HTTPTransport? = nil,
        refreshCoordinator: AuthRefreshCoordinator = AuthRefreshCoordinator()
    ) {
        self.baseURL = baseURL ?? Self.getConfiguredBaseURL()
        self._authToken = authToken
        self.transport = transport ?? HTTPTransport(session: session)
        self.refreshCoordinator = refreshCoordinator
    }

    struct RequestTarget: Sendable {
        let path: String
        let queryItems: [URLQueryItem]

        init(path: String, queryItems: [URLQueryItem] = []) {
            self.path = path
            self.queryItems = queryItems
        }
    }

    // MARK: - Generic Request

    func request(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil,
        isRetry: Bool = false
    ) async throws -> Data {
        let target = RequestTarget(path: path, queryItems: queryItems)
        return try await request(target, method: method, body: body, isRetry: isRetry)
    }

    private func request(
        _ target: RequestTarget,
        method: String,
        body: Data?,
        isRetry: Bool
    ) async throws -> Data {
        let url = try makeURL(for: target)

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #if DEBUG
        if authToken == nil {
            print("[APIClient] ⚠️ Request to \(url) WITHOUT auth token")
        }
        #endif

        req.httpBody = body

        do {
            let result = try await transport.send(req)
            let data = result.data
            let http = result.httpResponse

            print("[APIClient] 📡 Response status: \(http.statusCode)")

            guard 200..<300 ~= http.statusCode else {
                print("[APIClient] ❌ Server error: \(http.statusCode)")

                let backendMessage = parseBackendErrorMessage(from: data)

                if shouldAttemptTokenRefresh(
                    path: target.path,
                    statusCode: http.statusCode,
                    isRetry: isRetry
                ) {
                    print("[APIClient] 🔄 Token expired, attempting refresh and retry...")
                    let refreshed = await refreshCoordinator.refreshTokenIfNeeded()
                    if refreshed {
                        return try await request(
                            target,
                            method: method,
                            body: body,
                            isRetry: true
                        )
                    }
                    print("[APIClient] ❌ Token refresh failed or timed out")
                }

                // Throw appropriate error with parsed message
                if http.statusCode == 401 {
                    throw APIError.unauthorized(backendMessage)
                } else {
                    throw APIError.serverError(http.statusCode, backendMessage)
                }
            }

            return data
        } catch let error as APIError {
            throw error
        } catch {
            print("[APIClient] ❌ Network error: \(error.localizedDescription)")
            throw APIError.networkError(error)
        }
    }

    private func makeURL(for target: RequestTarget) throws -> URL {
        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            print("[APIClient] ❌ Invalid base URL: \(baseURL)")
            throw APIError.invalidURL
        }

        components.path = Self.joinPaths(
            basePath: components.path,
            endpointPath: target.path
        )
        components.queryItems = target.queryItems.isEmpty ? nil : target.queryItems

        guard let url = components.url else {
            print("[APIClient] ❌ Failed to build URL for path: \(target.path)")
            throw APIError.invalidURL
        }
        return url
    }

    private static func joinPaths(basePath: String, endpointPath: String) -> String {
        let trimmedBase = basePath == "/" ? "" : basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedEndpoint = endpointPath.hasPrefix("/") ? endpointPath : "/\(endpointPath)"
        let endpointBody = normalizedEndpoint.dropFirst()

        guard !trimmedBase.isEmpty else {
            return normalizedEndpoint
        }

        let combined = "/" + trimmedBase + "/" + endpointBody
        return combined.replacingOccurrences(of: "//", with: "/")
    }

    private func parseBackendErrorMessage(from data: Data) -> String? {
        guard let errorMessage = String(data: data, encoding: .utf8) else {
            return nil
        }
        print("[APIClient] Error response: \(errorMessage)")
        guard
            let errorData = errorMessage.data(using: .utf8),
            let errorDict = try? JSONSerialization.jsonObject(with: errorData)
                as? [String: Any]
        else {
            return nil
        }
        return errorDict["detail"] as? String
    }

    private func shouldAttemptTokenRefresh(
        path: String,
        statusCode: Int,
        isRetry: Bool
    ) -> Bool {
        statusCode == 401
            && authToken != nil
            && !isRetry
            && !path.contains("/api/v1/auth/refresh")
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
    public func listContents(offset: Int = 0, limit: Int = 50) async throws -> [Content] {
        let data = try await request(
            "/api/v1/content/",
            queryItems: [
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        return try JSONDecoder.apiDecoder.decode([Content].self, from: data)
    }

    /// Fetch lightweight processing statuses for a batch of content IDs.
    public func fetchContentStatuses(ids: [String]) async throws -> [ContentStatusSnapshot] {
        guard !ids.isEmpty else { return [] }
        let data = try await request(
            "/api/v1/content/statuses",
            queryItems: ids.map { URLQueryItem(name: "ids", value: $0) }
        )
        return try JSONDecoder.apiDecoder.decode([ContentStatusSnapshot].self, from: data)
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
    public func fetchContent(id: String) async throws -> Content {
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
            "/api/v1/content/\(contentID)/translate",
            queryItems: [URLQueryItem(name: "target_language", value: targetLanguage)],
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

    /// Retrieve lightweight search candidates for interactive suggestion UIs.
    public func searchRetrieve(query: String) async throws -> [SearchSource] {
        struct Req: Encodable { let query: String }
        let payload = try JSONEncoder().encode(Req(query: query))
        let data = try await request("/api/v1/search/retrieve", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode([SearchSource].self, from: data)
    }

    // MARK: - Tag Endpoints

    /// Fetch user's tag library with content counts.
    public func fetchUserTags() async throws -> [UserTag] {
        let data = try await request("/api/v1/tags/")
        return try JSONDecoder.apiDecoder.decode([UserTag].self, from: data)
    }

    /// Create a new tag.
    /// - Parameter name: The name of the tag to create
    /// - Returns: The newly created tag
    public func createTag(name: String) async throws -> UserTag {
        struct Req: Encodable { let tag_name: String }
        let payload = try JSONEncoder().encode(Req(tag_name: name))
        let data = try await request("/api/v1/tags/", method: "POST", body: payload)
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

public struct ContentStatusSnapshot: Codable, Sendable {
    public let id: String
    public let status: ContentStatus
    public let updatedAt: Date?
    public let l0Summary: String?
    public let processingError: String?

    public init(
        id: String,
        status: ContentStatus,
        updatedAt: Date?,
        l0Summary: String?,
        processingError: String?
    ) {
        self.id = id
        self.status = status
        self.updatedAt = updatedAt
        self.l0Summary = l0Summary
        self.processingError = processingError
    }

    private enum CodingKeys: String, CodingKey {
        case id, status
        case updatedAt = "updated_at"
        case l0Summary = "l0_summary"
        case processingError = "processing_error"
    }
}

// MARK: - Notification Names

extension Notification.Name {
    public static let refreshAuthToken = Notification.Name("refreshAuthToken")
    public static let authTokenRefreshCompleted = Notification.Name("authTokenRefreshCompleted")
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
