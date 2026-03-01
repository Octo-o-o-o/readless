import Foundation
import Observation
import Core

@Observable
public final class AICoordinator {
    // Command Bar State
    public var isCommandBarVisible = false
    public var commandQuery = ""
    public var commandResults: [CommandResult] = []
    public var selectedCommandIndex = 0

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

public struct CommandResult: Identifiable {
    public let id = UUID()
    public let title: String
    public let subtitle: String?
    public let icon: String
    public let action: () async -> Void

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
