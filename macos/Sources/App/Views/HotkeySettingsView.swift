import SwiftUI
import KeyboardShortcuts

struct HotkeySettingsView: View {
    var body: some View {
        Form {
            Section("Global Hotkeys") {
                KeyboardShortcuts.Recorder("Silent Import:", name: .silentImport)
                    .help("Import selected text silently into knowledge base")
                KeyboardShortcuts.Recorder("Import & Display:", name: .importAndDisplay)
                    .help("Import and show processing capsule + result")
                KeyboardShortcuts.Recorder("Import Clipboard:", name: .importClipboard)
                    .help("Import current clipboard content silently")
                KeyboardShortcuts.Recorder("Summon Readless:", name: .summonReadless)
                    .help("Open floating search/import panel")
            }

            Section("In-App Navigation") {
                Text("J / K — Navigate outline points")
                Text("Enter — Expand focused point (L2)")
                Text("S — Trace to original source")
                Text("P — Generate podcast")
                Text("Q — Ask follow-up question")
                Text("H / L — Collapse / Expand")
                Text("1 / 2 / 3 — Switch summary level")
                Text("Space — Play/Pause podcast")
                Text("[ / ] — Previous/Next podcast chapter")
                Text("/ or ⌘F — Search knowledge base")
                Text("Esc — Dismiss / Go back")
            }
            .foregroundStyle(.secondary)
            .font(.system(.body, design: .monospaced))
        }
        .formStyle(.grouped)
        .frame(width: 500)
    }
}
