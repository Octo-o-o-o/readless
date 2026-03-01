# Command Bar Service Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a multi-modal AI-powered Command Bar Service with configurable AI providers, supporting text, URL, image, and PDF inputs through a 4-step pipeline.

**Architecture:** UnifiedAIProvider layer with configurable base_url → 4 pipeline steps (InputParser, IntentAnalyzer, ContentExtractor, ActionExecutor) → CommandBarService coordinator → AICoordinator integration. Uses TDD throughout, dependency injection, and @Observable for state management.

**Tech Stack:** Swift 5.9+, @Observable, OpenAI SDK (or compatible), URLSession, PDFKit, TDD with XCTest

**Timeline:** Task 8-10 (estimated 3-5 days)

---

## Task 8: AI Provider Layer

### Subtask 8.1: AI Configuration Models

**Files:**
- Create: `macos/Sources/AIServices/Config/AIServiceConfig.swift`
- Test: `macos/Tests/AIServicesTests/AIServiceConfigTests.swift`

**Step 1: Write the failing test**

```swift
// macos/Tests/AIServicesTests/AIServiceConfigTests.swift
import XCTest
@testable import AIServices

final class AIServiceConfigTests: XCTestCase {
    func testDefaultConfig() {
        let config = AIServiceConfig.default

        XCTAssertEqual(config.inputParsing.model, "gpt-4o-mini")
        XCTAssertEqual(config.intentAnalysis.model, "deepseek-reasoner")
        XCTAssertEqual(config.contentExtraction.model, "gpt-4o")
    }

    func testReasoningModelDetection() {
        let reasoning = AIServiceConfig.StepConfig(
            providerName: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            model: "o1-preview",
            temperature: nil,
            maxTokens: 8000
        )

        XCTAssertTrue(reasoning.isReasoningModel)

        let normal = AIServiceConfig.StepConfig(
            providerName: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4",
            temperature: 0.7,
            maxTokens: 1000
        )

        XCTAssertFalse(normal.isReasoningModel)
    }

    func testConfigCodable() throws {
        let config = AIServiceConfig.default

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIServiceConfig.self, from: data)

        XCTAssertEqual(decoded.inputParsing.model, config.inputParsing.model)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd macos && swift test --filter AIServiceConfigTests`
Expected: FAIL with "Cannot find 'AIServiceConfig' in scope"

**Step 3: Implement AIServiceConfig**

```swift
// macos/Sources/AIServices/Config/AIServiceConfig.swift
import Foundation

public struct AIServiceConfig: Codable, Sendable {
    public struct StepConfig: Codable, Sendable {
        public let providerName: String
        public let baseURL: String
        public let model: String
        public let temperature: Double?
        public let maxTokens: Int

        public var isReasoningModel: Bool {
            let reasoningPrefixes = ["o1-", "o3-", "deepseek-reasoner"]
            return reasoningPrefixes.contains { model.hasPrefix($0) }
        }

        public init(
            providerName: String,
            baseURL: String,
            model: String,
            temperature: Double?,
            maxTokens: Int
        ) {
            self.providerName = providerName
            self.baseURL = baseURL
            self.model = model
            self.temperature = temperature
            self.maxTokens = maxTokens
        }
    }

    public let inputParsing: StepConfig
    public let intentAnalysis: StepConfig
    public let contentExtraction: StepConfig

    public init(
        inputParsing: StepConfig,
        intentAnalysis: StepConfig,
        contentExtraction: StepConfig
    ) {
        self.inputParsing = inputParsing
        self.intentAnalysis = intentAnalysis
        self.contentExtraction = contentExtraction
    }

    // Default configuration
    public static let `default` = AIServiceConfig(
        inputParsing: .init(
            providerName: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o-mini",
            temperature: 0.3,
            maxTokens: 500
        ),
        intentAnalysis: .init(
            providerName: "Deepseek",
            baseURL: "https://api.deepseek.com/v1",
            model: "deepseek-reasoner",
            temperature: nil,
            maxTokens: 8000
        ),
        contentExtraction: .init(
            providerName: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4o",
            temperature: 0.5,
            maxTokens: 4000
        )
    )
}
```

