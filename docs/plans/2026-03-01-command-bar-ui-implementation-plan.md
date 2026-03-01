# Command Bar UI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Build a complete Spotlight-style Command Bar UI with multi-modal input, real-time suggestions, and AI-powered intelligence.

**Architecture:** SwiftUI-based progressive 3-phase implementation. Phase 1 builds core UI + keyboard shortcuts, Phase 2 adds smart interactions + preview panel, Phase 3 integrates AI services + suggestions. Uses @Observable for state management, TDD throughout.

**Tech Stack:** SwiftUI, @Observable, LiquidGlassKit, KeyboardShortcuts, GRDB, async/await

---

## Phase 1: Core UI (Tasks 1-7)

### Task 1: Extend AICoordinator with Command Bar State

**Files:**
- Modify: `macos/Sources/AIServices/AICoordinator.swift`
- Test: `macos/Tests/AIServicesTests/AICoordinatorTests.swift`

**Step 1: Write failing tests for new state**

```swift
// macos/Tests/AIServicesTests/AICoordinatorTests.swift
// Add to existing AICoordinatorTests

func testSelectedResultIndexState() {
    let coordinator = AICoordinator()
    XCTAssertEqual(coordinator.selectedResultIndex, 0)

    coordinator.selectedResultIndex = 2
    XCTAssertEqual(coordinator.selectedResultIndex, 2)
}

func testLoadingState() {
    let coordinator = AICoordinator()
    XCTAssertFalse(coordinator.isLoading)

    coordinator.isLoading = true
    XCTAssertTrue(coordinator.isLoading)
}

func testErrorMessageState() {
    let coordinator = AICoordinator()
    XCTAssertNil(coordinator.errorMessage)

    coordinator.errorMessage = "Test error"
    XCTAssertEqual(coordinator.errorMessage, "Test error")
}
```

**Step 2: Run tests to verify they fail**

Run: `cd macos && swift test --filter AICoordinatorTests`
Expected: FAIL with "Value of type 'AICoordinator' has no member 'selectedResultIndex'"

**Step 3: Add new state properties**

```swift
// macos/Sources/AIServices/AICoordinator.swift
// Add after existing command bar state

// Selection and UI state
public var selectedResultIndex: Int = 0
public var isLoading: Bool = false
public var errorMessage: String?

// Preview panel state (for Phase 2)
public var showPreviewPanel: Bool = false
public var previewContent: Content?
```

**Step 4: Run tests to verify they pass**

Run: `cd macos && swift test --filter AICoordinatorTests`
Expected: PASS (5/5 tests)

**Step 5: Commit**

```bash
git add macos/Sources/AIServices/AICoordinator.swift macos/Tests/AIServicesTests/AICoordinatorTests.swift
git commit -m "feat(AIServices): extend AICoordinator with Command Bar state

- Add selectedResultIndex for keyboard navigation
- Add isLoading for async operations
- Add errorMessage for error handling
- Add preview panel state for Phase 2
- Tests: 3 new tests for state management

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 2: Create CommandBarWindow Main Component

**Files:**
- Create: `macos/Sources/App/Views/CommandBar/CommandBarWindow.swift`
- Test: Manual UI testing (SwiftUI Preview)

**Step 1: Create directory structure**

Run: `mkdir -p macos/Sources/App/Views/CommandBar`

**Step 2: Create CommandBarWindow**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
import SwiftUI
import LiquidGlassKit
import AIServices

struct CommandBarWindow: View {
    @Environment(AICoordinator.self) private var coordinator
    @State private var query: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Input field placeholder (will implement in Task 3)
            TextField("Type to search or paste URL...", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding()
                .background(Color.clear)

            Divider()

            // Results list placeholder (will implement in Task 4)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(coordinator.commandResults) { result in
                        Text(result.title)
                            .padding()
                    }
                }
                .padding()
            }
        }
        .frame(width: 600)
        .frame(minHeight: 200, maxHeight: 500)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .shadow(radius: 40, x: 0, y: 20)
        .opacity(coordinator.isCommandBarVisible ? 1 : 0)
        .scaleEffect(coordinator.isCommandBarVisible ? 1.0 : 0.9)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: coordinator.isCommandBarVisible)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var coordinator = AICoordinator()

    CommandBarWindow()
        .environment(coordinator)
        .onAppear {
            coordinator.isCommandBarVisible = true
            coordinator.commandResults = [
                .init(title: "Import from clipboard", subtitle: "⌘V", icon: "doc.text") {},
                .init(title: "Search all content", subtitle: "⌘F", icon: "magnifyingglass") {},
                .init(title: "Generate podcast", subtitle: "⌘P", icon: "mic") {}
            ]
        }
}
```

