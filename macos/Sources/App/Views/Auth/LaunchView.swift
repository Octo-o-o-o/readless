import SwiftUI

/// Elegant loading screen shown during app initialization and auto-login.
struct LaunchView: View {
    @State private var animateIn = false
    @State private var pulseRing = false

    var body: some View {
        ZStack {
            // ── Background ─────────────────────────────────────────────
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            RadialGradient(
                colors: [Color.accentColor.opacity(0.06), .clear],
                center: .init(x: 0.5, y: 0.35),
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()

            // ── Center content ─────────────────────────────────────────
            VStack(spacing: 20) {
                // App icon with pulse ring
                ZStack {
                    // Outer pulse ring
                    Circle()
                        .stroke(Color.accentColor.opacity(0.15), lineWidth: 1.5)
                        .frame(width: 90, height: 90)
                        .scaleEffect(pulseRing ? 1.15 : 1.0)
                        .opacity(pulseRing ? 0 : 0.6)

                    // Icon circle
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 72, height: 72)
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                        .shadow(color: .black.opacity(0.1), radius: 12, y: 4)

                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.primary)
                }

                VStack(spacing: 6) {
                    Text("Readless")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))

                    // Subtle loading dots
                    LoadingDotsView()
                        .frame(height: 6)
                }
            }
            .offset(y: animateIn ? 0 : 12)
            .opacity(animateIn ? 1 : 0)
        }
        .background(LaunchWindowSizer())
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                animateIn = true
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulseRing = true
            }
        }
    }
}

// MARK: - Loading Dots

/// Three dots that animate sequentially to indicate loading.
private struct LoadingDotsView: View {
    @State private var active = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 5, height: 5)
                    .scaleEffect(active ? 1.0 : 0.5)
                    .opacity(active ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: active
                    )
            }
        }
        .onAppear { active = true }
    }
}

// MARK: - Launch Window Sizer

/// Sizes the window to match LoginView dimensions during launch.
private struct LaunchWindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { SizerView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class SizerView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !window.isSheet else { return }
            DispatchQueue.main.async { [weak window] in
                guard let window else { return }
                window.setContentSize(NSSize(width: 540, height: 680))
                window.center()
            }
        }
    }
}
