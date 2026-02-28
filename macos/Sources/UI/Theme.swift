import SwiftUI

// MARK: - Theme

public enum Theme {
    // MARK: Typography

    public static let titleFont: Font = .system(size: 24, weight: .bold)
    public static let l0Font: Font = .system(size: 20, weight: .semibold)
    public static let l1Font: Font = .system(size: 16, weight: .medium)
    public static let l2Font: Font = .system(size: 15, weight: .regular)
    public static let citationFont: Font = .system(size: 13, design: .monospaced)

    // MARK: Spacing

    public static let lineSpacing: CGFloat = 8

    // MARK: Colors

    public static let accent: Color = .blue
    public static let citationColor: Color = .secondary
    public static let focusBorder: Color = .blue.opacity(0.6)
    public static let surfacePrimary: Color = Color(nsColor: .windowBackgroundColor)
    public static let surfaceFloating: Color = Color(nsColor: .controlBackgroundColor)

    // MARK: Animations

    public static let snapAnimation: Animation = .snappy(duration: 0.35)
    public static let springAnimation: Animation = .spring(duration: 0.5, bounce: 0.2)
    public static let capsuleAppear: Animation = .spring(duration: 0.3, bounce: 0.15)
    public static let capsuleDismiss: Animation = .smooth(duration: 0.2)

    // MARK: Capsule Dimensions

    public static let capsuleWidth: CGFloat = 280
    public static let capsuleHeight: CGFloat = 48
    public static let cornerRadius: CGFloat = 24
}
