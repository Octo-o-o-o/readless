# Command Bar Integration Testing Guide

This guide provides comprehensive testing procedures for the Command Bar feature in Readless.

## Overview

The Command Bar is a macOS-native quick launcher that provides:
- Quick actions (import, search, podcast generation)
- Real-time search with 300ms debouncing
- Keyboard-first navigation
- Preview panel for content
- Error handling with auto-dismiss
- Drag & drop support for files

## Architecture Components

The Command Bar integrates these components:

1. **AICoordinator** (`AIServices/AICoordinator.swift`)
   - Observable state container
   - Manages visibility, results, selection, loading, errors

2. **CommandBarService** (`App/Services/CommandBarService.swift`)
   - Search logic with debouncing
   - Content filtering
   - Quick actions

3. **CommandBarWindow** (`App/Views/CommandBar/CommandBarWindow.swift`)
   - SwiftUI UI layer
   - Keyboard event handling
   - Error banner with auto-dismiss

4. **HistoryManager** (`Storage/HistoryManager.swift`)
   - Command history persistence
   - FTS5 full-text search
   - Execution frequency tracking

## Automated Tests

### Running Tests

```bash
cd macos
swift test --filter CommandBarIntegrationTests
```

### Test Coverage

The integration test suite covers:

1. **Visibility Flow** - Open/close, state reset
2. **Search Results** - Population, navigation, bounds checking
3. **Error Handling** - Display, clear, recovery
4. **Loading States** - Start/finish, overlay display
5. **Preview Panel** - Toggle, content display
6. **Result Execution** - Action invocation, close on execute
7. **Complex Flows** - Multi-step user journeys
8. **State Consistency** - Multiple operations maintain correct state

All tests are in: `/Users/wangyixiao/WorkSpace/readless/macos/Tests/AIServicesTests/CommandBarIntegrationTests.swift`

## Manual Testing Checklist

### Basic Functionality

- [ ] **Open Command Bar**
  - Press `⌘K` globally
  - Command Bar appears centered on screen
  - Input field is focused
  - Quick actions are displayed (3 items)

- [ ] **Close Command Bar**
  - Press `Escape` key
  - Command Bar dismisses with smooth animation
  - Selection resets to index 0

### Search Flow

- [ ] **Quick Actions Display**
  - Open with empty query
  - Shows: "Import from clipboard", "Search all content", "Generate podcast"
  - Each has icon and keyboard shortcut

- [ ] **Real-time Search**
  - Type "test" in search field
  - Wait 300ms (debounce)
  - Loading indicator appears
  - Results update based on local content
  - Maximum 10 results displayed

- [ ] **Debouncing Works**
  - Type rapidly: "t-e-s-t"
  - Only one search fires after 300ms pause
  - Previous searches are cancelled

- [ ] **Empty Results**
  - Search for gibberish: "xyzabc123"
  - No results displayed (empty list)
  - No crash or error

### Navigation

- [ ] **Arrow Key Navigation**
  - Use ↓ arrow to move down results
  - Selection highlight moves
  - Use ↑ arrow to move up
  - Selection wraps/clamps at boundaries

- [ ] **Boundary Handling**
  - At first item, press ↑ (stays at index 0)
  - At last item, press ↓ (stays at last index)
  - No crash with empty results

- [ ] **Enter Key Execution**
  - Navigate to item
  - Press Enter
  - Action executes
  - Command Bar closes

### Preview Panel

- [ ] **Toggle Preview**
  - Press Tab key
  - Preview panel slides in from right
  - Press Tab again
  - Preview panel slides out

- [ ] **Preview Persistence**
  - Toggle preview on
  - Navigate between results
  - Preview panel stays visible
  - Preview content updates (if implemented)

### Error Handling

- [ ] **Error Display**
  - Trigger an error (drag invalid file type)
  - Orange error banner appears at bottom
  - Friendly error message displayed
  - Dismiss button (×) visible

- [ ] **Auto-Dismiss**
  - Error appears
  - Wait 5 seconds
  - Error banner auto-dismisses
  - Smooth fade-out animation

- [ ] **Manual Dismiss**
  - Error appears
  - Click × button
  - Error dismisses immediately

- [ ] **Error Clear on New Search**
  - Error is visible
  - Type in search field
  - Error clears immediately
  - New search proceeds normally

### Drag & Drop

- [ ] **Text Drop**
  - Drag plain text onto input field
  - Dashed border appears on hover
  - Drop text
  - Text appears in search field

- [ ] **File Drop**
  - Drag .txt file onto input field
  - Dashed border appears
  - Drop file
  - File path/content is parsed

- [ ] **Invalid Drop**
  - Drag unsupported file type
  - Error message appears
  - "Multi-modal analysis coming in Phase 3" for images/PDFs

### Loading States

- [ ] **Loading Indicator**
  - Perform search
  - Semi-transparent overlay appears
  - Large progress spinner centered
  - Results are dimmed but visible

- [ ] **Loading Dismisses**
  - Search completes
  - Loading overlay fades out
  - Results are fully visible
  - Interaction re-enabled

### Visual & Animation

- [ ] **Window Appearance**
  - Command Bar uses ultra-thin material
  - 16px corner radius
  - Shadow: 40px blur, 20px Y offset
  - Smooth spring animation (0.3s response, 0.8 damping)

