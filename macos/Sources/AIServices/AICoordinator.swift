import Foundation
import Observation
import Core

public enum CommandBarImportState: Equatable {
    case idle
    case importing
    case success
}

@Observable
public final class AICoordinator {
    // Command Bar State
    public var isCommandBarVisible = false
    public var commandQuery = ""
    public var commandResults: [CommandResult] = []

    // Selection and UI state
    public var selectedResultIndex: Int = 0
    public var isLoading: Bool = false
    public var errorMessage: String?

    // Import lifecycle state (for Command Bar)
    public var commandBarImportState: CommandBarImportState = .idle

    // Preview panel state (for Phase 2)
    public var showPreviewPanel: Bool = false
    public var previewContent: Content?

    // Semantic Search State
    public var searchQuery = ""
    public var searchResults: [SearchResult] = []
    public var isSearching = false

    // Context Suggestions State
    public var suggestions: [Suggestion] = []
    public var activeSuggestion: Suggestion?

    public init() {}

    // MARK: - Command Bar Actions

    @MainActor
    public func showCommandBar() {
        isCommandBarVisible = true
        commandQuery = ""
        commandResults = []
    }

    @MainActor
    public func hideCommandBar() {
        isCommandBarVisible = false
        commandBarImportState = .idle
    }

    @MainActor
    public func selectNextResult() {
        guard !commandResults.isEmpty else { return }
        selectedResultIndex = min(selectedResultIndex + 1, commandResults.count - 1)
    }

    @MainActor
    public func selectPreviousResult() {
        selectedResultIndex = max(selectedResultIndex - 1, 0)
    }

    @MainActor
    public func executeSelectedResult() async {
        guard selectedResultIndex < commandResults.count else { return }
        let result = commandResults[selectedResultIndex]
        await result.action()
        // Don't auto-close if an import is active or an error is being shown —
        // the import flow handles its own dismissal via success timer
        if commandBarImportState == .idle && errorMessage == nil {
            hideCommandBar()
        }
    }

    @MainActor
    public func resetSelection() {
        selectedResultIndex = 0
    }

    @MainActor
    public func searchCommands(_ query: String) async {
        commandQuery = query
        // Will be implemented with CommandBarService
    }

    @MainActor
    public func executeCommand(_ command: CommandResult) async {
        hideCommandBar()
        // Will be implemented with CommandBarService
    }
}

// MARK: - Models

public struct CommandResult: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let subtitle: String?
    public let icon: String
    public let action: () async -> Void

    public static func == (lhs: CommandResult, rhs: CommandResult) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
    }

    public init(title: String, subtitle: String? = nil, icon: String, action: @escaping () async -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
    }
}

public struct SearchResult: Identifiable {
    public let id = UUID()
    public let contentID: String
    public let title: String
    public let snippet: String
    public let relevanceScore: Double

    public init(contentID: String, title: String, snippet: String, relevanceScore: Double) {
        self.contentID = contentID
        self.title = title
        self.snippet = snippet
        self.relevanceScore = relevanceScore
    }
}

public enum Suggestion: Identifiable {
    case relatedContent(title: String, contentIDs: [String])
    case followUpQuestion(question: String)
    case deepDive(topic: String)

    public var id: String {
        switch self {
        case .relatedContent(let title, _): return "related-\(title)"
        case .followUpQuestion(let question): return "question-\(question)"
        case .deepDive(let topic): return "deepdive-\(topic)"
        }
    }
}
