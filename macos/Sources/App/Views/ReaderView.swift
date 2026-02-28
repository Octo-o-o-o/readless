import SwiftUI
import Core
import UI

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
        .task {
            await viewModel.loadParagraphs(contentID: contentID)
        }
    }

    // MARK: - Main Content Panel

    @ViewBuilder
    private var mainContentPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let content = viewModel.content {
                // L0 header: title + one-line summary
                VStack(alignment: .leading, spacing: 8) {
                    Text(content.title)
                        .font(Theme.titleFont)

                    if let summary = content.l0Summary {
                        Text(summary)
                            .font(Theme.l0Font)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                Divider()

                // L1 outline
                if let outline = content.l1Outline {
                    OutlineView(
                        points: outline,
                        focusedIndex: $viewModel.focusedIndex,
                        expandedDetails: viewModel.expandedDetails,
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
}
