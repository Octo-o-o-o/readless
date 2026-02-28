import SwiftUI
import AppKit

public enum CapsuleState {
    case processing
    case completed
    case dismissed
}

public struct CapsuleProgressView: View {
    @Binding var state: CapsuleState
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @State private var appear = false

    public init(state: Binding<CapsuleState>, onCancel: @escaping () -> Void, onConfirm: @escaping () -> Void) {
        self._state = state
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    public var body: some View {
        HStack(spacing: 16) {
            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.15)))
            }
            .buttonStyle(.plain)

            // Wave animation
            WaveAnimation(isActive: state == .processing)
                .frame(width: 140)

            // Confirm button
            Button(action: onConfirm) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(state == .completed ? .white : .white.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(state == .completed ? Color.green.opacity(0.6) : .white.opacity(0.1))
                    )
                    .scaleEffect(state == .completed ? 1.1 : 1.0)
                    .animation(Theme.capsuleAppear, value: state)
            }
            .buttonStyle(.plain)
            .disabled(state != .completed)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 5)
        .scaleEffect(appear ? 1 : 0.8)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 20)
        .onAppear {
            withAnimation(Theme.capsuleAppear) {
                appear = true
            }
        }
    }

    public func dismiss() {
        withAnimation(Theme.capsuleDismiss) {
            appear = false
        }
    }
}
