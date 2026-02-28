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
    @State private var selectedSection: SidebarSection? = .allItems

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSection)
        } detail: {
            if let section = selectedSection {
                Text("Select an item from \(section.title)")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select a section")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
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
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            HotkeysSettingsView()
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }

            ChannelsSettingsView()
                .tabItem {
                    Label("Channels", systemImage: "antenna.radiowaves.left.and.right")
                }

            AccountSettingsView()
                .tabItem {
                    Label("Account", systemImage: "person.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Text("General settings will appear here.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HotkeysSettingsView: View {
    var body: some View {
        Text("Hotkey settings will appear here.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ChannelsSettingsView: View {
    var body: some View {
        Text("Channel settings will appear here.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AccountSettingsView: View {
    var body: some View {
        Text("Account settings will appear here.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