**Step 4: Run test to verify it passes**

Run: `cd macos && swift test --filter AIServiceConfigTests`
Expected: PASS (3/3 tests)

**Step 5: Commit**

```bash
git add macos/Sources/AIServices/Config/ macos/Tests/AIServicesTests/AIServiceConfigTests.swift
git commit -m "feat(AIServices): add AI service configuration models

- StepConfig with provider, model, base_url
- Auto-detect reasoning models
- Codable for persistence
- Tests: default config, reasoning detection, serialization

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Subtask 8.2: UnifiedAIProvider Foundation

**Files:**
- Create: `macos/Sources/AIServices/Providers/UnifiedAIProvider.swift`
- Create: `macos/Sources/AIServices/Providers/Models.swift`
- Test: `macos/Tests/AIServicesTests/UnifiedAIProviderTests.swift`

**Step 1: Write the failing test**

```swift
// macos/Tests/AIServicesTests/UnifiedAIProviderTests.swift
import XCTest
@testable import AIServices

final class UnifiedAIProviderTests: XCTestCase {
    func testProviderInitialization() {
        let config = UnifiedAIProvider.ProviderConfig(
            baseURL: "https://api.openai.com/v1",
            apiKey: "test-key",
            name: "OpenAI"
        )

        let provider = UnifiedAIProvider(config: config)

        XCTAssertNotNil(provider)
    }

    func testReasoningModelDetection() {
        let config = UnifiedAIProvider.ProviderConfig.openai
        let provider = UnifiedAIProvider(config: config)

        XCTAssertTrue(provider.isReasoningModel("o1-preview"))
        XCTAssertTrue(provider.isReasoningModel("o3-mini"))
        XCTAssertTrue(provider.isReasoningModel("deepseek-reasoner"))
        XCTAssertFalse(provider.isReasoningModel("gpt-4"))
        XCTAssertFalse(provider.isReasoningModel("gpt-4o"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd macos && swift test --filter UnifiedAIProviderTests`
Expected: FAIL with "Cannot find 'UnifiedAIProvider' in scope"

**Step 3: Implement Models**

```swift
// macos/Sources/AIServices/Providers/Models.swift
import Foundation

// Chat message
public struct ChatMessage: Sendable {
    public enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    // Convenience constructors
    public static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: .system, content: content)
    }

    public static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    public static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: .assistant, content: content)
    }
}

// Chat options
public struct AIChatOptions: Sendable {
    public let temperature: Double?
    public let maxTokens: Int
    public let topP: Double?

    public init(temperature: Double? = 0.7, maxTokens: Int = 1000, topP: Double? = nil) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
    }

    public static let `default` = AIChatOptions()
}

// AI Content types
public enum AIContent: Sendable {
    case text(String)
    case image(Data, mimeType: String)
    case pdf(Data)
    case url(URL)
}

// AI Errors
public enum AIError: Error, LocalizedError {
    case invalidResponse
    case rateLimitExceeded
    case authenticationFailed
    case modelNotAvailable
    case timeout
    case networkError(Error)
    case noMockResponse

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "AI 返回了无效的响应"
        case .rateLimitExceeded: return "请求频率超限，请稍后再试"
        case .authenticationFailed: return "API 认证失败"
        case .modelNotAvailable: return "所选模型暂时不可用"
        case .timeout: return "请求超时"
        case .networkError(let error): return "网络错误: \(error.localizedDescription)"
        case .noMockResponse: return "Mock provider has no response"
        }
    }
}
```

**Step 4: Implement UnifiedAIProvider**

```swift
// macos/Sources/AIServices/Providers/UnifiedAIProvider.swift
import Foundation

public final class UnifiedAIProvider: Sendable {
    public struct ProviderConfig: Sendable {
        public let baseURL: String
        public let apiKey: String
        public let name: String

        public init(baseURL: String, apiKey: String, name: String) {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.name = name
        }

        // Preset configurations
        public static let openai = ProviderConfig(
            baseURL: "https://api.openai.com/v1",
            apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
            name: "OpenAI"
        )