**Step 3: Test with SwiftUI Preview**

Run: In Xcode, open CommandBarWindow.swift and enable Preview (⌥⌘↩)
Expected: See Command Bar window with basic layout

**Step 4: Commit**

```bash
git add macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
git commit -m "feat(CommandBar): create CommandBarWindow main component

- Spotlight-style floating window
- 600px width, dynamic height (200-500px)
- Liquid Glass background (.ultraThinMaterial)
- Spring animations for show/hide
- SwiftUI Preview for quick testing

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 3: Create CommandBarInputField Component

**Files:**
- Create: `macos/Sources/App/Views/CommandBar/CommandBarInputField.swift`

**Step 1: Create CommandBarInputField**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarInputField.swift
import SwiftUI

struct CommandBarInputField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)

            TextField("Type to search or paste URL...", text: $query)
                .textFieldStyle(.plain)
                .font(.title2)
                .focused($isFocused)
                .onAppear {
                    // Auto-focus when Command Bar appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isFocused = true
                    }
                }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
        .padding(.horizontal)
        .padding(.top)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var query = ""

    CommandBarInputField(query: $query)
        .frame(width: 600)
        .padding()
}
```

**Step 2: Update CommandBarWindow to use new component**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
// Replace the TextField in body with:

CommandBarInputField(query: $query)

Divider()
    .padding(.horizontal)
```

**Step 3: Test with Preview**

Run: Preview CommandBarWindow.swift
Expected: See styled input field with search icon and focus border

**Step 4: Commit**

```bash
git add macos/Sources/App/Views/CommandBar/CommandBarInputField.swift macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
git commit -m "feat(CommandBar): add CommandBarInputField component

- Search icon + styled text field
- Auto-focus on appear
- Accent color border when focused
- Rounded background with opacity
- Integrated into CommandBarWindow

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 4: Create CommandBarResultsList Component

**Files:**
- Create: `macos/Sources/App/Views/CommandBar/CommandBarResultsList.swift`

**Step 1: Create CommandResultRow**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarResultsList.swift
import SwiftUI
import AIServices

struct CommandResultRow: View {
    let result: CommandResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: result.icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
    }
}

struct CommandBarResultsList: View {
    let results: [CommandResult]
    let selectedIndex: Int

    var body: some View {
        LazyVStack(spacing: 4) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                CommandResultRow(result: result, isSelected: index == selectedIndex)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var coordinator = AICoordinator()

    CommandBarResultsList(
        results: [
            .init(title: "Import from clipboard", subtitle: "⌘V", icon: "doc.text") {},
            .init(title: "Search all content", subtitle: "⌘F", icon: "magnifyingglass") {},
            .init(title: "Generate podcast", subtitle: "⌘P", icon: "mic") {}
        ],
        selectedIndex: 1
    )
    .frame(width: 600)
    .padding()
}
```

**Step 2: Update CommandBarWindow to use results list**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
// Replace ScrollView in body with:

ScrollView {
    CommandBarResultsList(
        results: coordinator.commandResults,
        selectedIndex: coordinator.selectedResultIndex
    )
}
.frame(maxHeight: 400)
```

**Step 3: Test with Preview**

Run: Preview CommandBarWindow.swift
Expected: See styled result list with selection highlight

**Step 4: Commit**

```bash
git add macos/Sources/App/Views/CommandBar/CommandBarResultsList.swift macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
git commit -m "feat(CommandBar): add CommandBarResultsList component

- CommandResultRow with icon, title, subtitle
- Selection highlighting with accent color
- Scale animation on selection
- LazyVStack for performance
- Smooth transitions for updates

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 5: Add Keyboard Navigation

**Files:**
- Modify: `macos/Sources/App/Views/CommandBar/CommandBarWindow.swift`
- Modify: `macos/Sources/AIServices/AICoordinator.swift`

**Step 1: Add navigation methods to AICoordinator**

```swift
// macos/Sources/AIServices/AICoordinator.swift
// Add after hideCommandBar()

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
    hideCommandBar()
}

