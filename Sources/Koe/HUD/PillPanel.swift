import AppKit
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
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let host = FirstClickHostingView(rootView: rootView
            .padding(.bottom, Self.bottomInset)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .bottom))
        contentView = host
    }

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

    init(sessions: SessionController, onDrop: @escaping ([URL]) -> Void) {
        panel = PillPanel(rootView: PillView(sessions: sessions, onDrop: onDrop))
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        pendingHide?.cancel()
        guard !panel.isVisible else {
            panel.animator().alphaValue = 1
            return
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - PillPanel.size.width / 2, y: visible.minY))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
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
        pendingHide?.cancel()
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
        }
    }
}
