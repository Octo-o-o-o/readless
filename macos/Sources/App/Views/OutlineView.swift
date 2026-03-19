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
        LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                OutlinePointRow(
                    point: point,
                    index: index,
                    isFocused: index == viewModel.focusedIndex,
                    expandedDetail: viewModel.expandedDetails[index],
                    isLoading: viewModel.loadingExpandIndices.contains(index),
                    onExpand: { onExpand(index) },
                    onTrace: { anchors in onTrace(anchors) }
                )
                .id(index)
            }
        }
        .padding(.horizontal, Theme.space20)
        .padding(.vertical, Theme.space16)
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
    let onTrace: ([String]) -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.space6) {
            // L1 header — tappable to expand/collapse
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
                                    onTrace(point.anchors)
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

                // Loading spinner or expand/collapse chevron
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                        .padding(.top, 2)
                } else {
                    Button {
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
            .contentShape(Rectangle())
            .onTapGesture {
                onExpand()
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
                DetailTextView(text: detail, onCitationTap: { anchor in onTrace([anchor]) })
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

// MARK: - Detail Text View

/// Renders L2 detail text with clickable [¶N] citation markers.
/// Strips markdown headers (##) and bold (**) for clean display.
private struct DetailTextView: View {
    let text: String
    let onCitationTap: (String) -> Void

    @State private var cachedAttributedText: AttributedString?

    private nonisolated static func buildAttributedText(from text: String) -> AttributedString {
        let segments = parseSegments(text)
        var attrString = AttributedString()
        for segment in segments {
            switch segment {
            case .plain(let str):
                var part = AttributedString(str)
                part.font = .system(size: 13.5, weight: .regular)
                part.foregroundColor = .primary.opacity(0.7)
                attrString += part
            case .citation(let marker):
                let digits = marker.filter { $0.isNumber }
                var part = AttributedString(" \(marker) ")
                part.font = .system(size: 10, weight: .medium, design: .rounded)
                part.foregroundColor = Theme.accent
                part.link = URL(string: "readless://trace/\(digits)")
                attrString += part
            }
        }
        return attrString
    }

    var body: some View {
        Text(cachedAttributedText ?? AttributedString(text))
            .task(id: text) {
                let rendered = await Task.detached(priority: .utility) {
                    Self.buildAttributedText(from: text)
                }.value
                guard !Task.isCancelled else { return }
                cachedAttributedText = rendered
            }
            .lineSpacing(6)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "readless",
                   url.host == "trace",
                   let number = url.pathComponents.last {
                    onCitationTap("¶\(number)")
                    return .handled
                }
                return .systemAction
            })
    }

    // MARK: - Parsing

    enum Segment {
        case plain(String)
        case citation(String)
    }

    private nonisolated static func makeCitationRegex() -> NSRegularExpression? {
        try? NSRegularExpression(pattern: #"\[¶\d+\]"#)
    }

    /// Parse detail text into plain text and [¶N] citations.
    /// Also strips markdown headers and bold markers for clean display.
    private nonisolated static func parseSegments(_ text: String) -> [Segment] {
        // Clean markdown: strip ## headers and ** bold markers
        var cleaned = text
        // Remove markdown headers (## text → text)
        cleaned = cleaned.replacingOccurrences(
            of: #"^#{1,3}\s*"#,
            with: "",
            options: .regularExpression
        )
        // Handle multiline headers
        cleaned = cleaned.replacingOccurrences(
            of: #"\n#{1,3}\s*"#,
            with: "\n",
            options: .regularExpression
        )
        // Remove bold markers
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        // Trim leading/trailing whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        var segments: [Segment] = []
        guard let regex = makeCitationRegex() else {
            return [.plain(cleaned)]
        }

        let nsString = cleaned as NSString
        var lastEnd = 0

        let matches = regex.matches(in: cleaned, range: NSRange(location: 0, length: nsString.length))
        for match in matches {
            // Add plain text before the citation
            if match.range.location > lastEnd {
                let plainRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                segments.append(.plain(nsString.substring(with: plainRange)))
            }
            // Add the citation marker
            let citation = nsString.substring(with: match.range)
            segments.append(.citation(citation))
            lastEnd = match.range.location + match.range.length
        }

        // Add remaining plain text
        if lastEnd < nsString.length {
            segments.append(.plain(nsString.substring(from: lastEnd)))
        }

        return segments
    }
}
