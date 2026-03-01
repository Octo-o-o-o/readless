// macos/Sources/LiquidGlassKit/Colors/LGColor.swift
import SwiftUI
import AppKit

public enum LGColor {
    // Vibrant Labels (for Liquid Glass)
    case vibrantLabel
    case vibrantSecondaryLabel
    case vibrantTertiaryLabel

    // Vibrant Fills (for Liquid Glass)
    case vibrantFill
    case vibrantSecondaryFill
    case vibrantTertiaryFill

    // Vibrant Separator
    case vibrantSeparator

    // Semantic Colors (auto dark mode)
    case accent
    case label
    case secondaryLabel
    case tertiaryLabel
    case quaternaryLabel

    public var color: Color {
        switch self {
        case .vibrantLabel:
            return Color(nsColor: .labelColor)
        case .vibrantSecondaryLabel:
            return Color(nsColor: .secondaryLabelColor)
        case .vibrantTertiaryLabel:
            return Color(nsColor: .tertiaryLabelColor)
        case .vibrantFill:
            return Color(nsColor: .controlColor)
        case .vibrantSecondaryFill:
            return Color(nsColor: .controlBackgroundColor)
        case .vibrantTertiaryFill:
            return Color(nsColor: .textBackgroundColor)
        case .vibrantSeparator:
            return Color(nsColor: .separatorColor)
        case .accent:
            return Color.accentColor
        case .label:
            return Color(nsColor: .labelColor)
        case .secondaryLabel:
            return Color(nsColor: .secondaryLabelColor)
        case .tertiaryLabel:
            return Color(nsColor: .tertiaryLabelColor)
        case .quaternaryLabel:
            return Color(nsColor: .quaternaryLabelColor)
        }
    }

    /// Create dynamic color that adapts to dark mode
    public static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }))
    }
}
