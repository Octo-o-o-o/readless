import Foundation
import Core
import Networking

/// Manages user's tag library and tag filtering
@Observable
@MainActor
final class TagManager {
    private let apiClient: APIClient

    // MARK: - State

    /// User's tag library
    var userTags: [UserTag] = []

    /// Currently selected tag for filtering (nil = show all)
    var selectedTagId: Int?

    /// Loading state
    var isLoading = false

    /// Error state
    var error: Error?

    // MARK: - Initialization

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    // MARK: - Public Methods

    /// Load user's tag library
    func loadUserTags() async {
        isLoading = true
        defer { isLoading = false }

        do {
            userTags = try await apiClient.fetchUserTags()
            error = nil
        } catch {
            self.error = error
            print("[TagManager] Failed to load tags: \(error)")
        }
    }

    /// Create a new tag
    func createTag(name: String) async throws {
        let tag = try await apiClient.createTag(name: name)
        userTags.append(tag)
        error = nil
    }

    /// Delete a tag
    func deleteTag(id: Int) async throws {
        try await apiClient.deleteTag(id: id)
        userTags.removeAll { $0.id == id }

        // Clear selection if deleted tag was selected
        if selectedTagId == id {
            selectedTagId = nil
        }

        error = nil
    }

    /// Select a tag for filtering (nil to show all)
    func selectTag(_ tagId: Int?) {
        selectedTagId = tagId
    }

    /// Clear tag selection
    func clearSelection() {
        selectedTagId = nil
    }
}
