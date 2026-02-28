import AppKit
import ApplicationServices

/// Captures selected text from the frontmost application using the macOS Accessibility API,
/// with a fallback to simulated Cmd+C when direct text extraction is unavailable.
final class TextCaptureService {

    /// Attempts to read the currently selected text via the Accessibility API (AXUIElement).
    ///
    /// This is the preferred, non-destructive approach -- it reads the selection directly
    /// without touching the clipboard. Requires the user to have granted Accessibility
    /// permission in System Settings > Privacy & Security > Accessibility.
    ///
    /// - Returns: The selected text, or `nil` if unavailable.
    func getSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        guard focusResult == .success else { return nil }

        // AXUIElement is a CoreFoundation type; cast from AnyObject always succeeds.
        let element = focusedElement! as! AXUIElement

        var selectedText: AnyObject?
        let textResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )
        guard textResult == .success else { return nil }

        return selectedText as? String
    }

    /// Fallback: simulates Cmd+C to copy the selection, then reads the clipboard.
    ///
    /// This method saves the current clipboard content, synthesizes a Cmd+C keystroke,
    /// waits briefly for the copy to complete, then reads the new clipboard value.
    /// If the clipboard content changed, the newly copied text is returned via the
    /// completion handler.
    ///
    /// - Parameter completion: Called on the main thread with the captured text, or `nil`
    ///   if nothing was captured.
    func simulateCopyAndRead(completion: @escaping (String?) -> Void) {
        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)

        // Simulate Cmd+C using CGEvent.
        // Virtual key 0x08 = 'c' on a US keyboard layout.
        let source = CGEventSource(stateID: .combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        // Wait a short interval for the target app to process the copy command
        // and populate the pasteboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let newContent = pasteboard.string(forType: .string)
            if newContent != previousContent {
                completion(newContent)
            } else {
                completion(nil)
            }
        }
    }
}
