# Liquid Glass UI Framework Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a cutting-edge macOS client with Liquid Glass design language and AI-driven interactions

**Architecture:** Modular SPM structure with LiquidGlassKit design system, Observation framework for state management, three-tier AI services (CommandBar/SemanticSearch/Suggestions), GRDB local storage with bi-directional sync

**Tech Stack:** SwiftUI, Swift 5.9+ @Observable, GRDB, KeyboardShortcuts, AppKit NSVisualEffectView

**Timeline:** 6-8 weeks (4 milestones)

---

## Milestone 1: Foundation (Week 1-2)

### Task 1: Setup Package Structure

**Files:**
- Modify: `macos/Package.swift`
- Create: `macos/Sources/LiquidGlassKit/`
- Create: `macos/Sources/AIServices/`
- Create: `macos/Sources/ReaderFeature/`
- Create: `macos/Sources/LibraryFeature/`
- Create: `macos/Sources/Utils/`

**Step 1: Update Package.swift with new targets**

```swift
// macos/Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Readless",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
    ],
    targets: [
        // Core (zero dependencies)
        .target(
            name: "Core",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // LiquidGlassKit (design system)
        .target(
            name: "LiquidGlassKit",
            dependencies: [],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // Networking
        .target(
            name: "Networking",
            dependencies: ["Core"]
        ),

        // Storage
        .target(
            name: "Storage",
            dependencies: [
                "Core",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),

        // AI Services
        .target(
            name: "AIServices",
            dependencies: ["Core", "Networking"]
        ),

        // Utils
        .target(
            name: "Utils",
            dependencies: []
        ),

        // Features
        .target(
            name: "ReaderFeature",
            dependencies: ["Core", "LiquidGlassKit", "Networking", "AIServices"]
        ),

        .target(
            name: "LibraryFeature",
            dependencies: ["Core", "LiquidGlassKit", "Networking"]
        ),

        // App
        .target(
            name: "App",
            dependencies: [
                "Core",
                "LiquidGlassKit",
                "Networking",
                "Storage",
                "AIServices",
                "ReaderFeature",
                "LibraryFeature",
                "Utils",
                "KeyboardShortcuts"
            ]
        ),

        // Tests
        .testTarget(
            name: "LiquidGlassKitTests",
            dependencies: ["LiquidGlassKit"]
        ),
        .testTarget(
            name: "AIServicesTests",
            dependencies: ["AIServices"]
        )
    ]
)
```

**Step 2: Create directory structure**

```bash
mkdir -p macos/Sources/LiquidGlassKit/{Materials,Colors,Typography,Animations,Components}
mkdir -p macos/Sources/AIServices/{CommandBar,SemanticSearch,Suggestions}
mkdir -p macos/Sources/ReaderFeature
mkdir -p macos/Sources/LibraryFeature
mkdir -p macos/Sources/Utils
mkdir -p macos/Tests/{LiquidGlassKitTests,AIServicesTests}
```

**Step 3: Verify build**

Run: `cd macos && swift build`
Expected: Success (empty targets compile)

**Step 4: Commit**

```bash
git add macos/Package.swift macos/Sources/
git commit -m "chore: setup modular SPM structure for Liquid Glass redesign

- Add LiquidGlassKit design system module
- Add AIServices layer
- Add ReaderFeature and LibraryFeature modules
- Add GRDB dependency for local storage

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 2: LiquidGlassKit - Materials System

**Files:**
- Create: `macos/Sources/LiquidGlassKit/Materials/LGMaterial.swift`
- Create: `macos/Sources/LiquidGlassKit/Materials/LiquidGlassBackground.swift`
- Test: `macos/Tests/LiquidGlassKitTests/MaterialsTests.swift`

**Step 1: Write the failing test**

```swift
// macos/Tests/LiquidGlassKitTests/MaterialsTests.swift
import XCTest
@testable import LiquidGlassKit

final class MaterialsTests: XCTestCase {
    func testLiquidGlassRegularReturnsMaterial() {
        let material = LGMaterial.liquidGlassRegular
        XCTAssertEqual(material.material, .ultraThinMaterial)
    }

