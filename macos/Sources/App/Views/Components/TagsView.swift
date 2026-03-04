import SwiftUI
import UI

/// Display and manage tags for a content item
struct TagsView: View {
    let tags: [String]
    let availableTags: [String]
    let onAdd: (String) async -> Void
    let onRemove: (String) async -> Void

    @State private var showingTagPicker = false
    @State private var newTagName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space6) {
            FlowLayout(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(text: tag) {
                        Task {
                            await onRemove(tag)
                        }
                    }
                }

                // Dashed add button
                Button {
                    showingTagPicker = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Tag")
                            .font(Theme.captionFont)
                    }
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .strokeBorder(
                                Theme.borderSubtle,
                                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .popover(isPresented: $showingTagPicker) {
            TagPickerView(
                availableTags: availableTags.filter { !tags.contains($0) },
                newTagName: $newTagName,
                onSelect: { tag in
                    Task {
                        await onAdd(tag)
                        showingTagPicker = false
                    }
                },
                onCreateNew: {
                    Task {
                        await onAdd(newTagName)
                        newTagName = ""
                        showingTagPicker = false
                    }
                }
            )
            .frame(width: 250, height: 300)
        }
    }
}

/// Popover for selecting or creating tags
struct TagPickerView: View {
    let availableTags: [String]
    @Binding var newTagName: String
    let onSelect: (String) -> Void
    let onCreateNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space12) {
            Text("Add Tag")
                .font(.system(size: 14, weight: .semibold))

            HStack {
                TextField("New tag name", text: $newTagName)
                    .textFieldStyle(.roundedBorder)

                Button("Create") {
                    onCreateNew()
                }
                .disabled(newTagName.isEmpty)
            }

            Divider()

            Text("Or select existing:")
                .font(Theme.captionFont)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.space4) {
                    ForEach(availableTags, id: \.self) { tag in
                        Button {
                            onSelect(tag)
                        } label: {
                            HStack(spacing: Theme.space8) {
                                Image(systemName: "tag")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.accent.opacity(0.7))
                                Text(tag)
                                    .font(Theme.metaFont)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, Theme.space4)
                    }

                    if availableTags.isEmpty {
                        Text("No available tags")
                            .foregroundStyle(.secondary)
                            .font(Theme.captionFont)
                            .italic()
                    }
                }
            }
        }
        .padding()
    }
}

/// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
