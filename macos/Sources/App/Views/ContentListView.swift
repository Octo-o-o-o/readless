import SwiftUI
import Core

// MARK: - Content List View

/// A sidebar list displaying all imported content items with title, summary,
/// source type badge, and relative timestamp.
struct ContentListView: View {
    let contents: [Content]
    @Binding var selectedID: String?

    var body: some View {
        List(contents, selection: $selectedID) { content in
            VStack(alignment: .leading, spacing: 4) {
                Text(content.title)
                    .font(.headline)
                    .lineLimit(1)

                if let summary = content.l0Summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Text(content.sourceType.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.quaternary))

                    if let appName = content.sourceAppName {
                        Text(appName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Text(content.createdAt.relativeFormatted())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
            .tag(content.id)
        }
    }
}
