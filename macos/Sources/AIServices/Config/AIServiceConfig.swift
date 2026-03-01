import Foundation

public struct AIServiceConfig: Codable, Sendable, Equatable {
    public struct StepConfig: Codable, Sendable, Equatable {
        // M1: Extract magic strings to static constants
        private static let reasoningPrefixes = ["o1-", "o3-"]
        private static let reasoningModels = ["deepseek-reasoner"]

        public let providerName: String
        public let baseURL: String
        public let model: String
        public let temperature: Double?
        public let maxTokens: Int

        public var isReasoningModel: Bool {
            // I1: Fix reasoning model detection logic
            return Self.reasoningPrefixes.contains { model.hasPrefix($0) } ||
                   Self.reasoningModels.contains(model)
        }

        public init(
            providerName: String,
            baseURL: String,
            model: String,
            temperature: Double?,
            maxTokens: Int
        ) {
            // I2: Add input validation
            assert(!providerName.isEmpty, "Provider name cannot be empty")
            assert(!model.isEmpty, "Model name cannot be empty")
            assert(maxTokens > 0, "Max tokens must be positive")
            if let temp = temperature {
                assert(temp >= 0.0 && temp <= 2.0, "Temperature must be between 0.0 and 2.0")
            }

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