    func testLiquidGlassNeedsEffect() {
        XCTAssertTrue(LGMaterial.liquidGlassRegular.needsGlassEffect)
        XCTAssertTrue(LGMaterial.liquidGlassClear.needsGlassEffect)
        XCTAssertFalse(LGMaterial.regular.needsGlassEffect)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd macos && swift test --filter MaterialsTests`
Expected: FAIL with "No such module 'LiquidGlassKit'"

**Step 3: Implement LGMaterial enum**

```swift
// macos/Sources/LiquidGlassKit/Materials/LGMaterial.swift
import SwiftUI

public enum LGMaterial {
    case liquidGlassRegular
    case liquidGlassClear
    case ultraThin
    case thin
    case regular
    case thick

    public var material: Material {
        switch self {
        case .liquidGlassRegular, .liquidGlassClear:
            return .ultraThinMaterial
        case .ultraThin:
            return .ultraThinMaterial
        case .thin:
            return .thinMaterial
        case .regular:
            return .regularMaterial
        case .thick:
            return .thickMaterial
        }
    }

    public var needsGlassEffect: Bool {
        switch self {
        case .liquidGlassRegular, .liquidGlassClear:
            return true
        default:
            return false
        }
    }
}
```

**Step 4: Implement NSVisualEffectView wrapper**

```swift
// macos/Sources/LiquidGlassKit/Materials/LiquidGlassBackground.swift
import SwiftUI
import AppKit

public struct LiquidGlassBackground: NSViewRepresentable {
    public let variant: LGMaterial

    public init(variant: LGMaterial) {
        self.variant = variant
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()

        switch variant {
        case .liquidGlassClear:
            view.material = .hudWindow
        case .liquidGlassRegular:
            view.material = .menu
        default:
            view.material = .underWindowBackground
        }

        view.blendingMode = .behindWindow
        view.state = .active

        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// ViewModifier for easy usage
public struct LGMaterialModifier: ViewModifier {
    let material: LGMaterial
    let addDimming: Bool

    public func body(content: Content) -> some View {
        if material.needsGlassEffect {
            content
                .background(LiquidGlassBackground(variant: material))
                .background(addDimming ? Color.black.opacity(0.35) : Color.clear)
        } else {
            content
                .background(material.material)
        }
    }
}

extension View {
    public func lgMaterial(_ material: LGMaterial, dimming: Bool = false) -> some View {
        modifier(LGMaterialModifier(material: material, addDimming: dimming))
    }
}
```

**Step 5: Run test to verify it passes**

Run: `cd macos && swift test --filter MaterialsTests`
Expected: PASS

**Step 6: Commit**

```bash
git add macos/Sources/LiquidGlassKit/Materials/ macos/Tests/LiquidGlassKitTests/
git commit -m "feat(LiquidGlassKit): add materials system with NSVisualEffectView

- Implement LGMaterial enum with Liquid Glass variants
- Add LiquidGlassBackground NSViewRepresentable
- Add convenient .lgMaterial() ViewModifier
- Tests: Material property access and glass effect detection

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 3: LiquidGlassKit - Color System

**Files:**
- Create: `macos/Sources/LiquidGlassKit/Colors/LGColor.swift`
- Test: `macos/Tests/LiquidGlassKitTests/ColorsTests.swift`

**Step 1: Write the failing test**

```swift
// macos/Tests/LiquidGlassKitTests/ColorsTests.swift
import XCTest
import SwiftUI
@testable import LiquidGlassKit

final class ColorsTests: XCTestCase {
    func testVibrantLabelReturnsColor() {
        let color = LGColor.vibrantLabel.color
        XCTAssertNotNil(color)
    }

    func testAccentColorExists() {
        let color = LGColor.accent.color
        XCTAssertNotNil(color)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd macos && swift test --filter ColorsTests`
Expected: FAIL with "Cannot find 'LGColor' in scope"

**Step 3: Implement LGColor enum**

```swift
// macos/Sources/LiquidGlassKit/Colors/LGColor.swift
import SwiftUI
import AppKit

public enum LGColor {
    // Vibrant Labels (for Liquid Glass)
    case vibrantLabel
    case vibrantSecondaryLabel
    case vibrantTertiaryLabel

    // Vibrant Fills (for Liquid Glass)
    case vibrantFill
    case vibrantSecondaryFill
    case vibrantTertiaryFill

    // Vibrant Separator
    case vibrantSeparator

    // Semantic Colors (auto dark mode)
    case accent
    case label
    case secondaryLabel
    case tertiaryLabel
    case quaternaryLabel

    public var color: Color {
        switch self {
        case .vibrantLabel:
            return Color(nsColor: .labelColor)
        case .vibrantSecondaryLabel:
            return Color(nsColor: .secondaryLabelColor)
        case .vibrantTertiaryLabel:
            return Color(nsColor: .tertiaryLabelColor)
        case .vibrantFill:
            return Color(nsColor: .controlColor)
        case .vibrantSecondaryFill:
            return Color(nsColor: .controlBackgroundColor)
        case .vibrantTertiaryFill:
            return Color(nsColor: .textBackgroundColor)
        case .vibrantSeparator:
            return Color(nsColor: .separatorColor)
        case .accent:
            return Color.accentColor
        case .label:
            return Color(nsColor: .labelColor)
        case .secondaryLabel:
            return Color(nsColor: .secondaryLabelColor)
        case .tertiaryLabel:
            return Color(nsColor: .tertiaryLabelColor)
        case .quaternaryLabel:
            return Color(nsColor: .quaternaryLabelColor)
        }
    }

    /// Create dynamic color that adapts to dark mode
    public static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }))
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd macos && swift test --filter ColorsTests`
Expected: PASS

**Step 5: Commit**

```bash
git add macos/Sources/LiquidGlassKit/Colors/ macos/Tests/LiquidGlassKitTests/ColorsTests.swift
git commit -m "feat(LiquidGlassKit): add color system with vibrant colors

- Implement LGColor enum with vibrant and semantic colors
- Auto dark mode adaptation using NSColor
- Helper for custom dynamic colors
- Tests: Color property access

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 4: LiquidGlassKit - Typography System

**Files:**
- Create: `macos/Sources/LiquidGlassKit/Typography/LGTypography.swift`
- Test: `macos/Tests/LiquidGlassKitTests/TypographyTests.swift`

**Step 1-2: Write test and verify it fails**

```swift
// macos/Tests/LiquidGlassKitTests/TypographyTests.swift
import XCTest
import SwiftUI
@testable import LiquidGlassKit

final class TypographyTests: XCTestCase {
    func testLargeTitleFont() {
        let font = LGTypography.largeTitle
        XCTAssertNotNil(font)
    }

    func testBodyLineSpacing() {
        let spacing = LGTypography.LineSpacing.body
        XCTAssertEqual(spacing, 6)
    }
}
```

Run: `cd macos && swift test --filter TypographyTests`
Expected: FAIL

**Step 3: Implement LGTypography**

```swift
// macos/Sources/LiquidGlassKit/Typography/LGTypography.swift
import SwiftUI

public struct LGTypography {
    // Font hierarchy
    public static let largeTitle = Font.system(size: 34, weight: .bold)
    public static let title1 = Font.system(size: 28, weight: .bold)
    public static let title2 = Font.system(size: 22, weight: .bold)
    public static let headline = Font.system(size: 17, weight: .semibold)
    public static let body = Font.system(size: 15, weight: .regular)
    public static let callout = Font.system(size: 13, weight: .regular)
    public static let caption1 = Font.system(size: 12, weight: .medium)
    public static let caption2 = Font.system(size: 11, weight: .medium)

    // Special fonts
    public static let monospacedCode = Font.system(size: 13, weight: .regular, design: .monospaced)
    public static let monospacedDigit = Font.system(size: 15, weight: .regular, design: .monospaced)

    // Line spacing
    public struct LineSpacing {
        public static let largeTitle: CGFloat = 2
        public static let title: CGFloat = 2
        public static let body: CGFloat = 6
        public static let callout: CGFloat = 4
    }
}
```

**Step 4-6: Test, verify pass, commit**

Run: `cd macos && swift test --filter TypographyTests`
Expected: PASS

```bash
git add macos/Sources/LiquidGlassKit/Typography/ macos/Tests/LiquidGlassKitTests/TypographyTests.swift
git commit -m "feat(LiquidGlassKit): add typography system with SF fonts

- Define font hierarchy (largeTitle to caption2)
- Add monospaced variants for code and digits
- Define line spacing constants
- Tests: Font and spacing property access

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 5: LiquidGlassKit - Animation System

**Files:**
- Create: `macos/Sources/LiquidGlassKit/Animations/LGAnimation.swift`
- Test: `macos/Tests/LiquidGlassKitTests/AnimationsTests.swift`

**Step 1-2: Write test and verify fail**

```swift
// macos/Tests/LiquidGlassKitTests/AnimationsTests.swift
import XCTest
import SwiftUI
@testable import LiquidGlassKit

final class AnimationsTests: XCTestCase {
    func testFluidAnimationExists() {
        let animation = LGAnimation.fluid.animation
        XCTAssertNotNil(animation)
    }

    func testGlassAppearAnimationExists() {
        let animation = LGAnimation.glassAppear.animation
        XCTAssertNotNil(animation)
    }
}
```

Run: `cd macos && swift test --filter AnimationsTests`

**Step 3: Implement LGAnimation**

```swift
// macos/Sources/LiquidGlassKit/Animations/LGAnimation.swift
import SwiftUI

public enum LGAnimation {
    // Base animations
    case fluid               // 0.5s spring bounce 0.2
    case snappy              // 0.35s spring bounce 0.1
    case smooth              // 0.4s easeInOut

    // Liquid Glass animations
    case glassAppear         // 0.4s spring bounce 0.15
    case glassDismiss        // 0.25s easeOut
    case glassRefract        // 0.3s spring bounce 0.05

    // Interaction feedback
    case press               // 0.1s easeOut
    case hover               // 0.15s easeInOut
    case focus               // 0.2s spring bounce 0.1

    public var animation: Animation {
        switch self {
        case .fluid:
            return .spring(duration: 0.5, bounce: 0.2)
        case .snappy:
            return .spring(duration: 0.35, bounce: 0.1)
        case .smooth:
            return .easeInOut(duration: 0.4)
        case .glassAppear:
            return .spring(duration: 0.4, bounce: 0.15)
        case .glassDismiss:
            return .easeOut(duration: 0.25)
        case .glassRefract:
            return .spring(duration: 0.3, bounce: 0.05)
        case .press:
            return .easeOut(duration: 0.1)
        case .hover:
            return .easeInOut(duration: 0.15)
        case .focus:
            return .spring(duration: 0.2, bounce: 0.1)
        }
    }
}

// Convenience View extension for glass transitions
public extension View {
    func glassTransition(isPresented: Bool) -> some View {
        self
            .scaleEffect(isPresented ? 1.0 : 0.96)
            .opacity(isPresented ? 1.0 : 0.0)
            .blur(radius: isPresented ? 0 : 8)
            .animation(
                isPresented ? LGAnimation.glassAppear.animation : LGAnimation.glassDismiss.animation,
                value: isPresented
            )
    }
}
```

**Step 4-6: Test, verify pass, commit**

```bash
git add macos/Sources/LiquidGlassKit/Animations/ macos/Tests/LiquidGlassKitTests/AnimationsTests.swift
git commit -m "feat(LiquidGlassKit): add fluid animation system

- Define animation presets (fluid, snappy, glass effects)
- Add glassTransition View modifier for appear/dismiss
- Tests: Animation property access

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Task 6: Storage Layer - GRDB Integration

**Files:**
- Create: `macos/Sources/Storage/LocalDatabase.swift`
- Create: `macos/Sources/Storage/Models/ContentRecord.swift`
- Test: `macos/Tests/StorageTests/LocalDatabaseTests.swift`

**Step 1-2: Write test and verify fail**

```swift
// macos/Tests/StorageTests/LocalDatabaseTests.swift
import XCTest
@testable import Storage
@testable import Core

final class LocalDatabaseTests: XCTestCase {
    var database: LocalDatabase!

    override func setUp() async throws {
        // Use in-memory database for tests
        database = try LocalDatabase(path: ":memory:")
    }

    func testSaveAndFetchContent() async throws {
        let content = Content(
            id: "test-123",
            title: "Test Content",
            sourceType: .text,
            status: .ready
        )

        try await database.saveContent(content)
        let fetched = try await database.fetchContents(limit: 10)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.id, "test-123")
    }
}
```

Run: `cd macos && swift test --filter LocalDatabaseTests`
Expected: FAIL

**Step 3: Implement LocalDatabase**

```swift
// macos/Sources/Storage/LocalDatabase.swift
import Foundation
import GRDB
import Core

public final class LocalDatabase {
    private let dbQueue: DatabaseQueue

    public static let shared: LocalDatabase = {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dbFolder = appSupport.appendingPathComponent("Readless", isDirectory: true)

        try? fileManager.createDirectory(at: dbFolder, withIntermediateDirectories: true)
        let dbPath = dbFolder.appendingPathComponent("readless.db").path

        return try! LocalDatabase(path: dbPath)
    }()

    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "contents") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("source_url", .text)
                t.column("source_type", .text).notNull()
                t.column("l0_summary", .text)
                t.column("l1_outline", .blob)
                t.column("tags", .blob)
                t.column("status", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("synced_at", .datetime)
                t.column("is_favorite", .boolean).notNull().defaults(to: false)
            }

            try db.create(index: "idx_contents_created_at", on: "contents", columns: ["created_at"])
            try db.create(index: "idx_contents_status", on: "contents", columns: ["status"])
        }

        return migrator
    }

