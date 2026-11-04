import AppKit
import SwiftUI

/// Koe's one window: a standard macOS settings window with General, Permissions and Shortcuts in its toolbar.
/// First launch opens it on Permissions. While it is open Koe shows in the Dock and in ⌘Tab.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Pane: Int, CaseIterable {
        case general, permissions, shortcuts

        var title: String {
            switch self {
            case .general: "General"
            case .permissions: "Permissions"
            case .shortcuts: "Shortcuts"
            }
        }

        var icon: Icon {
            switch self {
            case .general: .settings
            case .permissions: .permissions
            case .shortcuts: .shortcuts
            }
        }
    }

    private let permissions: PermissionCenter
    private let tabs = NSTabViewController()
    private var poll: Timer?
    private var placed = false
    /// Called when the window closes, so the app can leave the Dock again.
    var onClose: (() -> Void)?

    init(library: SessionLibrary, permissions: PermissionCenter, openSessions: @escaping () -> Void) {
        self.permissions = permissions
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.allowUserInteraction]
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.backgroundColor = Tokens.background
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        for pane in Pane.allCases {
            let root: AnyView = switch pane {
            case .general: AnyView(GeneralPane(library: library, permissions: permissions, openSessions: openSessions))
            case .permissions: AnyView(PermissionsPane(center: permissions))
            case .shortcuts: AnyView(ShortcutsPane())
            }
            let host = NSHostingController(rootView: root)
            host.sizingOptions = [.preferredContentSize]
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = pane.icon.image(side: 16)
            tabs.addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isOpen: Bool { window?.isVisible ?? false }

    func present(_ pane: Pane? = nil) {
        permissions.refresh()
        if let pane { tabs.selectedTabViewItemIndex = pane.rawValue }
        guard let window else { return }
        if !placed {
            window.layoutIfNeeded()
            window.center()
            placed = true
        }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        startPolling()
    }

    func windowWillClose(_ notification: Notification) {
        poll?.invalidate()
        poll = nil
        onClose?()
    }

    /// System Settings sends no notice when a switch flips, so the window looks again every second while it is open.
    private func startPolling() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.permissions.refresh() }
        }
    }
}
