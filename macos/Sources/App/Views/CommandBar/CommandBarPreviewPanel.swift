// macos/Sources/App/Views/CommandBar/CommandBarPreviewPanel.swift
import SwiftUI
import Core

struct CommandBarPreviewPanel: View {
    let content: Content?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let content = content {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(content.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text(content.sourceType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // Content preview
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let l0 = content.l0Summary {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Summary")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(l0)
                                    .font(.body)
                            }
                        }

                        if let outline = content.l1Outline, !outline.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Outline")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(outline.prefix(5)) { point in
                                    Text("• \(point.point)")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

                Divider()

                // Quick actions
                HStack(spacing: 8) {
                    Button("Import") {
                        // Action handled by parent
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Share") {
                        // Action handled by parent
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ContentUnavailableView(
                    "No Preview",
                    systemImage: "doc.text",
                    description: Text("Select a result to see preview")
                )
            }
        }
        .padding()
        .frame(width: 300)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Preview

#Preview {
    CommandBarPreviewPanel(
        content: Content(
            id: "test",
            title: "Example Article",
            sourceType: .url,
            l0Summary: "A comprehensive guide to Swift programming.",
            l1Outline: [
                .init(point: "Introduction to Swift"),
                .init(point: "Basic syntax and features"),
                .init(point: "Advanced topics")
            ]
        )
    )
    .frame(height: 500)
}
