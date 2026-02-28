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
        self.api = api ?? APIClient(
            baseURL: URL(string: "http://localhost:8000/api")!
        )
    }

    // MARK: - Data Loading

    func loadParagraphs(contentID: String) async {
        // TODO: Fetch from API /content/{id}/paragraphs
        // For now this is a placeholder; the real implementation will call
        // the backend once the endpoint is available.
    }

    // MARK: - L2 Expand

    func expandPoint(at index: Int) async {
        guard let outline = content?.l1Outline, index < outline.count else { return }

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

        // Otherwise fetch from API
        isLoadingExpand = true
        defer { isLoadingExpand = false }

        // TODO: Call API /content/{id}/expand?index=\(index)
        // Placeholder until backend endpoint is implemented.
    }

    // MARK: - Source Tracing

    func traceSource(anchors: [String]) {
        sourceAnchorID = anchors.first
        showSourcePanel = true
    }

    // MARK: - Follow-Up Q&A (L3)

    func askFollowUp(question: String) async {
        guard !question.isEmpty else { return }
        isLoadingFollowUp = true
        defer { isLoadingFollowUp = false }

        // TODO: Call API /content/{id}/ask
        // Placeholder until backend endpoint is implemented.
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