        public static let deepseek = ProviderConfig(
            baseURL: "https://api.deepseek.com/v1",
            apiKey: ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? "",
            name: "Deepseek"
        )

        public static let local = ProviderConfig(
            baseURL: "http://localhost:1234/v1",
            apiKey: "not-needed",
            name: "Local"
        )
    }

    private let config: ProviderConfig

    public init(config: ProviderConfig) {
        self.config = config
    }

    // Detect reasoning models
    public func isReasoningModel(_ model: String) -> Bool {
        let reasoningModels = [
            "o1-preview", "o1-mini", "o3-mini",  // OpenAI
            "deepseek-reasoner",                 // Deepseek
        ]
        return reasoningModels.contains { model.hasPrefix($0) }
    }

    // Chat completion (stub for now, will implement with OpenAI SDK)
    public func chat(
        messages: [ChatMessage],
        model: String,
        options: AIChatOptions
    ) async throws -> String {
        // TODO: Implement with OpenAI SDK
        throw AIError.modelNotAvailable
    }
}
```

**Step 5: Run test to verify it passes**

Run: `cd macos && swift test --filter UnifiedAIProviderTests`
Expected: PASS (2/2 tests)

**Step 6: Commit**

```bash
git add macos/Sources/AIServices/Providers/ macos/Tests/AIServicesTests/UnifiedAIProviderTests.swift
git commit -m "feat(AIServices): add UnifiedAIProvider foundation

- ProviderConfig with preset configurations
- ChatMessage, AIChatOptions, AIContent models
- AIError enum with localized descriptions
- Reasoning model detection
- Tests: initialization, reasoning detection

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Subtask 8.3: Multi-modal Support (Image & PDF)

**Files:**
- Modify: `macos/Sources/AIServices/Providers/UnifiedAIProvider.swift`
- Test: `macos/Tests/AIServicesTests/UnifiedAIProviderMultimodalTests.swift`

**Step 1: Write the failing test**

```swift
// macos/Tests/AIServicesTests/UnifiedAIProviderMultimodalTests.swift
import XCTest
@testable import AIServices

final class UnifiedAIProviderMultimodalTests: XCTestCase {
    var provider: UnifiedAIProvider!

    override func setUp() async throws {
        provider = UnifiedAIProvider(config: .openai)
    }

    func testAnalyzeImageSignature() async throws {
        // Test that method exists with correct signature
        let testData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG header

        // This will fail until we implement the method
        _ = try? await provider.analyzeImage(
            imageData: testData,
            prompt: "Describe this image",
            model: "gpt-4o"
        )
    }

    func testAnalyzePDFSignature() async throws {
        // Test that method exists with correct signature
        let testData = Data([0x25, 0x50, 0x44, 0x46]) // PDF header

        _ = try? await provider.analyzePDF(
            pdfData: testData,
            prompt: "Extract text from this PDF",
            model: "gpt-4o"
        )
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd macos && swift test --filter UnifiedAIProviderMultimodalTests`
Expected: FAIL with "Value of type 'UnifiedAIProvider' has no member 'analyzeImage'"

**Step 3: Add multi-modal methods to UnifiedAIProvider**

```swift
// Add to macos/Sources/AIServices/Providers/UnifiedAIProvider.swift

extension UnifiedAIProvider {
    /// Analyze image using vision models
    public func analyzeImage(
        imageData: Data,
        prompt: String,
        model: String = "gpt-4o"
    ) async throws -> String {
        // Convert image to base64
        let base64 = imageData.base64EncodedString()

        // For now, stub implementation
        // TODO: Implement with OpenAI vision API
        throw AIError.modelNotAvailable
    }

    /// Analyze PDF (extract text and images)
    public func analyzePDF(
        pdfData: Data,
        prompt: String,
        model: String = "gpt-4o"
    ) async throws -> String {
        // For now, stub implementation
        // TODO: Convert PDF to images using PDFKit, then analyze
        throw AIError.modelNotAvailable
    }

    /// Helper: Extract images from PDF
    private func extractImagesFromPDF(_ pdfData: Data) throws -> [Data] {
        // TODO: Implement with PDFKit
        return []
    }
}
```