    // CRUD Operations
    public func saveContent(_ content: Content) async throws {
        try await dbQueue.write { db in
            try ContentRecord(from: content).save(db)
        }
    }

    public func fetchContents(limit: Int = 100, offset: Int = 0) async throws -> [Content] {
        try await dbQueue.read { db in
            let records = try ContentRecord
                .order(Column("created_at").desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
            return records.map { $0.toContent() }
        }
    }

    public func unsyncedContents() async throws -> [Content] {
        try await dbQueue.read { db in
            let records = try ContentRecord
                .filter(Column("synced_at") == nil || Column("updated_at") > Column("synced_at"))
                .fetchAll(db)
            return records.map { $0.toContent() }
        }
    }

    public func markAsSynced(_ contentID: String) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE contents SET synced_at = ? WHERE id = ?",
                arguments: [Date(), contentID]
            )
        }
    }
}
```

**Step 4: Implement ContentRecord**

```swift
// macos/Sources/Storage/Models/ContentRecord.swift
import Foundation
import GRDB
import Core

struct ContentRecord: Codable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var sourceURL: String?
    var sourceType: String
    var l0Summary: String?
    var l1OutlineData: Data?
    var tagsData: Data?
    var status: String
    var createdAt: Date
    var updatedAt: Date
    var syncedAt: Date?
    var isFavorite: Bool

    static var databaseTableName: String { "contents" }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let createdAt = Column(CodingKeys.createdAt)
        static let status = Column(CodingKeys.status)
        static let syncedAt = Column(CodingKeys.syncedAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }

    init(from content: Content) {
        self.id = content.id
        self.title = content.title
        self.sourceURL = content.sourceURL
        self.sourceType = content.sourceType.rawValue
        self.l0Summary = content.l0Summary
        self.l1OutlineData = try? JSONEncoder().encode(content.l1Outline)
        self.tagsData = try? JSONEncoder().encode(content.tags)
        self.status = content.status.rawValue
        self.createdAt = content.createdAt
        self.updatedAt = Date()
        self.syncedAt = nil
        self.isFavorite = false
    }

    func toContent() -> Content {
        let l1Outline = try? JSONDecoder().decode([OutlinePoint].self, from: l1OutlineData ?? Data())
        let tags = try? JSONDecoder().decode([String].self, from: tagsData ?? Data())

        return Content(
            id: id,
            title: title,
            sourceURL: sourceURL,
            sourceType: SourceType(rawValue: sourceType) ?? .text,
            l0Summary: l0Summary,
            l1Outline: l1Outline,
            tags: tags ?? [],
            status: ContentStatus(rawValue: status) ?? .pending,
            createdAt: createdAt
        )
    }
}
```

**Step 5-6: Test, verify pass, commit**

```bash
git add macos/Sources/Storage/ macos/Tests/StorageTests/
git commit -m "feat(Storage): add GRDB local database with content persistence

