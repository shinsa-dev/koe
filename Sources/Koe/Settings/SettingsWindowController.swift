import AppKit
import SwiftUI

/// Koe's one window: its settings on a single page, Shinsa's cards on Shinsa's canvas under the traffic lights. First
/// launch opens it so you can allow the permissions. While it is open Koe shows in the Dock and in ⌘Tab.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let size = NSSize(width: 520, height: 660)

    private let permissions: PermissionCenter
    private let page: SettingsPage
    private var poll: Timer?
    private var placed = false
    /// Called when the window closes, so the app can leave the Dock again.
    var onClose: (() -> Void)?

    init(library: SessionLibrary, permissions: PermissionCenter, models: ModelStore, updater: Updater,
         openSessions: @escaping () -> Void) {
        self.permissions = permissions
        page = SettingsPage(library: library, permissions: permissions, models: models, updater: updater, openSessions: openSessions)
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
            library: library, permissions: permissions, models: models, updater: updater, openSessions: openSessions
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

    /// Draws the whole page at twice its size, as tall as it runs, in the app's appearance.
    func snapshot(to url: URL) {
        let view = NSHostingView(rootView: page
            .padding(28)
            .frame(width: Self.size.width)
            .fixedSize(horizontal: false, vertical: true)
            .background(Palette.canvas)
            .font(Typography.body)
            .foregroundStyle(Palette.fg4)
            .tint(Palette.action))
        view.appearance = NSApp.effectiveAppearance
        view.frame.size = view.fittingSize
        view.layoutSubtreeIfNeeded()
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
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
    let models: ModelStore
    let updater: Updater
    let openSessions: () -> Void

    var body: some View {
        ScrollView {
            SettingsPage(library: library, permissions: permissions, models: models, updater: updater, openSessions: openSessions)
                .padding(.horizontal, 28)
                .padding(.top, 52)
                .padding(.bottom, 28)
        }
        .scrollIndicators(.never)
        .background(Palette.canvas)
        // The page fades out under the window's controls instead of running through them.
        .overlay(alignment: .top) {
            LinearGradient(stops: [.init(color: Palette.canvas, location: 0), .init(color: Palette.canvas, location: 0.5),
                                   .init(color: Palette.canvas.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 60)
                .allowsHitTesting(false)
        }
        .font(Typography.body)
        .foregroundStyle(Palette.fg4)
        .tint(Palette.action)
        .ignoresSafeArea()
        .frame(width: SettingsWindowController.size.width, height: SettingsWindowController.size.height)
    }
}
