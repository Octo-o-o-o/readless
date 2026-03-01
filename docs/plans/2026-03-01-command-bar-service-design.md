# Command Bar Service Design

**Date**: 2026-03-01
**Status**: Approved
**Author**: Claude Sonnet 4.5
**Target Platform**: macOS 14+
**Related**: Liquid Glass UI Framework (Task 8-10)

---

## Executive Summary

This design document outlines the architecture for the Command Bar Service, a multi-modal AI-powered input system for Readless macOS app. The service supports:

- **Multi-modal input**: Text, URL, images, PDF files
- **AI-powered NLU**: Natural language understanding via configurable AI providers
- **Flexible configuration**: Different AI providers and models for each processing step
- **Smart UX**: Two submission modes (Enter for quick import, Cmd+Enter for preview)

**Timeline**: Task 8-10 (estimated 1-2 weeks)
**Dependencies**: Task 7 (AICoordinator Foundation)
**Risk Level**: Medium (AI integration complexity)

---

## 1. Architecture Overview

### 1.1 System Architecture

```
┌─────────────────────────────────────────────────────┐
│ CommandBarService (协调层)                           │
│  - 处理用户输入                                        │
│  - 协调各个步骤                                        │
│  - 更新 AICoordinator 状态                            │
└─────────────────────────────────────────────────────┘
                      ↓
┌──────────────────────────────────────────────────────┐
│ Pipeline Steps (可独立配置 AI Provider)                │
├──────────────────────────────────────────────────────┤
│ 1. InputParser                                       │
│    - 识别输入类型（文本/URL/图片/PDF）                   │
│    - AI Model: GPT-4o-mini (快速分类)                  │
├──────────────────────────────────────────────────────┤
│ 2. IntentAnalyzer                                    │
│    - NLU 解析用户意图                                  │
│    - AI Model: GPT-4 或 Deepseek-reasoner            │
├──────────────────────────────────────────────────────┤
│ 3. ContentExtractor                                  │
│    - 从 URL/图片/PDF 提取内容                          │
│    - AI Model: GPT-4o (多模态)                         │
├──────────────────────────────────────────────────────┤
│ 4. ActionExecutor                                    │
│    - 执行具体命令（创建内容/搜索/生成播客）               │
│    - 调用 Backend API                                 │
└──────────────────────────────────────────────────────┘
                      ↓
┌──────────────────────────────────────────────────────┐
│ AI Provider Layer (抽象层)                            │
├──────────────────────────────────────────────────────┤
│ UnifiedAIProvider (基于 OpenAI SDK)                  │
│  - 支持任何 OpenAI 兼容 API                           │
│  - 可配置 base_url                                   │
│  - 自动适配推理模型                                    │
└──────────────────────────────────────────────────────┘
```

### 1.2 Design Principles

1. **Configuration-driven**: Each pipeline step can use different AI provider/model
2. **Dependency Injection**: All components are testable and replaceable
3. **Strategy Pattern**: Smart model selection based on task complexity
4. **Error Isolation**: Failures in one step don't affect others

---

## 2. AI Provider Unified Layer

### 2.1 Core Design

All AI providers use OpenAI SDK with configurable `base_url`:

```swift
public final class UnifiedAIProvider {
    private let client: OpenAI
    private let config: ProviderConfig

    public struct ProviderConfig {
        let baseURL: String
        let apiKey: String
        let name: String

        // Preset configurations
        public static let openai = ProviderConfig(
            baseURL: "https://api.openai.com/v1",
            apiKey: Config.openaiKey,
            name: "OpenAI"
        )

        public static let deepseek = ProviderConfig(
            baseURL: "https://api.deepseek.com/v1",
            apiKey: Config.deepseekKey,
            name: "Deepseek"
        )

        public static let local = ProviderConfig(
            baseURL: "http://localhost:1234/v1",
            apiKey: "not-needed",
            name: "Local"
        )
    }
}
```

### 2.2 Reasoning Model Auto-Adaptation

The provider automatically detects reasoning models and adjusts parameters:

