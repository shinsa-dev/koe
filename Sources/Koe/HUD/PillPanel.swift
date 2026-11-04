import AppKit
import SwiftUI

/// A borderless panel that floats over every app and space without taking focus, so you keep typing where you were.
/// The panel is larger than the pill and clear around it: clicks there go through to the app below.
@MainActor
final class PillPanel: NSPanel {
    static let size = NSSize(width: 560, height: 110)
    /// Room above the pill inside the panel, which puts the pill this far under the menu bar.
    static let topInset: CGFloat = 8
    /// How far under the top of the screen a note card opens: below a two-line pill.
    static let noteTop: CGFloat = 76

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
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
            .padding(.top, Self.topInset)
            .frame(width: Self.size.width, height: Self.size.height, alignment: .top))
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the first click, so the stop button works without first focusing a panel that never takes focus.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows the pill at the top centre of the screen you're working on, and hides it when the session ends.
@MainActor
final class PillController {
    private let panel: PillPanel

    init(sessions: SessionController, onDrop: @escaping ([URL]) -> Void) {
        panel = PillPanel(rootView: PillView(sessions: sessions, onDrop: onDrop))
    }

    var isVisible: Bool { panel.isVisible }

    func show() {
        guard !panel.isVisible else { return }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - PillPanel.size.width / 2, y: visible.maxY - PillPanel.size.height))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [panel] in
            MainActor.assumeIsolated { if panel.alphaValue == 0 { panel.orderOut(nil) } }
        }
    }
}
