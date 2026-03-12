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

public struct SendEmailCodeRequest: Codable {
    let email: String
}

public struct SendEmailCodeResponse: Codable {
    public let message: String
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case message
        case expiresIn = "expires_in"
    }
}

public struct VerifyEmailCodeRequest: Codable {
    let email: String
    let code: String
}

public struct EmailCodeLoginResponse: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
    public let user: User
    public let isNewUser: Bool

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
        case isNewUser = "is_new_user"
    }
}

public struct AppleSignInRequest: Codable {
    let identityToken: String

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
    }
}

public struct AppleSignInResponse: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresIn: Int
    public let user: User
    public let isNewUser: Bool

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
        case isNewUser = "is_new_user"
    }
}

public struct RefreshTokenRequest: Codable {
    let refreshToken: String
    let rotateRefreshToken: Bool

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
        case rotateRefreshToken = "rotate_refresh_token"
    }
}

public struct RefreshTokenResponse: Codable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

public struct MessageResponse: Codable {
    public let message: String
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

    public func sendEmailLoginCode(email: String) async throws -> SendEmailCodeResponse {
        let req = SendEmailCodeRequest(email: email)
        let payload = try JSONEncoder().encode(req)
        let data = try await request("/api/v1/auth/email/send-code", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(SendEmailCodeResponse.self, from: data)
    }

    public func verifyEmailLoginCode(email: String, code: String) async throws -> EmailCodeLoginResponse {
        let req = VerifyEmailCodeRequest(email: email, code: code)
        let payload = try JSONEncoder().encode(req)
        let data = try await request("/api/v1/auth/email/verify-code", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(EmailCodeLoginResponse.self, from: data)
    }

    public func appleSignIn(identityToken: String) async throws -> AppleSignInResponse {
        let req = AppleSignInRequest(identityToken: identityToken)
        let payload = try JSONEncoder().encode(req)
        let data = try await request("/api/v1/auth/apple-signin", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(AppleSignInResponse.self, from: data)
    }

    public func refreshToken(_ refreshToken: String) async throws -> RefreshTokenResponse {
        let req = RefreshTokenRequest(
            refreshToken: refreshToken,
            rotateRefreshToken: true
        )
        let payload = try JSONEncoder().encode(req)
        let data = try await request("/api/v1/auth/refresh", method: "POST", body: payload)
        return try JSONDecoder.apiDecoder.decode(RefreshTokenResponse.self, from: data)
    }

    public func logout() async throws -> MessageResponse {
        let data = try await request("/api/v1/auth/logout", method: "POST")
        return try JSONDecoder.apiDecoder.decode(MessageResponse.self, from: data)
    }

    public func getCurrentUser() async throws -> User {
        let data = try await request("/api/v1/auth/me")
        return try JSONDecoder.apiDecoder.decode(User.self, from: data)
    }
}
