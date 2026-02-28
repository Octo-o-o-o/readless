import SwiftUI
import Core
import UI

// MARK: - Outline View

struct OutlineView: View {
    let points: [OutlinePoint]
    @Binding var focusedIndex: Int
    let expandedDetails: [Int: String]
    let onExpand: (Int) -> Void
    let onTrace: ([String]) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        OutlinePointRow(
                            point: point,
                            index: index,
                            isFocused: index == focusedIndex,
                            expandedDetail: expandedDetails[index],
                            onExpand: { onExpand(index) },
                            onTrace: { onTrace(point.anchors) }
                        )
                        .id(index)
                    }
                }
                .padding()
            }
            .onChange(of: focusedIndex) { _, newIndex in
                withAnimation(Theme.snapAnimation) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }
}

// MARK: - Outline Point Row

struct OutlinePointRow: View {
    let point: OutlinePoint
    let index: Int
    let isFocused: Bool
    let expandedDetail: String?
    let onExpand: () -> Void
    let onTrace: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                // Focus indicator bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(isFocused ? Theme.focusBorder : .clear)
                    .frame(width: 3)
                    .animation(Theme.snapAnimation, value: isFocused)

                VStack(alignment: .leading, spacing: 4) {
                    // L1 point text
                    Text("\(index + 1). \(point.point)")
                        .font(Theme.l1Font)
                        .foregroundStyle(isFocused ? .primary : .secondary)

                    // Anchor citations (e.g. [P1], [P2])
                    if !point.anchors.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(point.anchors, id: \.self) { anchor in
                                Button(anchor) { onTrace() }
                                    .font(Theme.citationFont)
                                    .foregroundStyle(Theme.citationColor)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Spacer()

                // Expand/collapse chevron
                Image(systemName: expandedDetail != nil ? "chevron.down" : "chevron.right")
                    .foregroundStyle(.tertiary)
            }

            // L2 expanded detail
            if let detail = expandedDetail {
                Text(detail)
                    .font(Theme.l2Font)
                    .foregroundStyle(.secondary)
                    .lineSpacing(Theme.lineSpacing)
                    .padding(.leading, 16)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isFocused ? Color.primary.opacity(0.05) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onExpand() }
    }
}
