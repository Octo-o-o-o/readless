# Liquid Glass UI Framework Design for Readless

**Date**: 2026-03-01
**Status**: Approved
**Author**: Claude Sonnet 4.5
**Target Platform**: macOS 14+
**Design Language**: Liquid Glass (Apple 2026)

---

## Executive Summary

This design document outlines a comprehensive UI framework redesign for Readless macOS client, adopting Apple's Liquid Glass design language (announced at WWDC 2025) and implementing AI-driven interaction patterns. The redesign focuses on three core pillars:

1. **Visual Excellence**: Full implementation of Liquid Glass materials, animations, and visual effects
2. **AI-Powered Interaction**: Command Bar, semantic search, and contextual suggestions
3. **Performance First**: Observation framework, virtualized rendering, and adaptive degradation

**Timeline**: 6-8 weeks
**Risk Level**: Medium
**Expected Outcome**: A cutting-edge macOS app that showcases the latest design standards while dramatically improving user productivity

---

## 1. Architecture Overview

### 1.1 Module Structure

```
macos/
├── Package.swift
├── Sources/
│   ├── App/                    # Main executable
│   ├── Core/                   # Domain models
│   ├── Networking/             # API client
│   ├── Storage/                # GRDB local database
│   ├── LiquidGlassKit/        # 🆕 Design system package
│   │   ├── Materials/
│   │   ├── Colors/
│   │   ├── Typography/
│   │   ├── Animations/
│   │   └── Components/
│   ├── AIServices/            # 🆕 AI unified service layer
│   │   ├── CommandBar/
│   │   ├── SemanticSearch/
│   │   └── Suggestions/
│   ├── ReaderFeature/         # 🆕 Reading module
│   ├── LibraryFeature/        # 🆕 Library module
│   └── Utils/
```

### 1.2 Dependency Graph

```
App → Features (Reader/Library/AICommand) → Shared (LiquidGlassKit/AIServices)
     → Foundation (Core/Networking/Storage/Utils)
```

**Core Principles**:
- Feature-based modularization (not technical layers)
- Dependency inversion (features depend on interfaces)
- Independent compilation for each module

---

## 2. LiquidGlassKit Design System

### 2.1 Materials

