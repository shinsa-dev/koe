import AppKit
import KoeCore

/// What Koe's menu bar item shows. Rebuilt each time it opens, so the session and setup lines are always current.
@MainActor
enum StatusMenu {
    static func build(_ menu: NSMenu, checklist: SetupChecklist, phase: RecorderPhase, hotKeyTaken: Bool, target: AppDelegate) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        let state = NSMenuItem(title: stateLine(checklist: checklist, phase: phase), action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        if hotKeyTaken {
            let taken = NSMenuItem(
                title: "Another app uses \(KeyCombo.toggleSession.displayName), so start dictation from here.",
                action: nil, keyEquivalent: ""
            )
            taken.isEnabled = false
            menu.addItem(taken)
        }
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: toggleTitle(phase), action: #selector(AppDelegate.toggleSession), keyEquivalent: "")
        toggle.target = target
        toggle.isEnabled = phase.toggleIntent != .ignore
        // Display only: a status item's menu never fires its key equivalents; the hotkey is global.
        if !hotKeyTaken {
            toggle.keyEquivalent = " "
            toggle.keyEquivalentModifierMask = .option
        }
        menu.addItem(toggle)
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