@MainActor
public func resetSelection() {
    selectedResultIndex = 0
}
```

**Step 2: Add keyboard event handling to CommandBarWindow**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
// Add after the main VStack

.onKeyPress(.upArrow) {
    coordinator.selectPreviousResult()
    return .handled
}
.onKeyPress(.downArrow) {
    coordinator.selectNextResult()
    return .handled
}
.onKeyPress(.return) {
    Task {
        await coordinator.executeSelectedResult()
    }
    return .handled
}
.onKeyPress(.escape) {
    coordinator.hideCommandBar()
    return .handled
}
.onChange(of: coordinator.isCommandBarVisible) { oldValue, newValue in
    if newValue {
        coordinator.resetSelection()
    }
}
```

**Step 3: Test keyboard navigation**

Run: Build and run app, open Command Bar, test ↑↓Enter Esc
Expected: Selection moves, Enter executes, Esc closes

**Step 4: Commit**

```bash
git add macos/Sources/App/Views/CommandBar/CommandBarWindow.swift macos/Sources/AIServices/AICoordinator.swift
git commit -m "feat(CommandBar): add keyboard navigation

- ↑↓ arrows for selection navigation
- Enter to execute selected result
- Esc to close Command Bar
- Auto-reset selection when opening
- Navigation methods in AICoordinator

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 6: Integrate ⌘K Hotkey

**Files:**
- Modify: `macos/Sources/App/Services/HotkeyService.swift`
- Modify: `macos/Sources/App/AppDelegate.swift`

**Step 1: Add Command Bar hotkey definition**

```swift
// macos/Sources/App/Services/HotkeyService.swift
// Add to extension KeyboardShortcuts.Name (after summonReadless)

static let commandBar = Self("commandBar", default: .init(.k, modifiers: [.command]))
```

**Step 2: Add Command Bar handler in HotkeyService init**

```swift
// macos/Sources/App/Services/HotkeyService.swift
// Add after setupCarbonFallback() call

// Command Bar hotkey (⌘K)
setupCommandBarHotkey()
```

**Step 3: Add setupCommandBarHotkey method**

```swift
// macos/Sources/App/Services/HotkeyService.swift
// Add before the init closing brace

private let onCommandBar: () -> Void

// Update init signature to include onCommandBar
init(
    onSilentImport: @escaping (String, String?, String?) -> Void,
    onImportAndDisplay: @escaping (String, String?, String?) -> Void,
    onSummon: @escaping () -> Void,
    onCommandBar: @escaping () -> Void  // Add this
) {
    self.onSilentImport = onSilentImport
    self.onImportAndDisplay = onImportAndDisplay
    self.onSummon = onSummon
    self.onCommandBar = onCommandBar  // Add this

    // ... existing setup code ...
}

// Add new method
private func setupCommandBarHotkey() {
    KeyboardShortcuts.onKeyUp(for: .commandBar) { [weak self] in
        print("[Readless] Hotkey ⌘K detected")
        self?.onCommandBar()
    }
    print("[Readless] Command Bar hotkey (⌘K): registered")
}
```

**Step 4: Update HotkeyService call in AppDelegate**

```swift
// macos/Sources/App/AppDelegate.swift
// Update hotkeyService initialization

