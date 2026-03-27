import SwiftUI

// MARK: - Settings View

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
        .frame(width: 550, height: 450)
    }
}

// MARK: - General Settings

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

// MARK: - Channels Settings

struct ChannelsSettingsView: View {
    var body: some View {
        Form {
            Text("Folder watch, email, RSS settings placeholder")
        }
    }
}
