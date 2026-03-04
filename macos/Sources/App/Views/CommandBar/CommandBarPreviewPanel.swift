// macos/Sources/App/Views/CommandBar/CommandBarPreviewPanel.swift
import SwiftUI
import Core
import UI

struct CommandBarPreviewPanel: View {
    let content: Content?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space16) {
            if let content = content {
                // Header
                VStack(alignment: .leading, spacing: Theme.space6) {
                    Text(content.title)
                        .font(Theme.listTitleFont)
                        .lineLimit(2)

                    HStack(spacing: Theme.space4) {
                        Image(systemName: Theme.sourceTypeIcon(content.sourceType))
                            .font(.system(size: 10))
                        Text(content.sourceType.rawValue)
                            .font(Theme.captionFont)
                    }
                    .foregroundStyle(Theme.sourceTypeColor(content.sourceType))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Content: \(content.title)")
                .accessibilityValue("Type: \(content.sourceType.rawValue)")

                Divider()

                // Content preview
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.space12) {
                        if let l0 = content.l0Summary {
                            VStack(alignment: .leading, spacing: Theme.space4) {
                                Text("Summary")
                                    .font(Theme.captionFont)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(l0)
                                    .font(Theme.l2Font)
                                    .lineSpacing(Theme.l2LineSpacing)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Summary: \(l0)")
                        }

                        if let outline = content.l1Outline, !outline.isEmpty {
                            VStack(alignment: .leading, spacing: Theme.space4) {
                                Text("Outline")
                                    .font(Theme.captionFont)
                                    .foregroundStyle(Theme.textSecondary)
                                ForEach(outline.prefix(5)) { point in
                                    Text("• \(point.point)")
                                        .font(Theme.captionFont)
                                }
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Outline with \(min(outline.count, 5)) points")
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Content preview")

                Divider()

                // Quick actions
                HStack(spacing: Theme.space8) {
                    Button("Import") {
                        // Action handled by parent
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Import content")

                    Button("Share") {
                        // Action handled by parent
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Share content")
                }
            } else {
                ContentUnavailableView(
                    "No Preview",
                    systemImage: "doc.text",
                    description: Text("Select a result to see preview")
                )
                .accessibilityLabel("No preview available")
                .accessibilityHint("Select a result to see preview")
            }
        }
        .padding(Theme.space16)
        .frame(width: 300)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview panel")
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
