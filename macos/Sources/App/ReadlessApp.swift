import AppKit
import SwiftUI
import Core
import Networking
import Storage
import UI
import AIServices
import KeyboardShortcuts

@main
struct ReadlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var authService = AuthService.shared
    @State private var aiCoordinator = AICoordinator()
    @State private var tagManager = TagManager()

    var body: some Scene {
        WindowGroup {
            if !authService.isInitialized {
                LaunchView()
            } else if authService.isAuthenticated {
                ContentView()
                    .environment(authService)
                    .environment(aiCoordinator)
                    .environment(tagManager)
                    // Reliably expand the window back to content size after login
                    .background(MainWindowSizer())
                    .overlay {
                        if aiCoordinator.isCommandBarVisible {
                            Color.black.opacity(0.3)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    aiCoordinator.hideCommandBar()
                                }

                            CommandBarWindow()
                                .environment(aiCoordinator)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .toggleCommandBar)) { _ in
                        aiCoordinator.isCommandBarVisible.toggle()

                        // Activate app to foreground when Command Bar opens
                        if aiCoordinator.isCommandBarVisible {
                            NSApp.activate(ignoringOtherApps: true)
                        }
                    }
            } else {
                LoginView()
                    .environment(authService)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 800, height: 600)

        Settings {
            SettingsView()
        }
    }
}

// MARK: - Main Window Sizer
//
// Expands the window to main content dimensions after login, using
// viewDidMoveToWindow for reliable window access (NSApp.keyWindow can
// be nil during view transitions).

private struct MainWindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SizerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SizerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !window.isSheet else { return }
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                if !window.isZoomed {
                    window.zoom(nil)
                }
            }
        }
    }
}
