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

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw APIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
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

    /// Search across all content using a natural-language query.
    public func search(query: String) async throws -> SearchResult {
        struct Req: Encodable { let query: String }
        let payload = try JSONEncoder().encode(Req(query: query))
        let data = try await request("/api/v1/search/", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(SearchResult.self, from: data)
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