```swift
extension UnifiedAIProvider {
    private func isReasoningModel(_ model: String) -> Bool {
        let reasoningModels = [
            "o1-preview", "o1-mini", "o3-mini",  // OpenAI
            "deepseek-reasoner",                 // Deepseek
        ]
        return reasoningModels.contains { model.hasPrefix($0) }
    }

    public func chat(
        messages: [ChatMessage],
        model: String,
        options: AIChatOptions
    ) async throws -> String {
        if isReasoningModel(model) {
            // Remove unsupported parameters (temperature, top_p)
            return try await callReasoningModel(messages, model, adaptedOptions)
        } else {
            return try await callChatModel(messages, model, options)
        }
    }
}
```

### 2.3 Multi-modal Support

```swift
extension UnifiedAIProvider {
    /// Analyze images (GPT-4o, GPT-4-Vision)
    public func analyzeImage(
        imageData: Data,
        prompt: String,
        model: String = "gpt-4o"
    ) async throws -> String {
        let base64 = imageData.base64EncodedString()
        let messages: [ChatMessage] = [
            .user(content: [
                .text(prompt),
                .image(url: "data:image/jpeg;base64,\(base64)")
            ])
        ]
        return try await chat(messages: messages, model: model, options: .default)
    }

    /// Analyze PDF (convert to images first)
    public func analyzePDF(
        pdfData: Data,
        prompt: String,
        model: String = "gpt-4o"
    ) async throws -> String {
        let images = try extractImagesFromPDF(pdfData)
        var results: [String] = []
        for (index, imageData) in images.enumerated() {
            let pagePrompt = "\(prompt) (Page \(index + 1))"
            let result = try await analyzeImage(imageData: imageData, prompt: pagePrompt, model: model)
            results.append(result)
        }
        return results.joined(separator: "\n\n")
    }
}
```

### 2.4 Configuration Model

```swift
public struct AIServiceConfig: Codable {
    public struct StepConfig: Codable {
        let providerName: String  // "OpenAI", "Deepseek", "Local"
        let baseURL: String
        let model: String
        let temperature: Double?  // nil for reasoning models
        let maxTokens: Int

        var isReasoningModel: Bool {
            ["o1-", "o3-", "deepseek-reasoner"].contains { model.hasPrefix($0) }
        }
    }

    let inputParsing: StepConfig
    let intentAnalysis: StepConfig
    let contentExtraction: StepConfig

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
            temperature: nil,  // Not supported by reasoning models
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

---

## 3. Pipeline Steps

### 3.1 Step 1: InputParser

**Responsibility**: Identify input type and extract key information

```swift
public final class InputParser {
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
}
```

### 3.2 Step 2: IntentAnalyzer

**Responsibility**: Use AI NLU to understand user intent

```swift
public final class IntentAnalyzer {
    private let systemPrompt = """
    你是 Readless 应用的命令解析助手。用户输入可能是：
    1. 创建内容的请求（文本、URL、图片、PDF）
    2. 搜索内容的请求
    3. 生成播客的请求
    4. 打开特定内容的请求

    返回 JSON 格式的意图分析：
    {
        "intent": "create_content" | "search_content" | "generate_podcast" | "open_content",
        "params": {...},
        "confidence": 0.0-1.0
    }
    """

    public func analyze(_ input: ParsedInput) async throws -> UserIntent {
        let prompt = buildIntentPrompt(input)
        let response = try await aiProvider.chat(
            messages: [.system(systemPrompt), .user(prompt)],
            model: config.model,
            options: chatOptions(from: config)
        )
        return try parseIntentResponse(response)
    }
}
```

### 3.3 Step 3: ContentExtractor

**Responsibility**: Extract content from URL/image/PDF

```swift
public final class ContentExtractor {
    public func extract(from input: ParsedInput) async throws -> ExtractedContent {
        switch input {
        case .plainText(let text):
            return ExtractedContent(text: text, source: .text)
        case .url(let url):
            return try await extractFromURL(url)
        case .image(let data):
            return try await extractFromImage(data)
        case .pdf(let data):
            return try await extractFromPDF(data)
        case .command:
            throw ExtractionError.notApplicable
        }
    }

