import AppKit
import KoeCore
import SwiftUI

/// A borderless panel that floats over every app and space without taking focus, so you keep typing where you were.
/// The panel is larger than the pill and clear around it: clicks there go through to the app below.
@MainActor
final class PillPanel: NSPanel {
    static let size = NSSize(width: 560, height: 80)
    /// Room under the pill inside the panel, which puts the pill this far above the Dock or the screen's edge.
    static let bottomInset: CGFloat = 14
    /// How far above the bottom of the screen a note card or the clip review starts: just above the pill.
    static let cardsAbove: CGFloat = 58

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Floating HUDs are dark like the notch, whatever the theme.
        appearance = NSAppearance(named: .darkAqua)
        isFloatingPanel = true
        // Above the frozen screen the tools put up, since the pill says what to do while it shows.
        level = Self.level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let host = FirstClickHostingView(rootView: rootView
            .padding(.bottom, Self.bottomInset)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom)
            .focusEffectDisabled())
        contentView = host
    }

    static let level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the first click, so the stop button works without first focusing a panel that never takes focus.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows the pill at the bottom centre of the screen you're working on, and hides it when the session ends.
@MainActor
final class PillController {
    private let panel: PillPanel
    private var pendingHide: Task<Void, Never>?

    private let presence = PillPresence()
    private let sessions: SessionController
    private var list: ToolPanel?
    private var listWatch: Task<Void, Never>?
    private var viewer: ToolPanel?

    init(sessions: SessionController, tools: PillTools) {
        self.sessions = sessions
        panel = PillPanel(rootView: PillEntrance(presence: presence) {
            PillView(sessions: sessions, tools: tools)
        })
    }

    /// Opens the list of what the session holds just above the pill, or closes it.
    func toggleAttachments() {
        if list != nil { return closeAttachments() }
        guard !sessions.attachments.isEmpty else { return }
        let size = NSSize(width: AttachmentList.width + 40, height: 440)
        let frame = panel.frame
        let list = ToolPanel(frame: NSRect(x: frame.midX - size.width / 2, y: frame.minY + PillPanel.cardsAbove - 20,
                                           width: size.width, height: size.height), level: PillPanel.level)
        list.host(AttachmentList(sessions: sessions, open: { [weak self] in self?.view($0) },
                                 close: { [weak self] in self?.closeAttachments() })
            .padding(.bottom, 20)
            .frame(width: size.width, height: size.height, alignment: .bottom))
        list.onCancel = { [weak self] in self?.closeAttachments() }
        list.orderFrontRegardless()
        self.list = list
        // It closes once the session has nothing left to list, or the session ends.
        listWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                if sessions.attachments.isEmpty || !sessions.phase.isOpen { closeAttachments() }
            }
        }
    }

    /// Opens one attachment large over the screen the pill is on.
    private func view(_ annotation: Annotation) {
        closeViewer()
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let viewer = ToolPanel(frame: screen.frame, level: NSWindow.Level(rawValue: PillPanel.level.rawValue + 1))
        viewer.host(AttachmentViewer(annotation: annotation, screen: screen.frame.size,
                                     close: { [weak self] in self?.closeViewer() }))
        viewer.onCancel = { [weak self] in self?.closeViewer() }
        viewer.present()
        self.viewer = viewer
    }

    private func closeViewer() {
        viewer?.close()
        viewer = nil
    }

    func closeAttachments() {
        closeViewer()
        listWatch?.cancel()
        listWatch = nil
        list?.close()
        list = nil
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        pendingHide?.cancel()
        if !panel.isVisible {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: visible.midX - PillPanel.size.width / 2, y: visible.minY))
            }
            panel.orderFrontRegardless()
        }
        guard !presence.shown else { return }
        withAnimation(PillPresence.entrance) { presence.shown = true }
    }

    /// Leaves the pill up a moment so you can read what it says, unless `keep` says it is needed again by then.
    func hide(after delay: Duration, unless keep: @escaping @MainActor () -> Bool) {
        pendingHide?.cancel()
        pendingHide = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, !keep() else { return }
            self?.hide()
        }
    }

    func hide() {
        closeAttachments()
        pendingHide?.cancel()
        guard panel.isVisible, presence.shown else { return }
        withAnimation(PillPresence.exit) { presence.shown = false } completion: { [panel, presence] in
            if !presence.shown { panel.orderOut(nil) }
        }
    }
}

/// Whether the pill is on screen, animated in SwiftUI so it arrives and leaves the way its content changes.
@MainActor
@Observable
final class PillPresence {
    var shown = false

    static let entrance = Animation.spring(duration: 0.42, bounce: 0.3)
    static let exit = Animation.spring(duration: 0.28, bounce: 0)
}

/// The pill grows in from slightly small and blurred with a small bounce, and leaves the same way in reverse.
private struct PillEntrance<Content: View>: View {
    let presence: PillPresence
    @ViewBuilder var content: Content

    var body: some View {
        content
            .scaleEffect(presence.shown ? 1 : 0.86, anchor: .bottom)
            .blur(radius: presence.shown ? 0 : 8)
            .opacity(presence.shown ? 1 : 0)
    }
}
