import Foundation
import Core
import Networking

// MARK: - Reader View Model

@MainActor
@Observable
final class ReaderViewModel {
    var content: Content?
    var paragraphs: [(anchorID: String, text: String)] = []
    var expandedDetails: [Int: String] = [:]  // point index -> L2 detail text
    var focusedIndex: Int = 0
    var showSourcePanel: Bool = false
    var sourceAnchorID: String?
    var followUpAnswer: String?
    var isLoadingExpand: Bool = false
    var isLoadingFollowUp: Bool = false

    private let api: APIClient

    init(api: APIClient? = nil) {
        self.api = api ?? .shared
    }

    // MARK: - Data Loading

    func loadContent(contentID: String) async {
        // Reset state for new content
        expandedDetails = [:]
        focusedIndex = 0
        followUpAnswer = nil

        do {
            content = try await api.getContent(id: contentID)
        } catch {
            content = nil
        }
    }

    func loadParagraphs(contentID: String) async {
        do {
            let results = try await api.getParagraphs(contentID: contentID)
            paragraphs = results.map { (anchorID: $0.anchorID, text: $0.text) }
        } catch {
            paragraphs = []
        }
    }

    // MARK: - L2 Expand

    func expandPoint(at index: Int) async {
        guard let content, let outline = content.l1Outline, index < outline.count else { return }

        // If already expanded, toggle collapse
        if expandedDetails[index] != nil {
            expandedDetails.removeValue(forKey: index)
            return
        }

        // If the OutlinePoint already carries inline detail, use it
        if let inlineDetail = outline[index].detail {
            expandedDetails[index] = inlineDetail
            return
        }

        // Fetch from API
        isLoadingExpand = true
        defer { isLoadingExpand = false }

        do {
            let detail = try await api.expandPoint(contentID: content.id, pointIndex: index)
            expandedDetails[index] = detail
        } catch {
            // Silently fail; user can retry
        }
    }

    // MARK: - Source Tracing

    func traceSource(anchors: [String]) {
        sourceAnchorID = anchors.first
        showSourcePanel = true
    }

    // MARK: - Follow-Up Q&A (L3)

    func askFollowUp(question: String) async {
        guard let content, !question.isEmpty else { return }
        isLoadingFollowUp = true
        defer { isLoadingFollowUp = false }

        do {
            followUpAnswer = try await api.askFollowUp(contentID: content.id, question: question)
        } catch {
            followUpAnswer = "Failed to get answer. Please try again."
        }
    }

    // MARK: - Keyboard Navigation

    func moveDown() {
        guard let outline = content?.l1Outline else { return }
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
