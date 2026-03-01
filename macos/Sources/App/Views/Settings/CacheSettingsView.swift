import SwiftUI
import Storage
import Core

/// Cache management settings view
struct CacheSettingsView: View {
    @State private var viewModel = CacheSettingsViewModel()

    var body: some View {
        Form {
            Section {
                // Search mode picker
                Picker("Search Mode", selection: $viewModel.searchMode) {
                    Label("Cloud Search", systemImage: "cloud.fill")
                        .tag(SearchMode.cloud)

                    Label("Local Search", systemImage: "internaldrive.fill")
                        .tag(SearchMode.local)
                }
                .pickerStyle(.inline)
                .onChange(of: viewModel.searchMode) { _, newValue in
                    viewModel.updateSearchMode(newValue)
                }

                // Description based on selected mode
                if viewModel.searchMode == .cloud {
                    Label {
                        Text("Using AI-powered cloud search with semantic understanding. Requires internet connection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                    }
                    .padding(.vertical, 4)
                } else {
                    Label {
                        Text("Using local full-text search. Works offline but requires cached content data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Search")
            } footer: {
                Text("Choose between cloud AI search (accurate, requires network) or local search (fast, offline-capable).")
            }

            Section {
                // Cache size limit slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Cache Size Limit")
                            .font(.headline)

                        Spacer()

                        Text(viewModel.formattedSizeLimit)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: $viewModel.sizeLimitMB,
                        in: 50...10240,
                        step: 50
                    )
                    .onChange(of: viewModel.sizeLimitMB) { _, newValue in
                        viewModel.updateSizeLimit(mb: newValue)
                    }

                    HStack {
                        Text("50 MB")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("10 GB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Minimum: 50 MB • Default: 4096 MB (4 GB)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } header: {
                Text("Storage")
            } footer: {
                Text("When cache space is available (>50 MB), Readless will save complete content data locally for offline access and faster searches.")
            }

            Section {
                if let stats = viewModel.stats {
                    // Usage progress bar
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Cache Usage")
                                .font(.headline)

                            Spacer()

                            Text("\(Int(stats.usagePercentage))%")
                                .foregroundStyle(
                                    stats.usagePercentage > 90 ? .red :
                                    stats.usagePercentage > 75 ? .orange : .secondary
                                )
                        }

                        ProgressView(value: stats.usagePercentage, total: 100)
                            .tint(
                                stats.usagePercentage > 90 ? .red :
                                stats.usagePercentage > 75 ? .orange : .blue
                            )

                        HStack {
                            Label(
                                "\(stats.formattedCurrentSize) used",
                                systemImage: "internaldrive"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Spacer()

                            Label(
                                "\(stats.formattedAvailableSpace) available",
                                systemImage: "externaldrive.badge.checkmark"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)

                    Divider()

                    // Item count
                    LabeledContent {
                        Text("\(stats.itemCount)")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label("Cached Items", systemImage: "doc.text")
                    }

                } else {
                    ProgressView("Loading cache statistics...")
                }
            } header: {
                Text("Statistics")
            }

            Section {
                // Clear old items
                Button(action: { viewModel.showClearOldConfirmation = true }) {
                    Label("Clear Items Older Than 30 Days", systemImage: "calendar.badge.minus")
                }
                .confirmationDialog(
                    "Clear Old Cache",
                    isPresented: $viewModel.showClearOldConfirmation
                ) {
                    Button("Clear Items Older Than 30 Days", role: .destructive) {
                        Task { await viewModel.clearOld(days: 30) }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will delete cached items that haven't been accessed in the last 30 days. This action cannot be undone.")
                }

                // Clear all
                Button(role: .destructive, action: { viewModel.showClearAllConfirmation = true }) {
                    Label("Clear All Cache", systemImage: "trash")
                }
                .confirmationDialog(
                    "Clear All Cache",
                    isPresented: $viewModel.showClearAllConfirmation
                ) {
                    Button("Clear All Cache", role: .destructive) {
                        Task { await viewModel.clearAll() }
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This will delete all locally cached content. You'll need to re-fetch data from the server. This action cannot be undone.")
                }
            } header: {
                Text("Maintenance")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .task {
            await viewModel.loadStats()
        }
    }
}

// MARK: - View Model

@MainActor
@Observable
final class CacheSettingsViewModel {
    var sizeLimitMB: Double
    var searchMode: SearchMode
    var stats: CacheManager.CacheStats?
    var showClearAllConfirmation = false
    var showClearOldConfirmation = false

    private let cacheManager: CacheManager
    private let userDefaults: UserDefaults

    init(cacheManager: CacheManager = .shared, userDefaults: UserDefaults = .standard) {
        self.cacheManager = cacheManager
        self.userDefaults = userDefaults
        self.sizeLimitMB = Double(cacheManager.sizeLimit) / 1024 / 1024

        // Load search mode from UserDefaults
        if let modeString = userDefaults.string(forKey: "searchMode"),
           let mode = SearchMode(rawValue: modeString) {
            self.searchMode = mode
        } else {
            self.searchMode = .cloud  // Default to cloud search
        }
    }

    func updateSearchMode(_ mode: SearchMode) {
        userDefaults.set(mode.rawValue, forKey: "searchMode")
        print("[CacheSettings] Search mode updated to: \(mode.displayName)")
    }

    var formattedSizeLimit: String {
        let bytes = Int64(sizeLimitMB * 1024 * 1024)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func updateSizeLimit(mb: Double) {
        let bytes = Int64(mb * 1024 * 1024)
        cacheManager.sizeLimit = bytes
    }

    func loadStats() async {
        do {
            stats = try await cacheManager.getStats()
        } catch {
            print("[CacheSettings] Failed to load stats: \(error)")
        }
    }

    func clearAll() async {
        do {
            try await cacheManager.clearAll()
            await loadStats()
        } catch {
            print("[CacheSettings] Failed to clear all: \(error)")
        }
    }

    func clearOld(days: Int) async {
        do {
            try await cacheManager.clearOlderThan(days: days)
            await loadStats()
        } catch {
            print("[CacheSettings] Failed to clear old: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    CacheSettingsView()
}
