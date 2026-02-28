import Foundation
import Core

// MARK: - API Client Errors

public enum APIClientError: Error, Sendable {
    case invalidURL
    case unauthorized
    case serverError(statusCode: Int)
    case networkError(Error)
    case decodingError(Error)
}

// MARK: - API Client

public final class APIClient: Sendable {
    public let baseURL: URL
    private let authToken: String?
    private let session: URLSession

    public init(
        baseURL: URL,
        authToken: String? = nil,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.authToken = authToken
        self.session = session
    }

    /// Perform a health check against the backend API.
    /// - Returns: `true` if the server responds with a 2xx status.
    public func healthCheck() async throws -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(to: &request)

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return (200..<300).contains(httpResponse.statusCode)
    }

    // MARK: - Private Helpers

    private func applyAuth(to request: inout URLRequest) {
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
