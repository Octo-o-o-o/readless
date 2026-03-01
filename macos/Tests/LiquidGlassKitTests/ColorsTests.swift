// macos/Tests/LiquidGlassKitTests/ColorsTests.swift
import XCTest
import SwiftUI
@testable import LiquidGlassKit

final class ColorsTests: XCTestCase {
    func testVibrantLabelReturnsColor() {
        let color = LGColor.vibrantLabel.color
        XCTAssertNotNil(color)
    }

    func testAccentColorExists() {
        let color = LGColor.accent.color
        XCTAssertNotNil(color)
    }
}
