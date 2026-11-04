import AppKit
import KoeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let permissions = PermissionCenter()
    private lazy var setup = SetupWindowController(center: permissions)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Typography.registerFonts()
        applyAppearance()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Icon.microphone.image(side: 16)
        item.button?.setAccessibilityLabel("Koe")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        if !permissions.checklist.isReady || CommandLine.arguments.contains("--setup") {
            setup.present()
        }
        // For screenshots: opens the menu as if clicked, since the status item can't be clicked by script.
        if CommandLine.arguments.contains("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { item.button?.performClick(nil) }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        permissions.refresh()
        StatusMenu.build(menu, checklist: permissions.checklist, target: self)
    }

    /// `defaults write studio.shinsa.koe appearance light|dark` (or `-appearance dark` at launch) pins a theme;
    /// unset, Koe follows the system.
    private func applyAppearance() {
        switch UserDefaults.standard.string(forKey: "appearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    @objc func openSetup() { setup.present() }

    @objc func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
