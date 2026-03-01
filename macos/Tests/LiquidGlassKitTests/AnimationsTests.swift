import XCTest
import SwiftUI
@testable import LiquidGlassKit

final class AnimationsTests: XCTestCase {
    func testFluidAnimationExists() {
        let animation = LGAnimation.fluid.animation
        XCTAssertNotNil(animation)
    }

    func testGlassAppearAnimationExists() {
        let animation = LGAnimation.glassAppear.animation
        XCTAssertNotNil(animation)
    }
}
