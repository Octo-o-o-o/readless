import SwiftUI
import Core
import UI

// MARK: - Outline View

struct OutlineView: View {
    let points: [OutlinePoint]
    @Bindable var viewModel: ReaderViewModel
    let onExpand: (Int) -> Void
    let onTrace: ([String]) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                        OutlinePointRow(
                            point: point,
                            index: index,
                            isFocused: index == viewModel.focusedIndex,
                            expandedDetail: viewModel.expandedDetails[index],
                            isLoading: viewModel.loadingExpandIndices.contains(index),
                            onExpand: { onExpand(index) },
                            onTrace: { onTrace(point.anchors) }
                        )
                        .id(index)
                    }
                }
                .padding(.horizontal, Theme.space20)
                .padding(.vertical, Theme.space16)
                .id(viewModel.expandStateVersion)
            }
            .onChange(of: viewModel.focusedIndex) { _, newIndex in
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
    let isLoading: Bool
    let onExpand: () -> Void
    let onTrace: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space6) {
            HStack(alignment: .top, spacing: 0) {
                // Focus indicator bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(isFocused ? Theme.accent : Color.primary.opacity(0.08))
                    .frame(width: 3, height: isFocused ? nil : 20)
                    .animation(Theme.snapAnimation, value: isFocused)

                VStack(alignment: .leading, spacing: Theme.space6) {
                    // L1 point text — always readable, focused = bolder
                    Text("\(index + 1). \(point.point)")
                        .font(.system(size: 14.5, weight: isFocused ? .semibold : .regular))
                        .lineSpacing(4)
                        .foregroundStyle(isFocused ? Color.primary : Color.primary.opacity(0.78))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Anchor citation pills
                    if !point.anchors.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(point.anchors, id: \.self) { anchor in
                                Button {
                                    onTrace()
                                } label: {
                                    Text(anchor)
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(isFocused ? Theme.accent : .secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(isFocused ? Theme.accent.opacity(0.1) : Color.primary.opacity(0.04))
                                        )
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
                .padding(.leading, Theme.space8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    print("[OutlineView] Content area tapped index=\(index)")
                    onExpand()
                }

                // Loading spinner or expand/collapse chevron
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                        .padding(.top, 2)
                } else {
                    Button {
                        print("[OutlineView] Chevron tapped index=\(index)")
                        onExpand()
                    } label: {
                        Image(systemName: expandedDetail != nil ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isFocused ? Theme.accent : (isHovering ? Color.secondary : Color.primary.opacity(0.2)))
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(isFocused ? Theme.accent.opacity(0.08) : (isHovering ? Color.primary.opacity(0.04) : .clear))
                            )
                            .animation(Theme.snapAnimation, value: expandedDetail != nil)
                            .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                }
            }

            // L2 expanded detail or loading placeholder
            if isLoading && expandedDetail == nil {
                HStack(spacing: Theme.space8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading details...")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                .padding(.leading, 11)
                .padding(.top, Theme.space4)
                .transition(.opacity)
            } else if let detail = expandedDetail {
                Text(detail)
                    .font(.system(size: 13.5, weight: .regular))
                    .foregroundStyle(.primary.opacity(0.7))
                    .lineSpacing(6)
                    .padding(.leading, 11)
                    .padding(.top, Theme.space4)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, Theme.space12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isFocused
                        ? Theme.accent.opacity(0.06)
                        : isHovering
                            ? Color.primary.opacity(0.03)
                            : .clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isFocused ? Theme.accent.opacity(0.15) :
                    isHovering ? Color.primary.opacity(0.06) : .clear,
                    lineWidth: 1
                )
        )
        .animation(Theme.expandAnimation, value: expandedDetail != nil)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(Theme.hoverAnimation) {
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
