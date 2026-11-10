import AppKit
import ApplicationServices
import KoeCore

/// Makes one ⌘V paste the whole bundle. Only your words sit on the clipboard; when you paste them, Koe puts the
/// files on, pastes again for you and puts the words back, so the next ⌘V does the same. It only acts while the
/// clipboard is still the one Koe wrote (`changeCount`), and stops for good once you copy something else.
/// Watching for ⌘V and pressing it both need Accessibility.
@MainActor
final class BundlePaster {
    private var split: PastePlan.Split?
    private var armedCount = 0
    private var delivering = false
    private var monitor: Any?
    private let pasteboard = NSPasteboard.general

    /// Whether Koe's words are still what the clipboard holds.
    var holdsClipboard: Bool { split != nil && (delivering || pasteboard.changeCount == armedCount) }

    /// Leaves the words on the clipboard and waits for your ⌘V. False when it can't: nothing to follow with, or
    /// Accessibility isn't allowed; the caller then copies everything at once.
    func arm(_ items: [ClipboardItem]) -> Bool {
        disarm()
        guard AXIsProcessTrusted(), let split = PastePlan.split(items), BundleWriter.write([split.words]) else { return false }
        self.split = split
        armedCount = pasteboard.changeCount
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            guard event.keyCode == 9, command, !event.isARepeat else { return }
            MainActor.assumeIsolated { self?.pasted() }
        }
        return true
    }

    func disarm() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        split = nil
    }

    private func pasted() {
        guard let split, !delivering else { return }
        guard pasteboard.changeCount == armedCount else { return disarm() }
        guard PastePlan.takesFiles(appWithBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) else { return }
        let target = NSWorkspace.shared.frontmostApplication?.processIdentifier
        delivering = true
        Task {
            defer { delivering = false }
            // The app in front reads the words first, and you let go of ⌘V.
            try? await Task.sleep(for: .milliseconds(220))
            // Anything copied meanwhile, or another app in front, means this paste is no longer ours to finish.
            guard pasteboard.changeCount == armedCount,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target else { return disarm() }
            BundleWriter.write(split.files.map(ClipboardItem.file))
            let filesCount = pasteboard.changeCount
            Self.pressPaste()
            try? await Task.sleep(for: .milliseconds(600))
            guard pasteboard.changeCount == filesCount else { return disarm() }
            BundleWriter.write([split.words])
            armedCount = pasteboard.changeCount
        }
    }

    static func pressPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        guard let press = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let release = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        press.flags = .maskCommand
        release.flags = .maskCommand
        press.post(tap: .cghidEventTap)
        release.post(tap: .cghidEventTap)
    }
}
