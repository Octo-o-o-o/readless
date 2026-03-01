# Command Bar UI Complete Implementation Design

**Date**: 2026-03-01
**Status**: Approved
**Author**: Claude Sonnet 4.5
**Implementation Strategy**: Progressive (3 Phases)
**Target Platform**: macOS 14+
**Related**: Task 8-10 (Command Bar Service Foundation)

---

## Executive Summary

This design document outlines the complete UI implementation for the Command Bar feature in Readless macOS app. The Command Bar is a Spotlight-style floating window that provides:

- **Multi-modal input**: Text, URL, images, PDF files via paste/drag
- **Real-time suggestions**: AI-powered contextual recommendations
- **Content preview**: Right-side panel with quick actions
- **Command history**: Searchable history with smart ranking
- **Keyboard-first**: Complete keyboard navigation

**Implementation Approach**: Progressive 3-phase delivery
- **Phase 1** (1-2 days): Core UI + ⌘K hotkey
- **Phase 2** (2-3 days): Smart interactions + preview panel
- **Phase 3** (2-3 days): AI enhancement + suggestions

**Total Timeline**: 5-8 days
**Risk Level**: Low (progressive approach minimizes risk)

---

## 1. Architecture Overview

### 1.1 System Layers

```
┌─────────────────────────────────────────────────────────┐
│ UI Layer（SwiftUI）                                      │
│ ┌─────────────────────┐  ┌──────────────────────────┐  │
│ │ CommandBarWindow    │  │ CommandBarPreviewPanel   │  │
│ │ - Floating window   │  │ - Content preview        │  │
│ │ - Input field       │  │ - Metadata display       │  │
│ │ - Results list      │  │ - Quick actions          │  │
│ └─────────────────────┘  └──────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                          ↕
┌─────────────────────────────────────────────────────────┐
│ Coordination Layer（@Observable）                        │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ AICoordinator (extend existing)                     │ │
│ │ - Command Bar state                                 │ │
│ │ - Search results                                    │ │
│ │ - Suggestions                                       │ │
│ │ - History                                          │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
                          ↕
┌─────────────────────────────────────────────────────────┐
│ Service Layer                                            │
│ ┌──────────────────┐  ┌─────────────────────────────┐  │
│ │ CommandBarService│  │ SuggestionEngine            │  │
│ │ - Process input  │  │ - Generate suggestions      │  │
│ │ - Execute actions│  │ - Context awareness         │  │
│ └──────────────────┘  └─────────────────────────────┘  │
│ ┌──────────────────┐  ┌─────────────────────────────┐  │
│ │ HistoryManager   │  │ InputParser (implemented)   │  │
│ │ - Store history  │  │ - Parse user input          │  │
│ │ - Search history │  │ - Detect types              │  │
│ └──────────────────┘  └─────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                          ↕
┌─────────────────────────────────────────────────────────┐
│ Data Layer                                               │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ LocalDatabase (GRDB) + ContentManager               │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

### 1.2 Core Design Principles

1. **Single Source of Truth**: AICoordinator as the only state management center
2. **Dependency Injection**: All services are testable and replaceable
3. **Async-First**: All IO operations use async/await
4. **Liquid Glass**: Unified material system via LiquidGlassKit
5. **Keyboard-First**: Complete keyboard operation, no mouse required

### 1.3 File Organization

```
macos/Sources/
├── App/
│   ├── Views/
│   │   ├── CommandBar/
│   │   │   ├── CommandBarWindow.swift       (Main window)
│   │   │   ├── CommandBarInputField.swift   (Input field)
│   │   │   ├── CommandBarResultsList.swift  (Results list)
│   │   │   ├── CommandBarPreviewPanel.swift (Preview panel)
│   │   │   └── CommandBarSuggestions.swift  (Suggestions)
│   │   └── ...
│   ├── Services/
│   │   ├── CommandBarService.swift          (Business logic)
│   │   ├── SuggestionEngine.swift           (Suggestion engine)
│   │   └── HistoryManager.swift             (History manager)
│   └── ...
├── AIServices/ (existing)
│   ├── AICoordinator.swift (extend)
│   ├── CommandBar/
│   │   ├── InputParser.swift (implemented)
│   │   └── InputModels.swift (implemented)
│   └── ...
└── LiquidGlassKit/ (existing)
```

---

## 2. Phase 1: Core UI Implementation

### 2.1 CommandBarWindow Design

**Visual Specifications:**
- **Size**: Initial width 600px, height dynamic (200-500px)
- **Position**: Screen center, 20% from top
- **Material**: LiquidGlass Regular
- **Corner Radius**: 16px
- **Shadow**: Deep shadow (radius: 40, opacity: 0.3)
- **Background**: Semi-transparent blur (.ultraThinMaterial + vibrancy)

**Layout Structure:**
```
┌────────────────────────────────────────┐
│  🔍  [Type to search or paste URL...] │ ← Input field (60px)
├────────────────────────────────────────┤
│  📄  Import text from clipboard        │ ← Result items
│  🔍  Search: "machine learning"        │
│  🎙️  Generate podcast from selection  │
│  ⚙️  Open Settings                     │
├────────────────────────────────────────┤
│  💡 Suggestions (3)                    │ ← Suggestions (collapsible)
└────────────────────────────────────────┘
```

### 2.2 CommandBarInputField Component

**Features:**
```swift
struct CommandBarInputField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    // Features:
    // - Auto-focus (when window shows)
    // - Smart placeholder (context-aware)
    // - Real-time debounced search (300ms)
    // - Multi-modal input support:
    //   • Paste text/URL
    //   • Drag & drop files (images/PDFs)
    //   • Screenshot detection (auto-detect clipboard)
}
```

**Interaction Details:**
- **Dynamic Placeholder**:
  - Idle: "Type to search or paste URL..."
  - Has clipboard: "Press ⌘V to import clipboard"
  - File hovering: "Drop file here to analyze"

- **Visual Feedback**:
  - Border highlight on input (accent color)
  - Dashed border animation on drag
  - Brief ✓ icon on paste/drop success

### 2.3 CommandBarResultsList Component

**Result Row Structure:**
```swift
struct CommandResultRow: View {
    let result: CommandResult
    let isSelected: Bool