    private func extractFromImage(_ data: Data) async throws -> ExtractedContent {
        let prompt = "请识别图片中的所有文字内容，并总结图片的主要信息。"
        let result = try await aiProvider.analyzeImage(
            imageData: data,
            prompt: prompt,
            model: config.model
        )
        return ExtractedContent(text: result, source: .image)
    }
}
```

### 3.4 Step 4: ActionExecutor

**Responsibility**: Execute specific actions based on intent

```swift
public final class ActionExecutor {
    public func execute(
        intent: UserIntent,
        content: ExtractedContent?,
        mode: SubmissionMode
    ) async throws -> ExecutionResult {
        switch mode {
        case .quickImport:
            return try await executeDirectly(intent: intent, content: content)
        case .reviewFirst:
            return try await executeWithReview(intent: intent, content: content)
        }
    }

    private func executeDirectly(
        intent: UserIntent,
        content: ExtractedContent?
    ) async throws -> ExecutionResult {
        switch intent.intent {
        case .createContent:
            return try await createContent(from: content, params: intent.params)
        case .searchContent:
            return try await searchContent(query: intent.params["query"] ?? "")
        case .generatePodcast:
            return try await generatePodcast(contentId: intent.params["contentId"] ?? "")
        case .openContent:
            return try await openContent(contentId: intent.params["contentId"] ?? "")
        }
    }
}
```

### 3.5 Submission Modes

**Design**: Different keyboard shortcuts for different workflows

```swift
public enum SubmissionMode {
    case quickImport    // Enter - 直接创建内容
    case reviewFirst    // Cmd+Enter - 先预览检查
}
```

**Keyboard Flow**:
```
用户输入内容 → Command Bar TextField
         ↓
     按键判断
    ┌────┴────┐
    │         │
  Enter   Cmd+Enter
    │         │
    ↓         ↓
快速导入   检查预览
    │         │
    │    显示预览界面
    │         ↓
    │    用户点击"确认"
    │         │
    └────┬────┘
         ↓
    Pipeline 执行
```

---

## 4. CommandBarService Integration

### 4.1 Core Service Class

```swift
@Observable
public final class CommandBarService {
    private let aiConfig: AIServiceConfig
    private let providerRegistry: AIProviderRegistry
    private let inputParser: InputParser
    private let intentAnalyzer: IntentAnalyzer
    private let contentExtractor: ContentExtractor
    private let actionExecutor: ActionExecutor

    private weak var coordinator: AICoordinator?

    @MainActor
    public var isProcessing = false

    @MainActor
    public var currentStep: ProcessingStep = .idle

    public init(
        config: AIServiceConfig = .default,
        apiClient: APIClient,
        localStorage: LocalDatabase,
        coordinator: AICoordinator
    ) {
        // Initialize all components with dependency injection
    }
}
```

### 4.2 Main Processing Flow

```swift
extension CommandBarService {
    @MainActor
    public func processInput(
        _ input: CommandBarInput,
        mode: SubmissionMode
    ) async throws {
        isProcessing = true
        defer { isProcessing = false }

        // Step 1: Parse input
        currentStep = .parsingInput
        coordinator?.updateCommandStatus("解析输入...")
        let parsedInput = try await inputParser.parse(input)

        // Step 2: Analyze intent
        currentStep = .analyzingIntent
        coordinator?.updateCommandStatus("理解您的意图...")
        let intent = try await intentAnalyzer.analyze(parsedInput)

        // Step 3: Extract content (if needed)
        currentStep = .extractingContent
        var extractedContent: ExtractedContent?
        if intent.intent == .createContent {
            coordinator?.updateCommandStatus("提取内容...")
            extractedContent = try await contentExtractor.extract(from: parsedInput)
        }

        // Step 4: Execute action
        currentStep = .executingAction
        coordinator?.updateCommandStatus("执行操作...")
        let result = try await actionExecutor.execute(
            intent: intent,
            content: extractedContent,
            mode: mode
        )

        // Step 5: Handle result
        currentStep = .completed
        await handleResult(result, mode: mode)
    }
}
```

### 4.3 Keyboard Event Handling

```swift
extension CommandBarService {
    @MainActor
    public func handleSubmit(
        text: String,
        modifiers: EventModifiers
    ) async {
        let mode: SubmissionMode = modifiers.contains(.command) ? .reviewFirst : .quickImport
        let input = CommandBarInput.text(text)
        try? await processInput(input, mode: mode)
    }

