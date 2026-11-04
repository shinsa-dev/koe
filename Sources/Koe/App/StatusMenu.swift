import AppKit
import KoeCore

/// What Koe's menu bar item shows. Rebuilt each time it opens, so the session and setup lines are always current.
@MainActor
enum StatusMenu {
    static func build(_ menu: NSMenu, checklist: SetupChecklist, phase: RecorderPhase, takenHotKeys: Set<KeyCombo>,
                      target: AppDelegate) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        let state = NSMenuItem(title: stateLine(checklist: checklist, phase: phase), action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        if !takenHotKeys.isEmpty {
            let names = [KeyCombo.toggleSession, .screenshot, .note].filter(takenHotKeys.contains).map(\.displayName)
            let taken = NSMenuItem(
                title: "Another app uses \(names.joined(separator: ", ")), so use them from here.",
                action: nil, keyEquivalent: ""
            )
            taken.isEnabled = false
            menu.addItem(taken)
        }
        menu.addItem(.separator())

        let toggle = item(toggleTitle(phase), #selector(AppDelegate.toggleSession), .toggleSession, takenHotKeys, target)
        toggle.isEnabled = phase.toggleIntent != .ignore
        menu.addItem(toggle)
        let screenshot = item("Take a screenshot", #selector(AppDelegate.takeScreenshot), .screenshot, takenHotKeys, target)
        let note = item("Add a note", #selector(AppDelegate.addNote), .note, takenHotKeys, target)
        screenshot.isEnabled = phase.toggleIntent != .ignore
        note.isEnabled = phase.toggleIntent != .ignore
        menu.addItem(screenshot)
        menu.addItem(note)
        menu.addItem(.separator())

        let setup = NSMenuItem(title: "Set up permissions…", action: #selector(AppDelegate.openSetup), keyEquivalent: "")
        setup.target = target
        menu.addItem(setup)

        let about = NSMenuItem(title: "About Koe", action: #selector(AppDelegate.showAbout), keyEquivalent: "")
        about.target = target
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Koe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    /// The shortcut is display only: a status item's menu never fires key equivalents; the hotkeys are global.
    private static func item(_ title: String, _ action: Selector, _ combo: KeyCombo, _ taken: Set<KeyCombo>,
                             _ target: AppDelegate) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        if !taken.contains(combo), let key = combo.menuKey {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = combo.menuModifiers
        }
        return item
    }

    private static func stateLine(checklist: SetupChecklist, phase: RecorderPhase) -> String {
        switch phase {
        case .recording: "Koe is listening"
        case .preparing: "Koe is getting ready"
        case .finishing: "Koe is finishing"
        case .idle, .failed: checklist.isReady ? "Koe is ready" : "Koe needs permissions"
        }
    }

    private static func toggleTitle(_ phase: RecorderPhase) -> String {
        switch phase.toggleIntent {
        case .start: "Start dictation"
        case .stop: "Stop dictation"
        case .ignore: "Finishing…"
        }
    }
}

extension KeyCombo {
    /// The key as an NSMenuItem key equivalent: lower case, so ⇧ shows only when the combo has it.
    var menuKey: String? {
        if keyCode == 49 { return " " }
        guard let last = displayName.last, last.isLetter || last.isNumber else { return nil }
        return String(last).lowercased()
    }

    var menuModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & Self.command != 0 { flags.insert(.command) }
        if modifiers & Self.option != 0 { flags.insert(.option) }
        if modifiers & Self.shift != 0 { flags.insert(.shift) }
        if modifiers & Self.control != 0 { flags.insert(.control) }
        return flags
    }
}
