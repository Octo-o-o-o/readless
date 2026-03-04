import SwiftUI
import Core

// MARK: - Theme

public enum Theme {

    // MARK: - Typography

    /// Display — reader title only
    public static let titleFont: Font = .system(size: 26, weight: .bold)
    public static let titleLineSpacing: CGFloat = 6

    /// L0 summary — prominent but secondary to title
    public static let l0Font: Font = .system(size: 17, weight: .regular)
    public static let l0LineSpacing: CGFloat = 5

    /// L1 outline points — readable at scanning speed
    public static let l1Font: Font = .system(size: 15, weight: .medium)
    public static let l1LineSpacing: CGFloat = 4

    /// L2 expanded detail — comfortable long-form reading
    public static let l2Font: Font = .system(size: 14, weight: .regular)
    public static let l2LineSpacing: CGFloat = 6

    /// Citations and metadata
    public static let citationFont: Font = .system(size: 11, weight: .medium, design: .rounded)
    public static let metaFont: Font = .system(size: 12, weight: .regular)
    public static let captionFont: Font = .system(size: 11, weight: .regular)

    /// Content list
    public static let listTitleFont: Font = .system(size: 13, weight: .semibold)
    public static let listSummaryFont: Font = .system(size: 12, weight: .regular)

    // MARK: - Spacing (4pt grid)

    public static let space2: CGFloat = 2
    public static let space4: CGFloat = 4
    public static let space6: CGFloat = 6
    public static let space8: CGFloat = 8
    public static let space12: CGFloat = 12
    public static let space16: CGFloat = 16
    public static let space20: CGFloat = 20
    public static let space24: CGFloat = 24
    public static let space32: CGFloat = 32
    public static let space40: CGFloat = 40
    public static let space48: CGFloat = 48

    // MARK: - Corner Radius

    public static let radiusSmall: CGFloat = 6
    public static let radiusMedium: CGFloat = 10
    public static let radiusLarge: CGFloat = 14
    public static let radiusCapsule: CGFloat = 100

    // MARK: - Colors

    /// Accent — refined blue
    public static let accent: Color = Color(red: 0.25, green: 0.47, blue: 0.96)
    public static let accentSubtle: Color = accent.opacity(0.1)
    public static let accentMuted: Color = accent.opacity(0.06)

    /// Text hierarchy
    public static let textPrimary: Color = .primary
    public static let textSecondary: Color = .secondary
    public static let textTertiary: Color = Color.primary.opacity(0.35)

    /// Surfaces
    public static let surfacePrimary: Color = Color(nsColor: .windowBackgroundColor)
    public static let surfaceFloating: Color = Color(nsColor: .controlBackgroundColor)
    public static let surfaceHover: Color = Color.primary.opacity(0.04)
    public static let surfaceSelected: Color = Color.primary.opacity(0.08)
    public static let surfaceFocused: Color = accent.opacity(0.08)

    /// Borders
    public static let borderSubtle: Color = Color.primary.opacity(0.06)
    public static let borderMedium: Color = Color.primary.opacity(0.1)
    public static let borderFocused: Color = accent.opacity(0.5)

    /// Citation
    public static let citationColor: Color = Color.primary.opacity(0.55)
    public static let citationBg: Color = Color.primary.opacity(0.05)
    public static let citationHoverBg: Color = accent.opacity(0.1)

    /// Source type colors
    public static let sourceURL: Color = Color(red: 0.25, green: 0.47, blue: 0.96)
    public static let sourcePDF: Color = Color(red: 0.91, green: 0.30, blue: 0.24)
    public static let sourceText: Color = Color(red: 0.30, green: 0.69, blue: 0.31)
    public static let sourceImage: Color = Color(red: 0.61, green: 0.35, blue: 0.85)
    public static let sourceClipboard: Color = Color(red: 0.96, green: 0.65, blue: 0.14)
    public static let sourceDefault: Color = .secondary

    /// Tags
    public static let tagBg: Color = Color.primary.opacity(0.05)
    public static let tagText: Color = Color.primary.opacity(0.65)
    public static let tagBorder: Color = Color.primary.opacity(0.08)

    /// Highlight (source trace)
    public static let highlightBg: Color = Color(red: 1.0, green: 0.87, blue: 0.34).opacity(0.2)
    public static let highlightBorder: Color = accent.opacity(0.2)

    /// Legacy alias
    public static let focusBorder: Color = borderFocused
    public static let lineSpacing: CGFloat = 8

    // MARK: - Animations

    public static let snapAnimation: Animation = .snappy(duration: 0.3)
    public static let springAnimation: Animation = .spring(duration: 0.45, bounce: 0.15)
    public static let capsuleAppear: Animation = .spring(duration: 0.3, bounce: 0.15)
    public static let capsuleDismiss: Animation = .smooth(duration: 0.2)
    public static let hoverAnimation: Animation = .easeInOut(duration: 0.15)
    public static let expandAnimation: Animation = .spring(duration: 0.4, bounce: 0.1)

    // MARK: - Capsule Dimensions

    public static let capsuleWidth: CGFloat = 280
    public static let capsuleHeight: CGFloat = 48
    public static let cornerRadius: CGFloat = 24

    // MARK: - Source Type Helpers

    public static func sourceTypeColor(_ type: SourceType) -> Color {
        switch type {
        case .url, .rss:       return sourceURL
        case .pdf:             return sourcePDF
        case .text, .email:    return sourceText
        case .image:           return sourceImage
        case .clipboard:       return sourceClipboard
        case .folderWatch:     return sourceDefault
        }
    }

    public static func sourceTypeIcon(_ type: SourceType) -> String {
        switch type {
        case .url:          return "globe"
        case .pdf:          return "doc.richtext"
        case .text:         return "doc.text"
        case .image:        return "photo"
        case .clipboard:    return "doc.on.clipboard"
        case .folderWatch:  return "folder"
        case .email:        return "envelope"
        case .rss:          return "dot.radiowaves.up.forward"
        }
    }
}
