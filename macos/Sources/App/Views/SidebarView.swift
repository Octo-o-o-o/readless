import SwiftUI
import Core
import Networking
import Storage

// MARK: - Sidebar Section

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

// MARK: - Sidebar View

struct SidebarView: View {
    @Binding var selection: SidebarSection?
    @Environment(\.openSettings) private var openSettings
    @Environment(AuthService.self) private var authService
    @Environment(TagManager.self) private var tagManager
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
                                    await ContentManager.shared.filterByTag(tagId: tag.id)
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
                                            await ContentManager.shared.loadContents()
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
