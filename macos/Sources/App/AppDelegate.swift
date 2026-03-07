import AppKit
import Core

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var hotkeyService: HotkeyService?
    var folderWatchService: FolderWatchService?

    // MARK: - UserDefaults Keys

    private static let watchedFoldersKey = "watchedFolderPaths"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SPM executables launch as background processes by default.
        // This makes the app a regular foreground app with Dock icon and windows.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Defer hotkey setup one run-loop turn so the process is fully
        // registered as a foreground app before creating the CGEventTap.
        DispatchQueue.main.async { [self] in
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
                },
                onCommandBar: {
                    NotificationCenter.default.post(name: .toggleCommandBar, object: nil)
                }
            )
        }

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

            // Read file data off the main thread to avoid UI freezes.
            Task.detached(priority: .utility) {
                let body: String
                if ["pdf", "png", "jpg", "jpeg"].contains(ext) {
                    guard let data = FileManager.default.contents(atPath: path) else { return }
                    body = data.base64EncodedString()
                } else {
                    body = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                    if body.isEmpty { return }
                }

                await ContentManager.shared.importSilently(
                    text: body, appName: "Folder Watch: \(fileName)", bundleID: nil,
                    sourceType: sourceType
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
    static let toggleCommandBar = Notification.Name("toggleCommandBar")
}
