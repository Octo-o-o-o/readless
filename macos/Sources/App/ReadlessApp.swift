import SwiftUI
import Core
import Networking
import Storage
import UI
import AIServices
import KeyboardShortcuts

@main
struct ReadlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var aiCoordinator = AICoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(aiCoordinator)
                .overlay {
                    if aiCoordinator.isCommandBarVisible {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                            .onTapGesture {
                                aiCoordinator.hideCommandBar()
                            }

                        CommandBarWindow()
                            .environment(aiCoordinator)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .toggleCommandBar)) { _ in
                    aiCoordinator.isCommandBarVisible.toggle()

                    // Activate app to foreground when Command Bar opens
                    if aiCoordinator.isCommandBarVisible {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
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
        .onChange(of: contentManager.showResultPanel) { oldValue, newValue in
            // When showResultPanel becomes true, auto-select the newly processed content
            if newValue, let content = contentManager.processingContent {
                selectedContentID = content.id
                contentManager.showResultPanel = false

                // Activate app to foreground
                NSApp.activate(ignoringOtherApps: true)
            }
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
        case .unread: return "envelope.badge"
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
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            // Main sidebar list
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

            Divider()

            // Bottom toolbar with settings and account
            HStack(spacing: 16) {
                Button(action: { openSettings() }) {
                    Label("Settings", systemImage: "gear")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Settings")

                Spacer()

                Button(action: { /* TODO: Account/Login */ }) {
                    Label("Account", systemImage: "person.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help("Account")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
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
    @AppStorage("targetLanguage") private var targetLanguage = "auto"
    @AppStorage("autoTranslateFullText") private var autoTranslateFullText = false

    var body: some View {
        Form {
            Section("Language Settings") {
                Picker("Summary Language:", selection: $targetLanguage) {
                    Text("Follow content language").tag("auto")
                    Divider()
                    Text("English").tag("en")
                    Text("中文 (Chinese)").tag("zh")
                    Text("日本語 (Japanese)").tag("ja")
                    Text("Español (Spanish)").tag("es")
                    Text("Français (French)").tag("fr")
                    Text("Deutsch (German)").tag("de")
                    Text("한국어 (Korean)").tag("ko")
                }
                .pickerStyle(.menu)

                if targetLanguage != "auto" {
                    Toggle("Auto-translate full text", isOn: $autoTranslateFullText)
                        .help("When enabled, automatically translate source paragraphs")
                }
            }

            Section {
                Text("Readless uses AI to generate multi-level summaries of long-form content. Choose your preferred language for summaries, or follow the source content's language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
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