**Step 4: Run test to verify it compiles**

Run: `cd macos && swift test --filter UnifiedAIProviderMultimodalTests`
Expected: Tests compile and run (may fail gracefully with modelNotAvailable)

**Step 5: Commit**

```bash
git add macos/Sources/AIServices/Providers/UnifiedAIProvider.swift macos/Tests/AIServicesTests/UnifiedAIProviderMultimodalTests.swift
git commit -m "feat(AIServices): add multi-modal support stubs

- analyzeImage method for GPT-4o vision
- analyzePDF method for document analysis
- Stub implementations (to be completed with OpenAI SDK)
- Tests: method signatures

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Pipeline Steps

### Subtask 9.1: Input Types and Models

**Files:**
- Create: `macos/Sources/AIServices/CommandBar/InputModels.swift`
- Test: `macos/Tests/AIServicesTests/InputModelsTests.swift`

**Step 1: Write the failing test**

```swift
// macos/Tests/AIServicesTests/InputModelsTests.swift
import XCTest
@testable import AIServices

final class InputModelsTests: XCTestCase {
    func testCommandBarInputTypes() {
        let textInput = CommandBarInput.text("Hello")
        XCTAssertNotNil(textInput)

        let urlInput = CommandBarInput.url(URL(string: "https://example.com")!)
        XCTAssertNotNil(urlInput)

        let imageInput = CommandBarInput.image(Data())
        XCTAssertNotNil(imageInput)
    }

    func testParsedInputTypes() {
        let plainText = ParsedInput.plainText("test")
        XCTAssertNotNil(plainText)

        let command = ParsedInput.command("/search")
        XCTAssertNotNil(command)

        let url = ParsedInput.url(URL(string: "https://example.com")!)
        XCTAssertNotNil(url)
    }

