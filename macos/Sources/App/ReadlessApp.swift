import AppKit
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
    @State private var authService = AuthService.shared
    @State private var aiCoordinator = AICoordinator()
    @State private var tagManager = TagManager()

    var body: some Scene {
        WindowGroup {
            if !authService.isInitialized {
                LaunchView()
            } else if authService.isAuthenticated {
                ContentView()
                    .environment(authService)
                    .environment(aiCoordinator)
                    .environment(tagManager)
                    // Reliably expand the window back to content size after login
                    .background(MainWindowSizer())
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
            } else {
                LoginView()
                    .environment(authService)
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
    @Environment(AuthService.self) private var authService
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
            // Wait for AuthService to complete initial token sync
            while !authService.isInitialized {
                try? await Task.sleep(for: .milliseconds(50))
            }
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
    @Environment(AuthService.self) private var authService
    @Environment(TagManager.self) private var tagManager
    @State private var contentManager = ContentManager.shared
    @State private var showAuthSheet = false
    @State private var showSignOutConfirm = false

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

                    // Add tag filtering
                    if !tagManager.userTags.isEmpty {
                        Divider()

                        ForEach(tagManager.userTags) { tag in
                            Button {
                                // Clear sidebar selection when filtering by tag
                                selection = nil
                                tagManager.selectTag(tag.id)
                                Task {
                                    await contentManager.filterByTag(tagId: tag.id)
                                }
                            } label: {
                                HStack {
                                    Label(tag.tagName, systemImage: "tag")
                                    Spacer()
                                    Text("\(tag.contentCount)")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete Tag", role: .destructive) {
                                    Task {
                                        try? await tagManager.deleteTag(id: tag.id)
                                        // Reload content if this tag was selected
                                        if tagManager.selectedTagId == tag.id {
                                            await contentManager.loadContents()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .task {
                // Wait for AuthService to complete initial token sync
                while !authService.isInitialized {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                await tagManager.loadUserTags()
            }

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

                Button(action: handleAccountButtonTap) {
                    Label("Account", systemImage: authService.isAuthenticated ? "person.circle.fill" : "person.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .help(authService.isAuthenticated ? "Sign Out" : "Sign In")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .navigationTitle("Readless")
        .sheet(isPresented: $showAuthSheet) {
            LoginView()
        }
        .alert("Sign Out", isPresented: $showSignOutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                Task {
                    try? await authService.signOut()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }

    private func handleAccountButtonTap() {
        if authService.isAuthenticated {
            showSignOutConfirm = true
        } else {
            showAuthSheet = true
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
            CacheSettingsView()
                .tabItem { Label("Cache & Search", systemImage: "internaldrive") }
            HotkeySettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            ChannelsSettingsView()
                .tabItem { Label("Channels", systemImage: "antenna.radiowaves.left.and.right") }
            AccountSettingsView()
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .frame(width: 550, height: 450)  // Increased height for cache stats
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
    @Environment(AuthService.self) private var authService
    @State private var showAuthSheet = false
    @State private var showSubscriptionSheet = false

    var body: some View {
        Form {
            Section("Account") {
                if let user = authService.currentUser {
                    // Logged in state
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Signed In")
                                .font(.headline)
                            if let email = user.email {
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    Button(action: {
                        Task {
                            try? await authService.signOut()
                        }
                    }) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    // Logged out state
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Not signed in")
                            .font(.headline)
                        Text("Sign in to sync your content across devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button(action: {
                            showAuthSheet = true
                        }) {
                            Label("Sign In", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
            }

            Section("Subscription") {
                if let user = authService.currentUser {
                    // Show current subscription status
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Plan")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(user.subscriptionTier.displayName)
                                .font(.headline)
                        }

                        Spacer()

                        Button("Manage Subscription") {
                            showSubscriptionSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text("Sign in to manage your subscription")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("Your authentication is managed securely with JWT tokens. Refresh tokens are encrypted and stored securely in your device's Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .sheet(isPresented: $showAuthSheet) {
            LoginView()
        }
        .sheet(isPresented: $showSubscriptionSheet) {
            SubscriptionView()
        }
    }

}

// MARK: - Main Window Sizer
//
// Expands the window to main content dimensions after login, using
// viewDidMoveToWindow for reliable window access (NSApp.keyWindow can
// be nil during view transitions).

private struct MainWindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SizerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SizerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !window.isSheet else { return }
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                // Only expand if the window is currently login-sized
                let current = window.frame.size
                if current.width < 700 || current.height < 600 {
                    window.setContentSize(NSSize(width: 900, height: 650))
                    window.center()
                }
            }
        }
    }
}
