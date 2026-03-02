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
            showToast("Import failed: \(error.localizedDescription)")
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
            showToast("Import failed: \(error.localizedDescription)")
        }
    }

    /// Cancel any in-progress import and dismiss the capsule.
    func cancelProcessing() {
        capsuleState = .dismissed
        processingContent = nil
    }

    // MARK: - Data Loading

    /// Fetch the content list from the backend API and local cache.
    /// Merges backend data with local cache, prioritizing backend data when available.
    func loadContents() async {
        do {
            // Try to load from backend first
            let userId = currentUserId
            contents = try await api.listContents()

            // Save to local cache for offline access
            for content in contents {
                try? await database.saveContent(content, userId: userId)
            }
        } catch {
            // Fallback to local cache if backend is unavailable
            do {
                let userId = currentUserId
                let cached = try await database.fetchContents(userId: userId)
                if !cached.isEmpty {
                    contents = cached
                    print("[ContentManager] Loaded \(cached.count) items from local cache")
                }
            } catch {
                print("[ContentManager] Failed to load from cache: \(error)")
            }
        }
    }

    /// Filter content items by tag
    func filterByTag(tagId: Int) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let userId = currentUserId
            let filteredContent = try await api.fetchContentsByTag(tagId: tagId)
            contents = filteredContent
            error = nil

            // Cache filtered content
            for content in filteredContent {
                try? await database.saveContent(content, userId: userId)
            }
        } catch {
            self.error = error
            print("[ContentManager] Failed to filter by tag: \(error)")
        }
    }

    /// Clear tag filter and show all content
    func clearTagFilter() async {
        await loadContents()
    }

    /// Refresh a single content item by fetching its latest data
    func refreshContent(id: String) async {
        do {
            let userId = currentUserId
            let updatedContent = try await api.fetchContent(id: id)

            // Update in array
            if let index = contents.firstIndex(where: { $0.id == id }) {
                contents[index] = updatedContent
            }

            // Update in cache
            try await database.saveContent(updatedContent, userId: userId)

            error = nil
        } catch {
            self.error = error
            print("[ContentManager] Failed to refresh content: \(error)")
        }
    }

    // MARK: - Notifications

    private func showToast(_ message: String) {
        NotificationCenter.default.post(name: .showToast, object: message)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showToast = Notification.Name("showToast")
}
