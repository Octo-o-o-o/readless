import SwiftUI
import Core
import UI
import Networking

// MARK: - Reader View

/// The main reader view displaying multi-level summaries with source tracing.
///
/// Layout:
///  - L0: One-line summary at the top
///  - L1: Outline points with anchor citations (keyboard navigable with j/k)
///  - L2: Expandable detail for each point (Enter/Return to toggle)
///  - Source trace panel: Right sidebar showing original paragraphs
///  - L3: Follow-up Q&A via Cmd+K (placeholder)
struct ReaderView: View {
    @State private var viewModel = ReaderViewModel()
    @AppStorage("targetLanguage") private var targetLanguage = "auto"
    @Environment(TagManager.self) private var tagManager
    @State private var isHoveringOriginal = false
    @State private var showFullscreenSheet = false
    @State private var isWideEnough = false
    let contentID: String

    var body: some View {
        HStack(spacing: 0) {
            // Main content area (left) — fills all remaining space
            mainContentPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)

            // Right panel area
            if viewModel.showOriginalPanel, let original = viewModel.content {
                Divider()
                OriginalContentPanel(
                    content: original,
                    paragraphs: viewModel.paragraphs,
                    filterAnchors: viewModel.sourceAnchors,
                    isPresented: $viewModel.showOriginalPanel,
                    onFullscreen: { showFullscreenSheet = true }
                )
            } else if isWideEnough, viewModel.content?.l1Outline != nil {
                Divider()
                // Placeholder — reserve space so layout doesn't jump
                VStack {
                    Spacer()
                    Image(systemName: "text.quote")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.textTertiary.opacity(0.4))
                    Text("点击引用查看原文")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary.opacity(0.5))
                    Spacer()
                }
                .frame(width: 350)
                .background(.ultraThinMaterial)
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width >= 850
        } action: { wide in
            if wide != isWideEnough { isWideEnough = wide }
        }
        .onKeyPress(.downArrow) { viewModel.moveDown(); return .handled }
        .onKeyPress(.upArrow) { viewModel.moveUp(); return .handled }
        .onKeyPress("j") { viewModel.moveDown(); return .handled }
        .onKeyPress("k") { viewModel.moveUp(); return .handled }
        .onKeyPress(.return) {
            Task { await viewModel.expandPoint(at: viewModel.focusedIndex) }
            return .handled
        }
        .task(id: contentID) {
            // Load content first (drives the UI), then paragraphs in parallel
            await viewModel.loadContent(contentID: contentID)
            await viewModel.loadParagraphs(contentID: contentID)

            if shouldAutoTranslate {
                await viewModel.loadTranslation(targetLanguage: targetLanguage)
            }
        }
        .sheet(isPresented: $showFullscreenSheet) {
            fullscreenOriginalView
        }
    }

    private var shouldAutoTranslate: Bool {
        guard targetLanguage != "auto" else { return false }
        guard let sourceLanguage = viewModel.content?.sourceLanguage else { return false }
        return sourceLanguage != targetLanguage
    }

    // MARK: - Main Content Panel

    @ViewBuilder
    private var mainContentPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let baseContent = viewModel.content {
                // Language toggle toolbar (only show if translation available or loading)
                if viewModel.hasTranslation || viewModel.isLoadingTranslation {
                    languageToolbar
                    Divider()
                }

                // Main content display
                // Use displayedContent with fallback to content to avoid blank state
                // when showingTranslation is briefly true but translatedContent is nil
                let content = viewModel.displayedContent ?? baseContent

                // L0 header: title + one-line summary + metadata
                VStack(alignment: .leading, spacing: Theme.space12) {
                    // Source type & timestamp row
                    if let originalContent = viewModel.content {
                        HStack(spacing: Theme.space8) {
                            HStack(spacing: Theme.space4) {
                                Image(systemName: Theme.sourceTypeIcon(originalContent.sourceType))
                                    .font(.system(size: 10, weight: .medium))
                                Text(originalContent.sourceType.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .tracking(0.5)
                            }
                            .foregroundStyle(Theme.sourceTypeColor(originalContent.sourceType))
                            .padding(.horizontal, Theme.space8)
                            .padding(.vertical, Theme.space4)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                    .fill(Theme.sourceTypeColor(originalContent.sourceType).opacity(0.12))
                            )

                            Text(originalContent.createdAt, style: .relative)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)

                            Spacer()
                        }
                    }

                    // Title + View Original button
                    HStack(alignment: .top, spacing: Theme.space12) {
                        Text(content.title)
                            .font(.system(size: 24, weight: .bold))
                            .lineSpacing(Theme.titleLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)

                        if let originalContent = viewModel.content {
                            viewOriginalButton(for: originalContent)
                        }
                    }

                    // L0 summary
                    if let summary = content.l0Summary {
                        Text(summary)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.secondary.opacity(0.85))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Tags section
                    if let originalContent = viewModel.content {
                        TagsView(
                            tags: originalContent.tags,
                            availableTags: tagManager.userTags.map { $0.tagName },
                            onAdd: { tagName in
                                await addTag(tagName)
                            },
                            onRemove: { tagName in
                                await removeTag(tagName)
                            }
                        )
                        .padding(.top, Theme.space4)
                    }
                }
                .padding(.horizontal, Theme.space24)
                .padding(.top, Theme.space24)
                .padding(.bottom, Theme.space16)

                // Subtle separator
                Rectangle()
                    .fill(Theme.borderSubtle)
                    .frame(height: 1)
                    .padding(.horizontal, Theme.space24)

                // L1 outline
                if let outline = content.l1Outline {
                    OutlineView(
                        points: outline,
                        viewModel: viewModel,
                        onExpand: { index in
                            Task { await viewModel.expandPoint(at: index) }
                        },
                        onTrace: { anchors in
                            viewModel.traceSource(anchors: anchors)
                        }
                    )
                    .id(content.id)
                } else {
                    ContentUnavailableView(
                        "No Outline Available",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("This content has not been summarized yet.")
                    )
                }
            } else if viewModel.isLoadingContent {
                // Loading state
                VStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading...")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.top, Theme.space8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Empty state
                ContentUnavailableView(
                    "No Content Selected",
                    systemImage: "doc.text",
                    description: Text("Select a content item to view its summary.")
                )
            }
        }
    }

    @ViewBuilder
    private var languageToolbar: some View {
        HStack(spacing: Theme.space12) {
            Text("Language:")
                .font(Theme.captionFont)
                .foregroundStyle(Theme.textSecondary)

            Button(action: { viewModel.toggleTranslation(show: false) }) {
                Text("Original")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!viewModel.showingTranslation)

            Button(action: {
                if viewModel.hasTranslation {
                    viewModel.toggleTranslation(show: true)
                } else {
                    Task { await viewModel.loadTranslation(targetLanguage: targetLanguage) }
                }
            }) {
                if viewModel.isLoadingTranslation {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(languageName(targetLanguage))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.showingTranslation || viewModel.isLoadingTranslation)

            Spacer()
        }
        .padding(.horizontal, Theme.space16)
        .padding(.vertical, Theme.space8)
        .background(Theme.surfaceFloating)
    }

    private func languageName(_ code: String) -> String {
        switch code {
        case "en": return "English"
        case "zh": return "中文"
        case "ja": return "日本語"
        case "es": return "Español"
        case "fr": return "Français"
        case "de": return "Deutsch"
        case "ko": return "한국어"
        default: return code.uppercased()
        }
    }

    // MARK: - Fullscreen Original

    @ViewBuilder
    private var fullscreenOriginalView: some View {
        if let content = viewModel.content {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text(content.title)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)

                    Spacer()

                    Button("关闭") {
                        showFullscreenSheet = false
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(Theme.space16)

                Divider()

                // Full content
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.space16) {
                        if !viewModel.paragraphs.isEmpty {
                            ForEach(viewModel.paragraphs, id: \.anchorID) { para in
                                HStack(alignment: .top, spacing: Theme.space12) {
                                    Text(para.anchorID)
                                        .font(Theme.citationFont)
                                        .foregroundStyle(Theme.citationColor)
                                        .frame(width: 30, alignment: .trailing)

                                    Text(para.text)
                                        .font(.system(size: 15, weight: .regular))
                                        .lineSpacing(8)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        } else if let fullText = content.fullText {
                            Text(fullText)
                                .font(.system(size: 15, weight: .regular))
                                .lineSpacing(8)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Theme.space24)
                }
            }
            .frame(minWidth: 600, minHeight: 400)
        }
    }

    // MARK: - View Original

    @ViewBuilder
    private func viewOriginalButton(for content: Content) -> some View {
        Button {
            handleViewOriginal(content: content)
        } label: {
            HStack(spacing: Theme.space4) {
                Image(systemName: Theme.sourceTypeIcon(content.sourceType))
                    .font(.system(size: 11, weight: .medium))
                Text("查看原文")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isHoveringOriginal ? Theme.accent : .secondary)
            .padding(.horizontal, Theme.space8)
            .padding(.vertical, Theme.space6)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .fill(isHoveringOriginal ? Theme.accent.opacity(0.08) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .strokeBorder(
                        isHoveringOriginal ? Theme.accent.opacity(0.2) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Theme.hoverAnimation) {
                isHoveringOriginal = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func handleViewOriginal(content: Content) {
        switch content.sourceType {
        case .url, .rss:
            if let urlString = content.sourceURL,
               let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            } else {
                viewModel.toggleOriginalPanel()
            }
        default:
            viewModel.toggleOriginalPanel()
        }
    }

    // MARK: - Tag Management

    private func addTag(_ tagName: String) async {
        guard let content = viewModel.content else { return }
        var newTags = content.tags
        if !newTags.contains(tagName) {
            newTags.append(tagName)

            do {
                _ = try await APIClient.shared.updateContentTags(
                    contentId: content.id,
                    tags: newTags
                )

                // Refresh content and tags in parallel
                async let contentRefresh: Void = viewModel.loadContent(contentID: content.id)
                async let tagsRefresh: Void = tagManager.loadUserTags()
                await contentRefresh
                await tagsRefresh
            } catch {
                print("[ReaderView] Failed to add tag: \(error)")
            }
        }
    }

    private func removeTag(_ tagName: String) async {
        guard let content = viewModel.content else { return }
        var newTags = content.tags
        newTags.removeAll { $0 == tagName }

        do {
            _ = try await APIClient.shared.updateContentTags(
                contentId: content.id,
                tags: newTags
            )

            // Refresh content and tags in parallel
            async let contentRefresh: Void = viewModel.loadContent(contentID: content.id)
            async let tagsRefresh: Void = tagManager.loadUserTags()
            await contentRefresh
            await tagsRefresh
        } catch {
            print("[ReaderView] Failed to remove tag: \(error)")
        }
    }
}
