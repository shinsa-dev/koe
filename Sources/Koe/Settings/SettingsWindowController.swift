import AppKit
import SwiftUI

/// Koe's one window, drawn as Shinsa's desktop app draws settings: a sidebar of panes under the traffic lights and
/// the chosen pane as a page beside it. First launch opens it on Permissions. While it is open Koe shows in the Dock
/// and in ⌘Tab.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Pane: Int, CaseIterable, Identifiable {
        case general, permissions, shortcuts

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .permissions: "Permissions"
            case .shortcuts: "Shortcuts"
            }
        }

        var line: String {
            switch self {
            case .general: "What Koe copies when you stop, and how it looks."
            case .permissions: "Koe hears you and sees your screen on this Mac only. Nothing you say or capture leaves it."
            case .shortcuts: "They work in every app. You can't change them yet."
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

    @Observable final class Selection {
        var pane: Pane = .general
    }

    static let size = NSSize(width: 720, height: 500)

    private let permissions: PermissionCenter
    private let selection = Selection()
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
            selection: selection, library: library, permissions: permissions, openSessions: openSessions
        ))
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isOpen: Bool { window?.isVisible ?? false }

    func present(_ pane: Pane? = nil) {
        permissions.refresh()
        if let pane { selection.pane = pane }
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
    @Bindable var selection: SettingsWindowController.Selection
    let library: SessionLibrary
    let permissions: PermissionCenter
    let openSessions: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: selection, isReady: permissions.checklist.isReady)
            Rectangle().fill(Palette.border).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selection.pane.title).font(Typography.pageTitle).foregroundStyle(Palette.fg4)
                        Text(selection.pane.line)
                            .font(Typography.body)
                            .foregroundStyle(Palette.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    switch selection.pane {
                    case .general: GeneralPane(library: library, permissions: permissions, openSessions: openSessions)
                    case .permissions: PermissionsPane(center: permissions)
                    case .shortcuts: ShortcutsPane()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 44)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.never)
            .background(Palette.canvas)
        }
        .font(Typography.body)
        .foregroundStyle(Palette.fg4)
        .tint(Palette.action)
        .ignoresSafeArea()
        .frame(width: SettingsWindowController.size.width, height: SettingsWindowController.size.height)
    }
}

private struct Sidebar: View {
    @Bindable var selection: SettingsWindowController.Selection
    let isReady: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 22, height: 22)
                Text("Koe").font(Typography.title).foregroundStyle(Palette.fg4)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)
            ForEach(SettingsWindowController.Pane.allCases) { pane in
                SidebarRow(pane: pane, chosen: selection.pane == pane,
                           needsYou: pane == .permissions && !isReady) { selection.pane = pane }
            }
            Spacer()
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")")
                .font(Typography.meta)
                .foregroundStyle(Palette.fg1)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 10)
        .padding(.top, 48)
        .padding(.bottom, 14)
        .frame(width: 200, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(Palette.sidebar)
    }
}

/// The desktop sidebar's nav row: a glyph and a label, the chosen row on a bg-a2 wash.
private struct SidebarRow: View {
    let pane: SettingsWindowController.Pane
    let chosen: Bool
    let needsYou: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                IconView(icon: pane.icon, size: .medium, color: chosen ? Palette.fg4 : Palette.icon2)
                    .frame(width: 18)
                Text(pane.title)
                    .font(chosen ? Typography.label : Typography.meta)
                    .foregroundStyle(chosen ? Palette.fg4 : Palette.fg3)
                Spacer(minLength: 0)
                if needsYou {
                    Circle().fill(Tone.amber.solid).frame(width: 6, height: 6).accessibilityLabel("Needs you")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(chosen ? Palette.press : hovering ? Palette.hover : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
