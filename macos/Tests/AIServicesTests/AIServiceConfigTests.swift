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
        // I3: Expand test coverage for reasoning model edge cases

        // OpenAI reasoning models
        XCTAssertTrue(AIServiceConfig.StepConfig(
            providerName: "OpenAI",
            baseURL: "",
            model: "o1-preview",
            temperature: nil,
            maxTokens: 1000
        ).isReasoningModel)

        XCTAssertTrue(AIServiceConfig.StepConfig(
            providerName: "OpenAI",
            baseURL: "",
            model: "o1-mini",
            temperature: nil,
            maxTokens: 1000
        ).isReasoningModel)

        XCTAssertTrue(AIServiceConfig.StepConfig(
            providerName: "OpenAI",
            baseURL: "",
            model: "o3-mini",
            temperature: nil,
            maxTokens: 1000
        ).isReasoningModel)

        // Deepseek reasoning model
        XCTAssertTrue(AIServiceConfig.StepConfig(
            providerName: "Deepseek",
            baseURL: "",
            model: "deepseek-reasoner",
            temperature: nil,
            maxTokens: 1000
        ).isReasoningModel)

        // Non-reasoning models
        XCTAssertFalse(AIServiceConfig.StepConfig(
            providerName: "OpenAI",
            baseURL: "",
            model: "gpt-4",
            temperature: 0.7,
            maxTokens: 1000
        ).isReasoningModel)

        XCTAssertFalse(AIServiceConfig.StepConfig(
            providerName: "OpenAI",
            baseURL: "",
            model: "gpt-4o",
            temperature: 0.7,
            maxTokens: 1000
        ).isReasoningModel)

        XCTAssertFalse(AIServiceConfig.StepConfig(
            providerName: "Deepseek",
            baseURL: "",
            model: "deepseek-chat",
            temperature: 0.7,
            maxTokens: 1000
        ).isReasoningModel)
    }

    func testConfigCodable() throws {
        // I4: Comprehensive Codable test coverage
        let config = AIServiceConfig.default

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIServiceConfig.self, from: data)

        // Test inputParsing (all fields)
        XCTAssertEqual(decoded.inputParsing.providerName, config.inputParsing.providerName)
        XCTAssertEqual(decoded.inputParsing.baseURL, config.inputParsing.baseURL)
        XCTAssertEqual(decoded.inputParsing.model, config.inputParsing.model)
        XCTAssertEqual(decoded.inputParsing.temperature, config.inputParsing.temperature)
        XCTAssertEqual(decoded.inputParsing.maxTokens, config.inputParsing.maxTokens)

        // Test intentAnalysis (verify nil temperature)
        XCTAssertEqual(decoded.intentAnalysis.providerName, config.intentAnalysis.providerName)
        XCTAssertEqual(decoded.intentAnalysis.model, config.intentAnalysis.model)
        XCTAssertNil(decoded.intentAnalysis.temperature)
        XCTAssertEqual(decoded.intentAnalysis.maxTokens, config.intentAnalysis.maxTokens)

        // Test contentExtraction
        XCTAssertEqual(decoded.contentExtraction.providerName, config.contentExtraction.providerName)
        XCTAssertEqual(decoded.contentExtraction.model, config.contentExtraction.model)
        XCTAssertEqual(decoded.contentExtraction.temperature, config.contentExtraction.temperature)
        XCTAssertEqual(decoded.contentExtraction.maxTokens, config.contentExtraction.maxTokens)
    }
}
