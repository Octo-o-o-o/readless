import SwiftUI
import Core
import UI

// MARK: - Content Format Detection

private enum ContentFormat {
    case plain, markdown, json
}

private func detectContentFormat(_ text: String) -> ContentFormat {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // JSON: try parsing
    if let data = trimmed.data(using: .utf8),
       (try? JSONSerialization.jsonObject(with: data)) != nil {
        return .json
    }
    // Markdown: check for common patterns (multiline matching)
    let mdPatterns = [
        "(?m)^#{1,6} ",       // headers
        "(?m)^[\\-\\*] ",     // unordered list
        "```",                 // code blocks
        "\\[.+\\]\\(.+\\)",   // links
        "(?m)^>\\s",          // blockquotes
        "\\*\\*.+\\*\\*",     // bold
    ]
    let matchCount = mdPatterns.filter {
        text.range(of: $0, options: .regularExpression) != nil
    }.count
    if matchCount >= 2 { return .markdown }
    return .plain
}

// MARK: - Original Content Panel

/// Unified right sidebar panel that displays original source text with
/// optional paragraph-level highlighting for source tracing.
struct OriginalContentPanel: View {
    let content: Content
    let paragraphs: [(anchorID: String, text: String)]
    /// When non-empty, only show matching paragraphs (trace mode).
    /// When empty, show full continuous text (view original mode).
    let filterAnchors: [String]
    @Binding var isPresented: Bool
    var onFullscreen: () -> Void

    @State private var showRawSource: Bool = false
    @State private var cachedFormat: ContentFormat = .plain
    @State private var cachedFullText: String?

    /// Whether we're in trace mode (showing specific paragraphs)
    private var isTraceMode: Bool { !filterAnchors.isEmpty }

    /// Reset raw source toggle when switching between trace/full text modes
    private func resetRawSourceIfNeeded() {
        if isTraceMode && showRawSource {
            showRawSource = false
        }
    }

    /// Paragraphs filtered by anchors in trace mode
    private var filteredParagraphs: [(anchorID: String, text: String)] {
        guard isTraceMode else { return paragraphs }
        return paragraphs.filter { filterAnchors.contains($0.anchorID) }
    }

