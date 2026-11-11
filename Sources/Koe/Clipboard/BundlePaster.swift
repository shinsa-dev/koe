import AppKit
import ApplicationServices
import KoeCore

/// Makes one ⌘V paste the whole bundle. Only your words sit on the clipboard; when you paste them, Koe puts the
/// files on, pastes again for you and puts back what was there. It goes by the words, not by who wrote the
/// clipboard last: any ⌘V whose text is a bundle Koe copied gets its files, from a clipboard history too
/// (`PasteIndex`). Any other paste is left alone. Watching for ⌘V and pressing it both need Accessibility.
@MainActor
final class BundlePaster {
    private var index = PasteIndex()
    private(set) var delivering = false
    private var monitor: Any?
    private let pasteboard = NSPasteboard.general
    /// The "Copy attachments with the text" setting, read at each paste so a bundle remembered earlier follows it too.
    var filesAllowed: () -> Bool = { true }

    /// Whether the clipboard reads as these words right now.
    func clipboardReads(_ text: String) -> Bool {
        PasteIndex.matches(pasteboard.string(forType: .string), text)
    }

    /// Bundles from earlier sessions, so their words still bring their files after a relaunch.
    func remember(_ items: [ClipboardItem]) {
        if let split = PastePlan.split(items) { index.remember(split) }
    }

    /// Leaves the words on the clipboard and waits for your ⌘V. False when it can't: nothing to follow with, or
    /// Accessibility isn't allowed; the caller then copies everything at once.
    func arm(_ items: [ClipboardItem]) -> Bool {
        guard watch(), let split = PastePlan.split(items), BundleWriter.write([split.words]) else { return false }
        index.remember(split)
        return true
    }

    @discardableResult
    func watch() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard monitor == nil else { return true }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            guard event.keyCode == 9, command, !event.isARepeat else { return }
            MainActor.assumeIsolated { self?.pasted() }
        }
        return true
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func pasted() {
        guard !delivering, filesAllowed(), let split = index.split(pasting: pasteboard.string(forType: .string)) else { return }
        let files = split.files.filter { FileManager.default.fileExists(atPath: $0.path) }
        let front = NSWorkspace.shared.frontmostApplication
        guard !files.isEmpty, PastePlan.takesFiles(appWithBundleID: front?.bundleIdentifier) else { return }
        delivering = true
        Task {
            defer { delivering = false }
            // You let go of ⌘V (or a clipboard history's paste ends), then the app in front reads the words first.
            for _ in 0..<30 where Self.commandHeld { try? await Task.sleep(for: .milliseconds(50)) }
            try? await Task.sleep(for: .milliseconds(180))
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == front?.processIdentifier else { return }
            // A clipboard history may already have put back what was there before; whatever it is comes back after.
            let before = Self.snapshot(pasteboard)
            BundleWriter.write(files.map(ClipboardItem.file))
            let filesCount = pasteboard.changeCount
            Self.pressPaste()
            try? await Task.sleep(for: .milliseconds(600))
            // Anything copied meanwhile is yours to keep.
            guard pasteboard.changeCount == filesCount else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects(before)
        }
    }

    private static var commandHeld: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
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
