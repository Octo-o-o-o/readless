import XCTest
import SwiftUI
@testable import LiquidGlassKit

final class MaterialsTests: XCTestCase {
    func testLiquidGlassRegularReturnsMaterial() {
        let material = LGMaterial.liquidGlassRegular
        // Material doesn't conform to Equatable, so we verify it returns a Material type
        _ = material.material
        XCTAssertTrue(true) // If we got here without crashing, the property works
    }

    func testLiquidGlassNeedsEffect() {
        XCTAssertTrue(LGMaterial.liquidGlassRegular.needsGlassEffect)
        XCTAssertTrue(LGMaterial.liquidGlassClear.needsGlassEffect)
        XCTAssertFalse(LGMaterial.regular.needsGlassEffect)
    }

    func testAllMaterialsHaveMaterialProperty() {
        // Test that all cases return a valid Material
        let materials: [LGMaterial] = [
            .liquidGlassRegular,
            .liquidGlassClear,
            .ultraThin,
            .thin,
            .regular,
            .thick
        ]

        for lgMaterial in materials {
            _ = lgMaterial.material // Should not crash
        }

        XCTAssertTrue(true)
    }

    func testOnlyLiquidGlassNeedsEffect() {
        XCTAssertTrue(LGMaterial.liquidGlassRegular.needsGlassEffect)
        XCTAssertTrue(LGMaterial.liquidGlassClear.needsGlassEffect)

        // All other materials should not need glass effect
        XCTAssertFalse(LGMaterial.ultraThin.needsGlassEffect)
        XCTAssertFalse(LGMaterial.thin.needsGlassEffect)
        XCTAssertFalse(LGMaterial.regular.needsGlassEffect)
        XCTAssertFalse(LGMaterial.thick.needsGlassEffect)
    }
}