    /// Recompute cached full text and its detected format
    private func updateCachedText() {
        let text: String?
        if !paragraphs.isEmpty {
            text = paragraphs.map(\.text).joined(separator: "\n\n")
        } else {
            text = content.fullText
        }
        cachedFullText = text
        if let text, !text.isEmpty {
            cachedFormat = detectContentFormat(text)
        } else {
            cachedFormat = .plain
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerBar

            Divider()

            // Content body
            let filtered = filteredParagraphs
            if isTraceMode {
                // Trace mode: show only matching paragraphs
                if !filtered.isEmpty {
                    paragraphListView(filtered)
                } else {
                    ContentUnavailableView(
                        "段落不可用",
                        systemImage: "doc.text",
                        description: Text("未找到对应段落。")
                    )
                }
            } else if let text = cachedFullText, !text.isEmpty {
                richTextView(text)
            } else {
                ContentUnavailableView(
                    "原文不可用",
                    systemImage: "doc.text",
                    description: Text("该内容的原文暂不可用。")
                )
            }
        }
        .frame(minWidth: 350, maxWidth: 450)
        .background(.ultraThinMaterial)
        .onAppear { updateCachedText() }
        .onChange(of: paragraphs.count) { _, _ in updateCachedText() }
        .onChange(of: filterAnchors) { _, _ in
            resetRawSourceIfNeeded()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: Theme.space8) {
            Text(isTraceMode ? "原文" : "原始文本")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            // Source/Preview toggle (only for markdown/json in full text mode)
            if !isTraceMode && cachedFormat != .plain {
                headerButton(
                    icon: showRawSource ? "doc.richtext" : "chevron.left.forwardslash.chevron.right",
                    tooltip: showRawSource ? "显示预览" : "显示源码"
                ) {
                    showRawSource.toggle()
                }
            }

            // Open in browser for URL types
            if content.sourceType == .url || content.sourceType == .rss,
               let urlString = content.sourceURL,
               let url = URL(string: urlString) {
                headerButton(icon: "safari", tooltip: "在浏览器中打开") {
                    NSWorkspace.shared.open(url)
                }
            }

            // Fullscreen
            headerButton(icon: "arrow.up.left.and.arrow.down.right", tooltip: "全屏查看") {
                onFullscreen()
            }

            // Copy
            headerButton(icon: "doc.on.doc", tooltip: "复制原文") {
                copyFullText()
            }

            // Export
            headerButton(icon: "square.and.arrow.up", tooltip: "导出") {
                exportFullText()
            }

            // Close
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.textTertiary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(Theme.space16)
    }

    @ViewBuilder
    private func headerButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusSmall)
                        .fill(Color.primary.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Paragraph List (trace mode)

    private func paragraphListView(_ items: [(anchorID: String, text: String)]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.space12) {
                sourceInfoBadge

                ForEach(items, id: \.anchorID) { para in
                    HStack(alignment: .top, spacing: Theme.space8) {
                        Text(para.anchorID)
                            .font(Theme.citationFont)
                            .foregroundStyle(Theme.citationColor)
                            .frame(width: 30, alignment: .trailing)

                        Text(para.text)
                            .font(Theme.l2Font)
                            .lineSpacing(Theme.l2LineSpacing)
                            .textSelection(.enabled)
                            .padding(Theme.space8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .id(para.anchorID)
                }
            }
            .padding(Theme.space16)
        }
    }

    // MARK: - Rich Text View (full text mode with format detection)

    @ViewBuilder
    private func richTextView(_ text: String) -> some View {
        let format = cachedFormat
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.space12) {
                sourceInfoBadge

                if showRawSource || format == .plain {
                    // Raw source / plain text
                    Text(text)
                        .font(format == .plain ? Theme.l2Font : .system(size: 12, design: .monospaced))
                        .lineSpacing(format == .plain ? Theme.l2LineSpacing : 4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if format == .markdown {
                    // Markdown preview
                    MarkdownPreview(text: text)
                } else if format == .json {
                    // JSON preview
                    JSONPreview(text: text)
                }
            }
            .padding(Theme.space16)
        }
    }

    // MARK: - Source Info Badge

    @ViewBuilder
    private var sourceInfoBadge: some View {
        HStack(spacing: Theme.space8) {
            HStack(spacing: Theme.space4) {
                Image(systemName: Theme.sourceTypeIcon(content.sourceType))
                    .font(.system(size: 10, weight: .medium))
                Text(sourceTypeLabel)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Theme.sourceTypeColor(content.sourceType))
            .padding(.horizontal, Theme.space8)
            .padding(.vertical, Theme.space4)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .fill(Theme.sourceTypeColor(content.sourceType).opacity(0.12))
            )

            if let url = content.sourceURL {
                Text(url)
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
    }

    private var sourceTypeLabel: String {
        switch content.sourceType {
        case .url, .rss: return "网页提取"
        case .pdf: return "PDF 提取"
        case .image: return "OCR 识别"
        case .text, .clipboard: return "原始文本"
        case .email: return "邮件文本"
        case .folderWatch: return "文件文本"
        }
    }

    // MARK: - Actions

    private func copyFullText() {
        let text: String
        if !paragraphs.isEmpty {
            text = paragraphs.map { "\($0.anchorID) \($0.text)" }.joined(separator: "\n\n")
        } else {
            text = content.fullText ?? ""
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportFullText() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(content.title).txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let text: String
            if !paragraphs.isEmpty {
                text = paragraphs.map { "\($0.anchorID) \($0.text)" }.joined(separator: "\n\n")
            } else {
                text = content.fullText ?? ""
            }
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Markdown Preview

private struct MarkdownPreview: View {
    let text: String

    @State private var cachedAttributedString: AttributedString?

    private static func parseMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let full = try? AttributedString(markdown: text) {
            return full
        }
        if let inline = try? AttributedString(markdown: text, options: options) {
            return inline
        }
        return AttributedString(text)
    }

    var body: some View {
        Text(cachedAttributedString ?? AttributedString(text))
            .font(.system(size: 13.5))
            .lineSpacing(6)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: text) {
                cachedAttributedString = Self.parseMarkdown(text)
            }
    }
}

// MARK: - JSON Preview

private struct JSONPreview: View {
    let text: String

    @State private var cachedColorizedJSON: AttributedString?

    private static let jsonTokenRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"("(?:[^"\\]|\\.)*")\s*:|("(?:[^"\\]|\\.)*")|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)|(\btrue\b|\bfalse\b)|(\bnull\b)"#
    )

    private static func colorize(_ text: String) -> AttributedString {
        guard let data = text.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: obj,
                  options: [.prettyPrinted, .sortedKeys]
              ),
              let prettyStr = String(data: pretty, encoding: .utf8)
        else {
            return AttributedString(text)
        }

        var result = AttributedString()
        let monoFont = Font.system(size: 12, design: .monospaced)
        let nsString = prettyStr as NSString
        var lastEnd = 0

        guard let regex = jsonTokenRegex else {
            var plain = AttributedString(prettyStr)
            plain.font = monoFont
            return plain
        }

        let matches = regex.matches(in: prettyStr, range: NSRange(location: 0, length: nsString.length))
        for match in matches {
            if match.range.location > lastEnd {
                let range = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                var part = AttributedString(nsString.substring(with: range))
                part.font = monoFont
                part.foregroundColor = .primary.opacity(0.7)
                result += part
            }

            let fullMatch = nsString.substring(with: match.range)

            if match.range(at: 1).location != NSNotFound {
                let keyRange = match.range(at: 1)
                let key = nsString.substring(with: keyRange)
                var keyPart = AttributedString(key)
                keyPart.font = monoFont
                keyPart.foregroundColor = Color.accentColor
                result += keyPart
                let suffixStart = keyRange.location + keyRange.length
                let suffixLen = match.range.location + match.range.length - suffixStart
                if suffixLen > 0 {
                    let suffix = nsString.substring(with: NSRange(location: suffixStart, length: suffixLen))
                    var suffixPart = AttributedString(suffix)
                    suffixPart.font = monoFont
                    suffixPart.foregroundColor = .primary.opacity(0.5)
                    result += suffixPart
                }
            } else if match.range(at: 2).location != NSNotFound {
                var part = AttributedString(fullMatch)
                part.font = monoFont
                part.foregroundColor = Color.green
                result += part
            } else if match.range(at: 3).location != NSNotFound || match.range(at: 4).location != NSNotFound {
                var part = AttributedString(fullMatch)
                part.font = monoFont
                part.foregroundColor = Color.orange
                result += part
            } else if match.range(at: 5).location != NSNotFound {
                var part = AttributedString(fullMatch)
                part.font = monoFont
                part.foregroundColor = .secondary
                result += part
            }

            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsString.length {
            var part = AttributedString(nsString.substring(from: lastEnd))
            part.font = monoFont
            part.foregroundColor = .primary.opacity(0.7)
            result += part
        }

        return result
    }

    var body: some View {
        Text(cachedColorizedJSON ?? AttributedString(text))
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: text) {
                cachedColorizedJSON = Self.colorize(text)
            }
    }
}
