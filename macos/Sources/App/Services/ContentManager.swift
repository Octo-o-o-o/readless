import Foundation
import AppKit
import Core
import Networking
import UI
import Storage

// MARK: - Content Manager

/// Coordinates content imports between the macOS client and the backend API.
///
/// `ContentManager` is the central bridge that takes raw text from hotkeys,
/// clipboard, or drag-and-drop, sends it to the FastAPI backend for processing,
/// and manages the resulting content list.
@MainActor
@Observable
final class ContentManager {
    static let shared = ContentManager()

    // MARK: - Published State

    var contents: [Content] = []
    var processingContent: Content?
    var capsuleState: CapsuleState = .dismissed
    var showResultPanel: Bool = false
    var isLoading: Bool = false
    var error: Error?

    // MARK: - Private

    private let api = APIClient.shared
    private let database = LocalDatabase.shared
    private var lastLoadedUserId: String?

    /// Get current user ID for database filtering
    private var currentUserId: String? {
        AuthService.shared.currentUser?.id.uuidString
    }

    private init() {}

    // MARK: - Import Methods

    /// Import content silently -- saves in the background with a brief toast notification.
    func importSilently(text: String, appName: String?, bundleID: String?, sourceType: String? = nil) async {
        showToast("Received from \(appName ?? "clipboard")")
        do {
            let sourceType = sourceType ?? (text.hasPrefix("http") ? "url" : "text")
            let content = try await api.createContent(
                sourceType: sourceType,
                body: text,
                appName: appName,
                bundleID: bundleID
            )
            contents.insert(content, at: 0)

            // Save to local cache
            try await database.saveContent(content, userId: currentUserId)
        } catch {
            // Show user-friendly error message
            let message = userFriendlyErrorMessage(for: error)
            showToast(message)
        }
    }

    /// Import content and display the floating capsule progress, then show the result panel.
    func importAndDisplay(text: String, appName: String?, bundleID: String?) async {
        capsuleState = .processing
        do {
            let sourceType = text.hasPrefix("http") ? "url" : "text"
            let content = try await api.createContent(
                sourceType: sourceType,
                body: text,
                appName: appName,
                bundleID: bundleID
            )
            contents.insert(content, at: 0)
            processingContent = content
            capsuleState = .completed

            // Save to local cache
            try await database.saveContent(content, userId: currentUserId)

            // Brief delay before transitioning to the result panel.
            try? await Task.sleep(for: .milliseconds(500))
            if capsuleState == .completed {
                showResultPanel = true
                capsuleState = .dismissed
            }
        } catch {
            capsuleState = .dismissed
            // Show user-friendly error message
            let message = userFriendlyErrorMessage(for: error)
            showToast(message)
        }
    }

    /// Cancel any in-progress import and dismiss the capsule.
    func cancelProcessing() {
        capsuleState = .dismissed
        processingContent = nil
    }

    // MARK: - Data Loading

    /// Load content list with a cache-first strategy:
    /// 1) Show local cache immediately (fast UI)
    /// 2) Refresh from backend in background (fresh data)
    func loadContents() async {
        isLoading = true
        defer { isLoading = false }

        let userId = currentUserId
        if lastLoadedUserId != userId {
            contents = []
            lastLoadedUserId = userId
        }

        // Claim legacy cache rows (user_id was added in v4; older rows are NULL).
        if let userId {
            try? await database.claimLegacyCache(userId: userId)
        }

        // 1) Preload from local cache (instant list)
        do {
            let cached = try await database.fetchContents(userId: userId)
            if !cached.isEmpty {
                contents = cached
                print("[ContentManager] Preloaded \(cached.count) items from local cache")
            }
        } catch {
            print("[ContentManager] Failed to preload cache: \(error)")
        }

        // 2) Refresh from backend
        do {
            let fresh = try await api.listContents()
            contents = fresh
            error = nil
            await cacheContents(fresh)
        } catch {
            // Keep cached list if refresh fails
            self.error = error
            print("[ContentManager] Failed to refresh content list: \(error)")
        }
    }

    /// Filter content items by tag.
    func filterByTag(tagId: Int) async {
        isLoading = true
        defer { isLoading = false }

        do {
            contents = try await api.fetchContentsByTag(tagId: tagId)
            error = nil
            await cacheContents(contents)
        } catch {
            self.error = error
            print("[ContentManager] Failed to filter by tag: \(error)")
        }
    }

    /// Clear tag filter and show all content.
    func clearTagFilter() async {
        await loadContents()
    }

    /// Refresh a single content item by fetching its latest data.
    func refreshContent(id: String) async {
        do {
            let updatedContent = try await api.fetchContent(id: id)

            if let index = contents.firstIndex(where: { $0.id == id }) {
                contents[index] = updatedContent
            }

            try? await database.saveContent(updatedContent, userId: currentUserId)
            error = nil
        } catch {
            self.error = error
            print("[ContentManager] Failed to refresh content: \(error)")
        }
    }

    /// Save an array of content items to local cache.
    private func cacheContents(_ items: [Content]) async {
        let userId = currentUserId
        for content in items {
            try? await database.saveContent(content, userId: userId)
        }
    }

    // MARK: - Notifications

    private func showToast(_ message: String) {
        NotificationCenter.default.post(name: .showToast, object: message)
    }

    /// Convert technical errors into user-friendly messages
    private func userFriendlyErrorMessage(for error: Error) -> String {
        // Check for API errors first (most specific)
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }

        // Check for network errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection. Please check your network."
            case .timedOut:
                return "Request timed out. Please try again."
            case .cannotFindHost, .cannotConnectToHost:
                return "Could not connect to server. Please try again later."
            default:
                return "Network error. Please check your connection."
            }
        }

        // Fallback to generic message
        return "Import failed. Please try again."
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showToast = Notification.Name("showToast")
}
