import SwiftUI
import Core
import UI

// MARK: - Content List View

/// A sidebar list displaying all imported content items with title, summary,
/// source type badge, and relative timestamp.
struct ContentListView: View {
    let contents: [Content]
    @Binding var selectedID: String?

    var body: some View {
        List(contents, selection: $selectedID) { content in
            VStack(alignment: .leading, spacing: 6) {
                // Title — slightly larger, bolder
                Text(content.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                // L0 summary
                if let summary = content.l0Summary {
                    Text(summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .lineSpacing(1)
                }

                // Metadata row
                HStack(spacing: 6) {
                    // Source type pill with icon and color
                    HStack(spacing: 3) {
                        Image(systemName: Theme.sourceTypeIcon(content.sourceType))
                            .font(.system(size: 8, weight: .medium))
                        Text(content.sourceType.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Theme.sourceTypeColor(content.sourceType))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Theme.sourceTypeColor(content.sourceType).opacity(0.12))
                    )

                    if let appName = content.sourceAppName {
                        Text(appName)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(content.createdAt, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .tag(content.id)
        }
    }
}
