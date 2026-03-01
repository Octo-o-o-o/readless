import SwiftUI

public struct LGTypography {
    // Font hierarchy (macOS HIG standard sizes)

    /// Large title style for top-level headings (26pt, Regular)
    public static let largeTitle = Font.system(size: 26, weight: .regular)

    /// Title 1 style for primary headings (22pt, Regular)
    public static let title1 = Font.system(size: 22, weight: .regular)

    /// Title 2 style for secondary headings (16pt, Regular)
    public static let title2 = Font.system(size: 16, weight: .regular)

    /// Title 3 style for tertiary headings (14pt, Regular)
    public static let title3 = Font.system(size: 14, weight: .regular)

    /// Headline style for prominent text (13pt, Semibold)
    public static let headline = Font.system(size: 13, weight: .semibold)

    /// Body style for standard content (13pt, Regular)
    public static let body = Font.system(size: 13, weight: .regular)

    /// Subheadline style for supporting text (11pt, Regular)
    public static let subheadline = Font.system(size: 11, weight: .regular)

    /// Callout style for secondary content (12pt, Regular)
    public static let callout = Font.system(size: 12, weight: .regular)

    /// Caption 1 style for small labels (10pt, Regular)
    public static let caption1 = Font.system(size: 10, weight: .regular)

    /// Caption 2 style for tiny labels (9pt, Regular)
    public static let caption2 = Font.system(size: 9, weight: .regular)

    /// Footnote style for fine print (10pt, Regular)
    public static let footnote = Font.system(size: 10, weight: .regular)

    // Special fonts

    /// Monospaced font for code snippets (13pt, Monospaced)
    public static let monospacedCode = Font.system(size: 13, weight: .regular, design: .monospaced)

    /// Monospaced font for numeric displays (13pt, Monospaced)
    public static let monospacedDigit = Font.system(size: 13, weight: .regular, design: .monospaced)

    // Line spacing (optimized for macOS readability)
    public struct LineSpacing {
        /// Line spacing for large titles (4pt)
        public static let largeTitle: CGFloat = 4

        /// Line spacing for titles (3pt)
        public static let title: CGFloat = 3

        /// Line spacing for body text (6pt)
        public static let body: CGFloat = 6

        /// Line spacing for callouts (4pt)
        public static let callout: CGFloat = 4
    }
}
