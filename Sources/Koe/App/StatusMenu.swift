import AppKit
import KoeCore

/// What Koe's menu bar item shows. Rebuilt each time it opens, so the setup line is always current.
@MainActor
enum StatusMenu {
    static func build(_ menu: NSMenu, checklist: SetupChecklist, target: AppDelegate) {
        menu.removeAllItems()
        menu.autoenablesItems = false

        let state = NSMenuItem(title: checklist.isReady ? "Koe is ready" : "Koe needs permissions", action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
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
}
