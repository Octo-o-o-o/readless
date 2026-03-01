import XCTest
@testable import AIServices

final class AIServicesTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(AIServices.version, "1.0.0")
    }
}
