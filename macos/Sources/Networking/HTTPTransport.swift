import Foundation

public struct HTTPTransportResponse: Sendable {
    public let data: Data
    public let httpResponse: HTTPURLResponse
}

public final class HTTPTransport: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPTransportResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(0, "Invalid response type")
        }
        return HTTPTransportResponse(data: data, httpResponse: http)
    }
}
