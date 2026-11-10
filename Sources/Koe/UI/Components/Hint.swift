import AppKit
import SwiftUI

extension View {
    /// The web's `Hint`: a tooltip with a label and an optional key, in place of the system's `help` tag. It opens
    /// only after the pointer rests 700 ms; moving straight on to a neighbour while one shows swaps it without the
    /// wait. A click closes it and starts the wait over. It fades in and out.
    func hint(_ label: String, shortcut: String? = nil) -> some View {
        background(HintAnchor(label: label, shortcut: shortcut))
    }
}

/// The web's tooltip: 12 fg-4 on the popover colour with a bg-3 hairline, rounded 7, at least 24 tall; a key sits
/// at the end on a bg-a2 tile 16 tall.
struct HintBubble: View {
    let label: String
    let shortcut: String?
    @State private var shown = false

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Typography.meta)
                .foregroundStyle(Palette.fg4)
                .padding(.trailing, shortcut == nil ? 0 : 4)
            if let shortcut {
                Text(shortcut)
                    .font(Typography.label)
                    .foregroundStyle(Palette.fg3)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Palette.press, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .lineLimit(1)
        .padding(.leading, 8)
        // A key sits as far from the end as from the top and bottom.
        .padding(.trailing, shortcut == nil ? 8 : 4)
        .padding(.vertical, shortcut == nil ? 4 : 2)
        .frame(minHeight: 24)
        .background(Palette.popover, in: shape)
        .overlay(shape.strokeBorder(Palette.ringHover, lineWidth: 1))
        .fixedSize()
        .padding(2)
        .scaleEffect(shown ? 1 : 0.96, anchor: .bottom)
        .offset(y: shown ? 0 : 2)
        .onAppear { withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.22)) { shown = true } }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 7, style: .continuous) }
}

private struct HintAnchor: NSViewRepresentable {
    let label: String
    let shortcut: String?

    func makeNSView(context: Context) -> HintAnchorView {
        let view = HintAnchorView()
        view.label = label
        view.shortcut = shortcut
        return view
    }

    func updateNSView(_ view: HintAnchorView, context: Context) {
        view.label = label
        view.shortcut = shortcut
    }

    static func dismantleNSView(_ view: HintAnchorView, coordinator: ()) {
        HintCenter.shared.leave(view)
    }
}

final class HintAnchorView: NSView {
    var label = ""
    var shortcut: String?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { HintCenter.shared.enter(self) }
    override func mouseExited(with event: NSEvent) { HintCenter.shared.leave(self) }
    override func mouseDown(with event: NSEvent) { HintCenter.shared.leave(self, clicked: true) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { HintCenter.shared.leave(self) }
    }
}

/// One tooltip for the whole app, as on the web: one panel that moves between anchors.
@MainActor
final class HintCenter {
    static let shared = HintCenter()

    private var panel: NSPanel?
    private weak var anchor: HintAnchorView?
    private var pending: Task<Void, Never>?
    private var lastClosed = Date.distantPast

    func enter(_ view: HintAnchorView) {
        anchor = view
        pending?.cancel()
        let warm = Date().timeIntervalSince(lastClosed) < 0.3
        pending = Task { [weak self, weak view] in
            if !warm { try? await Task.sleep(for: .milliseconds(700)) }
            guard !Task.isCancelled, let self, let view, self.anchor === view else { return }
            self.show(for: view)
        }
    }

    func leave(_ view: HintAnchorView, clicked: Bool = false) {
        guard anchor === view else { return }
        anchor = nil
        pending?.cancel()
        guard let panel, panel.isVisible, panel.alphaValue > 0 else { return }
        // Only moving off a showing hint keeps the next one warm; a click starts the wait again.
        lastClosed = clicked ? .distantPast : Date()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if self?.anchor == nil { panel.orderOut(nil) }
            }
        }
    }

    private func show(for view: HintAnchorView) {
        guard let window = view.window else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.appearance = window.effectiveAppearance
        let host = NSHostingView(rootView: HintBubble(label: view.label, shortcut: view.shortcut))
        panel.contentView = host
        let size = host.fittingSize
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 2)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
            if origin.y + size.height > screen.maxY { origin.y = rect.minY - size.height - 2 }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the pill, which floats over the tools' frozen screen.
        panel.level = NSWindow.Level(rawValue: PillPanel.level.rawValue + 1)
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        return panel
    }
}
