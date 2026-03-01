import SwiftUI

public enum LGMaterial {
    case liquidGlassRegular
    case liquidGlassClear
    case ultraThin
    case thin
    case regular
    case thick

    public var material: Material {
        switch self {
        case .liquidGlassRegular, .liquidGlassClear:
            return .ultraThinMaterial
        case .ultraThin:
            return .ultraThinMaterial
        case .thin:
            return .thinMaterial
        case .regular:
            return .regularMaterial
        case .thick:
            return .thickMaterial
        }
    }

    public var needsGlassEffect: Bool {
        switch self {
        case .liquidGlassRegular, .liquidGlassClear:
            return true
        default:
            return false
        }
    }
}
