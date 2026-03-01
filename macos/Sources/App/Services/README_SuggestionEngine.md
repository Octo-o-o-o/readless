# SuggestionEngine

AI-powered suggestion service for Phase 3 of the Readless project.

## Overview

The `SuggestionEngine` generates context-based suggestions to help users discover relevant content and actions. It analyzes the current reading material to provide intelligent recommendations without requiring external AI API calls for the MVP.

## Features

### 1. Related Content Discovery
- Finds similar content by analyzing L0 summaries and titles
- Uses Jaccard similarity coefficient for keyword matching
- Groups related items by common topics
- Returns top 3 most relevant matches

### 2. Follow-Up Questions
- Extracts key topics from L1 outline points
- Generates contextual questions based on content structure
- Supports both English and Chinese content
- Returns 2-3 relevant questions

### 3. Deep Dive Topics
- Identifies substantial topics that warrant deeper exploration
- Prioritizes outline points with multiple paragraph anchors
- Detects depth indicators (e.g., "comprehensive", "detailed", "analysis")
- Returns 1-2 deep dive suggestions

### 4. Intelligent Caching
- Caches suggestions per content ID
- 5-minute TTL (time-to-live) for cache entries
- Prevents redundant calculations for frequently accessed content
- Manual cache clearing support

## Architecture

```
SuggestionEngine
├── Cache Management
│   ├── CachedSuggestions (struct)
│   └── 5-minute expiration
├── Content Analysis
│   ├── Keyword extraction
│   ├── Similarity calculation
│   └── Topic extraction
└── Suggestion Generation
    ├── Related content
    ├── Follow-up questions
    └── Deep dive topics
```

## API Reference

### Initialization

```swift
let engine = SuggestionEngine()
// Or with custom ContentManager for testing
let engine = SuggestionEngine(contentManager: customManager)
```

### Main Methods

#### `generateSuggestions(for:)`
Generates all types of suggestions for a content item.

```swift
func generateSuggestions(for content: Content) async -> [Suggestion]
```

**Returns:** Combined list of up to 7 suggestions (3 related + 3 questions + 2 deep dives)

**Caching:** Results are cached for 5 minutes per content ID

#### `getRelatedContent(for:)`
Finds related content based on similarity.

```swift
func getRelatedContent(for content: Content) async -> [Suggestion]
```

**Returns:** `.relatedContent` suggestions with grouped content IDs

#### `generateFollowUpQuestions(for:)`
Creates contextual questions from outline points.

```swift
func generateFollowUpQuestions(for content: Content) async -> [Suggestion]
```

**Returns:** `.followUpQuestion` suggestions based on L1 outline

#### `suggestDeepDiveTopics(for:)`
Identifies topics worthy of deeper exploration.

```swift
func suggestDeepDiveTopics(for content: Content) async -> [Suggestion]
```

**Returns:** `.deepDive` suggestions for complex topics

#### `clearCache()`
Clears all cached suggestions.

```swift
func clearCache()
```

#### `clearCache(for:)`
Clears cached suggestions for a specific content ID.

```swift
func clearCache(for contentID: String)
```

## Suggestion Types

The engine generates three types of suggestions defined in `AICoordinator`:

```swift
public enum Suggestion: Identifiable {
    case relatedContent(title: String, contentIDs: [String])
    case followUpQuestion(question: String)
    case deepDive(topic: String)
}
```

### `.relatedContent`
- **Title:** Display name (e.g., "More about Swift" or "Related articles")
- **ContentIDs:** Array of related content identifiers
- **Use Case:** Help users discover similar content they've saved

### `.followUpQuestion`
- **Question:** Contextual question based on content structure
- **Format:** Pattern-based (English) or template-based (Chinese)
- **Use Case:** Encourage deeper exploration of specific topics

### `.deepDive`
- **Topic:** Extracted topic worthy of exploration
- **Criteria:** Multiple anchors or depth keywords
- **Use Case:** Guide users to complex subtopics

## Algorithm Details

### Related Content Matching

1. **Keyword Extraction**
   - Splits text into words
   - Filters out stop words (English + Chinese)
   - Minimum 2 characters per word

2. **Similarity Calculation**
   - Uses Jaccard similarity: `|A ∩ B| / |A ∪ B|`
   - Compares keyword sets between content items
   - Scores range from 0.0 (no match) to 1.0 (perfect match)

3. **Topic Grouping**
   - Finds most common keywords appearing in 2+ items
   - Groups related content under common topic
   - Fallback: Uses individual titles

### Follow-Up Question Generation

1. **Topic Extraction**
   - Removes paragraph anchors (¶1, ¶2, etc.)
   - Truncates to first sentence
   - Limits to 60 characters max

2. **Question Patterns**
   - "How" topics → "Can you explain...?"
   - "Why" topics → "What are the reasons for...?"
   - "What" topics → "Tell me more about..."
   - Default → "What about...?"
   - Chinese → "关于...的更多细节？"

### Deep Dive Detection

1. **Anchor Count**
   - Points with 2+ paragraph anchors
   - Indicates substantial content

2. **Depth Indicators (Keywords)**
   - English: comprehensive, detailed, analysis, framework, system, etc.
   - Chinese: 详细, 深入, 分析, 系统, 框架, etc.

## Configuration

Default limits (configurable in source):

```swift
private let maxRelatedContent = 3
private let maxFollowUpQuestions = 3
private let maxDeepDiveTopics = 2
private let maxTotalSuggestions = 7
private let cacheExpirationInterval: TimeInterval = 300 // 5 minutes
```

## Integration with AICoordinator

```swift
@MainActor
class ExampleViewModel {
    private let suggestionEngine = SuggestionEngine()
    private let aiCoordinator: AICoordinator

    func loadSuggestions(for content: Content) async {
        let suggestions = await suggestionEngine.generateSuggestions(for: content)
        aiCoordinator.suggestions = suggestions
    }
}
```

## Performance Considerations

- **No AI API calls:** All processing is local for MVP
- **Efficient caching:** Prevents redundant calculations
- **Lazy evaluation:** Suggestions generated only when requested
- **Memory bounded:** Cache clears old entries automatically

## Future Enhancements

Phase 4 could add:

1. **AI-Powered Similarity**
   - Semantic embeddings via OpenAI
   - Vector similarity search
   - Better cross-language matching

2. **Personalization**
   - User preference learning
   - Reading history analysis
   - Interest-based ranking

3. **Advanced Question Generation**
   - LLM-based question formulation
   - Context-aware phrasing
   - Multi-level questions

4. **Dynamic Deep Dives**
   - AI identifies unexplored angles
   - Generates research paths
   - Suggests external resources

## Testing Strategy

Without a dedicated AppTests target, manual testing approach:

1. **Build Verification:** `swift build` passes
2. **Integration Testing:** Use in ReaderView with real content
3. **Cache Testing:** Verify no redundant calculations
4. **Edge Cases:**
   - Empty content library
   - Content with no L1 outline
   - Content with no L0 summary
   - Chinese vs English content

## Example Usage

See `/Users/wangyixiao/WorkSpace/readless/macos/Examples/SuggestionEngineExample.swift` for comprehensive usage examples.

## Implementation Notes

- **MainActor:** All methods run on main actor for UI safety
- **Async/await:** Uses modern Swift concurrency
- **Pure Swift:** No external dependencies beyond Core and AIServices
- **Extensible:** Designed to add AI providers later without breaking API

## Related Files

- `AICoordinator.swift` - Defines `Suggestion` enum
- `ContentManager.swift` - Provides content data
- `Content.swift` - Core data model
- `OutlinePoint.swift` - L1 outline structure