    @MainActor
    public func handleFileDrop(_ urls: [URL]) async {
        // Handle drag & drop files
    }

    @MainActor
    public func handlePaste(_ data: Data) async {
        // Handle clipboard paste
    }
}
```

---

## 5. Testing Strategy

### 5.1 Test Levels

```
E2E Tests (Integration)
  - Full pipeline flow
  - Real AI calls (optional mock)
  - UI interaction
        ↓
Service Tests (Unit)
  - CommandBarService
  - Individual pipeline steps
  - Mock AI Provider
        ↓
Provider Tests (Integration)
  - UnifiedAIProvider
  - Real API calls
  - Reasoning model adaptation
```

### 5.2 Mock AI Provider

```swift
public final class MockAIProvider: AIProvider {
    public var responseQueue: [String] = []
    public var callHistory: [AICall] = []

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
}
```

### 5.3 Test Coverage Goals

| Component | Unit Test Coverage | Integration Test |
|-----------|-------------------|------------------|
| UnifiedAIProvider | 90%+ | ✅ |
| InputParser | 95%+ | ✅ |
| IntentAnalyzer | 90%+ | ✅ |
| ContentExtractor | 85%+ | ✅ |
| ActionExecutor | 90%+ | ✅ |
| CommandBarService | 80%+ | ✅ |

---

## 6. Error Handling

### 6.1 Error Types

```swift
public enum AIError: Error, LocalizedError {
    case invalidResponse
    case rateLimitExceeded
    case authenticationFailed
    case modelNotAvailable
    case timeout
    case networkError(Error)
}

public enum ExtractionError: Error, LocalizedError {
    case urlNotAccessible
    case invalidImageFormat
    case pdfReadFailed
    case contentTooLarge
    case notApplicable
}

public enum ExecutionError: Error, LocalizedError {
    case missingContent
    case apiCallFailed(Error)
    case databaseError(Error)
    case previewNotSupported
}
```

### 6.2 Retry Mechanism

```swift
extension UnifiedAIProvider {
    private func chatWithRetry(
        messages: [ChatMessage],
        model: String,
        options: AIChatOptions,
        maxRetries: Int = 3
    ) async throws -> String {
        for attempt in 1...maxRetries {
            do {
                return try await callChatModel(messages, model, options)
            } catch let error as AIError {
                switch error {
                case .rateLimitExceeded, .timeout, .networkError:
                    // Retryable errors - exponential backoff
                    let delay = TimeInterval(attempt * 2)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                case .authenticationFailed, .modelNotAvailable, .invalidResponse:
                    // Non-retryable errors
                    throw error
                }
            }
        }
        throw lastError ?? AIError.invalidResponse
    }
}
```

---

## 7. Implementation Roadmap

### Task 8: AI Provider Layer
- Implement `UnifiedAIProvider` with OpenAI SDK
- Add reasoning model auto-detection
- Support multi-modal (image, PDF)
- Comprehensive tests

### Task 9: Pipeline Steps
- Implement `InputParser`, `IntentAnalyzer`, `ContentExtractor`, `ActionExecutor`
- Add submission modes (Enter vs Cmd+Enter)
- Mock AI Provider for testing
- Unit tests for each step

### Task 10: CommandBarService Integration
- Integrate all pipeline steps
- Connect with AICoordinator
- Keyboard event handling
- E2E integration tests

---

## 8. Success Criteria

- ✅ All input types supported (text, URL, image, PDF)
- ✅ AI NLU correctly identifies intent >85% accuracy
- ✅ Multi-modal extraction works for common formats
- ✅ Quick import (<2s for text, <5s for files)
- ✅ Preview mode shows accurate content preview
- ✅ Error handling provides actionable feedback
- ✅ Test coverage >80% for all components
- ✅ Zero memory leaks in pipeline

---

## 9. Future Enhancements

**Post-MVP features:**
- Voice input support
- Batch file processing
- Command history and suggestions
- Keyboard shortcuts customization
- Offline mode with local models
- Analytics and usage tracking

---

**End of Design Document**
