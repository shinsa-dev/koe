import AppKit
import SwiftUI

/// A titled window around `SettingsView`, drawn as the setup window is. While open it checks Accessibility each
/// second, since flipping it in System Settings sends no notice.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let permissions: PermissionCenter
    private var poll: Timer?

    init(library: SessionLibrary, permissions: PermissionCenter, openSessions: @escaping () -> Void) {
        self.permissions = permissions
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = Tokens.background
        window.isReleasedWhenClosed = false
        window.title = "Koe settings"
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: SettingsView(
            library: library, permissions: permissions, openSessions: openSessions
        ))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        permissions.refresh()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.permissions.refresh() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        poll?.invalidate()
        poll = nil
    }
}
