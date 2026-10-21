import Foundation
import Core
import Networking
import Storage

// MARK: - Reader View Model

@MainActor
@Observable
final class ReaderViewModel {
    var content: Content?
    var paragraphs: [(anchorID: String, text: String)] = []

    // Expansion state — both are directly observed by SwiftUI
    var expandedDetails: [Int: String] = [:]       // Index → detail text (only for expanded items)
    var loadingExpandIndices: Set<Int> = []         // Per-point loading state

    var isLoadingContent: Bool = false
    var focusedIndex: Int = 0
    var showOriginalPanel: Bool = false
    var sourceAnchors: [String] = []
    var followUpAnswer: String?
    var isLoadingFollowUp: Bool = false

    // Translation state
    var translatedContent: Content?
    var showingTranslation: Bool = false
    var isLoadingTranslation: Bool = false

    @ObservationIgnored
    private let repository: ContentRepository

    // Private cache of ALL fetched details (persists across collapse/expand)
    @ObservationIgnored
    private var cachedDetails: [Int: String] = [:]
    @ObservationIgnored
    private var activeContentID: String?
    @ObservationIgnored
    private var contentUpdateObserver: NSObjectProtocol?

    init(api: APIClient? = nil, database: LocalDatabase? = nil) {
        self.repository = ContentRepository(
            api: api ?? .shared,
            database: database ?? .shared
        )
        observeContentUpdates()
    }

    deinit {
        if let contentUpdateObserver {
            NotificationCenter.default.removeObserver(contentUpdateObserver)
        }
    }

    /// Whether a translation is available
    var hasTranslation: Bool {
        translatedContent != nil
    }

    /// The content currently being displayed (original or translated)
    var displayedContent: Content? {
        showingTranslation ? translatedContent : content
    }

    // MARK: - Data Loading

    func loadContent(contentID: String) async {
        activeContentID = contentID

        // Reset state for new content
        expandedDetails = [:]
        cachedDetails = [:]
        focusedIndex = 0
        followUpAnswer = nil
        loadingExpandIndices = []
        showOriginalPanel = false
        sourceAnchors = []
        paragraphs = []

        // Reset translation state — set showingTranslation FIRST to avoid
        // a frame where displayedContent is nil (showingTranslation=true,
        // translatedContent=nil).
        showingTranslation = false
        translatedContent = nil
        isLoadingTranslation = false

        // Show loading state only when we have no content to display
        let hadContent = content != nil
        isLoadingContent = !hadContent

        // 1. Load from local cache first (instant display)
        if let cached = try? await repository.fetchCachedContent(id: contentID) {
            guard activeContentID == contentID, !Task.isCancelled else { return }
            content = cached
            isLoadingContent = false
            cachedDetails = (try? await repository.fetchExpandedDetails(contentId: contentID)) ?? [:]
            await ContentManager.shared.trackContentIfNeeded(cached)
        }

        // 2. Fetch from API in background to get fresh data
        do {
            let fresh = try await repository.fetchContent(id: contentID)
            guard activeContentID == contentID, !Task.isCancelled else { return }
            content = fresh
            isLoadingContent = false
            // Update local cache
            let userId = AuthService.shared.currentUser?.id.uuidString
            try? await repository.cacheContent(fresh, userId: userId)
            await ContentManager.shared.trackContentIfNeeded(fresh)
        } catch is CancellationError {
            // Ignore canceled work when user quickly switches content.
        } catch {
            // Keep cached content if API fails
            guard activeContentID == contentID else { return }
            isLoadingContent = false
        }
    }

    func loadParagraphs(contentID: String) async {
        guard activeContentID == contentID else { return }

        // 1. Load from local cache first
        if let cached = try? await repository.fetchParagraphs(contentId: contentID), !cached.isEmpty {
            guard activeContentID == contentID, !Task.isCancelled else { return }
            paragraphs = cached
        }

        // 2. Fetch from API for fresh data
        do {
            let fresh = try await repository.refreshParagraphs(contentId: contentID)
            guard activeContentID == contentID, !Task.isCancelled else { return }
            paragraphs = fresh
            // Save to local cache
            try? await repository.cacheParagraphs(fresh, contentId: contentID)
        } catch is CancellationError {
            // Ignore canceled work when user quickly switches content.
        } catch {
            // Keep cached paragraphs if API fails
        }
    }

    // MARK: - L2 Expand

