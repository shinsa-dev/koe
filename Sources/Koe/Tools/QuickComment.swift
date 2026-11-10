import AppKit
import KoeCore

/// The comment being said after a ⌘⇧-click. There is no overlay: the screen was pictured at the click and stays
/// yours, with only the comment's pin left where you clicked.
@MainActor
final class QuickComment {
    let picker: RegionPicker
    var marker: ToolPanel?
    var keys: [UInt32] = []

    init(picker: RegionPicker) {
        self.picker = picker
    }
}

extension ToolCoordinator {
    /// The comments this session has, counting the ones still being saved.
    var commentsSoFar: Int { sessions.attachments.filter(\.isComment).count + savingComments }

    /// Pins a comment at `point` (Quartz space, from the top left of the main screen) without freezing anything.
    /// What you say next is the comment, until Return, the pill's check, or the next ⌘⇧-click.
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
            comment.marker = marker(at: point, number: picker.commentNumber)
            // No window of Koe's has the keys, so Return is held system-wide while the comment is open.
            comment.keys = [36, 76].compactMap { key in
                HotKeys.shared.register(KeyCombo(keyCode: key, modifiers: 0)) { [weak self] in self?.status.onConfirm?() }
            }
        }
    }

    private func endQuick() {
        quick?.marker?.close()
        quick?.keys.forEach(HotKeys.shared.unregister)
        quick = nil
    }

    private func marker(at point: CGPoint, number: Int) -> ToolPanel {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let side: CGFloat = 34
        let panel = ToolPanel(frame: NSRect(x: point.x - side / 2, y: mainHeight - point.y - side / 2, width: side, height: side),
                              level: .statusBar)
        panel.ignoresMouseEvents = true
        panel.host(Pin(number: number, saved: false))
        panel.orderFrontRegardless()
        return panel
    }
}
