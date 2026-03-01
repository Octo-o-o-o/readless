import AppKit
import ApplicationServices
import KeyboardShortcuts

// MARK: - Hotkey Name Definitions (used by Settings UI Recorder)

extension KeyboardShortcuts.Name {
    static let silentImport = Self("silentImport", default: .init(.r, modifiers: [.option, .shift]))
    static let importAndDisplay = Self("importAndDisplay", default: .init(.d, modifiers: [.option, .shift]))
    static let importClipboard = Self("importClipboard", default: .init(.v, modifiers: [.option, .shift]))
    static let summonReadless = Self("summonReadless", default: .init(.s, modifiers: [.option, .shift]))
    static let commandBar = Self("commandBar", default: .init(.k, modifiers: [.command]))
}

// MARK: - HotkeyService

/// Registers and manages all global hotkeys for Readless.
///
/// Uses three layered mechanisms for maximum reliability:
/// 1. NSEvent local monitor  — works when app is focused (no permissions needed)
/// 2. NSEvent global monitor — works when app is NOT focused (needs Accessibility)
/// 3. KeyboardShortcuts Carbon — additional fallback
@MainActor
final class HotkeyService {

    private let textCapture = TextCaptureService()

    private let onSilentImport: (String, String?, String?) -> Void
    private let onImportAndDisplay: (String, String?, String?) -> Void
    private let onSummon: () -> Void
    private let onCommandBar: () -> Void

    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(
        onSilentImport: @escaping (String, String?, String?) -> Void,
        onImportAndDisplay: @escaping (String, String?, String?) -> Void,
        onSummon: @escaping () -> Void,
        onCommandBar: @escaping () -> Void
    ) {
        self.onSilentImport = onSilentImport
        self.onImportAndDisplay = onImportAndDisplay
        self.onSummon = onSummon
        self.onCommandBar = onCommandBar

        // --- Diagnostics ---
        let trusted = AXIsProcessTrusted()
        print("[Readless] ===== Hotkey Setup =====")
        print("[Readless] Accessibility trusted: \(trusted)")
        print("[Readless] Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")

        // Layer 1: Local monitor (always works, catches hotkeys when app is focused)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if self?.matchAndDispatch(event) == true {
                return nil  // consume the event
            }
            return event
        }
        print("[Readless] Local event monitor: active")

        // Layer 2: Global monitor (catches hotkeys when another app is focused)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            _ = self?.matchAndDispatch(event)
        }
        if globalMonitor != nil {
            print("[Readless] Global event monitor: active")
        } else {
            print("[Readless] Global event monitor: FAILED (grant Accessibility permission)")
        }

        // Layer 3: Carbon / KeyboardShortcuts fallback
        setupCarbonFallback()

        // Command Bar hotkey (⌘K)
        setupCommandBarHotkey()

        // Prompt for Accessibility if not trusted
        if !trusted {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }

        print("[Readless] ===== Hotkey Setup Complete =====")
    }

    deinit {
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
    }

    // MARK: - Event Matching

    /// Returns `true` if the event matches one of our hotkeys and the action
    /// was dispatched.
    private func matchAndDispatch(_ event: NSEvent) -> Bool {
        // Require Option + Shift, nothing else.
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods == [.option, .shift] else { return false }

        switch event.keyCode {
        case 15:  // R — silent import
            print("[Readless] Hotkey ⌥⇧R detected")
            handleImport(display: false)
            return true
        case 2:   // D — import & display
            print("[Readless] Hotkey ⌥⇧D detected")
            handleImport(display: true)
            return true
        case 9:   // V — clipboard import
            print("[Readless] Hotkey ⌥⇧V detected")
            handleClipboardImport()
            return true
        case 1:   // S — summon
            print("[Readless] Hotkey ⌥⇧S detected")
            onSummon()
            return true
        default:
            return false
        }
    }

    // MARK: - Carbon Fallback

    private func setupCarbonFallback() {
        KeyboardShortcuts.onKeyUp(for: .silentImport) { [weak self] in
            print("[Readless] Carbon: ⌥⇧R fired")
            self?.handleImport(display: false)
        }
        KeyboardShortcuts.onKeyUp(for: .importAndDisplay) { [weak self] in
            print("[Readless] Carbon: ⌥⇧D fired")
            self?.handleImport(display: true)
        }
        KeyboardShortcuts.onKeyUp(for: .importClipboard) { [weak self] in
            print("[Readless] Carbon: ⌥⇧V fired")
            self?.handleClipboardImport()
        }
        KeyboardShortcuts.onKeyUp(for: .summonReadless) { [weak self] in
            print("[Readless] Carbon: ⌥⇧S fired")
            self?.onSummon()
        }
        print("[Readless] Carbon hotkey handlers: registered")
    }

    private func setupCommandBarHotkey() {
        KeyboardShortcuts.onKeyUp(for: .commandBar) { [weak self] in
            print("[Readless] Hotkey ⌘K detected")
            self?.onCommandBar()
        }
        print("[Readless] Command Bar hotkey (⌘K): registered")
    }

    // MARK: - Import Handlers

    private func handleImport(display: Bool) {
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let appName = sourceApp?.localizedName
        let bundleID = sourceApp?.bundleIdentifier

        if let text = textCapture.getSelectedText(), !text.isEmpty {
            if display {
                onImportAndDisplay(text, appName, bundleID)
            } else {
                onSilentImport(text, appName, bundleID)
            }
        } else {
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

    private func handleClipboardImport() {
        let sourceApp = NSWorkspace.shared.frontmostApplication
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        onSilentImport(text, sourceApp?.localizedName, sourceApp?.bundleIdentifier)
    }
}
