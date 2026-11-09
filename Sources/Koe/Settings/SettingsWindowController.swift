import AppKit
import SwiftUI

/// Koe's one window: its settings on a single page, Shinsa's cards on Shinsa's canvas under the traffic lights. First
/// launch opens it so you can allow the permissions. While it is open Koe shows in the Dock and in ⌘Tab.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let size = NSSize(width: 520, height: 660)

    private let permissions: PermissionCenter
    private var poll: Timer?
    private var placed = false
    /// Called when the window closes, so the app can leave the Dock again.
    var onClose: (() -> Void)?

    init(library: SessionLibrary, permissions: PermissionCenter, openSessions: @escaping () -> Void) {
        self.permissions = permissions
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Koe"
        window.isMovableByWindowBackground = true
        window.backgroundColor = Tokens.background
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsRoot(
            library: library, permissions: permissions, openSessions: openSessions
        ).focusEffectDisabled())
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isOpen: Bool { window?.isVisible ?? false }

    func present() {
        permissions.refresh()
        guard let window else { return }
        if !placed {
            window.setContentSize(Self.size)
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

private struct SettingsRoot: View {
    let library: SessionLibrary
    let permissions: PermissionCenter
    let openSessions: () -> Void

    var body: some View {
        ScrollView {
            SettingsPage(library: library, permissions: permissions, openSessions: openSessions)
                .padding(.horizontal, 28)
                .padding(.top, 52)
                .padding(.bottom, 28)
        }
        .scrollIndicators(.never)
        .background(Palette.canvas)
        .font(Typography.body)
        .foregroundStyle(Palette.fg4)
        .tint(Palette.action)
        .ignoresSafeArea()
        .frame(width: SettingsWindowController.size.width, height: SettingsWindowController.size.height)
    }
}
