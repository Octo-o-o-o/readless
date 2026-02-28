import SwiftUI

// MARK: - Toast View

/// A lightweight toast notification that appears briefly at the top of the window
/// and automatically fades out after 1.5 seconds.
struct ToastView: View {
    let message: String
    @State private var isVisible = true

    var body: some View {
        if isVisible {
            Text(message)
                .font(.callout)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .shadow(radius: 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            isVisible = false
                        }
                    }
                }
        }
    }
}

// MARK: - Toast Modifier

/// A view modifier that listens for toast notifications via NotificationCenter
/// and displays a ToastView overlay.
struct ToastModifier: ViewModifier {
    @State private var toastMessage: String?

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
                withAnimation(.easeIn(duration: 0.2)) {
                    toastMessage = message
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
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
