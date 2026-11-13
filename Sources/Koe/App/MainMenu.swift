import AppKit

/// The menu bar Koe shows while its window is open: the standard app, Edit and Window menus.
@MainActor
enum MainMenu {
    static func build(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let app = NSMenu(title: "Koe")
        app.addItem(item("About Koe", #selector(AppDelegate.showAbout), "", target: target))
        app.addItem(.separator())
        app.addItem(item("Settings…", #selector(AppDelegate.openSettings), ",", target: target))
        app.addItem(.separator())
        app.addItem(item("Hide Koe", #selector(NSApplication.hide(_:)), "h"))
        let others = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(others)
        app.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:)), ""))
        app.addItem(.separator())
        app.addItem(item("Quit Koe", #selector(NSApplication.terminate(_:)), "q"))
        add(app, to: main)

        let edit = NSMenu(title: "Edit")
        edit.addItem(item("Undo", Selector(("undo:")), "z"))
        let redo = item("Redo", Selector(("redo:")), "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        add(edit, to: main)

        let window = NSMenu(title: "Window")
        window.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        add(window, to: main)
        NSApp.windowsMenu = window
        return main
    }

    private static func add(_ menu: NSMenu, to main: NSMenu) {
        let holder = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        main.addItem(holder)
    }

    private static func item(_ title: String, _ action: Selector, _ key: String, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
