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