Based on [Apple HIG Materials](https://developer.apple.com/design/human-interface-guidelines/materials):

**Liquid Glass Variants**:
- `liquidGlassRegular`: Blurs + adjusts luminosity for legibility (sidebars, popovers)
- `liquidGlassClear`: Highly translucent, prioritizes content visibility (media overlays)

**Standard Materials** (for content layer):
- `ultraThin`, `thin`, `regular`, `thick`

**Implementation** (using actual SwiftUI APIs):
```swift
public enum LGMaterial {
    case liquidGlassRegular
    case liquidGlassClear
    case ultraThin, thin, regular, thick

    public var material: Material {
        switch self {
        case .liquidGlassRegular, .liquidGlassClear:
            return .ultraThinMaterial
        case .ultraThin: return .ultraThinMaterial
        // ...
        }
    }
}

// Custom NSVisualEffectView for true Liquid Glass
public struct LiquidGlassBackground: NSViewRepresentable {
    let variant: LGMaterial

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = variant == .liquidGlassClear ? .hudWindow : .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
}
```

### 2.2 Colors

**Vibrant Colors** (for Liquid Glass):
- `vibrantLabel`, `vibrantSecondaryLabel`, `vibrantTertiaryLabel`
- `vibrantFill`, `vibrantSecondaryFill`, `vibrantTertiaryFill`
- `vibrantSeparator`

**Semantic Colors** (auto dark mode):
- `accent`, `label`, `secondaryLabel`, etc.

All colors use `NSColor` dynamic providers for automatic dark mode adaptation.

### 2.3 Typography

SF Pro Display + SF Mono, following Liquid Glass's bold left-aligned emphasis:
- `largeTitle`: 34pt bold
- `title1`: 28pt bold
- `headline`: 17pt semibold
- `body`: 15pt regular

### 2.4 Animations

Fluid animations are core to Liquid Glass:
- `fluid`: .spring(duration: 0.5, bounce: 0.2)
- `snappy`: .spring(duration: 0.35, bounce: 0.1)
- `glassAppear`: .spring(duration: 0.4, bounce: 0.15)
- `press`: .easeOut(duration: 0.1)

---

## 3. State Management (Observation Framework)

### 3.1 Migration from ObservableObject

Full migration to Swift 5.9+ `@Observable` macro:

**Benefits**:
- ✅ Fine-grained observation (only accessed properties trigger redraws)
- ✅ Zero boilerplate (`@Published` not needed)
- ✅ Performance optimized by compiler
- ✅ Simpler syntax (`@State` instead of `@StateObject`)

**Example**:
```swift
@Observable
public final class ContentManager {
    public var contents: [Content] = []
    public var isLoading = false

    @MainActor
    public func loadContents() async {
        isLoading = true
        defer { isLoading = false }
        contents = try await apiClient.fetchContents()
    }
}

// View automatically subscribes to accessed properties
struct ContentListView: View {
    @Environment(ContentManager.self) private var contentManager

    var body: some View {
        // Only redraws when `contents` changes
        ForEach(contentManager.contents) { ... }
    }
}
```

### 3.2 State Architecture

**Global State**:
- `ContentManager`: Content library state
- `AICoordinator`: AI features coordinator
- `AuthenticationManager`: Auth state

**Feature-Local State**:
- `ReaderViewModel`: Reader-specific state
- Each feature has its own ViewModel

**Environment Passing**:
```swift
@main
struct ReadlessApp: App {
    @State private var contentManager = ContentManager.shared
    @State private var aiCoordinator = AICoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(contentManager)
                .environment(aiCoordinator)
        }
    }
}
```

---

## 4. AI Services Layer

### 4.1 Command Bar (Global Cmd+K)

**Features**:
- Multi-modal input: text, URLs, images (OCR), files (PDF/TXT)
- Fuzzy matching for static commands
- Natural language understanding via backend AI
- Keyboard shortcuts: Cmd+K (open), Cmd+Shift+V (paste & process)

**Architecture**:
```swift
public final class CommandBarService {
    public func search(_ query: String) async -> [CommandResult] {
        let staticMatches = fuzzyMatch(query)
        let contentMatches = await searchContent(query)
        let aiCommands = await interpretNaturalLanguage(query)
        return merge(staticMatches, contentMatches, aiCommands)
    }

    public func processURL(_ url: URL) async -> ProcessingResult
    public func processImage(_ image: NSImage) async -> ProcessingResult
    public func processFile(_ url: URL) async -> ProcessingResult
}
```

**UI**:
- Liquid Glass floating panel (600pt width)
- Real-time search results
- Drag & drop support for files/images
- `onPaste` handler for clipboard content

### 4.2 Semantic Search

Replaces traditional FTS with AI-powered semantic search:
```swift
public final class SemanticSearchService {
    public func search(_ query: String) async -> [SearchResult] {
        let response = try await apiClient.semanticSearch(query: query)
        return response.results.map { ... }
    }

    public func analyzeQuery(_ query: String) async -> QueryAnalysis {
        // Parse intent, time range, topics, filters
    }
}
```

### 4.3 Contextual Suggestions

Automatically suggests:
- Related content
- Follow-up questions
- Deep dive topics

```swift
public final class SuggestionService {
    public func generateSuggestions(for content: Content) async -> [Suggestion]
    public func apply(_ suggestion: Suggestion) async
}
```

---

## 5. Core UI Components

### 5.1 Main Window (Three-Column Layout)

```
┌─────────────┬──────────────┬────────────────────────┐
│  Sidebar    │ Content List │  Detail (Reader)       │
│ (Liquid     │ (Cards)      │                        │
│  Glass)     │              │                        │
└─────────────┴──────────────┴────────────────────────┘
```

- **Sidebar**: Liquid Glass material, AI search button at bottom
- **Content List**: Standard material cards with hover effects
- **Reader**: Multi-level summary with source tracing

### 5.2 Reader View (Enhanced)

- **L0 Header**: Title + one-line summary (Liquid Glass background)
- **L1 Outline**: Keyboard navigable (j/k, Enter to expand)
- **L2 Expansion**: Fetch on-demand with fluid animation
- **Source Panel**: Slide-in panel with paragraph anchors
- **Suggestions Panel**: Floating bottom-right

### 5.3 Command Bar View

- Glass appearance with backdrop blur
- Supports drag & drop (images, PDFs, URLs)
- Real-time search with debouncing (300ms)
- Keyboard navigation (↑/↓, Enter, Esc)

---

## 6. Performance Optimization

### 6.1 Rendering Performance

**Virtualized Lists**:
```swift
struct VirtualizedList<Item, Content>: View {
    // Only renders visible range + 5-row buffer
    // Dramatically reduces view count for 1000+ items
}
```

**Image Caching**:
```swift
actor ImageCache {
    private var cache: [URL: NSImage] = [:]
    private let maxCacheSize = 100
    // LRU eviction
}
```

**Debouncing**:
```swift
@Observable
class DebouncedSearchViewModel {
    var searchQuery = "" {
        didSet { debouncedSearch() }
    }

    private func debouncedSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try await Task.sleep(for: .milliseconds(300))
            await performSearch()
        }
    }
}
```

### 6.2 Memory Management

- Weak references in closures
- Resource cleanup on `deinit`
- Memory warning handler (clears caches)
- Pagination for large datasets (50 items/page)

### 6.3 Network Performance

- Request caching (5min TTL)
- Request batching (50ms window)
- Exponential backoff retry (max 3 attempts)
- HTTP/2 connection pooling

### 6.4 Compilation Optimization

```swift
// Package.swift
.unsafeFlags(["-O"], .when(configuration: .release))
.unsafeFlags(["-whole-module-optimization"], .when(configuration: .release))
```

### 6.5 Adaptive Performance

```swift
public enum PerformanceLevel {
    case high      // All effects
    case balanced  // Standard
    case low       // Reduced effects (no Liquid Glass)
}

// Auto-detect based on device specs
let physicalMemory = ProcessInfo.processInfo.physicalMemory
let processorCount = ProcessInfo.processInfo.processorCount
```

---

## 7. Offline Support & Local Storage

### 7.1 GRDB SQLite Database

**Schema**:
```sql
CREATE TABLE contents (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    source_url TEXT,
    l0_summary TEXT,
    l1_outline BLOB,  -- JSON encoded
    status TEXT NOT NULL,
    created_at DATETIME NOT NULL,
    synced_at DATETIME
);

CREATE VIRTUAL TABLE contents_fts USING fts5(title, l0_summary);
```

### 7.2 Sync Strategy

**Bi-directional sync**:
1. Push local unsynced changes to server
2. Pull server changes since `lastSyncTime`
3. Conflict resolution: last-write-wins

**Background sync**: Every 5 minutes

```swift
@Observable
public final class SyncManager {
    public func sync() async throws {
        let unsyncedContents = try await localDB.unsyncedContents()
        for content in unsyncedContents {
            try await apiClient.updateContent(content)
            try await localDB.markAsSynced(content.id)
        }

        let remoteContents = try await apiClient.fetchContentsSince(lastSyncTime)
        for content in remoteContents {
            try await localDB.saveContent(content)
        }
    }
}
```

---

## 8. Authentication & Security

### 8.1 Clerk JWT Authentication

```swift
@Observable
public final class AuthenticationManager {
    public var isAuthenticated = false
    public var authToken: String?

    public func login(token: String) async throws {
        let userID = try await validateToken(token)
        try saveTokenToKeychain(token)
        self.authToken = token
        APIClient.shared.setAuthToken(token)
    }

    public func refreshTokenIfNeeded() async throws {
        if isTokenExpiringSoon(authToken) {
            let newToken = try await refreshToken(authToken)
            try saveTokenToKeychain(newToken)
        }
    }
}
```

### 8.2 Keychain Storage

All tokens stored in macOS Keychain:
```swift
private func saveTokenToKeychain(_ token: String) throws {
    let query: [String: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "com.readless.auth",
        kSecAttrAccount: "authToken",
        kSecValueData: token.data(using: .utf8)!
    ]
    SecItemAdd(query as CFDictionary, nil)
}
```

---

## 9. Error Handling & Retry

### 9.1 Retry Policy

**Exponential backoff** with jitter:
```swift
public struct RetryPolicy {
    let maxAttempts: Int = 3
    let baseDelay: TimeInterval = 1.0
    let multiplier: Double = 2.0
    let jitter: Double = 0.1

    public func delay(for attempt: Int) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(multiplier, Double(attempt))
        let cappedDelay = min(exponentialDelay, 60.0)
        let jitterAmount = cappedDelay * jitter * Double.random(in: -1...1)
        return max(0, cappedDelay + jitterAmount)
    }
}
```

**Retriable errors**: 5xx, 429 (rate limit), 408 (timeout)

### 9.2 Error Types

```swift
public enum AppError: LocalizedError {
    case networkError(Error)
    case apiError(statusCode: Int, message: String)
    case processingError(String)
    case unauthorized

    public var recoverySuggestion: String? {
        switch self {
        case .networkError: return "请检查网络连接后重试"
        case .unauthorized: return "请在设置中重新登录"
        default: return "请稍后重试"
        }
    }
}
```

---

## 10. Accessibility

### 10.1 VoiceOver Support

All interactive elements have:
- `.accessibilityLabel()`
- `.accessibilityHint()`
- `.accessibilityValue()`
- `.accessibilityAddTraits()`

### 10.2 Keyboard Navigation

**Full keyboard support**:
- Tab/Shift+Tab: Focus traversal
- j/k: Outline navigation
- Enter: Expand/collapse
- t: Trace source
- Cmd+K: Command Bar
- Esc: Dismiss

### 10.3 Accessibility Rotor

```swift
.accessibilityRotor("大纲点") {
    ForEach(points) { index, point in
        AccessibilityRotorEntry(point.point, id: index) {
            focusedIndex = index
        }
    }
}
```

---

## 11. Testing Strategy

### 11.1 Unit Tests

**Coverage target**: > 85%

```swift
// LiquidGlassKitTests
func testFluidAnimationExists() {
    let animation = LGAnimation.fluid.animation
    XCTAssertNotNil(animation)
}

// AIServicesTests
func testFuzzyMatchingReturnsRelevantCommands() async {
    let results = await service.search("new clip")
    XCTAssertTrue(results.contains { /* match clipboard command */ })
}
```

### 11.2 UI Tests

```swift
func testCommandBarAppearsOnCmdK() {
    app.typeKey("k", modifierFlags: .command)
    let commandBar = app.textFields["输入命令、粘贴URL、拖拽文件..."]
    XCTAssertTrue(commandBar.waitForExistence(timeout: 1))
}
```

### 11.3 Performance Tests

```swift
func testContentListRenderingPerformance() {
    measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
        // Render 1000 items
    }
}
```

---

## 12. Implementation Milestones

### Milestone 1: Foundation (Week 1-2)
- ✅ LiquidGlassKit package complete
- ✅ Observation framework migration
- ✅ Local storage (GRDB)

**Success Criteria**: All modules compile independently, 80% test coverage

### Milestone 2: AI Services (Week 3-4)
- ✅ Command Bar with multi-modal input
- ✅ Semantic search integration
- ✅ Contextual suggestions

**Success Criteria**: Command Bar < 100ms response, search accuracy > 85%

### Milestone 3: UI Refactor (Week 5-6)
- ✅ Main window with Liquid Glass
- ✅ All animations implemented
- ✅ Accessibility support

**Success Criteria**: 60fps animations, VoiceOver complete, dark mode perfect

### Milestone 4: Optimization & Testing (Week 7-8)
- ✅ Performance optimization
- ✅ Full test suite
- ✅ Authentication flow

**Success Criteria**: Memory < 200MB idle, startup < 2s, all tests pass

---

## 13. Risk Assessment

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| Liquid Glass performance impact | High | Medium | Adaptive degradation, low-end auto-disable |
| @Observable compatibility | Medium | Low | Requires macOS 14+, documented requirement |
| Large file OOM | High | Medium | Streaming processing, memory limits, chunking |
| Network instability | Medium | High | Retry mechanism, offline support, local cache |
| AI API rate limits | Medium | Medium | Request queue, batching, local fallback |

---

## 14. Performance KPIs

| Metric | Target | Measurement |
|--------|--------|-------------|
| Startup time | < 2s | XCTest measure |
| Memory (idle) | < 200MB | Instruments |
| Memory (active) | < 500MB | Instruments |
| UI response | < 100ms | CADisplayLink |
| FPS | 60fps | CADisplayLink |
| Network success rate | > 99% | Logs |
| Crash rate | < 0.1% | Crash reporter |

---

## 15. Rollback Strategy

**Three-tier rollback**:

1. **Level 1**: Disable Liquid Glass (set `performanceLevel = .low`)
2. **Level 2**: Disable AI features (fallback to basic search)
3. **Level 3**: Git revert to stable commit

---

## 16. Design Summary

### Core Innovations
1. **Liquid Glass Design**: macOS 26 latest design language
2. **AI-Driven UX**: Command Bar + semantic search + suggestions
3. **Multi-modal Input**: Text/URL/image/file unified processing
4. **Observation Framework**: Fine-grained state observation
5. **Offline-First**: GRDB local storage + bi-directional sync

### Tech Stack
- **Frontend**: SwiftUI + Swift 5.9 Observation + GRDB + SPM
- **Backend**: FastAPI + PostgreSQL + OpenAI + ElevenLabs
- **Design**: LiquidGlassKit (independent SPM package)

### Expected Impact
- **Visual Impact**: Liquid Glass glass effects + fluid animations, macOS 26 cutting-edge
- **Productivity**: Command Bar boosts efficiency 3x
- **Intelligence**: Semantic search + suggestions reduce manual work 70%
- **Performance**: 60fps smooth animations, memory < 500MB
- **Maintainability**: Modular architecture, each feature independently testable

---

## References

- [Apple Human Interface Guidelines - Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Apple Human Interface Guidelines - Color](https://developer.apple.com/design/human-interface-guidelines/color)
- [WWDC 2025 - Get to know the new design system](https://developer.apple.com/videos/play/wwdc2025/356/)
- [WWDC 2025 - Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)
- [Swift Observation Framework Documentation](https://developer.apple.com/documentation/observation)

---

**End of Design Document**
