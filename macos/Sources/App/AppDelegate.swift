import AppKit
import Core

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var hotkeyService: HotkeyService?
    var folderWatchService: FolderWatchService?

    // MARK: - UserDefaults Keys

    private static let watchedFoldersKey = "watchedFolderPaths"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // MARK: Hotkey Service

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

        // MARK: Folder Watch Service

        folderWatchService = FolderWatchService { [weak self] newFiles in
            self?.handleNewFiles(newFiles)
        }

        // Start watching any previously configured folder paths.
        let savedPaths = UserDefaults.standard.stringArray(forKey: Self.watchedFoldersKey) ?? []
        if !savedPaths.isEmpty {
            folderWatchService?.watch(paths: savedPaths)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        folderWatchService?.stop()
    }

    // MARK: - Folder Watch Handler

    /// Called when FolderWatchService detects new files in watched directories.
    /// Each file is imported silently via ContentManager.
    private func handleNewFiles(_ paths: [String]) {
        for path in paths {
            let fileName = (path as NSString).lastPathComponent
            let ext = (path as NSString).pathExtension.lowercased()

            // Determine source type from file extension.
            let sourceType: String
            switch ext {
            case "pdf":
                sourceType = "pdf"
            case "png", "jpg", "jpeg":
                sourceType = "image"
            case "html":
                sourceType = "url"
            default:
                sourceType = "text"
            }

            // Read text-based files; for binary types pass the file path as body.
            let body: String
            if ["pdf", "png", "jpg", "jpeg"].contains(ext) {
                body = path // Backend handles file paths for binary types.
            } else {
                body = (try? String(contentsOfFile: path, encoding: .utf8)) ?? path
            }

            Task { @MainActor in
                await ContentManager.shared.importSilently(
                    text: body, appName: "Folder Watch: \(fileName)", bundleID: nil
                )
            }
        }
    }

    // MARK: - Public API for Folder Watch Configuration

    /// Updates the set of watched folders and persists them to UserDefaults.
    func updateWatchedFolders(_ paths: [String]) {
        UserDefaults.standard.set(paths, forKey: Self.watchedFoldersKey)
        if paths.isEmpty {
            folderWatchService?.stop()
        } else {
            folderWatchService?.watch(paths: paths)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showSummonPanel = Notification.Name("showSummonPanel")
}
