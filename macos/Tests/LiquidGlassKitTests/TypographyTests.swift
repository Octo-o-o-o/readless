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

    func testAllFontStylesExist() {
        // Verify all standard text styles
        XCTAssertNotNil(LGTypography.largeTitle)
        XCTAssertNotNil(LGTypography.title1)
        XCTAssertNotNil(LGTypography.title2)
        XCTAssertNotNil(LGTypography.title3)
        XCTAssertNotNil(LGTypography.headline)
        XCTAssertNotNil(LGTypography.body)
        XCTAssertNotNil(LGTypography.subheadline)
        XCTAssertNotNil(LGTypography.callout)
        XCTAssertNotNil(LGTypography.caption1)
        XCTAssertNotNil(LGTypography.caption2)
        XCTAssertNotNil(LGTypography.footnote)

        // Verify monospaced variants
        XCTAssertNotNil(LGTypography.monospacedCode)
        XCTAssertNotNil(LGTypography.monospacedDigit)
    }
}
