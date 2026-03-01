// macos/Examples/SuggestionEngineExample.swift
//
// This example demonstrates how to use SuggestionEngine to generate
// context-based suggestions for content discovery.
//
// NOTE: This is not a runnable file, just documentation of usage patterns.

import Foundation
import Core
import AIServices

// Example: Using SuggestionEngine in a view model or coordinator

@MainActor
class ContentDetailViewModel: ObservableObject {
    private let suggestionEngine = SuggestionEngine()
    private let aiCoordinator: AICoordinator

    @Published var currentContent: Content?
    @Published var suggestions: [Suggestion] = []
    @Published var isLoadingSuggestions = false

    init(aiCoordinator: AICoordinator) {
        self.aiCoordinator = aiCoordinator
    }

    func loadSuggestions(for content: Content) async {
        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }

        // Generate suggestions
        let newSuggestions = await suggestionEngine.generateSuggestions(for: content)

        // Update UI state
        suggestions = newSuggestions
        aiCoordinator.suggestions = newSuggestions
    }

    func handleSuggestionTap(_ suggestion: Suggestion) async {
        switch suggestion {
        case .relatedContent(let title, let contentIDs):
            print("User wants to explore: \(title)")
            print("Related content IDs: \(contentIDs)")
            // Navigate to first related content
            if let firstID = contentIDs.first {
                await openContent(id: firstID)
            }

        case .followUpQuestion(let question):
            print("User asked: \(question)")
            // Could trigger semantic search with this question
            aiCoordinator.searchQuery = question
            // Or send to command bar for processing
            await aiCoordinator.searchCommands(question)

        case .deepDive(let topic):
            print("User wants to deep dive into: \(topic)")
            // Could generate a focused summary or search for related material
            await performDeepDive(topic: topic)
        }
    }

    func refreshSuggestions() async {
        guard let content = currentContent else { return }

        // Clear cache to force regeneration
        suggestionEngine.clearCache(for: content.id)

        // Reload
        await loadSuggestions(for: content)
    }

    // MARK: - Helpers

    private func openContent(id: String) async {
        // Implementation to navigate to content
    }

    private func performDeepDive(topic: String) async {
        // Implementation to explore topic deeply
        // Could use semantic search, generate questions, etc.
    }
}

// Example: Testing suggestion generation

func exampleUsage() async {
    // Create test content
    let content = Content(
        id: "test-1",
        title: "Understanding Swift Concurrency",
        sourceType: .url,
        l0Summary: "Swift concurrency introduces async/await syntax for modern asynchronous programming",
        l1Outline: [
            OutlinePoint(
                point: "Introduction to async/await patterns ¶1-2",
                anchors: ["¶1", "¶2"]
            ),
            OutlinePoint(
                point: "Detailed analysis of structured concurrency ¶3-5",
                anchors: ["¶3", "¶4", "¶5"]
            ),
            OutlinePoint(
                point: "Actor model for thread safety ¶6-7",
                anchors: ["¶6", "¶7"]
            )
        ],
        status: .ready
    )

    // Generate suggestions
    let engine = SuggestionEngine()
    let suggestions = await engine.generateSuggestions(for: content)

    print("Generated \(suggestions.count) suggestions:")
    for suggestion in suggestions {
        switch suggestion {
        case .relatedContent(let title, let ids):
            print("  - Related: \(title) (IDs: \(ids))")
        case .followUpQuestion(let question):
            print("  - Question: \(question)")
        case .deepDive(let topic):
            print("  - Deep Dive: \(topic)")
        }
    }

    // Expected output might include:
    // - Related content about Swift or concurrency
    // - Follow-up questions like "What about async/await patterns?"
    // - Deep dive into "structured concurrency" (has multiple anchors)
}

// Example: Cache management

func exampleCacheManagement() async {
    let engine = SuggestionEngine()
    let content = Content(id: "test", title: "Test", sourceType: .text, status: .ready)

    // First call - generates fresh
    let suggestions1 = await engine.generateSuggestions(for: content)

    // Second call within 5 minutes - returns cached
    let suggestions2 = await engine.generateSuggestions(for: content)

    // Clear cache for specific content
    engine.clearCache(for: content.id)

    // Or clear entire cache
    engine.clearCache()

    // Next call generates fresh again
    let suggestions3 = await engine.generateSuggestions(for: content)
}

// Example: Individual suggestion methods

func exampleIndividualMethods() async {
    let engine = SuggestionEngine()
    let content = Content(
        id: "test",
        title: "Machine Learning Basics",
        sourceType: .url,
        l0Summary: "Introduction to neural networks and deep learning algorithms",
        l1Outline: [
            OutlinePoint(point: "Neural network architecture", anchors: ["¶1", "¶2"]),
            OutlinePoint(point: "Training algorithms", anchors: ["¶3"])
        ],
        status: .ready
    )

    // Get only related content
    let related = await engine.getRelatedContent(for: content)
    // Expected: Other ML/AI content from library

    // Get only follow-up questions
    let questions = await engine.generateFollowUpQuestions(for: content)
    // Expected: "What about neural network architecture?", etc.

    // Get only deep dive topics
    let deepDives = await engine.suggestDeepDiveTopics(for: content)
    // Expected: Deep dive into "Neural network architecture" (multiple anchors)
}
