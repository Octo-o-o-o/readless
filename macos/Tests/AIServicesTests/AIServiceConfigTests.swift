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