- [ ] **Scale Effect**
  - Opens from 0.9 to 1.0 scale
  - Closes from 1.0 to 0.9 scale
  - Opacity fades in/out

- [ ] **Preview Panel Animation**
  - Slides from right edge
  - Combined move + opacity transition
  - Smooth spring animation

## Performance Testing

### Search Performance

- [ ] **Debounce Timing**
  - Type rapidly for 2 seconds
  - Only last search executes after 300ms pause
  - No lag or dropped keystrokes

- [ ] **Large Result Sets**
  - Search with many matches (50+ content items)
  - Only 10 results displayed
  - No performance degradation
  - Smooth scrolling

### Memory

- [ ] **Repeated Open/Close**
  - Open and close 50+ times
  - No memory leaks
  - Smooth animations throughout
  - No slowdown

## Integration Points

### With ContentManager

- [ ] **Import from Clipboard**
  - Select "Import from clipboard" action
  - Press Enter
  - Clipboard content imports
  - Toast notification appears
  - New content in library

### With HistoryManager (Future)

- [ ] **Command History Saved**
  - Execute command
  - History persists to database
  - Execution count increments for repeats

- [ ] **Recent Commands**
  - Open Command Bar
  - Recent commands appear in suggestions

### With InputParser

- [ ] **Text Parsing**
  - Drop plain text
  - Parsed as `.plainText` type
  - Appears in search field

- [ ] **URL Detection**
  - Drop URL string
  - Parsed as `.url` type
  - Search executes for URL

## Known Limitations

1. **Multi-modal Support**
   - Image/PDF drag & drop shows "coming in Phase 3" error
   - InputParser configured but not fully integrated

2. **Preview Content**
   - Preview panel toggles but content not populated yet
   - `previewContent` property exists but not set by service

3. **Quick Actions**
   - "Search all content" and "Generate podcast" are placeholders
   - Will be implemented in Phase 3

4. **ContentManager Dependency**
   - CommandBarService requires ContentManager.shared
   - Makes unit testing harder (integration tests only)

## Regression Testing

When making changes, verify these critical paths:

1. **Open → Search → Navigate → Execute → Close**
2. **Open → Error → Dismiss → New Search → Success**
3. **Open → Toggle Preview → Navigate → Close**
4. **Rapid typing → Debounce → Results → Clear**

## Test Data Setup

For meaningful manual testing:

1. **Create Sample Content**
   - Import 10-20 articles with varied titles
   - Mix of URLs, text, PDFs
   - Different source types for icon variety

2. **Test Search Queries**
   - "technology" (should match multiple)
   - "specific-unique-term" (single match)
   - "nonexistent" (zero matches)
   - "" (empty - shows quick actions)

## Accessibility Testing

- [ ] **VoiceOver**
  - Command Bar announces on open
  - Results are navigable with VO
  - Selection is announced
  - Error messages are read

- [ ] **Keyboard-Only**
  - All functionality accessible via keyboard
  - No mouse required for any operation
  - Tab order is logical

- [ ] **Reduced Motion**
  - Test with macOS "Reduce motion" enabled
  - Animations are simplified/removed
  - Functionality still works

## Debugging Tips

### Common Issues

1. **Command Bar doesn't open**
   - Check HotkeyService is registered
   - Verify `isCommandBarVisible` binding
   - Check window level settings

2. **Search doesn't work**
   - Verify ContentManager has content
   - Check debounce timing (300ms)
   - Inspect `commandResults` array

3. **Results don't appear**
   - Check filter logic in `performSearch`
   - Verify content title/summary fields
   - Ensure results limit (10) not too restrictive

4. **Errors not displaying**
   - Verify `errorMessage` is set
   - Check ErrorBanner conditional rendering
   - Ensure auto-dismiss task not cancelled early

### Logging

Add temporary logging for debugging:

```swift
// In CommandBarService.search()
print("🔍 Search query: \(query)")

// In performSearch()
print("📊 Found \(results.count) results")

// In CommandBarWindow onChange
print("⚠️ Error: \(errorMessage ?? "none")")
```

## Continuous Integration

Automated tests run on every commit:

```bash
swift test --parallel
```

Expected result:
- All 8 test methods pass
- No memory leaks
- < 5 seconds total runtime

## Success Criteria

Phase 3 Command Bar is complete when:

- ✅ All automated tests pass
- ✅ All manual checklist items verified
- ✅ No known critical bugs
- ✅ Performance is acceptable (< 300ms search)
- ✅ Animations are smooth (60 FPS)
- ✅ Error handling is robust
- ✅ Documentation is complete

## Next Steps (Future Phases)

1. **Phase 4: History Integration**
   - Wire up HistoryManager to save executed commands
   - Show recent/frequent commands in suggestions
   - Implement FTS5 search across history

2. **Phase 5: Multi-modal**
   - Enable image/PDF drag & drop
   - Integrate InputParser with AI analysis
   - Show preview panel content

3. **Phase 6: Quick Actions**
   - Implement "Search all content" with backend
   - Implement "Generate podcast" workflow
   - Add more quick actions (settings, etc.)

---

**Last Updated**: 2026-03-01
**Test Suite Version**: v1.0
**Platform**: macOS 14+
