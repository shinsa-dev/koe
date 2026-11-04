import AppKit
import ApplicationServices
import KoeCore

/// Puts a bundle on the clipboard as `ClipboardPlan` lays it out, and can press ⌘V for you.
@MainActor
enum BundleWriter {
    /// Writes the items in order: the text item carries plain text and HTML, each file item its file URL.
    @discardableResult
    static func write(_ items: [ClipboardItem], to pasteboard: NSPasteboard = .general) -> Bool {
        guard !items.isEmpty else { return false }
        let entries: [NSPasteboardItem] = items.map { item in
            let entry = NSPasteboardItem()
            switch item {
            case .text(let plain, let html):
                entry.setString(plain, forType: .string)
                entry.setString(html, forType: .html)
            case .file(let url):
                entry.setString(url.absoluteString, forType: .fileURL)
            }
            return entry
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects(entries)
    }

    /// Presses ⌘V in the app in front. Koe's panels never take focus, so that is the app you were in; when Koe itself
    /// is in front (its settings were open), or Accessibility isn't allowed, it does nothing and says so.
    static func paste() async -> Bool {
        guard AXIsProcessTrusted(), !NSApp.isActive else { return false }
        // Gives the app in front a moment to see the new clipboard, and you to let go of the stop hotkey's keys.
        try? await Task.sleep(for: .milliseconds(250))
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        guard let press = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let release = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return false }
        press.flags = .maskCommand
        release.flags = .maskCommand
        press.post(tap: .cghidEventTap)
        release.post(tap: .cghidEventTap)
        return true
    }
}
