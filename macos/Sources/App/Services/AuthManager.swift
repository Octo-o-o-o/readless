import Foundation
import Networking
import ClerkKit

/// Manages authentication state and synchronizes Clerk session with APIClient
@MainActor
@Observable
final class AuthManager {
    /// Shared singleton instance
    static let shared = AuthManager()

    /// Reference to Clerk instance
    private var clerk: Clerk { Clerk.shared }

    /// Whether the user is currently authenticated
    var isAuthenticated: Bool {
        clerk.user != nil
    }

    /// Current user ID (if authenticated)
    var userId: String? {
        clerk.user?.id
    }

    private init() {
        print("[AuthManager] 🚀 AuthManager initializing...")

        // Observe Clerk session changes and sync to APIClient
        Task { @MainActor in
            print("[AuthManager] 🔄 Starting session observation...")
            await observeSessionChanges()
            print("[AuthManager] ✅ Session observation complete")
        }

        // Listen for token refresh requests
        NotificationCenter.default.addObserver(
            forName: .refreshAuthToken,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                do {
                    try await self.refreshToken()
                } catch {
                    print("[AuthManager] ❌ Auto-refresh failed: \(error)")
                }
            }
        }
    }

    // MARK: - Session Observation

    /// Observe Clerk session changes and update APIClient token
    private func observeSessionChanges() async {
        // Get initial token if user is already signed in
        if let session = clerk.session {
            do {
                if let token = try await session.getToken() {
                    APIClient.shared.authToken = token
                    print("[AuthManager] ✅ Initial session token synced to APIClient")
                    print("[AuthManager] Token preview: \(String(token.prefix(20)))...")
                } else {
                    print("[AuthManager] ⚠️ Session exists but getToken() returned nil")
                }
            } catch {
                print("[AuthManager] ❌ Failed to get initial token: \(error)")
            }
        } else {
            print("[AuthManager] ℹ️ No active session at startup")
        }

        // Monitor session changes (Clerk SDK should provide session observers)
        // For now, we'll update token manually when needed
        // In a production app, you'd use Clerk's session change notifications
    }

    // MARK: - Authentication Actions

    /// Sign out the current user
    func signOut() async throws {
        try await clerk.auth.signOut()
        APIClient.shared.authToken = nil
        print("[AuthManager] ✅ Signed out, token cleared from APIClient")
    }

    /// Manually refresh and sync the session token to APIClient
    func refreshToken() async throws {
        guard let session = clerk.session else {
            print("[AuthManager] ⚠️ No active session to refresh")
            return
        }

        if let token = try await session.getToken() {
            APIClient.shared.authToken = token
            print("[AuthManager] ✅ Token refreshed and synced to APIClient")
            print("[AuthManager] Token preview: \(String(token.prefix(20)))...")
            print("[AuthManager] API base URL: \(APIClient.shared.baseURL)")
        } else {
            print("[AuthManager] ⚠️ Session exists but getToken() returned nil")
        }
    }
}
