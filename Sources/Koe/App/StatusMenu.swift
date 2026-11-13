import AppKit
import KoeCore

/// What Koe's menu bar item shows. Rebuilt each time it opens, so the session and setup lines are always current.
@MainActor
enum StatusMenu {
    /// What the menu reflects when it opens.
    struct State {
        var checklist: SetupChecklist
        var phase: RecorderPhase
        var recordingClip: Bool
        /// The shortcuts another app already holds, which the menu points out.
        var shortcuts = Shortcuts()
        var takenHotKeys: Set<ShortcutAction>
        /// Past sessions, newest first, each copied again when clicked.
        var recent: [HistoryEntry] = []
    }

    static func build(_ menu: NSMenu, state current: State, target: AppDelegate) {
        let checklist = current.checklist
        let phase = current.phase
        let recordingClip = current.recordingClip
        let takenHotKeys = current.takenHotKeys
        let shortcuts = current.shortcuts
        menu.removeAllItems()
        menu.autoenablesItems = false

        let state = NSMenuItem(title: stateLine(checklist: checklist, phase: phase), action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        addTakenNotice(takenHotKeys, shortcuts, to: menu)
        menu.addItem(.separator())

        let toggle = item(toggleTitle(phase), #selector(AppDelegate.toggleSession), .toggleSession, target)
        toggle.isEnabled = phase.toggleIntent != .ignore
        menu.addItem(toggle)
        let comment = item("Comment on something", #selector(AppDelegate.addComment), .comment, target)
        let screenshot = item("Take a screenshot", #selector(AppDelegate.takeScreenshot), .screenshot, target)
        let clip = item(recordingClip ? "Stop the clip" : "Record a clip", #selector(AppDelegate.recordClip), .clip, target)
        comment.isEnabled = phase.toggleIntent != .ignore && !recordingClip
        screenshot.isEnabled = phase.toggleIntent != .ignore && !recordingClip
        clip.isEnabled = phase.toggleIntent != .ignore || recordingClip
        menu.addItem(comment)
        menu.addItem(screenshot)
        menu.addItem(clip)
        menu.addItem(.separator())

        addRecent(current.recent, to: menu, target: target)

        let settings = NSMenuItem(title: "Settings…", action: #selector(AppDelegate.openSettings), keyEquivalent: "")
        settings.target = target
        menu.addItem(settings)

        let setup = NSMenuItem(title: "Set up permissions…", action: #selector(AppDelegate.openSetup), keyEquivalent: "")
        setup.target = target
        menu.addItem(setup)

        let about = NSMenuItem(title: "About Koe", action: #selector(AppDelegate.showAbout), keyEquivalent: "")
        about.target = target
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Koe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        // macOS adds its own symbols to items it recognises, such as a gear on "Settings…"; Koe draws none. The setter
        // is in the macOS 27 SDK only, and releases build with Xcode 26.3, so it is reached by name: 2 is `.hidden`.
        let hideImage = NSSelectorFromString("setPreferredImageVisibility:")
        for item in menu.items where item.responds(to: hideImage) {
            item.setValue(2, forKey: "preferredImageVisibility")
        }
    }

    /// Past sessions under a header; clicking one copies its bundle again.
    private static func addRecent(_ recent: [HistoryEntry], to menu: NSMenu, target: AppDelegate) {
        menu.addItem(.sectionHeader(title: "Recent sessions"))
        if recent.isEmpty {
            let none = NSMenuItem(title: "Sessions you finish show here.", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for entry in recent {
            let item = NSMenuItem(title: entry.title(), action: #selector(AppDelegate.copyRecent(_:)), keyEquivalent: "")
            item.subtitle = entry.detail()
            item.representedObject = entry.id
            item.target = target
            item.toolTip = "Copy this session again"
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }

    /// The shortcut is display only: a status item's menu never fires key equivalents; the hotkeys are global.
    private static func item(_ title: String, _ action: Selector, _ shortcut: ShortcutAction,
                             _ target: AppDelegate) -> NSMenuItem {
        let shortcuts = ShortcutCenter.shared.shortcuts
        let taken = ShortcutCenter.shared.taken
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        let combo = shortcuts[shortcut]
        if !taken.contains(shortcut), let key = combo.menuKey {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = combo.menuModifiers
        }
        return item
    }

    private static func stateLine(checklist: SetupChecklist, phase: RecorderPhase) -> String {
        switch phase {
        case .recording: "Koe is listening"
        case .paused: "Koe is paused"
        case .finishing: "Koe is copying"
        case .idle, .failed: checklist.isReady ? "Koe is ready" : "Koe needs permissions"
        }
    }

    private static func toggleTitle(_ phase: RecorderPhase) -> String {
        switch phase.toggleIntent {
        case .start: "Start dictation"
        case .stop: "Finish and copy"
        case .ignore: "Copying…"
        }
    }

    /// Says which shortcuts another app holds, so you use those tools from the menu or the pill instead.
    private static func addTakenNotice(_ takenHotKeys: Set<ShortcutAction>, _ shortcuts: Shortcuts, to menu: NSMenu) {
        guard !takenHotKeys.isEmpty else { return }
        let names = ShortcutAction.allCases.filter(takenHotKeys.contains).map { shortcuts[$0].displayName }
        let taken = NSMenuItem(title: "Another app uses \(names.joined(separator: ", ")), so use them from here.",
                               action: nil, keyEquivalent: "")
        taken.isEnabled = false
        menu.addItem(taken)
    }
}

extension KeyCombo {
    /// The key as an NSMenuItem key equivalent: lower case, so ⇧ shows only when the combo has it.
    var menuKey: String? {
        if keyCode == 49 { return " " }
        // A named key such as F5 or ← has no one-character equivalent; the menu then shows no shortcut.
        guard let name = Self(keyCode: keyCode, modifiers: 0).displayName.first.map(String.init),
              Self(keyCode: keyCode, modifiers: 0).displayName.count == 1, name.unicodeScalars.allSatisfy(\.isASCII)
        else { return nil }
        return name.lowercased()
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