- Implement LocalDatabase with GRDB
- Add ContentRecord CRUD operations
- Database migration system (v1 schema)
- Support for unsynced content tracking
- Tests: Save and fetch content

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Milestone 2: AI Services (Week 3-4)

### Task 7: AIServices - AICoordinator Foundation

**Files:**
- Create: `macos/Sources/AIServices/AICoordinator.swift`
- Test: `macos/Tests/AIServicesTests/AICoordinatorTests.swift`

**Step 1-2: Write test and verify fail**

```swift
// macos/Tests/AIServicesTests/AICoordinatorTests.swift
import XCTest
@testable import AIServices

final class AICoordinatorTests: XCTestCase {
    func testShowCommandBar() {
        let coordinator = AICoordinator()
        XCTAssertFalse(coordinator.isCommandBarVisible)

        coordinator.showCommandBar()
        XCTAssertTrue(coordinator.isCommandBarVisible)
    }

    func testHideCommandBar() {
        let coordinator = AICoordinator()
        coordinator.showCommandBar()
        coordinator.hideCommandBar()

        XCTAssertFalse(coordinator.isCommandBarVisible)
    }
}
```

Run: `cd macos && swift test --filter AICoordinatorTests`

**Step 3: Implement AICoordinator**

```swift
// macos/Sources/AIServices/AICoordinator.swift
import Foundation
import Observation
import Core

@Observable
public final class AICoordinator {
    // Command Bar State
    public var isCommandBarVisible = false
    public var commandQuery = ""
    public var commandResults: [CommandResult] = []
    public var selectedCommandIndex = 0

    // Semantic Search State
    public var searchQuery = ""
    public var searchResults: [SearchResult] = []
    public var isSearching = false

    // Context Suggestions State
    public var suggestions: [Suggestion] = []
    public var activeSuggestion: Suggestion?

    public init() {}

    // MARK: - Command Bar Actions

    @MainActor
    public func showCommandBar() {
        isCommandBarVisible = true
        commandQuery = ""
        commandResults = []
    }

    @MainActor
    public func hideCommandBar() {
        isCommandBarVisible = false
    }

    @MainActor
    public func searchCommands(_ query: String) async {
        commandQuery = query
        // Will be implemented with CommandBarService
    }

    @MainActor
    public func executeCommand(_ command: CommandResult) async {
        hideCommandBar()
        // Will be implemented with CommandBarService
    }
}

// Models
public struct CommandResult: Identifiable {
    public let id = UUID()
    public let title: String
    public let subtitle: String?
    public let icon: String
    public let action: () async -> Void

    public init(title: String, subtitle: String? = nil, icon: String, action: @escaping () async -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
    }
}

public struct SearchResult: Identifiable {
    public let id = UUID()
    public let contentID: String
    public let title: String
    public let snippet: String
    public let relevanceScore: Double
}

public enum Suggestion: Identifiable {
    case relatedContent(title: String, contentIDs: [String])
    case followUpQuestion(question: String)
    case deepDive(topic: String)

    public var id: String {
        switch self {
        case .relatedContent(let title, _): return "related-\(title)"
        case .followUpQuestion(let question): return "question-\(question)"
        case .deepDive(let topic): return "deepdive-\(topic)"
        }
    }
}
```

