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
