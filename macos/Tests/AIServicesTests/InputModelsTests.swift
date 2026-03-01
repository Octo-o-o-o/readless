import XCTest
@testable import AIServices

final class InputModelsTests: XCTestCase {
    func testCommandBarInputTypes() {
        let textInput = CommandBarInput.text("Hello")
        XCTAssertNotNil(textInput)

        let urlInput = CommandBarInput.url(URL(string: "https://example.com")!)
        XCTAssertNotNil(urlInput)

        let imageInput = CommandBarInput.image(Data())
        XCTAssertNotNil(imageInput)
    }

    func testParsedInputTypes() {
        let plainText = ParsedInput.plainText("test")
        XCTAssertNotNil(plainText)

        let command = ParsedInput.command("/search")
        XCTAssertNotNil(command)

        let url = ParsedInput.url(URL(string: "https://example.com")!)
        XCTAssertNotNil(url)
    }

    func testUserIntent() throws {
        let intent = UserIntent(
            intent: .createContent,
            params: ["source": "url"],
            confidence: 0.95
        )

        XCTAssertEqual(intent.intent, .createContent)
        XCTAssertEqual(intent.confidence, 0.95)
    }
}
