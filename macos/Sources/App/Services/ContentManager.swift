import Foundation
import AppKit
import Core
import Networking
import UI

// MARK: - Content Manager

/// Coordinates content imports between the macOS client and the backend API.
///
/// `ContentManager` is the central bridge that takes raw text from hotkeys,
/// clipboard, or drag-and-drop, sends it to the FastAPI backend for processing,
/// and manages the resulting content list.
@MainActor
@Observable
final class ContentManager {
    static let shared = ContentManager()

    // MARK: - Published State

    var contents: [Content] = []
    var processingContent: Content?
    var capsuleState: CapsuleState = .dismissed
    var showResultPanel: Bool = false

    // MARK: - Private

    private let api = APIClient()

    private init() {}

    // MARK: - Import Methods

    /// Import content silently -- saves in the background with a brief toast notification.
    func importSilently(text: String, appName: String?, bundleID: String?) async {
        showToast("Received from \(appName ?? "clipboard")")
        do {
            let sourceType = text.hasPrefix("http") ? "url" : "text"
            let content = try await api.createContent(
                sourceType: sourceType,
                body: text,
                appName: appName,
                bundleID: bundleID
            )
            contents.insert(content, at: 0)
        } catch {
            showToast("Import failed: \(error.localizedDescription)")
        }
    }

    /// Import content and display the floating capsule progress, then show the result panel.
    func importAndDisplay(text: String, appName: String?, bundleID: String?) async {
        capsuleState = .processing
        do {
            let sourceType = text.hasPrefix("http") ? "url" : "text"
            let content = try await api.createContent(
                sourceType: sourceType,
                body: text,
                appName: appName,
                bundleID: bundleID
            )
            contents.insert(content, at: 0)
            processingContent = content
            capsuleState = .completed

            // Brief delay before transitioning to the result panel.
            try? await Task.sleep(for: .milliseconds(500))
            if capsuleState == .completed {
                showResultPanel = true
                capsuleState = .dismissed
            }
        } catch {
            capsuleState = .dismissed
            showToast("Import failed: \(error.localizedDescription)")
        }
    }

    /// Cancel any in-progress import and dismiss the capsule.
    func cancelProcessing() {
        capsuleState = .dismissed
        processingContent = nil
    }

    // MARK: - Data Loading

    /// Fetch the content list from the backend API.
    func loadContents() async {
        do {
            contents = try await api.listContents()
        } catch {
            // Silently handle errors for now; the UI will show an empty state.
        }
    }

    // MARK: - Notifications

    private func showToast(_ message: String) {
        NotificationCenter.default.post(name: .showToast, object: message)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showToast = Notification.Name("showToast")
}
