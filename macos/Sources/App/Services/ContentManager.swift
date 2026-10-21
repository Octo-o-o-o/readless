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

    @ObservationIgnored
    private let repository: ContentRepository
    @ObservationIgnored
    private var lastLoadedUserId: String?
    private typealias ProcessingBehavior = ImportTrackingCoordinator.TrackingBehavior
    @ObservationIgnored
    private var importTracker: ImportTrackingCoordinator! = nil
    private let completionDelay: Duration = .milliseconds(500)

    /// Get current user ID for database filtering
    private var currentUserId: String? {
        AuthService.shared.currentUser?.id.uuidString
    }

    private init(repository: ContentRepository = ContentRepository()) {
        self.repository = repository
        self.importTracker = makeImportTracker()
    }

    // MARK: - Import Methods

    /// Import content silently -- saves in the background with a brief toast notification.
    func importSilently(text: String, appName: String?, bundleID: String?, sourceType: String? = nil) async {
        showToast("Received from \(appName ?? "clipboard")")
        do {
            let sourceType = sourceType ?? (text.hasPrefix("http") ? "url" : "text")
            let content = try await repository.createContent(
                sourceType: sourceType,
                body: text,
                appName: appName,
                bundleID: bundleID
            )
            upsertContent(content)
            try await repository.cacheContent(content, userId: currentUserId)
            await startTrackingIfNeeded(content, behavior: .silentImport)
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
            let content = try await repository.createContent(
                sourceType: sourceType,
                body: text,
                appName: appName,
                bundleID: bundleID
            )
            upsertContent(content)
            try await repository.cacheContent(content, userId: currentUserId)
            processingContent = content
            await startTrackingIfNeeded(content, behavior: .displayImport)
        } catch {
            capsuleState = .dismissed
            // Show user-friendly error message
            let message = userFriendlyErrorMessage(for: error)
            showToast(message)
        }
    }

    /// Import content quietly — no capsule, no toast. For use from Command Bar.
    func importQuietly(text: String, appName: String?, bundleID: String?) async throws -> Content {
        let sourceType = text.hasPrefix("http") ? "url" : "text"
        let content = try await repository.createContent(
            sourceType: sourceType,
            body: text,
            appName: appName,
            bundleID: bundleID
        )
        upsertContent(content)
        try await repository.cacheContent(content, userId: currentUserId)
        await startTrackingIfNeeded(content, behavior: .quietImport)
        return content
    }

    /// Cancel any in-progress import and dismiss the capsule.
    func cancelProcessing() {
        capsuleState = .dismissed
        if let contentID = processingContent?.id {
            Task {
                await importTracker.disableInteractiveBehavior(contentID: contentID)
            }
        }
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

        // Claim legacy cache rows (user_id was added in v4; older rows are NULL).
        if let userId {
            try? await repository.claimLegacyCache(userId: userId)
        }

        // 1) Preload from local cache — merge with user-switch clear into one assignment
        if lastLoadedUserId != userId {
            lastLoadedUserId = userId
            let cached = (try? await repository.fetchCachedContents(userId: userId)) ?? []
            contents = cached  // single render: either cached data or empty
            if !cached.isEmpty {
                print("[ContentManager] Preloaded \(cached.count) items from local cache")
            }
            await resumeBackgroundTracking(for: cached)
        } else {
            if let cached = try? await repository.fetchCachedContents(userId: userId), !cached.isEmpty {
                contents = cached
                print("[ContentManager] Preloaded \(cached.count) items from local cache")
                await resumeBackgroundTracking(for: cached)
            }
        }

        // 2) Refresh from backend — only assign if data actually changed
        do {
            let fresh = try await repository.listContents()
            if fresh != contents {
                contents = fresh
                await cacheContents(fresh)
            }
            error = nil
            await resumeBackgroundTracking(for: fresh)
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
            contents = try await repository.fetchContentsByTag(tagId: tagId)
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
            let updatedContent = try await repository.fetchContent(id: id)
            upsertContent(updatedContent)
            try? await repository.cacheContent(updatedContent, userId: currentUserId)
            await startTrackingIfNeeded(updatedContent, behavior: .background)
            notifyContentUpdated(updatedContent)
            error = nil
        } catch {
            self.error = error
            print("[ContentManager] Failed to refresh content: \(error)")
        }
    }

    /// Save an array of content items to local cache in a single transaction.
    private func cacheContents(_ items: [Content]) async {
        try? await repository.cacheContents(items, userId: currentUserId)
    }

    private func upsertContent(_ content: Content) {
        if let index = contents.firstIndex(where: { $0.id == content.id }) {
            contents[index] = content
        } else {
            contents.insert(content, at: 0)
        }
    }

    private func resumeBackgroundTracking(for items: [Content]) async {
        await importTracker.resumeBackgroundTracking(for: items)
    }

    private func startTrackingIfNeeded(_ content: Content, behavior: ProcessingBehavior) async {
        if behavior.showResultOnReady || behavior.keepsCapsule {
            processingContent = content
        }

        await importTracker.trackIfNeeded(content, behavior: behavior)
    }

    private func handleTrackedContentFailure(_ content: Content, behavior: ProcessingBehavior) {
        if behavior.keepsCapsule {
            capsuleState = .dismissed
        }

        if behavior.showFailureToast {
            showToast(content.l0Summary ?? "Import failed. Please try again.")
        }

        if processingContent?.id == content.id {
            processingContent = content
        }
    }

    private func handleTrackedContentReady(_ content: Content, behavior: ProcessingBehavior) {
        if behavior.showResultOnReady {
            processingContent = content
        }

        if behavior.keepsCapsule {
            capsuleState = .completed
            Task { @MainActor [weak self] in
                guard let self else { return }
                try? await Task.sleep(for: self.completionDelay)
                guard self.capsuleState == .completed else { return }
                if behavior.showResultOnReady {
                    self.showResultPanel = true
                }
                self.capsuleState = .dismissed
            }
        } else if behavior.showResultOnReady {
            showResultPanel = true
        }
    }

    private func handleTrackedContentUpdate(_ content: Content) {
        upsertContent(content)
        if processingContent?.id == content.id {
            processingContent = content
        }
        error = nil
        notifyContentUpdated(content)
    }

    func trackContentIfNeeded(_ content: Content) async {
        await startTrackingIfNeeded(content, behavior: .background)
    }

    private func notifyContentUpdated(_ content: Content) {
        NotificationCenter.default.post(name: .contentDidUpdate, object: content)
    }

    private func makeImportTracker() -> ImportTrackingCoordinator {
        ImportTrackingCoordinator(
            fetchStatuses: { [repository] contentIDs in
                try await repository.fetchContentStatuses(ids: contentIDs)
            },
            fetchContent: { [repository] contentID in
                try await repository.fetchContent(id: contentID)
            },
            persistContent: { [weak self, repository] content in
                let userId = await MainActor.run { self?.currentUserId }
                try? await repository.cacheContent(content, userId: userId)
            },
            onContentUpdate: { [weak self] content in
                await MainActor.run {
                    self?.handleTrackedContentUpdate(content)
                }
            },
            onReady: { [weak self] content, behavior in
                await MainActor.run {
                    self?.handleTrackedContentReady(content, behavior: behavior)
                }
            },
            onFailure: { [weak self] content, behavior in
                await MainActor.run {
                    self?.handleTrackedContentFailure(content, behavior: behavior)
                }
            },
            onPollingError: { contentID, error in
                await MainActor.run {
                    print("[ContentManager] Polling failed for \(contentID): \(error)")
                }
            }
        )
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
    static let contentDidUpdate = Notification.Name("contentDidUpdate")
}
