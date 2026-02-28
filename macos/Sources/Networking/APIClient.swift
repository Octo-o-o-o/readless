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

public final class APIClient: Sendable {
    public let baseURL: URL
    private let authToken: String?
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "http://localhost:8000")!,
        authToken: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authToken = authToken
        self.session = session
    }

    // MARK: - Generic Request

    private func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
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
}

// MARK: - JSON Decoder Extension

extension JSONDecoder {
    /// A shared decoder configured for the Readless API's snake_case + ISO-8601 conventions.
    public static let apiDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
