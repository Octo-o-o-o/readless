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