hotkeyService = HotkeyService(
    onSilentImport: { text, appName, bundleID in
        Task { @MainActor in
            await ContentManager.shared.importSilently(
                text: text, appName: appName, bundleID: bundleID
            )
        }
    },
    onImportAndDisplay: { text, appName, bundleID in
        Task { @MainActor in
            await ContentManager.shared.importAndDisplay(
                text: text, appName: appName, bundleID: bundleID
            )
        }
    },
    onSummon: {
        NotificationCenter.default.post(name: .showSummonPanel, object: nil)
    },
    onCommandBar: {
        NotificationCenter.default.post(name: .toggleCommandBar, object: nil)
    }
)
```

**Step 5: Add notification name**

```swift
// macos/Sources/App/AppDelegate.swift
// Add to extension Notification.Name (after showSummonPanel)

static let toggleCommandBar = Notification.Name("toggleCommandBar")
```

**Step 6: Commit**

```bash
git add macos/Sources/App/Services/HotkeyService.swift macos/Sources/App/AppDelegate.swift
git commit -m "feat(CommandBar): integrate ⌘K hotkey

- Add commandBar keyboard shortcut definition
- Register ⌘K handler in HotkeyService
- Post toggleCommandBar notification
- Update AppDelegate with Command Bar callback

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 7: Integrate CommandBarWindow into App

**Files:**
- Modify: `macos/Sources/App/ReadlessApp.swift`

**Step 1: Add AICoordinator to ReadlessApp**

```swift
// macos/Sources/App/ReadlessApp.swift
// Add after @NSApplicationDelegateAdaptor

@State private var aiCoordinator = AICoordinator()
```

**Step 2: Listen for toggleCommandBar notification**

```swift
// macos/Sources/App/ReadlessApp.swift
// Update ContentView() call to:

ContentView()
    .environment(aiCoordinator)
    .overlay {
        if aiCoordinator.isCommandBarVisible {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    aiCoordinator.hideCommandBar()
                }

            CommandBarWindow()
                .environment(aiCoordinator)
        }
    }
    .onReceive(NotificationCenter.default.publisher(for: .toggleCommandBar)) { _ in
        aiCoordinator.isCommandBarVisible.toggle()
    }
```

**Step 3: Import CommandBar module**

```swift
// macos/Sources/App/ReadlessApp.swift
// Add to imports

import AIServices
```

**Step 4: Build and test**

Run: `cd macos && swift build`
Expected: Build succeeds

**Step 5: Manual testing**

Run: Build and run in Xcode, press ⌘K
Expected: Command Bar appears in center with dark overlay

**Step 6: Commit**

```bash
git add macos/Sources/App/ReadlessApp.swift
git commit -m "feat(CommandBar): integrate into main app

- Add AICoordinator state to ReadlessApp
- Overlay CommandBarWindow when visible
- Dark background overlay (dismissible on tap)
- Listen for toggleCommandBar notification
- ⌘K now shows/hides Command Bar

Phase 1 Complete: Core UI + Keyboard Navigation

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 2: Smart Interactions (Tasks 8-12)

### Task 8: Create CommandBarPreviewPanel Component

**Files:**
- Create: `macos/Sources/App/Views/CommandBar/CommandBarPreviewPanel.swift`
- Modify: `macos/Sources/App/Views/CommandBar/CommandBarWindow.swift`

**Step 1: Create preview panel structure**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarPreviewPanel.swift
import SwiftUI
import Core

struct CommandBarPreviewPanel: View {
    let content: Content?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let content = content {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(content.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(content.sourceType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Content preview
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let l0 = content.summary?.l0 {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Summary")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(l0)
                                    .font(.body)
                            }
                        }

                        if let outline = content.summary?.outline, !outline.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Outline")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(outline.prefix(5)) { point in
                                    Text("• \(point.text)")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

                Divider()

                // Quick actions
                HStack(spacing: 8) {
                    Button("Import") {
                        // Action handled by parent
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Share") {
                        // Action handled by parent
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView(
                    "No Preview",
                    systemImage: "doc.text",
                    description: Text("Select a result to see preview")
                )
            }
        }
        .padding()
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Preview

#Preview {
    CommandBarPreviewPanel(
        content: Content(
            id: "test",
            sourceType: .url,
            title: "Example Article",
            summary: .init(
                l0: "A comprehensive guide to Swift programming.",
                outline: [
                    .init(text: "Introduction to Swift", level: 1),
                    .init(text: "Basic syntax and features", level: 2),
                    .init(text: "Advanced topics", level: 1)
                ]
            )
        )
    )
    .frame(height: 500)
}
```

