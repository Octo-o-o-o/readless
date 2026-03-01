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

    // MARK: - Text Input Tests

    func testParseURL() async throws {
        let input = CommandBarInput.text("https://example.com/article")
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .url(URL(string: "https://example.com/article")!))
    }

    func testParseHTTPURL() async throws {
        let input = CommandBarInput.text("http://example.com")
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .url(URL(string: "http://example.com")!))
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

    func testParseCommandWithAngleBracket() async throws {
        let input = CommandBarInput.text(">generate podcast")
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .command(">generate podcast"))
    }

    // MARK: - Direct Input Tests

    func testParseDirectURL() async throws {
        let url = URL(string: "https://example.com")!
        let input = CommandBarInput.url(url)
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .url(url))
    }

    func testParseDirectImage() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0x00]) // JPEG signature
        let input = CommandBarInput.image(imageData)
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .image(imageData))
    }

    func testParseDirectPDF() async throws {
        let pdfData = Data([0x25, 0x50, 0x44, 0x46]) // PDF signature
        let input = CommandBarInput.pdf(pdfData)
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .pdf(pdfData))
    }

    // MARK: - Pasted Content Detection Tests

    func testDetectPastedJPEG() async throws {
        let jpegData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let input = CommandBarInput.pastedContent(jpegData)
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .image(jpegData))
    }

    func testDetectPastedPNG() async throws {
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let input = CommandBarInput.pastedContent(pngData)
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .image(pngData))
    }

    func testDetectPastedPDF() async throws {
        let pdfData = Data([0x25, 0x50, 0x44, 0x46, 0x2D, 0x31])
        let input = CommandBarInput.pastedContent(pdfData)
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .pdf(pdfData))
    }

    func testDetectPastedText() async throws {
        let textData = "Some pasted text".data(using: .utf8)!
        let input = CommandBarInput.pastedContent(textData)
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .plainText("Some pasted text"))
    }

    func testDetectPastedURL() async throws {
        let urlData = "https://example.com/article".data(using: .utf8)!
        let input = CommandBarInput.pastedContent(urlData)
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .url(URL(string: "https://example.com/article")!))
    }

    // MARK: - URL Scheme Validation Tests

    func testURLSchemeValidation_HTTPSAllowed() async throws {
        let input = CommandBarInput.text("https://example.com")
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .url(URL(string: "https://example.com")!))
    }

    func testURLSchemeValidation_HTTPAllowed() async throws {
        let input = CommandBarInput.text("http://example.com")
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .url(URL(string: "http://example.com")!))
    }

    func testURLSchemeValidation_FileSchemeRejected() async throws {
        let input = CommandBarInput.text("file:///etc/passwd")
        let result = try await parser.parse(input)

        // Should be treated as plain text, not URL
        XCTAssertEqual(result, .plainText("file:///etc/passwd"))
    }

    func testURLSchemeValidation_JavaScriptSchemeRejected() async throws {
        let input = CommandBarInput.text("javascript:alert('xss')")
        let result = try await parser.parse(input)

        // Should be treated as plain text, not URL
        XCTAssertEqual(result, .plainText("javascript:alert('xss')"))
    }

    func testURLSchemeValidation_DataSchemeRejected() async throws {
        let input = CommandBarInput.text("data:text/html,<script>alert('xss')</script>")
        let result = try await parser.parse(input)

        // Should be treated as plain text, not URL
        XCTAssertEqual(result, .plainText("data:text/html,<script>alert('xss')</script>"))
    }

    // MARK: - Empty String Edge Cases

    func testParseEmptyString() async throws {
        let input = CommandBarInput.text("")
        let result = try await parser.parse(input)

        XCTAssertEqual(result, .plainText(""))
    }

    func testParseWhitespaceOnlyString() async throws {
        let input = CommandBarInput.text("   \n\t  ")
        let result = try await parser.parse(input)

        // Should return the original text (not trim it)
        XCTAssertEqual(result, .plainText("   \n\t  "))
    }

    func testParseWhitespaceAroundURL() async throws {
        let input = CommandBarInput.text("  https://example.com  ")
        let result = try await parser.parse(input)

        // Should still detect URL after trimming
        XCTAssertEqual(result, .url(URL(string: "https://example.com")!))
    }

    func testParseWhitespaceAroundCommand() async throws {
        let input = CommandBarInput.text("  /search test  ")
        let result = try await parser.parse(input)

        // Should still detect command after trimming (but preserve original)
        XCTAssertEqual(result, .command("  /search test  "))
    }
}
