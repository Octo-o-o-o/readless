// macos/Sources/App/Services/CommandBarService.swift
import Foundation
import AppKit
import Core
import AIServices

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
    private let contentManager: ContentManager
    private let aiCoordinator: AICoordinator
    private var searchTask: Task<Void, Never>?

    init(contentManager: ContentManager, aiCoordinator: AICoordinator) {
        self.contentManager = contentManager
        self.aiCoordinator = aiCoordinator
    }

    convenience init(aiCoordinator: AICoordinator) {
        self.init(contentManager: .shared, aiCoordinator: aiCoordinator)
    }

    // Process user input with debouncing - handles both search and content import
    func search(_ query: String) {
        // Cancel previous search
        searchTask?.cancel()

        guard !query.isEmpty else {
            showQuickActions()
            return
        }

        // Debounce 300ms
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))

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
        // Search local content
        let results = contentManager.contents.filter { content in
            content.title.localizedCaseInsensitiveContains(query) ||
            (content.l0Summary?.localizedCaseInsensitiveContains(query) ?? false)
        }

        if results.isEmpty {
            // No results - suggest importing as new content
            aiCoordinator.commandResults = [
                CommandResult(
                    title: "No results found for \"\(query)\"",
                    subtitle: "Import this as new content?",
                    icon: "doc.badge.plus"
                ) {
                    await self.importText(query)
                }
            ]
        } else {
            // Convert to command results
            aiCoordinator.commandResults = results.prefix(10).map { content in
                CommandResult(
                    title: content.title,
                    subtitle: content.sourceType.rawValue,
                    icon: iconForSourceType(content.sourceType)
                ) {
                    // Open content
                    NotificationCenter.default.post(
                        name: Notification.Name("openContent"),
                        object: content.id
                    )
                }
            }
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

    private func importFromClipboard() async {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            aiCoordinator.errorMessage = "No text in clipboard"
            return
        }
        await importText(text)
    }

    private func importText(_ text: String) async {
        aiCoordinator.isLoading = true
        defer { aiCoordinator.isLoading = false }

        // Import and display the content
        await contentManager.importAndDisplay(
            text: text,
            appName: "Command Bar",
            bundleID: nil
        )

        // Close command bar after request is sent
        // (ContentManager will show error toast if backend is not running)
        aiCoordinator.hideCommandBar()
    }

    private func importURL(_ url: URL) async {
        aiCoordinator.isLoading = true
        defer { aiCoordinator.isLoading = false }

        // Import URL content
        await contentManager.importAndDisplay(
            text: url.absoluteString,
            appName: "Command Bar",
            bundleID: nil
        )

        // Close command bar after successful import
        aiCoordinator.hideCommandBar()
    }

    private func iconForSourceType(_ type: SourceType) -> String {
        switch type {
        case .text: return "doc.text"
        case .url: return "link"
        case .pdf: return "doc.fill"
        case .image: return "photo"
        case .clipboard: return "doc.on.clipboard"
        case .folderWatch: return "folder"
        case .email: return "envelope"
        case .rss: return "antenna.radiowaves.left.and.right"
        }
    }
}
