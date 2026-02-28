import SwiftUI
import Core
import Networking
import Storage
import UI
import KeyboardShortcuts

@main
struct ReadlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 600)

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Main Content View

struct ContentView: View {
    @State private var contentManager = ContentManager.shared
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

// MARK: - Sidebar

enum SidebarSection: String, CaseIterable, Identifiable {
    case allItems
    case unread
    case favorites
    case knowledgeBase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allItems: return "All Items"
        case .unread: return "Unread"
        case .favorites: return "Favorites"
        case .knowledgeBase: return "Knowledge Base"
        }
    }

    var systemImage: String {
        switch self {
        case .allItems: return "tray.full"
        case .unread: return "circle.badge"
        case .favorites: return "star"
        case .knowledgeBase: return "brain"
        }
    }

    static var libraryItems: [SidebarSection] {
        [.allItems, .unread, .favorites]
    }

    static var knowledgeItems: [SidebarSection] {
        [.knowledgeBase]
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarSection?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                ForEach(SidebarSection.libraryItems) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }

            Divider()

            Section("Knowledge") {
                ForEach(SidebarSection.knowledgeItems) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Readless")
    }
}

// MARK: - Settings

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            HotkeySettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            ChannelsSettingsView()
                .tabItem { Label("Channels", systemImage: "antenna.radiowaves.left.and.right") }
            AccountSettingsView()
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .frame(width: 550, height: 400)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Text("General settings placeholder")
        }
    }
}

struct ChannelsSettingsView: View {
    var body: some View {
        Form {
            Text("Folder watch, email, RSS settings placeholder")
        }
    }
}

struct AccountSettingsView: View {
    var body: some View {
        Form {
            Text("Account & subscription placeholder")
        }
    }
}