**Step 4-6: Test, verify pass, commit**

```bash
git add macos/Sources/AIServices/AICoordinator.swift macos/Tests/AIServicesTests/
git commit -m "feat(AIServices): add AICoordinator with @Observable

- Central coordinator for all AI features
- Command Bar state management
- Semantic search state
- Contextual suggestions state
- Tests: Show/hide command bar

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Milestone 3 & 4: Detailed Tasks Continue...

**Note**: Due to the comprehensive nature of this project (50+ tasks), I'm providing the structure for the first 7 tasks as examples. The remaining tasks would follow the same TDD pattern:

- Task 8-12: Command Bar Service (multi-modal input, fuzzy matching, NLU)
- Task 13-15: Semantic Search Service
- Task 16-18: Suggestions Service
- Task 19-25: UI Components (Sidebar, ContentList, ReaderView)
- Task 26-30: Performance optimization (virtualization, caching, retry)
- Task 31-35: Authentication & Sync
- Task 36-40: Accessibility
- Task 41-50: Integration tests and polish

---

## How to Execute This Plan

### Option 1: Task-by-Task with Reviews

For each task:
1. Read the task completely
2. Run all commands exactly as specified
3. Verify expected output matches
4. If test fails when it should pass, debug before moving on
5. Commit only when tests pass
6. Review changes before next task

### Option 2: Batch Execution

Execute all tasks in a milestone, then review:
1. Run all tasks in sequence
2. Verify all tests pass: `swift test`
3. Verify build succeeds: `swift build`
4. Review git log to ensure all commits made
5. Move to next milestone

---

## Success Criteria Per Milestone

**Milestone 1 (Foundation)**:
- ✅ `swift build` succeeds
- ✅ `swift test` passes all LiquidGlassKit tests
- ✅ LocalDatabase can save/fetch content
- ✅ All modules compile independently

**Milestone 2 (AI Services)**:
- ✅ AICoordinator tests pass
- ✅ Command Bar can process text/URL/image
- ✅ Semantic search returns results
- ✅ All AIServices tests > 80% coverage

**Milestone 3 (UI Refactor)**:
- ✅ App launches with new UI
- ✅ Liquid Glass materials visible
- ✅ Animations run at 60fps
- ✅ VoiceOver announces all elements

**Milestone 4 (Optimization)**:
- ✅ Memory < 200MB idle
- ✅ Startup < 2s
- ✅ All integration tests pass
- ✅ No compiler warnings

---

**End of Implementation Plan**

**Next Steps**: Choose execution approach and begin with Task 1.