    // Layout:
    // [Icon] [Title]              [Shortcut]
    //        [Subtitle/Description]

    // States:
    // - Default: Semi-transparent
    // - Hover/Selected: Highlight + slight scale
    // - Pressed: Scale down animation
}
```

**Result Grouping:**
1. **Quick Actions** (always shown)
   - Import from clipboard
   - Search all content
   - Generate podcast

2. **Search Results** (when query exists)
   - Content search results
   - Command history

3. **Suggestions** (AI-powered)
   - Context-based recommendations

### 2.4 Keyboard Shortcuts System

**Global Shortcuts:**
- `⌘K` - Show/hide Command Bar
- `Esc` - Close Command Bar
- `⌘,` - Open Settings (in Command Bar)

**Navigation Shortcuts:**
- `↑/↓` - Select previous/next item
- `Enter` - Execute selected item
- `⌘Enter` - Execute and keep open (for continuous actions)
- `Tab` - Switch to preview panel
- `⌘1-9` - Direct select Nth item

### 2.5 Animations & Transitions

**Window Animations:**
- **Open**: Scale 0.9→1.0 + Opacity 0→1 (250ms, easeOut)
- **Close**: Scale 1.0→0.95 + Opacity 1→0 (200ms, easeIn)
- **Content switch**: CrossFade transition (150ms)

**List Animations:**
- **Appear**: Top-to-bottom fade in, 30ms stagger
- **Update**: Smart diff, only animate changed items
- **Selection**: Slight scale (1.02x) + highlight fade in

**Performance Optimization:**
- Use `.animation(.spring(response: 0.3, dampingFraction: 0.8))`
- List virtualization (LazyVStack)
- Icon preloading

### 2.6 HotkeyService Integration

**Modify HotkeyService.swift:**
```swift
extension KeyboardShortcuts.Name {
    static let commandBar = Self("commandBar", default: .init(.k, modifiers: [.command]))
}

// In HotkeyService init:
KeyboardShortcuts.onKeyUp(for: .commandBar) {
    NotificationCenter.default.post(name: .toggleCommandBar, object: nil)
}
```

**Integrate in ReadlessApp.swift:**
```swift
@State private var aiCoordinator = AICoordinator()

