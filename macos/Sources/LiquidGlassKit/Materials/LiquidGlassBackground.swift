import SwiftUI
import AppKit

public struct LiquidGlassBackground: NSViewRepresentable {
    public let variant: LGMaterial

    public init(variant: LGMaterial) {
        self.variant = variant
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()

        switch variant {
        case .liquidGlassClear:
            view.material = .hudWindow
        case .liquidGlassRegular:
            view.material = .menu
        default:
            view.material = .underWindowBackground
        }

        view.blendingMode = .behindWindow
        view.state = .active

        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// ViewModifier for easy usage
public struct LGMaterialModifier: ViewModifier {
    let material: LGMaterial
    let addDimming: Bool

    public func body(content: Content) -> some View {
        if material.needsGlassEffect {
            content
                .background(LiquidGlassBackground(variant: material))
                .background(addDimming ? Color.black.opacity(0.35) : Color.clear)
        } else {
            content
                .background(material.material)
        }
    }
}

extension View {
    public func lgMaterial(_ material: LGMaterial, dimming: Bool = false) -> some View {
        modifier(LGMaterialModifier(material: material, addDimming: dimming))
    }
}
