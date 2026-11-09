import AppKit
import SwiftUI

/// A borderless panel that takes keys without activating Koe, so the app you were in stays in front and gets its
/// focus back when the panel closes. Esc anywhere in it cancels, Return confirms.
@MainActor
final class ToolPanel: NSPanel {
    var onCancel: (() -> Void)?
    /// Return anywhere in the panel, when set.
    var onSubmit: (() -> Void)?
    private var escape: Any?

    init(frame: NSRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Floating HUDs are dark like the notch, whatever the theme.
        appearance = NSAppearance(named: .darkAqua)
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
        // Koe draws its own states, as the web does; the system's keyboard focus ring never shows.
        contentView = FirstMouseHostingView(rootView: view.focusEffectDisabled())
    }

    func present() {
        orderFrontRegardless()
        makeKey()
        // A text field's editor turns Esc into completion before it reaches the window, so watch for the key itself.
        escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self else { return event }
            if event.keyCode == 53 {
                onCancel?()
                return nil
            }
            if [36, 76].contains(event.keyCode), let onSubmit {
                onSubmit()
                return nil
            }
            return event
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
