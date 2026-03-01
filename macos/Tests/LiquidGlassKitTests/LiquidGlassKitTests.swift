import XCTest
@testable import LiquidGlassKit

final class LiquidGlassKitTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(LiquidGlassKit.version, "1.0.0")
    }
}