var body: some Scene {
    WindowGroup {
        ContentView()
            .overlay {
                if aiCoordinator.isCommandBarVisible {
                    CommandBarWindow()
                        .environment(aiCoordinator)
                }
            }
    }
}
```

---

## 3. Phase 2: Smart Interactions

### 3.1 Preview Panel Design (CommandBarPreviewPanel)

**Layout:**
```
┌─────────────┬──────────────────────────┐
│  Command Bar│  Preview Panel (300px)   │
│  (600px)    │                          │
│             │  ┌────────────────────┐  │
│  [Input]    │  │ 📄 Article Title  │  │
│             │  │ source: nytimes.com│  │
│  Results:   │  ├────────────────────┤  │
│  • Item 1   │  │ L0: One-liner...   │  │
│  • Item 2 ←─┼→ │ L1: Summary...     │  │
│  • Item 3   │  │ ...                │  │
│             │  ├────────────────────┤  │
│             │  │ Quick Actions:     │  │
│             │  │ [Import] [Share]   │  │
│             │  └────────────────────┘  │
└─────────────┴──────────────────────────┘
```

**Preview Content:**
- **Content preview**: L0+L1 summary (if exists)
- **Metadata**: Source, type, creation time
- **Quick actions**: Import, Share, Generate podcast
- **Related content**: Smart recommendations

**Interaction:**
- Tab to switch focus to preview panel
- Scrollable within preview panel
- Shift+Tab to return to main panel

### 3.2 Multi-Modal Input Support

**Drag & Drop Handling:**
```swift
.onDrop(of: [.fileURL, .image, .pdf], isTargeted: $isDropTargeted) { providers in
    // 1. Detect file type
    // 2. Read file content
    // 3. Call InputParser.parse()
    // 4. Show preview or process directly
}
```

**Supported Input Types:**
- **Text**: Paste or type
- **URL**: Auto-detect and extract
- **Image**: Drag & drop → OCR + vision analysis
- **PDF**: Drag & drop → extract text + structure analysis
- **Screenshot**: Auto-detect clipboard image

### 3.3 Real-Time Search

**Search Strategy:**
```swift
@Published var query: String = "" {
    didSet {
        // Debounce 300ms
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            await performSearch(query)
        }
    }
}
```

**Search Scope:**
1. **Local content**: GRDB full-text search (FTS5)
2. **Command history**: Recent 100 commands
3. **Smart suggestions**: Context-based generation

---

## 4. Phase 3: AI Enhancement

### 4.1 CommandBarService Business Logic

**Core Responsibilities:**
```swift
@MainActor
final class CommandBarService {
    private let inputParser: InputParser
    private let aiCoordinator: AICoordinator
    private let contentManager: ContentManager
    private let historyManager: HistoryManager

    // Process user input
    func processInput(_ input: CommandBarInput, mode: SubmissionMode) async throws -> ExecutionResult

    // Execute command
    func executeCommand(_ command: CommandResult) async throws

    // Generate suggestions
    func generateSuggestions(context: SuggestionContext) async -> [Suggestion]
}
```

**Processing Flow:**
```
User Input
    ↓
InputParser.parse()  // Already implemented
    ↓
[Text] → Execute directly
[URL] → Extract content → Preview or import
[Image/PDF] → Multi-modal analysis → Preview or import
    ↓
Update AICoordinator state
    ↓
UI auto-updates (@Observable)
```

### 4.2 SuggestionEngine Smart Recommendations

**Suggestion Sources:**
1. **Context suggestions**:
   - Related to currently reading content
   - Related to recent operations

2. **Time-based suggestions**:
   - Unread content reminders
   - Periodic review suggestions

3. **AI-generated suggestions**:
   - Deep exploration based on content relationships
   - Follow-up questions

**Implementation Strategy:**
```swift
struct SuggestionEngine {
    // Generate suggestions (real-time, with cache)
    func generateSuggestions(
        currentContent: Content?,
        recentHistory: [CommandHistory],
        userPreferences: UserPreferences
    ) async -> [Suggestion]

    // Rank suggestions by priority
    func rankSuggestions(_ suggestions: [Suggestion]) -> [Suggestion]
}
```

### 4.3 HistoryManager History Management

**Data Model:**
```swift
struct CommandHistory: Codable, Identifiable {
    let id: UUID
    let query: String
    let commandType: CommandType
    let timestamp: Date
    let success: Bool
    let metadata: [String: String]
}
```

**Storage Strategy:**
- **SQLite**: Store in GRDB
- **Limit**: Maximum 1000 entries
- **Index**: Full-text index on query field
- **Cleanup**: Auto-clean after 30 days

---

## 5. State Management

### 5.1 AICoordinator Extension

**New State:**
```swift
@Observable
public final class AICoordinator {
    // Existing state
    public var isCommandBarVisible = false
    public var commandQuery = ""
    public var commandResults: [CommandResult] = []

