import AppKit
import SwiftUI

/// A plain titled window around `SetupView`, drawn on Shinsa's canvas with the title bar folded into it.
@MainActor
final class SetupWindowController: NSWindowController, NSWindowDelegate {
    private let center: PermissionCenter
    private var poll: Timer?

    init(center: PermissionCenter) {
        self.center = center
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
        window.title = "Set up Koe"
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: SetupView(center: center) { [weak self] in
            self?.close()
        })
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        center.refresh()
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        startPolling()
    }

    func windowWillClose(_ notification: Notification) {
        poll?.invalidate()
        poll = nil
    }

    /// System Settings sends no notice when a switch flips, so the window looks again every second while it is open.
    private func startPolling() {
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.center.refresh() }
        }
    }
}
