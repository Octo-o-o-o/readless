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
