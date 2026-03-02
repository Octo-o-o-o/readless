import Foundation
import Networking
import Core

/// Manages authentication state and session
@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    // MARK: - Published State
    private(set) var currentUser: User?
    private(set) var isAuthenticated = false
    private(set) var isInitialized = false

    // MARK: - Private
    private var accessToken: String?
    private var refreshToken: String?
    private let keychain = KeychainService()

    private init() {
        print("[AuthService] Initializing...")
        Task {
            await restoreSession()
            isInitialized = true
            print("[AuthService] Initialization complete")
        }
    }

    // MARK: - Session Restoration

    private func restoreSession() async {
        guard let refreshToken = keychain.loadRefreshToken() else {
            print("[AuthService] No saved session found")
            return
        }

        self.refreshToken = refreshToken

        do {
            try await refreshAccessToken()
            print("[AuthService] Session restored")
        } catch {
            print("[AuthService] Session restoration failed: \(error)")
            clearSession()
        }
    }

    // MARK: - Authentication

    func register(email: String, password: String) async throws {
        let response = try await APIClient.shared.register(email: email, password: password)
        print("[AuthService] Registration successful. User ID: \(response.userId)")
        // User needs to verify email before logging in
    }

    func login(email: String, password: String) async throws {
        let response = try await APIClient.shared.login(email: email, password: password)

        self.accessToken = response.accessToken
        self.refreshToken = response.refreshToken
        self.currentUser = response.user
        self.isAuthenticated = true

        try keychain.saveRefreshToken(response.refreshToken)
        APIClient.shared.authToken = response.accessToken

        print("[AuthService] Logged in as: \(response.user.email ?? "unknown")")
    }

    func signOut() async throws {
        // TODO: Call logout endpoint when auth middleware is added
        clearSession()
        print("[AuthService] Signed out")
    }

    // MARK: - Token Management

    func refreshAccessToken() async throws {
        guard let refreshToken = self.refreshToken else {
            throw AuthError.noRefreshToken
        }

        let response = try await APIClient.shared.refreshToken(refreshToken)
        self.accessToken = response.accessToken
        APIClient.shared.authToken = response.accessToken

        // TODO: Fetch current user info
        // For now, keep existing user or create placeholder
        if currentUser == nil {
            currentUser = User(
                id: UUID(),
                email: nil,
                subscriptionTier: .trial,
                trialExpiresAt: nil,
                subscriptionExpiresAt: nil,
                emailVerified: false,
                createdAt: Date()
            )
        }
        self.isAuthenticated = true

        print("[AuthService] Token refreshed")
    }

    private func clearSession() {
        self.accessToken = nil
        self.refreshToken = nil
        self.currentUser = nil
        self.isAuthenticated = false
        APIClient.shared.authToken = nil
        keychain.deleteRefreshToken()
    }
}

// MARK: - Auth Error

enum AuthError: Error {
    case noRefreshToken
}
