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
