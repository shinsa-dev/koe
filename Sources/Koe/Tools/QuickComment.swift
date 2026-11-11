import AppKit
import KoeCore
import SwiftUI

/// The comment being said after a ⌘⇧-click. It shows what the comment tool shows (the dimmed screen, the window
/// you clicked and the pins) on a window that lets every click through, so the screen stays yours.
@MainActor
final class QuickComment {
    let picker: RegionPicker
    let presence = PinPresence()
    /// The spot, in Quartz space, so the next ⌘⇧-click can bring this pin along.
    let point: CGPoint
    var marks: ToolPanel?
    var keys: [UInt32] = []

    init(picker: RegionPicker, point: CGPoint) {
        self.picker = picker
        self.point = point
    }
}

@MainActor
@Observable
final class PinPresence {
    var shown = false
}

/// The comment tool's marks, arriving and leaving with a quick fade.
private struct QuickMarks: View {
    let picker: RegionPicker
    let index: Int
    let presence: PinPresence

    var body: some View {
        RegionPickerView(picker: picker, index: index, passive: true)
            .opacity(presence.shown ? 1 : 0)
            .onAppear { withAnimation(.easeOut(duration: 0.12)) { presence.shown = true } }
    }
}

extension ToolCoordinator {
    /// The comments this session has, counting the ones still being saved.
    var commentsSoFar: Int { sessions.attachments.filter(\.isComment).count + savingComments }

    /// Pins a comment at `point` (Quartz space, from the top left of the main screen) without freezing anything.
    /// What you say next is the comment, until Return, the pill's check, or your next click anywhere.
    func quickComment(at point: CGPoint) {
        let chained = quick
        if let chained {
            // A ⌘⇧-click opens nothing new in the app below, so the comments before stay and the new pin comes
            // out of the last one. Its marks stay up until the new ones replace them.
            quickTrail.append(chained.point)
            quickLeaving = chained.marks
            chained.marks = nil
            status.onConfirm?()
        } else {
            quickTrail = []
        }
        guard !isBusy else {
            dropLeavingMarks()
            return
        }
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
                dropLeavingMarks()
                sessions.post(notice: error.localizedDescription)
                sessions.close(ticket, with: nil)
                return
            }
            guard let index = freeze.screens.firstIndex(where: { $0.frame.contains(point) }) ?? freeze.screens.indices.first else {
                dropLeavingMarks()
                sessions.close(ticket, with: nil)
                return
            }
            open(on: freeze, index: index, at: point, ticket: ticket)
        }
    }

    private func open(on freeze: Freeze, index: Int, at point: CGPoint, ticket: AnnotationLedger.Ticket) {
        let origin = freeze.screens[index].frame.origin
        let screenFrame = freeze.screens[index].frame
        let carried = quickTrail.filter { screenFrame.contains($0) }
            .map { (screen: index, point: CGPoint(x: $0.x - origin.x, y: $0.y - origin.y)) }
        let picker = RegionPicker(freeze: freeze, purpose: .comment,
                                  commentsBefore: max(0, commentsSoFar - carried.count))
        picker.carry(carried)
        let voice = VoiceNote { [sessions] in sessions.currentTime }
        follow(picker, voice: voice, ticket: ticket)
        let finish = picker.onFinish
        picker.onFinish = { [weak self] choice in
            self?.endQuick()
            finish?(choice)
        }
        let comment = QuickComment(picker: picker, point: point)
        quick = comment
        picker.preset(click: CGPoint(x: point.x - origin.x, y: point.y - origin.y), note: nil, on: index)
        comment.marks = marks(for: comment, on: index, instantly: quickLeaving != nil)
        dropLeavingMarks()
        // No window of Koe's has the keys, so Return is held system-wide while the comment is open.
        comment.keys = [36, 76].compactMap { key in
            HotKeys.shared.register(KeyCombo(keyCode: key, modifiers: 0)) { [weak self] in self?.status.onConfirm?() }
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
        quickTrail = []
        status.onConfirm?()
    }

    private func endQuick() {
        guard let quick else { return }
        quick.keys.forEach(HotKeys.shared.unregister)
        self.quick = nil
        guard let marks = quick.marks else { return }
        withAnimation(.easeOut(duration: 0.14)) { quick.presence.shown = false } completion: {
            marks.close()
        }
    }

    private func dropLeavingMarks() {
        quickLeaving?.close()
        quickLeaving = nil
    }

    private func marks(for comment: QuickComment, on index: Int, instantly: Bool) -> ToolPanel {
        let panel = ToolPanel(frame: comment.picker.freeze.screens[index].screen.frame, level: .statusBar)
        panel.ignoresMouseEvents = true
        if instantly { comment.presence.shown = true }
        panel.host(QuickMarks(picker: comment.picker, index: index, presence: comment.presence))
        panel.orderFrontRegardless()
        return panel
    }
}