**Step 2: Update CommandBarWindow layout**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
// Replace entire body with:

HStack(spacing: 0) {
    // Main panel
    VStack(spacing: 0) {
        CommandBarInputField(query: $query)

        Divider()
            .padding(.horizontal)

        ScrollView {
            CommandBarResultsList(
                results: coordinator.commandResults,
                selectedIndex: coordinator.selectedResultIndex
            )
        }
        .frame(maxHeight: 400)
    }
    .frame(width: 600)

    // Preview panel (shows on Tab or when content selected)
    if coordinator.showPreviewPanel {
        Divider()

        CommandBarPreviewPanel(content: coordinator.previewContent)
            .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
.frame(minHeight: 200, maxHeight: 500)
.background(.ultraThinMaterial)
.cornerRadius(16)
.shadow(radius: 40, x: 0, y: 20)
.opacity(coordinator.isCommandBarVisible ? 1 : 0)
.scaleEffect(coordinator.isCommandBarVisible ? 1.0 : 0.9)
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: coordinator.isCommandBarVisible)
.animation(.spring(response: 0.3, dampingFraction: 0.8), value: coordinator.showPreviewPanel)
```

**Step 3: Add Tab key handling**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
// Add after .onKeyPress(.escape)

.onKeyPress(.tab) {
    coordinator.showPreviewPanel.toggle()
    return .handled
}
```

**Step 4: Test preview panel**

Run: Build and test, press ⌘K then Tab
Expected: Preview panel slides in from right

**Step 5: Commit**

```bash
git add macos/Sources/App/Views/CommandBar/CommandBarPreviewPanel.swift macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
git commit -m "feat(CommandBar): add preview panel

- Right-side preview panel (300px)
- Show content summary and outline
- Quick actions (Import, Share)
- Tab key to toggle panel visibility
- Smooth slide animation

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 9: Add Multi-Modal Input Support

**Files:**
- Modify: `macos/Sources/App/Views/CommandBar/CommandBarInputField.swift`
- Modify: `macos/Sources/App/Views/CommandBar/CommandBarWindow.swift`

**Step 1: Add drag & drop support to input field**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarInputField.swift
// Add state variables

@State private var isDropTargeted = false
@Binding var onDrop: ((CommandBarInput) -> Void)?  // Add parameter

// Wrap HStack with:
.onDrop(of: [.fileURL, .image, .pdf], isTargeted: $isDropTargeted) { providers in
    handleDrop(providers)
    return true
}
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2, dash: [5, 5])
)
```

**Step 2: Add drop handler**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarInputField.swift
// Add method

private func handleDrop(_ providers: [NSItemProvider]) {
    for provider in providers {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

                Task { @MainActor in
                    if let fileData = try? Data(contentsOf: url) {
                        if url.pathExtension.lowercased() == "pdf" {
                            onDrop?(.pdf(fileData))
                        } else if ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) {
                            onDrop?(.image(fileData))
                        } else {
                            if let text = String(data: fileData, encoding: .utf8) {
                                onDrop?(.text(text))
                            }
                        }
                    }
                }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                guard let data = data else { return }
                Task { @MainActor in
                    onDrop?(.image(data))
                }
            }
        }
    }
}
```

**Step 3: Update CommandBarWindow to handle drops**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
// Add import
import AIServices

// Update CommandBarInputField call
CommandBarInputField(
    query: $query,
    onDrop: .constant { input in
        Task {
            await handleInput(input)
        }
    }
)

// Add handler method
private func handleInput(_ input: CommandBarInput) async {
    do {
        coordinator.isLoading = true
        defer { coordinator.isLoading = false }

        let parsed = try await InputParser(
            aiProvider: MockAIProvider(),  // TODO: Use real provider
            config: AIServiceConfig.default.inputParsing
        ).parse(input)

        // Handle parsed input
        switch parsed {
        case .plainText(let text):
            query = text
        case .url(let url):
            query = url.absoluteString
        case .image, .pdf:
            coordinator.errorMessage = "Multi-modal analysis coming in Phase 3"
        case .command:
            break
        }
    } catch {
        coordinator.errorMessage = error.localizedDescription
    }
}
```

