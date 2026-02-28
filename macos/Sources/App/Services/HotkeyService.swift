import KeyboardShortcuts
import AppKit

// MARK: - Hotkey Name Definitions

extension KeyboardShortcuts.Name {
    /// Silent import: captures selected text and imports without any UI feedback.
    static let silentImport = Self("silentImport", default: .init(.r, modifiers: [.option, .shift]))

    /// Import & display: captures selected text and shows the floating capsule.
    static let importAndDisplay = Self("importAndDisplay", default: .init(.d, modifiers: [.option, .shift]))

    /// Import clipboard: reads the current clipboard content and imports it.
    static let importClipboard = Self("importClipboard", default: .init(.v, modifiers: [.option, .shift]))

    /// Summon Readless: brings the main window to front or shows the summon panel.
    static let summonReadless = Self("summonReadless", default: .init(.s, modifiers: [.option, .shift]))
}

// MARK: - HotkeyService

/// Registers and manages all global hotkeys for Readless.
///
/// The service captures the frontmost application identity *before* Readless activates,
/// ensuring accurate source-app attribution on imported content.
@MainActor
final class HotkeyService {

    private let textCapture = TextCaptureService()

    /// Called when the user triggers a silent import (no UI).
    /// Parameters: (text, appName, bundleID)
    private let onSilentImport: (String, String?, String?) -> Void

    /// Called when the user triggers an import-and-display (shows floating capsule).
    /// Parameters: (text, appName, bundleID)
    private let onImportAndDisplay: (String, String?, String?) -> Void

    /// Called when the user summons Readless.
    private let onSummon: () -> Void

    init(
        onSilentImport: @escaping (String, String?, String?) -> Void,
        onImportAndDisplay: @escaping (String, String?, String?) -> Void,
        onSummon: @escaping () -> Void
    ) {
        self.onSilentImport = onSilentImport
        self.onImportAndDisplay = onImportAndDisplay
        self.onSummon = onSummon

        KeyboardShortcuts.onKeyUp(for: .silentImport) { [weak self] in
            self?.handleImport(display: false)
        }
        KeyboardShortcuts.onKeyUp(for: .importAndDisplay) { [weak self] in
            self?.handleImport(display: true)
        }
        KeyboardShortcuts.onKeyUp(for: .importClipboard) { [weak self] in
            self?.handleClipboardImport()
        }
        KeyboardShortcuts.onKeyUp(for: .summonReadless) { [weak self] in
            self?.onSummon()
        }
    }

    // MARK: - Import Handlers

    /// Captures the source app, extracts selected text, and routes to the appropriate callback.
    ///
    /// The source app is captured *immediately* (before any async work) so that even if
    /// Readless becomes the frontmost app during the operation, we still attribute the
    /// content to the correct source.
    private func handleImport(display: Bool) {
        // Capture source app BEFORE our window activates
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let appName = sourceApp?.localizedName
        let bundleID = sourceApp?.bundleIdentifier

        // Attempt direct accessibility read first
        if let text = textCapture.getSelectedText(), !text.isEmpty {
            if display {
                onImportAndDisplay(text, appName, bundleID)
            } else {
                onSilentImport(text, appName, bundleID)
            }
        } else {
            // Fallback: simulate Cmd+C then read clipboard
            textCapture.simulateCopyAndRead { [weak self] text in
                guard let self, let text, !text.isEmpty else { return }
                if display {
                    self.onImportAndDisplay(text, appName, bundleID)
                } else {
                    self.onSilentImport(text, appName, bundleID)
                }
            }
        }
    }

    /// Imports the current clipboard content directly (no text capture needed).
    private func handleClipboardImport() {
        let sourceApp = NSWorkspace.shared.frontmostApplication
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        onSilentImport(text, sourceApp?.localizedName, sourceApp?.bundleIdentifier)
    }
}
