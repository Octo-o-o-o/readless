import SwiftUI
import AppKit

public class FloatingPanelWindow: NSPanel {
    public override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .fullSizeContentView],
        backing: NSWindow.BackingStoreType = .buffered,
        defer flag: Bool = false
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
    }
}
