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

// MARK: - ContentManager (Placeholder)
//
// This is a temporary stub so the project compiles before the real ContentManager
// is implemented in Task 15. It will be replaced by a full implementation that
// persists content, triggers summarization, etc.

@MainActor
final class ContentManager {
    static let shared = ContentManager()

    private init() {}

    /// Silent import -- saves content in the background with no UI feedback.
    func importSilently(text: String, appName: String?, bundleID: String?) async {
        let preview = text.prefix(80)
        print("[ContentManager] Silent import from \(appName ?? "unknown") (\(bundleID ?? "?")): \"\(preview)...\"")
    }

    /// Import and display -- saves content and shows the floating capsule.
    func importAndDisplay(text: String, appName: String?, bundleID: String?) async {
        let preview = text.prefix(80)
        print("[ContentManager] Import & display from \(appName ?? "unknown") (\(bundleID ?? "?")): \"\(preview)...\"")
        NotificationCenter.default.post(
            name: .showFloatingCapsule,
            object: nil,
            userInfo: ["text": text, "appName": appName as Any, "bundleID": bundleID as Any]
        )
    }
}

extension Notification.Name {
    static let showFloatingCapsule = Notification.Name("showFloatingCapsule")
}
