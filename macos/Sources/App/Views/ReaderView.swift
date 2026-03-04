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
    @State private var contentManager = ContentManager.shared
    let contentID: String

    var body: some View {
        HSplitView {
            // Main content area (left)
            mainContentPanel
                .frame(minWidth: 400)

            // Source trace panel (right sidebar)
            if viewModel.showSourcePanel {
                SourceTracePanel(
                    paragraphs: viewModel.paragraphs,
                    highlightAnchor: viewModel.sourceAnchorID,
                    isPresented: $viewModel.showSourcePanel
                )
            }
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
            await viewModel.loadContent(contentID: contentID)
            await viewModel.loadParagraphs(contentID: contentID)

            // Auto-translate if needed
            if shouldAutoTranslate {
                await viewModel.loadTranslation(targetLanguage: targetLanguage)
            }
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
            if viewModel.content != nil {
                // Language toggle toolbar (only show if translation available or loading)
                if viewModel.hasTranslation || viewModel.isLoadingTranslation {
                    languageToolbar
                    Divider()
                }

                // Main content display
                if let content = viewModel.displayedContent {
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

                                Text(originalContent.createdAt.relativeFormatted())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.textTertiary)

                                Spacer()
                            }
                        }

                        // Title
                        Text(content.title)
                            .font(.system(size: 24, weight: .bold))
                            .lineSpacing(Theme.titleLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)

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
                    } else {
                        ContentUnavailableView(
                            "No Outline Available",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text("This content has not been summarized yet.")
                        )
                    }
                }
            } else {
                // Loading / empty state
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

                // Refresh content to get updated tags
                await contentManager.refreshContent(id: content.id)
                await viewModel.loadContent(contentID: content.id)

                // Reload tags to update counts
                await tagManager.loadUserTags()
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

            // Refresh content to get updated tags
            await contentManager.refreshContent(id: content.id)
            await viewModel.loadContent(contentID: content.id)

            // Reload tags to update counts
            await tagManager.loadUserTags()
        } catch {
            print("[ReaderView] Failed to remove tag: \(error)")
        }
    }
}
