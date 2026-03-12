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
    private var refreshObserver: NSObjectProtocol?

    private init() {
        print("[AuthService] Initializing...")
        setupTokenRefreshObserver()
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
        try applySession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            user: response.user
        )
        print("[AuthService] Logged in as: \(response.user.email ?? "unknown")")
    }

    func sendLoginCode(email: String) async throws {
        _ = try await APIClient.shared.sendEmailLoginCode(email: email)
    }

    func loginWithCode(email: String, code: String) async throws {
        let response = try await APIClient.shared.verifyEmailLoginCode(email: email, code: code)
        try applySession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            user: response.user
        )
        print("[AuthService] Logged in with code as: \(response.user.email ?? "unknown")")
    }

    func signInWithApple(identityToken: String) async throws {
        let response = try await APIClient.shared.appleSignIn(identityToken: identityToken)
        try applySession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            user: response.user
        )
        print("[AuthService] Apple login success: \(response.user.email ?? "unknown")")
    }

    func signOut() async throws {
        var logoutError: Error?

        if isAuthenticated, accessToken != nil {
            do {
                _ = try await APIClient.shared.logout()
            } catch {
                logoutError = error
            }
        }

        clearSession()
        print("[AuthService] Signed out")

        if let logoutError {
            throw logoutError
        }
    }

    // MARK: - Token Management

    func refreshAccessToken() async throws {
        guard let refreshToken = self.refreshToken else {
            throw AuthError.noRefreshToken
        }

        let response = try await APIClient.shared.refreshToken(refreshToken)
        if let rotatedRefreshToken = response.refreshToken {
            try keychain.saveRefreshToken(rotatedRefreshToken)
            self.refreshToken = rotatedRefreshToken
        }
        self.accessToken = response.accessToken
        APIClient.shared.authToken = response.accessToken

        // Keep local user state in sync with backend after refresh.
        self.currentUser = try await APIClient.shared.getCurrentUser()
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

    private func applySession(accessToken: String, refreshToken: String, user: User) throws {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.currentUser = user
        self.isAuthenticated = true
        APIClient.shared.authToken = accessToken
        try keychain.saveRefreshToken(refreshToken)
    }

    private func setupTokenRefreshObserver() {
        refreshObserver = NotificationCenter.default.addObserver(
            forName: .refreshAuthToken,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try await self.refreshAccessToken()
                    NotificationCenter.default.post(
                        name: .authTokenRefreshCompleted,
                        object: nil,
                        userInfo: ["success": true]
                    )
                } catch {
                    NotificationCenter.default.post(
                        name: .authTokenRefreshCompleted,
                        object: nil,
                        userInfo: ["success": false]
                    )
                }
            }
        }
    }
}

// MARK: - Auth Error

enum AuthError: Error {
    case noRefreshToken
}
