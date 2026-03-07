// macos/Sources/App/Services/SuggestionEngine.swift
import Foundation
import Core
import AIServices

/// Generates context-based suggestions to help users discover relevant content and actions.
///
/// The SuggestionEngine analyzes current content to provide:
/// - Related content recommendations based on similarity
/// - Follow-up questions derived from outline points
/// - Deep dive topic suggestions for exploration
///
/// Results are cached per content ID to avoid redundant calculations.
///
/// # Usage Example
///
/// ```swift
/// let engine = SuggestionEngine()
/// let suggestions = await engine.generateSuggestions(for: currentContent)
///
/// // Display suggestions in AICoordinator
/// aiCoordinator.suggestions = suggestions
///
/// // Handle user selection
/// if case .relatedContent(_, let contentIDs) = selectedSuggestion {
///     // Open first related content
///     let contentID = contentIDs.first
/// }
/// ```
///
/// # Implementation Details
///
/// - **Related Content**: Uses Jaccard similarity on L0 summaries and titles
/// - **Follow-up Questions**: Extracts topics from L1 outline points
/// - **Deep Dive Topics**: Identifies complex points with multiple anchors
/// - **Caching**: 5-minute TTL per content ID to avoid redundant calculations
/// - **MVP Approach**: Simple keyword matching, extensible for AI enhancement later
@MainActor
final class SuggestionEngine {
    // MARK: - Properties

    private let contentManager: ContentManager
    private var cache: [String: CachedSuggestions] = [:]
    private let cacheExpirationInterval: TimeInterval = 300 // 5 minutes
    private let maxCacheSize = 50

    // MARK: - Configuration

    private let maxRelatedContent = 3
    private let maxFollowUpQuestions = 3
    private let maxDeepDiveTopics = 2
    private let maxTotalSuggestions = 7

    // MARK: - Cache Model

    struct CachedSuggestions {
        let suggestions: [Suggestion]
        let cachedAt: Date

        func isExpired(expirationInterval: TimeInterval) -> Bool {
            Date().timeIntervalSince(cachedAt) > expirationInterval
        }
    }

    // MARK: - Initialization

    init(contentManager: ContentManager) {
        self.contentManager = contentManager
    }

    convenience init() {
        self.init(contentManager: .shared)
    }

    // MARK: - Public API

    /// Generates all types of suggestions for the given content.
    /// Returns a combined list limited to maxTotalSuggestions.
    func generateSuggestions(for content: Content) async -> [Suggestion] {
        // Check cache first
        if let cached = cache[content.id], !cached.isExpired(expirationInterval: cacheExpirationInterval) {
            return cached.suggestions
        }

        // Generate fresh suggestions
        var allSuggestions: [Suggestion] = []

        // Add related content (top priority)
        let related = await getRelatedContent(for: content)
        allSuggestions.append(contentsOf: related)

        // Add follow-up questions
        let questions = await generateFollowUpQuestions(for: content)
        allSuggestions.append(contentsOf: questions)

        // Add deep dive topics
        let deepDives = await suggestDeepDiveTopics(for: content)
        allSuggestions.append(contentsOf: deepDives)

        // Limit total suggestions
        let finalSuggestions = Array(allSuggestions.prefix(maxTotalSuggestions))

        // Cache results with LRU eviction
        cache[content.id] = CachedSuggestions(
            suggestions: finalSuggestions,
            cachedAt: Date()
        )
        if cache.count > maxCacheSize {
            let oldest = cache.min(by: { $0.value.cachedAt < $1.value.cachedAt })?.key
            if let oldest { cache.removeValue(forKey: oldest) }
        }

        return finalSuggestions
    }

    /// Finds related content based on similarity of L0 summaries and titles.
    /// Uses simple keyword matching for MVP.
    func getRelatedContent(for content: Content) async -> [Suggestion] {
        guard let currentSummary = content.l0Summary, !currentSummary.isEmpty else {
            return []
        }

        // Extract keywords from current content
        let keywords = extractKeywords(from: currentSummary + " " + content.title)
        guard !keywords.isEmpty else { return [] }

        // Find similar content
        let similarContent = contentManager.contents
            .filter { $0.id != content.id } // Exclude current content
            .filter { $0.status == .ready } // Only show ready content
            .compactMap { candidate -> (Content, Double)? in
                guard let candidateSummary = candidate.l0Summary else { return nil }
                let candidateText = candidateSummary + " " + candidate.title
                let score = calculateSimilarity(keywords: keywords, text: candidateText)
                return score > 0 ? (candidate, score) : nil
            }
            .sorted { $0.1 > $1.1 } // Sort by score descending
            .prefix(maxRelatedContent)

        // Group by topic if we have multiple related items
        if similarContent.count >= 2 {
            let contentIDs = similarContent.map { $0.0.id }
            let topic = extractCommonTopic(from: Array(similarContent.map { $0.0 }))
            return [.relatedContent(title: topic, contentIDs: contentIDs)]
        } else if let first = similarContent.first {
            return [.relatedContent(title: first.0.title, contentIDs: [first.0.id])]
        }

        return []
    }

