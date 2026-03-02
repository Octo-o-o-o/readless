import Foundation
import Core

// MARK: - Auth Request/Response Models

public struct RegisterRequest: Codable {
    let email: String
    let password: String
}

public struct RegisterResponse: Codable {
    public let message: String
    public let userId: UUID
    public let trialExpiresAt: Date

    enum CodingKeys: String, CodingKey {
        case message
        case userId = "user_id"
        case trialExpiresAt = "trial_expires_at"
    }
}

public struct LoginRequest: Codable {
    let email: String
    let password: String
}

public struct LoginResponse: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
    public let user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

public struct RefreshTokenRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

public struct RefreshTokenResponse: Codable {
    public let accessToken: String
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
    }
}

// MARK: - API Client Auth Extension

extension APIClient {
    public func register(email: String, password: String) async throws -> RegisterResponse {
        let req = RegisterRequest(email: email, password: password)
        let payload = try JSONEncoder().encode(req)
        let data = try await request("/api/v1/auth/register", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(RegisterResponse.self, from: data)
    }

    public func login(email: String, password: String) async throws -> LoginResponse {
        let req = LoginRequest(email: email, password: password)
        let payload = try JSONEncoder().encode(req)
        let data = try await request("/api/v1/auth/login", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(LoginResponse.self, from: data)
    }

    public func refreshToken(_ refreshToken: String) async throws -> RefreshTokenResponse {
        let req = RefreshTokenRequest(refreshToken: refreshToken)
        let payload = try JSONEncoder().encode(req)
        let data = try await request("/api/v1/auth/refresh", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(RefreshTokenResponse.self, from: data)
    }
}
