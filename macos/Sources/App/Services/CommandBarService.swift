// macos/Sources/App/Services/CommandBarService.swift
import Foundation
import AppKit
import Core
import AIServices
import Storage
import Networking

// Simple mock provider for input parsing (doesn't need actual AI)
private struct SimpleMockProvider: AIProviderProtocol {
    func chat(messages: [ChatMessage], model: String, options: AIChatOptions) async throws -> String {
        return ""
    }

    func analyzeImage(imageData: Data, prompt: String, model: String) async throws -> String {
        return ""
    }

    func analyzePDF(pdfData: Data, prompt: String, model: String) async throws -> String {
        return ""
    }

    func isReasoningModel(_ model: String) -> Bool {
        return false
    }
}

@MainActor
final class CommandBarService {
    private enum SearchBudget {
        static let minimumCharacters = 2
        static let maximumLiveQueryCharacters = 240
    }

    private let contentManager: ContentManager
    private let aiCoordinator: AICoordinator
    private let apiClient: APIClient
    private let localSearch: LocalSearchService
    private let userDefaults: UserDefaults
    private var searchTask: Task<Void, Never>?

    init(
        contentManager: ContentManager,
        aiCoordinator: AICoordinator,
        apiClient: APIClient = .shared,
        localSearch: LocalSearchService = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.contentManager = contentManager
        self.aiCoordinator = aiCoordinator
        self.apiClient = apiClient
        self.localSearch = localSearch
        self.userDefaults = userDefaults
    }

    convenience init(aiCoordinator: AICoordinator) {
        self.init(contentManager: .shared, aiCoordinator: aiCoordinator)
    }

    /// Current search mode from settings
    private var searchMode: SearchMode {
        if let modeString = userDefaults.string(forKey: "searchMode"),
           let mode = SearchMode(rawValue: modeString) {
            return mode
        }
        return .local  // Default to local search
    }

    // Process user input with debouncing - handles both search and content import
    func search(_ query: String) {
        // Cancel previous search
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            showQuickActions()
            return
        }

        guard trimmed.count >= SearchBudget.minimumCharacters else {
            aiCoordinator.commandResults = []
            aiCoordinator.isLoading = false
            return
        }