    /// Generates follow-up questions based on outline points.
    func generateFollowUpQuestions(for content: Content) async -> [Suggestion] {
        guard let outline = content.l1Outline, !outline.isEmpty else {
            return []
        }

        var questions: [Suggestion] = []

        // Extract interesting topics from outline points
        let topics = outline.prefix(5).map { extractTopicFromPoint($0.point) }

        // Generate questions from topics
        for topic in topics.prefix(maxFollowUpQuestions) {
            guard !topic.isEmpty else { continue }

            let question = generateQuestionFromTopic(topic)
            questions.append(.followUpQuestion(question: question))

            if questions.count >= maxFollowUpQuestions {
                break
            }
        }

        return questions
    }

    /// Suggests deep dive topics based on outline structure.
    func suggestDeepDiveTopics(for content: Content) async -> [Suggestion] {
        guard let outline = content.l1Outline, !outline.isEmpty else {
            return []
        }

        var deepDives: [Suggestion] = []

        // Look for complex or interesting topics that warrant deeper exploration
        for point in outline.prefix(5) {
            let topic = extractTopicFromPoint(point.point)

            // Check if this point has multiple anchors (indicates substantial content)
            // or contains certain keywords that suggest depth
            if point.anchors.count >= 2 || isDeepDiveWorthy(point.point) {
                deepDives.append(.deepDive(topic: topic))

                if deepDives.count >= maxDeepDiveTopics {
                    break
                }
            }
        }

        return deepDives
    }

    /// Clears the suggestion cache.
    func clearCache() {
        cache.removeAll()
    }

    /// Clears cache for a specific content ID.
    func clearCache(for contentID: String) {
        cache.removeValue(forKey: contentID)
    }

    // MARK: - Private Helpers

    private static let stopWords: Set<String> = [
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "as", "is", "was", "are", "were", "be",
        "this", "that", "these", "those", "it", "its", "they", "their",
        // Chinese stop words
        "的", "了", "在", "是", "我", "有", "和", "就", "不", "人", "都", "一", "个"
    ]

    /// Extracts keywords from text (simple word frequency approach).
    private func extractKeywords(from text: String) -> Set<String> {
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 } // Min 2 characters
            .filter { !Self.stopWords.contains($0) }

        return Set(words)
    }

    /// Calculates similarity score based on keyword overlap.
    private func calculateSimilarity(keywords: Set<String>, text: String) -> Double {
        let textKeywords = extractKeywords(from: text)
        let intersection = keywords.intersection(textKeywords)

        guard !keywords.isEmpty else { return 0 }

        // Jaccard similarity coefficient
        let union = keywords.union(textKeywords)
        return Double(intersection.count) / Double(union.count)
    }

    /// Extracts a common topic from multiple related content items.
    private func extractCommonTopic(from contents: [Content]) -> String {
        // Simple approach: find most common significant word in titles/summaries
        var wordFrequency: [String: Int] = [:]

        for content in contents {
            let text = content.title + " " + (content.l0Summary ?? "")
            let keywords = extractKeywords(from: text)

            for word in keywords {
                wordFrequency[word, default: 0] += 1
            }
        }

        // Find most common word that appears in at least 2 items
        if let commonWord = wordFrequency
            .filter({ $0.value >= 2 })
            .max(by: { $0.value < $1.value })?.key {
            return "More about \(commonWord)"
        }

        return "Related articles"
    }

    /// Extracts the main topic from an outline point.
    private func extractTopicFromPoint(_ point: String) -> String {
        // Remove common prefixes and extract core topic
        var topic = point
            .replacingOccurrences(of: "¶\\d+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Trim to first sentence or clause
        if let firstPeriod = topic.firstIndex(of: ".") ?? topic.firstIndex(of: "。") {
            topic = String(topic[..<firstPeriod])
        }

        // Limit length
        if topic.count > 60 {
            let endIndex = topic.index(topic.startIndex, offsetBy: 60)
            topic = String(topic[..<endIndex]) + "..."
        }

        return topic
    }

    /// Generates a follow-up question from a topic.
    private func generateQuestionFromTopic(_ topic: String) -> String {
        let lowerTopic = topic.lowercased()

        // Pattern-based question generation
        if lowerTopic.contains("how") {
            return "Can you explain \(topic.lowercased())?"
        } else if lowerTopic.contains("why") {
            return "What are the reasons for \(topic.lowercased())?"
        } else if lowerTopic.contains("what") {
            return "Tell me more about \(topic.lowercased())"
        } else {
            // Check if topic looks like it's in Chinese
            if topic.range(of: "\\p{Han}", options: .regularExpression) != nil {
                return "关于\(topic)的更多细节？"
            } else {
                return "What about \(topic.lowercased())?"
            }
        }
    }

    /// Determines if a point is worthy of deep dive exploration.
    private func isDeepDiveWorthy(_ point: String) -> Bool {
        let deepDiveIndicators = [
            "comprehensive", "detailed", "analysis", "framework", "system",
            "architecture", "methodology", "approach", "strategy", "theory",
            "mechanism", "process", "implementation", "advanced",
            // Chinese indicators
            "详细", "深入", "分析", "系统", "框架", "方法", "理论", "机制", "实现"
        ]

        let lowerPoint = point.lowercased()
        return deepDiveIndicators.contains { lowerPoint.contains($0) }
    }
}
