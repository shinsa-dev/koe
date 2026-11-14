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
        /// Whether ⇧⌘-click comments, which the comment row then shows in place of its shortcut.
        var clickToComment = true
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

        var labels: [NSMenuItem: String] = [:]
        func item(_ title: String, _ action: Selector, _ shortcut: ShortcutAction) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            labels[item] = shortcuts.menuLabel(for: shortcut, taken: takenHotKeys, clickToComment: current.clickToComment)
            return item
        }
        let toggle = item(toggleTitle(phase), #selector(AppDelegate.toggleSession), .toggleSession)
        toggle.isEnabled = phase.toggleIntent != .ignore
        menu.addItem(toggle)
        let comment = item("Comment on something", #selector(AppDelegate.addComment), .comment)
        let screenshot = item("Take a screenshot", #selector(AppDelegate.takeScreenshot), .screenshot)
        let clip = item(recordingClip ? "Stop the clip" : "Record a clip", #selector(AppDelegate.recordClip), .clip)
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

        labels[addQuit(to: menu)] = quitCombo.displayName
        // macOS adds its own symbols to items it recognises, such as a gear on "Settings…"; Koe draws none. The setter
        // is in the macOS 27 SDK only, and releases build with Xcode 26.3, so it is reached by name: 2 is `.hidden`.
        let hideImage = NSSelectorFromString("setPreferredImageVisibility:")
        for item in menu.items where item.responds(to: hideImage) {
            item.setValue(2, forKey: "preferredImageVisibility")
        }
        drawLabels(labels, in: menu)
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

    /// Returns the row that shows ⌘Q. A hidden twin holds the key equivalent, so ⌘Q still quits while the menu is
    /// open without making the menu keep a shortcut column (see `drawLabels`).
    private static func addQuit(to menu: NSMenu) -> NSMenuItem {
        let quit = NSMenuItem(title: "Quit Koe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.addItem(quit)
        let quitKey = NSMenuItem(title: "Quit Koe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitKey.isHidden = true
        quitKey.allowsKeyEquivalentWhenHidden = true
        menu.addItem(quitKey)
        return quit
    }

    private static let quitCombo = KeyCombo(keyCode: 12, modifiers: KeyCombo.command)

    /// Draws each row's shortcut into its title, right-aligned at the menu's edge. A key equivalent can't name a
    /// click, and any row with one makes the menu keep a shortcut column no title can reach, so no row has one: every
    /// shortcut is drawn this way and they all line up. The menu's padding is measured on a menu of one row.
    private static func drawLabels(_ labels: [NSMenuItem: String], in menu: NSMenu) {
        let font = NSFont.menuFont(ofSize: 0)
        let sample = NSAttributedString(string: "Koe", attributes: [.font: font])
        let probe = NSMenu()
        probe.addItem(NSMenuItem(title: "", action: nil, keyEquivalent: ""))
        probe.items[0].attributedTitle = sample
        let padding = probe.size.width - sample.size().width
        let gap: CGFloat = 24
        let widest = labels.map { item, label in
            NSAttributedString(string: item.title + label, attributes: [.font: font]).size().width + gap
        }.max() ?? 0
        let edge = max(widest, menu.size.width - padding)
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: edge)]
        for (item, label) in labels {
            let title = NSMutableAttributedString(string: item.title + "\t", attributes: [.font: font, .paragraphStyle: style])
            title.append(NSAttributedString(string: label, attributes: [
                .font: font, .paragraphStyle: style,
                .foregroundColor: item.isEnabled ? NSColor.tertiaryLabelColor : NSColor.quaternaryLabelColor,
            ]))
            item.attributedTitle = title
        }
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
