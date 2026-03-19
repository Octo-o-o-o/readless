import XCTest
@testable import Core

final class ContentTests: XCTestCase {
    func testContentDefaultValues() {
        let content = Content(title: "Test Article", sourceType: .url)
        XCTAssertEqual(content.title, "Test Article")
        XCTAssertEqual(content.sourceType, .url)
        XCTAssertEqual(content.status, .pending)
        XCTAssertTrue(content.tags.isEmpty)
        XCTAssertNil(content.l0Summary)
        XCTAssertNil(content.l1Outline)
        XCTAssertNil(content.podcastURL)
        XCTAssertFalse(content.id.isEmpty)
    }

    func testContentCodable() throws {
        let content = Content(
            title: "Test",
            sourceURL: "https://example.com",
            sourceType: .pdf,
            tags: ["swift", "test"],
            status: .ready
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(content)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Content.self, from: data)

        XCTAssertEqual(decoded.id, content.id)
        XCTAssertEqual(decoded.title, content.title)
        XCTAssertEqual(decoded.sourceURL, content.sourceURL)
        XCTAssertEqual(decoded.sourceType, content.sourceType)
        XCTAssertEqual(decoded.tags, content.tags)
        XCTAssertEqual(decoded.status, content.status)
    }

    func testOutlinePointDefaultValues() {
        let point = OutlinePoint(point: "Key insight")
        XCTAssertEqual(point.point, "Key insight")
        XCTAssertTrue(point.anchors.isEmpty)
        XCTAssertFalse(point.expanded)
        XCTAssertNil(point.detail)
        XCTAssertFalse(point.id.isEmpty)
    }

    func testOutlinePointCodable() throws {
        let point = OutlinePoint(
            point: "Summary point",
            anchors: ["anchor1", "anchor2"],
            expanded: true,
            detail: "Detailed explanation"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(point)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(OutlinePoint.self, from: data)

        XCTAssertEqual(decoded.id, point.id)
        XCTAssertEqual(decoded.point, point.point)
        XCTAssertEqual(decoded.anchors, point.anchors)
        XCTAssertTrue(decoded.expanded)
        XCTAssertEqual(decoded.detail, point.detail)
    }

    func testOutlinePointFallbackIDIsStableWithoutBackendID() throws {
        let json = """
        {
          "point": "Stable point",
          "anchors": ["¶2", "¶1"]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let first = try decoder.decode(OutlinePoint.self, from: json)
        let second = try decoder.decode(OutlinePoint.self, from: json)

        XCTAssertEqual(first.id, second.id)
    }

    func testSourceTypeRawValues() {
        XCTAssertEqual(SourceType.url.rawValue, "url")
        XCTAssertEqual(SourceType.pdf.rawValue, "pdf")
        XCTAssertEqual(SourceType.text.rawValue, "text")
        XCTAssertEqual(SourceType.image.rawValue, "image")
        XCTAssertEqual(SourceType.clipboard.rawValue, "clipboard")
        XCTAssertEqual(SourceType.folderWatch.rawValue, "folderWatch")
        XCTAssertEqual(SourceType.email.rawValue, "email")
        XCTAssertEqual(SourceType.rss.rawValue, "rss")
    }

    func testContentStatusRawValues() {
        XCTAssertEqual(ContentStatus.pending.rawValue, "pending")
        XCTAssertEqual(ContentStatus.processing.rawValue, "processing")
        XCTAssertEqual(ContentStatus.ready.rawValue, "ready")
        XCTAssertEqual(ContentStatus.failed.rawValue, "failed")
    }
}
