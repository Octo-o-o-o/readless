import SwiftUI
import UI

/// A single tag chip with optional remove button
struct TagChip: View {
    let text: String
    let onRemove: (() -> Void)?

    init(text: String, onRemove: (() -> Void)? = nil) {
        self.text = text
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(text)
                .font(Theme.captionFont)
                .foregroundStyle(Theme.tagText)

            if let onRemove {
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .fill(Theme.tagBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(Theme.tagBorder, lineWidth: 0.5)
        )
    }
}
