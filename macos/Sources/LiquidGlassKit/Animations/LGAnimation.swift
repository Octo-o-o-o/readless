import SwiftUI

public enum LGAnimation {
    // Base animations
    case fluid               // 0.5s spring bounce 0.2
    case snappy              // 0.35s spring bounce 0.1
    case smooth              // 0.4s easeInOut

    // Liquid Glass animations
    case glassAppear         // 0.4s spring bounce 0.15
    case glassDismiss        // 0.25s easeOut
    case glassRefract        // 0.3s spring bounce 0.05

    // Interaction feedback
    case press               // 0.1s easeOut
    case hover               // 0.15s easeInOut
    case focus               // 0.2s spring bounce 0.1

    public var animation: Animation {
        switch self {
        case .fluid:
            return .spring(duration: 0.5, bounce: 0.2)
        case .snappy:
            return .spring(duration: 0.35, bounce: 0.1)
        case .smooth:
            return .easeInOut(duration: 0.4)
        case .glassAppear:
            return .spring(duration: 0.4, bounce: 0.15)
        case .glassDismiss:
            return .easeOut(duration: 0.25)
        case .glassRefract:
            return .spring(duration: 0.3, bounce: 0.05)
        case .press:
            return .easeOut(duration: 0.1)
        case .hover:
            return .easeInOut(duration: 0.15)
        case .focus:
            return .spring(duration: 0.2, bounce: 0.1)
        }
    }
}

// Convenience View extension for glass transitions
public extension View {
    func glassTransition(isPresented: Bool) -> some View {
        self
            .scaleEffect(isPresented ? 1.0 : 0.96)
            .opacity(isPresented ? 1.0 : 0.0)
            .blur(radius: isPresented ? 0 : 8)
            .animation(
                isPresented ? LGAnimation.glassAppear.animation : LGAnimation.glassDismiss.animation,
                value: isPresented
            )
    }
}