    // New state
    public var selectedResultIndex: Int = 0
    public var previewContent: Content?
    public var suggestions: [Suggestion] = []
    public var commandHistory: [CommandHistory] = []
    public var isLoading: Bool = false
    public var errorMessage: String?

    // Preview panel state
    public var showPreviewPanel: Bool = false
    public var previewMode: PreviewMode = .content
}
```

### 5.2 State Flow

```
User Action
    ↓
CommandBarWindow (View)
    ↓
CommandBarService (Logic)
    ↓
AICoordinator (State)
    ↓
View auto-updates (@Observable)
```

**Advantages:**
- Unidirectional data flow, easy to debug
- Centralized state management
- Automatic UI updates
- Easy to test

---

## 6. Error Handling & Testing

### 6.1 Error Handling

**Layered Error Handling:**
```swift
enum CommandBarError: LocalizedError {
    case inputParsingFailed(String)
    case aiServiceUnavailable
    case contentExtractionFailed(URL)
    case networkError(Error)
    case fileAccessDenied

    var errorDescription: String? {
        // User-friendly error messages
    }

    var recoverySuggestion: String? {
        // Recovery suggestions
    }
}
```

**Error Display:**
- Toast notifications (lightweight errors)
- Inline error messages (important errors)
- Error recovery buttons (recoverable errors)

### 6.2 Testing Strategy

**Unit Tests:**
- InputParser: 100% coverage (completed)
- CommandBarService: Business logic tests
- SuggestionEngine: Suggestion generation tests
- HistoryManager: Storage and retrieval tests

**UI Tests:**
- CommandBarWindow open/close
- Keyboard navigation
- Search functionality
- File drag & drop

**Integration Tests:**
- End-to-end user flows
- Multi-modal input flows
- AI service integration

---

## 7. Implementation Timeline

### Phase 1: Core UI (1-2 days)
- Day 1 AM: CommandBarWindow + InputField
- Day 1 PM: ResultsList + Animations
- Day 2 AM: HotkeyService integration
- Day 2 PM: Testing + polish

**Deliverable**: Working Command Bar with ⌘K shortcut

### Phase 2: Smart Interactions (2-3 days)
- Day 3: Preview panel + Tab navigation
- Day 4: Multi-modal input (drag & drop)
- Day 5: Real-time search + performance optimization

**Deliverable**: Complete interactive experience

### Phase 3: AI Enhancement (2-3 days)
- Day 6: CommandBarService + InputParser integration
- Day 7: SuggestionEngine + context awareness
- Day 8: HistoryManager + final testing

**Deliverable**: Full AI-powered Command Bar

---

## 8. Success Criteria

**Phase 1:**
- ✅ ⌘K opens Command Bar in center of screen
- ✅ Liquid Glass material applied correctly
- ✅ Keyboard navigation works (↑↓Enter Esc)
- ✅ All animations smooth (60fps)

**Phase 2:**
- ✅ Preview panel shows on Tab
- ✅ Drag & drop works for images and PDFs
- ✅ Real-time search < 300ms response
- ✅ Multi-modal input correctly detected

**Phase 3:**
- ✅ AI suggestions appear in real-time
- ✅ Command history searchable
- ✅ Content import works end-to-end
- ✅ All error cases handled gracefully

---

## 9. Risk Mitigation

**Technical Risks:**
1. **Performance**: Real-time search may be slow
   - Mitigation: Debouncing, indexing, caching

2. **AI latency**: Suggestions may be slow
   - Mitigation: Background generation, caching

3. **UI complexity**: Many interactions to handle
   - Mitigation: Progressive enhancement, extensive testing

**Execution Risks:**
1. **Scope creep**: Features keep expanding
   - Mitigation: Strict phase boundaries

2. **Integration issues**: Components don't work together
   - Mitigation: Early integration testing

---

## 10. Next Steps

After design approval:
1. ✅ **Create implementation plan** (writing-plans skill)
2. ✅ **Execute Phase 1** (1-2 days)
3. ✅ **User testing & feedback**
4. ✅ **Execute Phase 2** (2-3 days)
5. ✅ **User testing & feedback**
6. ✅ **Execute Phase 3** (2-3 days)
7. ✅ **Final testing & polish**
8. ✅ **Ship it!** 🚀

---

**Design Status**: ✅ Approved
**Ready for Implementation**: Yes
**Next Action**: Invoke writing-plans skill