    func expandPoint(at index: Int) async {
        print("[ReaderViewModel] Expand tapped index=\(index)")

        guard !loadingExpandIndices.contains(index) else {
            print("[ReaderViewModel] Skip expand: index \(index) already loading")
            return
        }

        guard let displayedContent else {
            print("[ReaderViewModel] Skip expand: no displayed content")
            return
        }

        guard let outline = displayedContent.l1Outline else {
            print("[ReaderViewModel] Skip expand: no outline on displayed content")
            return
        }

        guard index < outline.count else {
            print("[ReaderViewModel] Skip expand: index \(index) out of bounds, outline count=\(outline.count)")
            return
        }

        let contentID = content?.id ?? displayedContent.id

        func setExpandedDetail(_ detail: String?) {
            var updated = expandedDetails
            if let detail {
                updated[index] = detail
            } else {
                updated.removeValue(forKey: index)
            }
            expandedDetails = updated
        }

        func setLoading(_ isLoading: Bool) {
            var updated = loadingExpandIndices
            if isLoading {
                updated.insert(index)
            } else {
                updated.remove(index)
            }
            loadingExpandIndices = updated
        }

        // Toggle: if already expanded, collapse
        if expandedDetails[index] != nil {
            print("[ReaderViewModel] Collapse index \(index)")
            setExpandedDetail(nil)
            return
        }

        // Check in-memory cache (instant expansion)
        if let cached = cachedDetails[index] {
            print("[ReaderViewModel] Cache hit for index \(index), length=\(cached.count)")
            setExpandedDetail(cached)
            return
        }

        // Check inline detail from OutlinePoint
        if let inlineDetail = outline[index].detail, !inlineDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("[ReaderViewModel] Inline detail hit for index \(index), length=\(inlineDetail.count)")
            cachedDetails[index] = inlineDetail
            setExpandedDetail(inlineDetail)
            return
        }

        // Cache miss — show loading, fetch from API
        print("[ReaderViewModel] Cache miss for index \(index), requesting backend")
        setLoading(true)
        do {
            let detail = try await repository.expandPoint(contentID: contentID, pointIndex: index)
            cachedDetails[index] = detail
            setLoading(false)
            setExpandedDetail(detail)
            print("[ReaderViewModel] Expand success index \(index), length=\(detail.count)")
            // Persist to local SQLite cache
            try? await repository.cacheExpandedDetail(
                contentId: contentID,
                pointIndex: index,
                detailText: detail
            )
        } catch {
            // Silently fail; user can retry
            setLoading(false)
            print("[ReaderViewModel] Expand failed index \(index): \(error)")
        }
    }

    // MARK: - Source Tracing

    func traceSource(anchors: [String]) {
        sourceAnchors = anchors
        showOriginalPanel = true
    }

    func toggleOriginalPanel() {
        if showOriginalPanel {
            showOriginalPanel = false
            sourceAnchors = []
        } else {
            sourceAnchors = []
            showOriginalPanel = true
        }
    }

    // MARK: - Follow-Up Q&A (L3)

    func askFollowUp(question: String) async {
        guard let content, !question.isEmpty else { return }
        isLoadingFollowUp = true
        defer { isLoadingFollowUp = false }

        do {
            followUpAnswer = try await repository.askFollowUp(
                contentID: content.id,
                question: question
            )
        } catch {
            followUpAnswer = "Failed to get answer. Please try again."
        }
    }

    // MARK: - Translation

    func loadTranslation(targetLanguage: String) async {
        guard let content else { return }
        let translatingContentID = content.id
        guard activeContentID == translatingContentID else { return }
        guard let sourceLanguage = content.sourceLanguage else { return }

        // Smart translation: skip if same language
        guard sourceLanguage != targetLanguage else {
            showingTranslation = false
            return
        }

        isLoadingTranslation = true
        defer {
            if activeContentID == translatingContentID {
                isLoadingTranslation = false
            }
        }

        do {
            let translated = try await repository.translateContent(
                contentID: translatingContentID,
                targetLanguage: targetLanguage
            )
            guard activeContentID == translatingContentID, !Task.isCancelled else { return }
            translatedContent = translated
            showingTranslation = true
        } catch is CancellationError {
            // Ignore canceled work when user quickly switches content.
        } catch {
            // Translation failed, keep showing original
            guard activeContentID == translatingContentID else { return }
            showingTranslation = false
        }
    }

    func toggleTranslation(show: Bool) {
        showingTranslation = show && hasTranslation
    }

    private func observeContentUpdates() {
        contentUpdateObserver = NotificationCenter.default.addObserver(
            forName: .contentDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let updatedContent = notification.object as? Content
            else {
                return
            }
            Task { @MainActor [weak self] in
                self?.handleTrackedContentUpdate(updatedContent)
            }
        }
    }

    private func handleTrackedContentUpdate(_ updatedContent: Content) {
        guard activeContentID == updatedContent.id else { return }
        let previousStatus = content?.status
        content = updatedContent

        if updatedContent.status == .ready, previousStatus != .ready {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.loadParagraphs(contentID: updatedContent.id)
            }
        }
    }

    // MARK: - Keyboard Navigation

    func moveDown() {
        guard let outline = displayedContent?.l1Outline else { return }
        if focusedIndex < outline.count - 1 {
            focusedIndex += 1
        }
    }

    func moveUp() {
        if focusedIndex > 0 {
            focusedIndex -= 1
        }
    }
}