        // Debounce 300ms
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))

            guard !Task.isCancelled else { return }

            await processUserInput(query)
        }
    }

    private func processUserInput(_ query: String) async {
        aiCoordinator.isLoading = true
        defer { aiCoordinator.isLoading = false }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Use InputParser to detect input type
        do {
            let input = CommandBarInput.text(trimmedQuery)
            let parsed = try await InputParser(
                aiProvider: SimpleMockProvider(),
                config: AIServiceConfig.default.inputParsing
            ).parse(input)

            switch parsed {
            case .url(let url):
                // URL detected - provide import option
                aiCoordinator.commandResults = [
                    CommandResult(
                        title: "Import from URL: \(url.host ?? url.absoluteString)",
                        subtitle: "Extract and summarize content",
                        icon: "link"
                    ) {
                        await self.importURL(url)
                    }
                ]

            case .plainText(let text):
                // Check if this is long text that should be imported
                if text.count > 100 {
                    // Long text - provide simple import/retrieve options
                    aiCoordinator.commandResults = [
                        CommandResult(
                            title: "Import this content",
                            subtitle: "Enter — Generate summary and outline",
                            icon: "square.and.arrow.down"
                        ) {
                            await self.importText(text)
                        },
                        CommandResult(
                            title: "Search for similar content",
                            subtitle: "⌘↩ — Search local library",
                            icon: "magnifyingglass"
                        ) {
                            await self.performSearch(text)
                        }
                    ]
                } else {
                    // Short text - perform search
                    await performSearch(text)
                }

            case .image, .pdf:
                // Multi-modal content - already handled by drag & drop in Task 9
                aiCoordinator.errorMessage = "Please drag and drop images/PDFs instead of pasting"

            case .command:
                // Command detected - search for matching commands
                await performSearch(trimmedQuery)
            }

        } catch {
            // If parsing fails, fall back to search
            await performSearch(trimmedQuery)
        }
    }

    private func performSearch(_ query: String) async {
        let normalizedQuery = normalizedSearchQuery(query)
        guard normalizedQuery.count >= SearchBudget.minimumCharacters else {
            aiCoordinator.commandResults = []
            return
        }

        // Route to appropriate search based on mode
        switch searchMode {
        case .cloud:
            await performCloudSearch(normalizedQuery)
        case .local:
            await performLocalSearch(normalizedQuery)
        }
    }

    /// Cloud-based AI search (PostgreSQL FTS + OpenAI)
    private func performCloudSearch(_ query: String) async {
        do {
            let sources = try await apiClient.searchRetrieve(query: query)

            if sources.isEmpty {
                // No results - suggest importing as new content
                aiCoordinator.commandResults = [
                    CommandResult(
                        title: "No results found",
                        subtitle: "Import this as new content?",
                        icon: "doc.badge.plus"
                    ) {
                        await self.importText(query)
                    }
                ]
            } else {
                aiCoordinator.commandResults = sources.prefix(10).map { source in
                    CommandResult(
                        title: source.title,
                        subtitle: source.l0Summary ?? "Click to open",
                        icon: "doc.text"
                    ) {
                        self.aiCoordinator.requestOpenContent(source.id)
                    }
                }
            }
        } catch {
            // Show user-friendly error message
            if let apiError = error as? APIError {
                aiCoordinator.errorMessage = apiError.localizedDescription
            } else if error is URLError {
                aiCoordinator.errorMessage = "Could not search. Please check your internet connection."
            } else {
                aiCoordinator.errorMessage = "Search failed. Please try again."
            }
        }
    }

    /// Local SQLite FTS5 search
    private func performLocalSearch(_ query: String) async {
        do {
            let result = try await localSearch.search(query: query)

            if result.results.isEmpty {
                // No results - suggest importing or explicitly escalating to cloud.
                aiCoordinator.commandResults = [
                    CommandResult(
                        title: "No results in local cache",
                        subtitle: "Import this as new content?",
                        icon: "doc.badge.plus"
                    ) {
                        await self.importText(query)
                    },
                    makeCloudSearchResult(for: query)
                ]
            } else {
                // Convert to command results
                var results = result.results.prefix(10).map { item in
                    CommandResult(
                        title: item.title,
                        subtitle: item.snippet,
                        icon: "doc.text"
                    ) {
                        self.aiCoordinator.requestOpenContent(item.id)
                    }
                }
                results.append(makeCloudSearchResult(for: query))
                aiCoordinator.commandResults = results
            }
        } catch {
            aiCoordinator.errorMessage = "Local search failed. Please try again."
        }
    }

    private func showQuickActions() {
        aiCoordinator.commandResults = [
            CommandResult(
                title: "Import from clipboard",
                subtitle: "⌘V - Paste content to import",
                icon: "doc.on.clipboard"
            ) {
                await self.importFromClipboard()
            },
            CommandResult(
                title: "Search all content",
                subtitle: "Type to search...",
                icon: "magnifyingglass"
            ) {
                // Placeholder - focus will be on search field
            },
            CommandResult(
                title: "Import from URL",
                subtitle: "Paste a URL to extract content",
                icon: "link"
            ) {
                // Placeholder - will be triggered when URL is pasted
            }
        ]
    }

    func importFromClipboard() async {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            aiCoordinator.errorMessage = "No text in clipboard"
            return
        }
        await importText(text)
    }

    private func importText(_ text: String) async {
        aiCoordinator.commandBarImportState = .importing

        do {
            let content = try await contentManager.importQuietly(
                text: text,
                appName: "Command Bar",
                bundleID: nil
            )

            // Signal success — CommandBarWindow handles the auto-dismiss timer
            aiCoordinator.commandBarImportState = .success
            _ = content
        } catch {
            aiCoordinator.commandBarImportState = .idle
            let message = userFriendlyErrorMessage(for: error)
            aiCoordinator.errorMessage = message
        }
    }

    private func importURL(_ url: URL) async {
        aiCoordinator.commandBarImportState = .importing

        do {
            let content = try await contentManager.importQuietly(
                text: url.absoluteString,
                appName: "Command Bar",
                bundleID: nil
            )

            aiCoordinator.commandBarImportState = .success
            _ = content
        } catch {
            aiCoordinator.commandBarImportState = .idle
            let message = userFriendlyErrorMessage(for: error)
            aiCoordinator.errorMessage = message
        }
    }

    private func userFriendlyErrorMessage(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        } else if error is URLError {
            return "Could not connect. Please check your internet connection."
        }
        return "Import failed. Please try again."
    }

    private func normalizedSearchQuery(_ query: String) -> String {
        let collapsed = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count <= SearchBudget.maximumLiveQueryCharacters {
            return collapsed
        }
        return String(collapsed.prefix(SearchBudget.maximumLiveQueryCharacters))
    }

    private func makeCloudSearchResult(for query: String) -> CommandResult {
        CommandResult(
            title: "Search in cloud",
            subtitle: "Semantic search with server index",
            icon: "cloud.fill"
        ) {
            await self.performCloudSearch(query)
        }
    }

}
