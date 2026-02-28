import AppKit
import Core

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var hotkeyService: HotkeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotkeyService = HotkeyService(
            onSilentImport: { text, appName, bundleID in
                Task { @MainActor in
                    await ContentManager.shared.importSilently(
                        text: text, appName: appName, bundleID: bundleID
                    )
                }
            },
            onImportAndDisplay: { text, appName, bundleID in
                Task { @MainActor in
                    await ContentManager.shared.importAndDisplay(
                        text: text, appName: appName, bundleID: bundleID
                    )
                }
            },
            onSummon: {
                NotificationCenter.default.post(name: .showSummonPanel, object: nil)
            }
        )
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showSummonPanel = Notification.Name("showSummonPanel")
}
