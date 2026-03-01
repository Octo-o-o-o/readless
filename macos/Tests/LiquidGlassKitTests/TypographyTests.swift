import XCTest
import SwiftUI
@testable import LiquidGlassKit

final class TypographyTests: XCTestCase {
    func testLargeTitleFont() {
        let font = LGTypography.largeTitle
        XCTAssertNotNil(font)
    }

    func testBodyLineSpacing() {
        let spacing = LGTypography.LineSpacing.body
        XCTAssertEqual(spacing, 6)
    }
}