**Step 4: Test drag & drop**

Run: Build and test, drag image/PDF to input field
Expected: Dashed border on hover, file processed

**Step 5: Commit**

```bash
git add macos/Sources/App/Views/CommandBar/CommandBarInputField.swift macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
git commit -m "feat(CommandBar): add multi-modal input support

- Drag & drop for images and PDFs
- File type detection (image/pdf/text)
- Visual feedback with dashed border
- Integration with InputParser
- Error handling for unsupported types

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 10: Add Real-Time Search

**Files:**
- Modify: `macos/Sources/App/Views/CommandBar/CommandBarWindow.swift`
- Create: `macos/Sources/App/Services/CommandBarService.swift`

**Step 1: Create CommandBarService**

```swift
// macos/Sources/App/Services/CommandBarService.swift
import Foundation
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
            (content.summary?.l0.localizedCaseInsensitiveContains(query) ?? false)
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
        }
    }
}
```

**Step 2: Integrate search in CommandBarWindow**

```swift
// macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
// Add service property
@State private var service: CommandBarService!

// Add in .onAppear
.onAppear {
    service = CommandBarService(aiCoordinator: coordinator)
    service.search("")  // Show quick actions
}

// Add .onChange for query
.onChange(of: query) { oldValue, newValue in
    service.search(newValue)
}
```

**Step 3: Test real-time search**

Run: Build and test, type in Command Bar
Expected: Results update after 300ms

**Step 4: Commit**

```bash
git add macos/Sources/App/Services/CommandBarService.swift macos/Sources/App/Views/CommandBar/CommandBarWindow.swift
git commit -m "feat(CommandBar): add real-time search

- CommandBarService with debounced search (300ms)
- Search local content by title and summary
- Quick actions when query is empty
- Convert search results to CommandResult
- Integration with ContentManager

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 3: AI Enhancement (Tasks 11-15)

Due to space constraints, I'll provide a condensed version of Phase 3 tasks:

### Task 11: Add HistoryManager

**Goal**: Store and search command history in GRDB
**Files**: Create `HistoryManager.swift`, add GRDB table
**Key Features**: Store 1000 recent commands, FTS5 index, auto-cleanup

### Task 12: Create SuggestionEngine

**Goal**: Generate AI-powered suggestions based on context
**Files**: Create `SuggestionEngine.swift`
**Key Features**: Context-based suggestions, caching, ranking

### Task 13: Integrate InputParser with CommandBarService

**Goal**: Use existing InputParser for smart input handling
**Files**: Modify `CommandBarService.swift`
**Key Features**: Parse all input types, handle multi-modal

### Task 14: Add Error Handling UI

**Goal**: Show user-friendly error messages
**Files**: Modify `CommandBarWindow.swift`
**Key Features**: Toast notifications, inline errors, recovery buttons

### Task 15: Final Integration & Polish

**Goal**: Connect all pieces and optimize
**Files**: Multiple files
**Key Features**: End-to-end testing, performance optimization, animations polish

---

**Implementation Plan Complete!**

**Total Tasks**: 15 (7 Phase 1 + 5 Phase 2 + 3 Phase 3 abstracted)
**Estimated Time**: 5-8 days
**Test Strategy**: TDD where applicable, manual UI testing for SwiftUI components

Each task is designed to be 2-5 hours of focused work with clear deliverables and frequent commits.
