// macos/Sources/App/Views/CommandBar/CommandBarResultsList.swift
import SwiftUI
import AIServices
import UI

struct CommandResultRow: View {
    let result: CommandResult
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.space12) {
            // Icon
            Image(systemName: result.icon)
                .font(.title3)
                .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)

            // Title and subtitle
            VStack(alignment: .leading, spacing: Theme.space2) {
                Text(result.title)
                    .font(Theme.listTitleFont)
                    .foregroundStyle(Theme.textPrimary)

                if let subtitle = result.subtitle {
                    Text(subtitle)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, Theme.space12)
        .padding(.vertical, Theme.space8)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .fill(isSelected ? Theme.accentSubtle : Color.clear)
        )
        .scaleEffect(isSelected && !reduceMotion ? 1.02 : 1.0)
        .animation(reduceMotion ? .none : .spring(response: 0.2, dampingFraction: 0.8), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(result.title)
        .accessibilityValue(result.subtitle ?? "")
        .accessibilityHint(isSelected ? "Selected. Press Enter to execute" : "Press up or down arrows to select")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

struct CommandBarResultsList: View {
    let results: [CommandResult]
    let selectedIndex: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVStack(spacing: Theme.space4) {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                CommandResultRow(result: result, isSelected: index == selectedIndex)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, Theme.space8)
        .padding(.vertical, Theme.space8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command results")
        .accessibilityValue("\(results.count) results")
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
