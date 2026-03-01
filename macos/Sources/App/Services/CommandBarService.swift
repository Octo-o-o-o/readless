// macos/Sources/App/Services/CommandBarService.swift
import Foundation
import AppKit
import Core
import AIServices

@MainActor
final class CommandBarService {
    private let contentManager: ContentManager
    private let aiCoordinator: AICoordinator
    private var searchTask: Task<Void, Never>?

    init(contentManager: ContentManager = .shared, aiCoordinator: AICoordinator) {
        self.contentManager = contentManager
        self.aiCoordinator = aiCoordinator
    }

    // Search with debouncing
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

            await performSearch(query)
        }
    }

    private func performSearch(_ query: String) async {
        aiCoordinator.isLoading = true
        defer { aiCoordinator.isLoading = false }

        // Search local content
        let results = contentManager.contents.filter { content in
            content.title.localizedCaseInsensitiveContains(query) ||
            (content.l0Summary?.localizedCaseInsensitiveContains(query) ?? false)
        }

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

    private func showQuickActions() {
        aiCoordinator.commandResults = [
            CommandResult(
                title: "Import from clipboard",
                subtitle: "⌘V",
                icon: "doc.text"
            ) {
                await self.importFromClipboard()
            },
            CommandResult(
                title: "Search all content",
                subtitle: "⌘F",
                icon: "magnifyingglass"
            ) {
                // Will implement in Phase 3
            },
            CommandResult(
                title: "Generate podcast",
                subtitle: "⌘P",
                icon: "mic"
            ) {
                // Will implement in Phase 3
            }
        ]
    }

    private func importFromClipboard() async {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        await contentManager.importSilently(text: text, appName: "Clipboard", bundleID: nil)
    }

    private func iconForSourceType(_ type: SourceType) -> String {
        switch type {
        case .text: return "doc.text"
        case .url: return "link"
        case .pdf: return "doc.fill"
        case .image: return "photo"
        case .clipboard: return "doc.text"
        case .folderWatch: return "folder"
        case .email: return "envelope"
        case .rss: return "antenna.radiowaves.left.and.right"
        }
    }
}
