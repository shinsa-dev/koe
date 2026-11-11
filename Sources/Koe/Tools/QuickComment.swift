import AppKit
import KoeCore
import SwiftUI

/// The comment being said after a ⌘⇧-click. There is no overlay: the screen was pictured at the click and stays
/// yours, with only the comment's pin left where you clicked.
@MainActor
final class QuickComment {
    let picker: RegionPicker
    let presence = PinPresence()
    var marker: ToolPanel?
    var keys: [UInt32] = []

    init(picker: RegionPicker) {
        self.picker = picker
    }
}

@MainActor
@Observable
final class PinPresence {
    var shown = false
}

/// The pin of a ⌘⇧-click: it arrives and leaves the way the pill does, only smaller.
private struct QuickPin: View {
    let number: Int
    let presence: PinPresence

    var body: some View {
        Pin(number: number, saved: false)
            .scaleEffect(presence.shown ? 1 : 0.7)
            .blur(radius: presence.shown ? 0 : 4)
            .opacity(presence.shown ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { withAnimation(.spring(duration: 0.2, bounce: 0.2)) { presence.shown = true } }
    }
}

extension ToolCoordinator {
    /// The comments this session has, counting the ones still being saved.
    var commentsSoFar: Int { sessions.attachments.filter(\.isComment).count + savingComments }

    /// Pins a comment at `point` (Quartz space, from the top left of the main screen) without freezing anything.
    /// What you say next is the comment, until Return, the pill's check, or your next click anywhere.
    func quickComment(at point: CGPoint) {
        if quick != nil { status.onConfirm?() }
        guard !isBusy else { return }
        permissions.refresh()
        guard backdrop != nil || permissions.checklist.status(of: .screenRecording) == .granted else {
            presentSetup()
            return
        }
        guard ensureSession(), let ticket = sessions.openTicket() else { return }
        freezing = true
        Task { [self] in
            defer { freezing = false }
            let freeze: Freeze
            do {
                if let backdrop { freeze = .backdrop(backdrop) } else { freeze = try await ScreenFreezer.freeze() }
            } catch {
                sessions.post(notice: error.localizedDescription)
                sessions.close(ticket, with: nil)
                return
            }
            guard let index = freeze.screens.firstIndex(where: { $0.frame.contains(point) }) ?? freeze.screens.indices.first else {
                sessions.close(ticket, with: nil)
                return
            }
            let picker = RegionPicker(freeze: freeze, purpose: .comment, commentsBefore: commentsSoFar)
            let voice = VoiceNote { [sessions] in sessions.currentTime }
            follow(picker, voice: voice, ticket: ticket)
            let finish = picker.onFinish
            picker.onFinish = { [weak self] choice in
                self?.endQuick()
                finish?(choice)
            }
            let comment = QuickComment(picker: picker)
            quick = comment
            let origin = freeze.screens[index].frame.origin
            picker.preset(click: CGPoint(x: point.x - origin.x, y: point.y - origin.y), note: nil, on: index)
            comment.marker = marker(at: point, number: picker.commentNumber, presence: comment.presence)
            // No window of Koe's has the keys, so Return is held system-wide while the comment is open.
            comment.keys = [36, 76].compactMap { key in
                HotKeys.shared.register(KeyCombo(keyCode: key, modifiers: 0)) { [weak self] in self?.status.onConfirm?() }
            }
        }
    }

    /// A click that went to the app under the pin: the comment is kept with what you said, and its pin leaves
    /// quickly, since the page it pointed at may be gone. A click on Koe's own windows is theirs.
    func clickedElsewhere(at point: CGPoint) {
        guard quick != nil else { return }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let spot = NSPoint(x: point.x, y: mainHeight - point.y)
        let onKoe = NSApp.windows.contains { $0.isVisible && !$0.ignoresMouseEvents && $0.frame.contains(spot) }
        guard !onKoe else { return }
        status.onConfirm?()
    }

    private func endQuick() {
        guard let quick else { return }
        quick.keys.forEach(HotKeys.shared.unregister)
        self.quick = nil
        guard let marker = quick.marker else { return }
        withAnimation(.easeOut(duration: 0.14)) { quick.presence.shown = false } completion: {
            marker.close()
        }
    }

    private func marker(at point: CGPoint, number: Int, presence: PinPresence) -> ToolPanel {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        // Room around the pin for its swell and blur, so neither is cut at the window's edge.
        let side: CGFloat = 64
        let panel = ToolPanel(frame: NSRect(x: point.x - side / 2, y: mainHeight - point.y - side / 2, width: side, height: side),
                              level: .statusBar)
        panel.ignoresMouseEvents = true
        panel.host(QuickPin(number: number, presence: presence))
        panel.orderFrontRegardless()
        return panel
    }
}
