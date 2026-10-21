import SwiftUI
import Core
import Networking
import AIServices
import UI

// MARK: - Main Content View

struct ContentView: View {
    @State private var contentManager = ContentManager.shared
    @Environment(AuthService.self) private var authService
    @Environment(AICoordinator.self) private var aiCoordinator
    @Environment(TagManager.self) private var tagManager
    @State private var selectedSection: SidebarSection? = .allItems
    @State private var selectedContentID: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSection)
        } content: {
            ContentListView(
                contents: filteredContents,
                selectedID: $selectedContentID
            )
            .navigationTitle(selectedSection?.title ?? "All Items")
        } detail: {
            detailView
        }
        .frame(minWidth: 800, minHeight: 600)
        .toastOverlay()
        .overlay(alignment: .bottom) {
            capsuleOverlay
                .padding(.bottom, 24)
        }
        .task {
            await contentManager.loadContents()
        }
        .onChange(of: selectedSection) { oldValue, newValue in
            // Clear tag filter when selecting a sidebar section
            tagManager.clearSelection()
        }
        .onChange(of: contentManager.showResultPanel) { oldValue, newValue in
            // When showResultPanel becomes true, auto-select the newly processed content
            if newValue, let content = contentManager.processingContent {
                selectedContentID = content.id
                contentManager.showResultPanel = false

                // Activate app to foreground
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .onChange(of: aiCoordinator.requestedContentID) { _, newValue in
            guard let contentID = newValue else { return }
            selectedSection = .allItems
            selectedContentID = contentID
            aiCoordinator.requestedContentID = nil

            Task {
                await contentManager.refreshContent(id: contentID)
            }

            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Filtered Contents

    /// Returns content items filtered by the currently selected sidebar section.
    private var filteredContents: [Content] {
        switch selectedSection {
        case .allItems, .none:
            return contentManager.contents
        case .unread:
            return contentManager.contents.filter { $0.status == .pending || $0.status == .processing }
        case .favorites:
            // Favorites not yet implemented; return empty for now.
            return []
        case .knowledgeBase:
            return contentManager.contents.filter { $0.status == .ready }
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if let contentID = selectedContentID {
            ReaderView(contentID: contentID)
                .id(contentID)
        } else {
            ContentUnavailableView(
                "No Content Selected",
                systemImage: "doc.text",
                description: Text("Select a content item to view its summary.")
            )
        }
    }

    // MARK: - Capsule Overlay

    @ViewBuilder
    private var capsuleOverlay: some View {
        if contentManager.capsuleState != .dismissed {
            CapsuleProgressView(
                state: $contentManager.capsuleState,
                onCancel: {
                    contentManager.cancelProcessing()
                },
                onConfirm: {
                    if let content = contentManager.processingContent {
                        selectedContentID = content.id
                    }
                    contentManager.capsuleState = .dismissed
                    contentManager.showResultPanel = false
                }
            )
        }
    }
}
