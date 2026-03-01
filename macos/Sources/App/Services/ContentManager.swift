import Foundation
import AppKit
import Core
import Networking
import UI

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

    /// Fetch the content list from the backend API.
    func loadContents() async {
        do {
            contents = try await api.listContents()
        } catch {
            // Silently handle errors for now; the UI will show an empty state.
        }
    }

    /// Filter content items by tag
    func filterByTag(tagId: Int) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let filteredContent = try await api.fetchContentsByTag(tagId: tagId)
            contents = filteredContent
            error = nil
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
            let updatedContent = try await api.fetchContent(id: id)

            // Update in array
            if let index = contents.firstIndex(where: { $0.id == id }) {
                contents[index] = updatedContent
            }

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
