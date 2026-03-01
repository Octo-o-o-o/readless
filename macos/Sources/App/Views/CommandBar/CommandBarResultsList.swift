// macos/Sources/App/Views/CommandBar/CommandBarResultsList.swift
import SwiftUI
import AIServices

struct CommandResultRow: View {
    let result: CommandResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: result.icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Title and subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
    }
}

struct CommandBarResultsList: View {
    let results: [CommandResult]
    let selectedIndex: Int

    var body: some View {
        LazyVStack(spacing: 4) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                CommandResultRow(result: result, isSelected: index == selectedIndex)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var coordinator = AICoordinator()

    CommandBarResultsList(
        results: [
            .init(title: "Import from clipboard", subtitle: "⌘V", icon: "doc.text") {},
            .init(title: "Search all content", subtitle: "⌘F", icon: "magnifyingglass") {},
            .init(title: "Generate podcast", subtitle: "⌘P", icon: "mic") {}
        ],
        selectedIndex: 1
    )
    .frame(width: 600)
    .padding()
}
