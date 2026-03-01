import SwiftUI

/// Display and manage tags for a content item
struct TagsView: View {
    let tags: [String]
    let availableTags: [String]
    let onAdd: (String) async -> Void
    let onRemove: (String) async -> Void

    @State private var showingTagPicker = false
    @State private var newTagName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Display existing tags
            FlowLayout(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    TagChip(text: tag) {
                        Task {
                            await onRemove(tag)
                        }
                    }
                }

                // Add button
                Button {
                    showingTagPicker = true
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Tag")
                .font(.headline)

            // Create new tag
            HStack {
                TextField("New tag name", text: $newTagName)
                    .textFieldStyle(.roundedBorder)

                Button("Create") {
                    onCreateNew()
                }
                .disabled(newTagName.isEmpty)
            }

            Divider()

            // Select existing tag
            Text("Or select existing:")
                .font(.caption)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(availableTags, id: \.self) { tag in
                        Button {
                            onSelect(tag)
                        } label: {
                            HStack {
                                Image(systemName: "tag")
                                Text(tag)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }

                    if availableTags.isEmpty {
                        Text("No available tags")
                            .foregroundStyle(.secondary)
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
    var spacing: CGFloat = 8

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
