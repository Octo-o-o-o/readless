import SwiftUI

public struct LGTypography {
    // Font hierarchy
    public static let largeTitle = Font.system(size: 34, weight: .bold)
    public static let title1 = Font.system(size: 28, weight: .bold)
    public static let title2 = Font.system(size: 22, weight: .bold)
    public static let headline = Font.system(size: 17, weight: .semibold)
    public static let body = Font.system(size: 15, weight: .regular)
    public static let callout = Font.system(size: 13, weight: .regular)
    public static let caption1 = Font.system(size: 12, weight: .medium)
    public static let caption2 = Font.system(size: 11, weight: .medium)

    // Special fonts
    public static let monospacedCode = Font.system(size: 13, weight: .regular, design: .monospaced)
    public static let monospacedDigit = Font.system(size: 15, weight: .regular, design: .monospaced)

    // Line spacing
    public struct LineSpacing {
        public static let largeTitle: CGFloat = 2
        public static let title: CGFloat = 2
        public static let body: CGFloat = 6
        public static let callout: CGFloat = 4
    }
}
