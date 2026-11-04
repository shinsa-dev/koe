import AppKit
import SwiftUI

/// A borderless panel that takes typing without activating Koe, so the app you were in stays in front and gets its
/// focus back when the panel closes. Esc anywhere in it cancels.
@MainActor
final class ToolPanel: NSPanel {
    var onCancel: (() -> Void)?
    private var escape: Any?

    init(frame: NSRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Setting isFloatingPanel resets the level, so it goes first.
        isFloatingPanel = true
        self.level = level
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func host<Content: View>(_ view: Content) {
        contentView = FirstMouseHostingView(rootView: view)
    }

    func present() {
        orderFrontRegardless()
        makeKey()
        // A text field's editor turns Esc into completion before it reaches the window, so watch for the key itself.
        escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, event.window === self else { return event }
            onCancel?()
            return nil
        }
    }

    override func close() {
        if let escape { NSEvent.removeMonitor(escape) }
        escape = nil
        super.close()
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