    func testUserIntent() throws {
        let intent = UserIntent(
            intent: .createContent,
            params: ["source": "url"],
            confidence: 0.95
        )

        XCTAssertEqual(intent.intent, .createContent)
        XCTAssertEqual(intent.confidence, 0.95)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd macos && swift test --filter InputModelsTests`
Expected: FAIL with "Cannot find 'CommandBarInput' in scope"

**Step 3: Implement input models**

```swift
// macos/Sources/AIServices/CommandBar/InputModels.swift
import Foundation
import Core

// Input from user
public enum CommandBarInput: Sendable {
    case text(String)
    case url(URL)
    case image(Data)
    case pdf(Data)
    case pastedContent(Data)
}

// Parsed input type
public enum ParsedInput: Sendable, Equatable {
    case plainText(String)
    case command(String)
    case url(URL)
    case image(Data)
    case pdf(Data)

    public static func == (lhs: ParsedInput, rhs: ParsedInput) -> Bool {
        switch (lhs, rhs) {
        case (.plainText(let a), .plainText(let b)): return a == b
        case (.command(let a), .command(let b)): return a == b
        case (.url(let a), .url(let b)): return a == b
        case (.image(let a), .image(let b)): return a == b
        case (.pdf(let a), .pdf(let b)): return a == b
        default: return false
        }
    }
}

// User intent
public struct UserIntent: Codable, Sendable {
    public enum IntentType: String, Codable {
        case createContent = "create_content"
        case searchContent = "search_content"
        case generatePodcast = "generate_podcast"
        case openContent = "open_content"
    }

    public let intent: IntentType
    public let params: [String: String]
    public let confidence: Double

    public init(intent: IntentType, params: [String: String], confidence: Double) {
        self.intent = intent
        self.params = params
        self.confidence = confidence
    }
}

// Extracted content
public struct ExtractedContent: Sendable {
    public let text: String
    public let source: SourceType
    public let title: String?
    public let summary: String?

    public init(text: String, source: SourceType, title: String? = nil, summary: String? = nil) {
        self.text = text
        self.source = source
        self.title = title
        self.summary = summary
    }
}

// Submission mode
public enum SubmissionMode: Sendable {
    case quickImport    // Enter
    case reviewFirst    // Cmd+Enter
}

// Execution result
public enum ExecutionResult: Sendable {
    case contentCreated(Content)
    case searchCompleted([Content])
    case podcastGenerated(URL)
    case contentOpened(Content)
    case reviewPending(ContentPreview)
}

// Content preview
public struct ContentPreview: Sendable {
    public enum PreviewType {
        case creation
        case search
        case podcast
        case open
    }

    public let type: PreviewType
    public let title: String
    public let summary: String
    public let sourceType: SourceType?
    public let metadata: [String: String]

    public init(type: PreviewType, title: String, summary: String, sourceType: SourceType? = nil, metadata: [String: String] = [:]) {
        self.type = type
        self.title = title
        self.summary = summary
        self.sourceType = sourceType
        self.metadata = metadata
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd macos && swift test --filter InputModelsTests`
Expected: PASS (3/3 tests)

**Step 5: Commit**

```bash
git add macos/Sources/AIServices/CommandBar/InputModels.swift macos/Tests/AIServicesTests/InputModelsTests.swift
git commit -m "feat(AIServices): add Command Bar input models

- CommandBarInput enum (text, url, image, pdf)
- ParsedInput, UserIntent, ExtractedContent
- SubmissionMode, ExecutionResult, ContentPreview
- Tests: all model types

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

### Subtask 9.2: InputParser

**Files:**
- Create: `macos/Sources/AIServices/CommandBar/InputParser.swift`
- Test: `macos/Tests/AIServicesTests/InputParserTests.swift`

**Step 1: Write the failing test**

```swift
// macos/Tests/AIServicesTests/InputParserTests.swift
import XCTest
@testable import AIServices

final class InputParserTests: XCTestCase {
    var parser: InputParser!
    var mockProvider: MockAIProvider!

    override func setUp() async throws {
        mockProvider = MockAIProvider()
        let config = AIServiceConfig.StepConfig(
            providerName: "mock",
            baseURL: "",
            model: "test",
            temperature: 0.3,
            maxTokens: 500
        )
        parser = InputParser(aiProvider: mockProvider, config: config)
    }

    func testParseURL() async throws {
        let input = CommandBarInput.text("https://example.com/article")
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .url(URL(string: "https://example.com/article")!))
    }

    func testParsePlainText() async throws {
        let input = CommandBarInput.text("这是一段普通文本")
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .plainText("这是一段普通文本"))
    }

    func testParseCommand() async throws {
        let input = CommandBarInput.text("/搜索 Swift")
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .command("/搜索 Swift"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd macos && swift test --filter InputParserTests`
Expected: FAIL with "Cannot find 'InputParser' in scope"

**Step 3: Create MockAIProvider**

```swift
// macos/Tests/AIServicesTests/Mocks/MockAIProvider.swift
import Foundation
@testable import AIServices

public final class MockAIProvider: Sendable {
    public var responseQueue: [String] = []
    public var callHistory: [AICall] = []

    public enum AICall {
        case chat([ChatMessage], String, AIChatOptions)
        case image(String, String)
        case pdf(String, String)
    }

    public init() {}

    public func chat(
        messages: [ChatMessage],
        model: String,
        options: AIChatOptions
    ) async throws -> String {
        callHistory.append(.chat(messages, model, options))

        guard !responseQueue.isEmpty else {
            throw AIError.noMockResponse
        }

        return responseQueue.removeFirst()
    }

    public func analyzeImage(
        imageData: Data,
        prompt: String,
        model: String
    ) async throws -> String {
        callHistory.append(.image(prompt, model))

        guard !responseQueue.isEmpty else {
            throw AIError.noMockResponse
        }

        return responseQueue.removeFirst()
    }

    public func analyzePDF(
        pdfData: Data,
        prompt: String,
        model: String
    ) async throws -> String {
        callHistory.append(.pdf(prompt, model))

        guard !responseQueue.isEmpty else {
            throw AIError.noMockResponse
        }

        return responseQueue.removeFirst()
    }

    public func isReasoningModel(_ model: String) -> Bool {
        ["o1-", "o3-", "deepseek-reasoner"].contains { model.hasPrefix($0) }
    }
}
```

**Step 4: Implement InputParser**

```swift
// macos/Sources/AIServices/CommandBar/InputParser.swift
import Foundation

public final class InputParser: Sendable {
    private let aiProvider: any AIProviderProtocol
    private let config: AIServiceConfig.StepConfig

    public init(aiProvider: any AIProviderProtocol, config: AIServiceConfig.StepConfig) {
        self.aiProvider = aiProvider
        self.config = config
    }

    public func parse(_ input: CommandBarInput) async throws -> ParsedInput {
        switch input {
        case .text(let text):
            return try await parseText(text)
        case .url(let url):
            return .url(url)
        case .image(let data):
            return .image(data)
        case .pdf(let data):
            return .pdf(data)
        case .pastedContent(let data):
            return try await detectPastedType(data)
        }
    }

    private func parseText(_ text: String) async throws -> ParsedInput {
        // 1. Check if URL
        if let url = URL(string: text), url.scheme != nil {
            return .url(url)
        }

        // 2. Check if command keyword
        if text.hasPrefix("/") || text.hasPrefix(">") {
            return .command(text)
        }

        // 3. Plain text
        return .plainText(text)
    }

    private func detectPastedType(_ data: Data) async throws -> ParsedInput {
        // Try to decode as UTF-8 text
        if let text = String(data: data, encoding: .utf8) {
            return try await parseText(text)
        }

        // Check for image signature
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { // JPEG
            return .image(data)
        }

        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { // PNG
            return .image(data)
        }

        // Check for PDF signature
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { // %PDF
            return .pdf(data)
        }

        // Default to text
        return .plainText(String(decoding: data, as: UTF8.self))
    }
}

// Protocol for AI provider (to support mock)
public protocol AIProviderProtocol: Sendable {
    func chat(messages: [ChatMessage], model: String, options: AIChatOptions) async throws -> String
    func analyzeImage(imageData: Data, prompt: String, model: String) async throws -> String
    func analyzePDF(pdfData: Data, prompt: String, model: String) async throws -> String
    func isReasoningModel(_ model: String) -> Bool
}

// Make UnifiedAIProvider conform
extension UnifiedAIProvider: AIProviderProtocol {}
```

**Step 5: Run test to verify it passes**

Run: `cd macos && swift test --filter InputParserTests`
Expected: PASS (3/3 tests)

**Step 6: Commit**

```bash
git add macos/Sources/AIServices/CommandBar/InputParser.swift macos/Tests/AIServicesTests/InputParserTests.swift macos/Tests/AIServicesTests/Mocks/
git commit -m "feat(AIServices): add InputParser with URL/command detection

- Parse text input to detect URLs, commands, plain text
- Detect pasted content type by signature
- AIProviderProtocol for testability
- MockAIProvider for unit tests
- Tests: URL, plain text, command parsing

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

**Note:** Due to length constraints, this plan continues with:
- Subtask 9.3: IntentAnalyzer
- Subtask 9.4: ContentExtractor
- Subtask 9.5: ActionExecutor
- Task 10: CommandBarService Integration

Each following the same TDD pattern: test → fail → implement → pass → commit.

The complete implementation plan would be approximately 1500-2000 lines covering all subtasks in detail with exact code, commands, and expected outputs for each step.

---

## Execution Strategy

After implementing Task 8-10, the next steps would be:

1. **Integration Testing**: Full pipeline E2E tests
2. **UI Integration**: Connect CommandBarService to SwiftUI views
3. **OpenAI SDK Integration**: Replace stub implementations with real API calls
4. **Error Handling**: Add retry logic and user-friendly error messages
5. **Performance Testing**: Measure and optimize pipeline latency

---

**End of Implementation Plan (Abbreviated)**

For the complete plan with all subtasks, continue the same pattern for IntentAnalyzer, ContentExtractor, ActionExecutor, and CommandBarService integration.
