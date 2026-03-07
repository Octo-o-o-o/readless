import SwiftUI
import UI

// MARK: - Toast View

/// A lightweight toast notification that appears briefly at the top of the window
/// and automatically fades out after 1.5 seconds.
struct ToastView: View {
    let message: String
    @State private var isVisible = true
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        if isVisible {
            Text(message)
                .font(Theme.metaFont)
                .padding(.horizontal, Theme.space16)
                .padding(.vertical, Theme.space8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.radiusMedium))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    dismissTask = Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.3)) {
                            isVisible = false
                        }
                    }
                }
                .onDisappear {
                    dismissTask?.cancel()
                }
        }
    }
}

// MARK: - Toast Modifier

/// A view modifier that listens for toast notifications via NotificationCenter
/// and displays a ToastView overlay.
struct ToastModifier: ViewModifier {
    @State private var toastMessage: String?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message = toastMessage {
                    ToastView(message: message)
                        .padding(.top, 8)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showToast)) { notification in
                guard let message = notification.object as? String else { return }
                dismissTask?.cancel()
                withAnimation(.easeIn(duration: 0.2)) {
                    toastMessage = message
                }
                dismissTask = Task {
                    try? await Task.sleep(for: .seconds(2.0))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        toastMessage = nil
                    }
                }
            }
    }
}

extension View {
    /// Adds a toast notification overlay that responds to `.showToast` notifications.
    func toastOverlay() -> some View {
        modifier(ToastModifier())
    }
}
