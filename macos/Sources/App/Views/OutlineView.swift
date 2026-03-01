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

    @State private var isHovering = false

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
                            Text("Source: ")
                                .font(Theme.citationFont)
                                .foregroundStyle(.tertiary)

                            ForEach(point.anchors, id: \.self) { anchor in
                                Button {
                                    onTrace()
                                } label: {
                                    Text(anchor)
                                        .font(Theme.citationFont)
                                        .foregroundStyle(Theme.citationColor)
                                        .underline()
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    if hovering {
                                        NSCursor.pointingHand.push()
                                    } else {
                                        NSCursor.pop()
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Expand/collapse chevron
                Image(systemName: expandedDetail != nil ? "chevron.down" : "chevron.right")
                    .foregroundStyle(isHovering ? .primary : .tertiary)
                    .imageScale(.small)
                    .animation(Theme.snapAnimation, value: expandedDetail != nil)
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
                .fill(
                    isFocused
                        ? Color.primary.opacity(0.08)
                        : isHovering
                            ? Color.primary.opacity(0.04)
                            : .clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isHovering ? Color.primary.opacity(0.1) : .clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { onExpand() }
        .onHover { hovering in
            withAnimation(Theme.snapAnimation) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
