import AppKit
import KoeCore
import os
import SwiftUI

/// Runs the tools you use while talking: a screenshot of a region or window, a typed note, and files dropped on the
/// pill. Each is stamped with the session's audio time at the moment you start it, and starts a session when none
/// is running.
@MainActor
final class ToolCoordinator {
    private let sessions: SessionController
    private let permissions: PermissionCenter
    /// Starts a session when none runs (or opens setup when it can't) and says whether one is running now.
    private let ensureSession: () -> Bool
    private let presentSetup: () -> Void
    private var overlay: [ToolPanel] = []
    private var notePanel: ToolPanel?
    private static let log = Logger(subsystem: "studio.shinsa.koe", category: "tools")

    /// Replaces the live screen capture for `--backdrop`, so captures of Koe show a known image, not your screen.
    var backdrop: CGImage?

    init(sessions: SessionController, permissions: PermissionCenter, ensureSession: @escaping () -> Bool,
         presentSetup: @escaping () -> Void) {
        self.sessions = sessions
        self.permissions = permissions
        self.ensureSession = ensureSession
        self.presentSetup = presentSetup
    }

    var isBusy: Bool { !overlay.isEmpty || notePanel != nil }

    // MARK: Screenshot

    func screenshot(preset: CGRect? = nil, note: String? = nil, holds: Bool = true) {
        guard !isBusy else { return }
        permissions.refresh()
        guard backdrop != nil || permissions.checklist.status(of: .screenRecording) == .granted else {
            presentSetup()
            return
        }
        guard ensureSession(), let ticket = sessions.openTicket() else { return }
        Task { [self] in
            let freeze: Freeze
            do {
                if let backdrop {
                    freeze = Freeze.backdrop(backdrop)
                } else {
                    freeze = try await ScreenFreezer.freeze()
                }
            } catch {
                Self.log.error("Freeze failed: \(error.localizedDescription, privacy: .public)")
                sessions.post(notice: error.localizedDescription)
                sessions.close(ticket, with: nil)
                return
            }
            let picker = RegionPicker(freeze: freeze)
            if let preset { picker.preset(preset, note: note) }
            showOverlay(for: picker)
            picker.onFinish = { [weak self] choice in
                self?.closeOverlay()
                self?.save(choice, ticket: ticket)
            }
            if preset != nil, !holds {
                try? await Task.sleep(for: .milliseconds(600))
                picker.submit()
            }
        }
    }

    private func showOverlay(for picker: RegionPicker) {
        overlay = picker.freeze.screens.indices.map { index in
            let panel = ToolPanel(frame: picker.freeze.screens[index].screen.frame, level: .screenSaver)
            panel.host(RegionPickerView(picker: picker, index: index))
            panel.onCancel = { picker.cancel() }
            return panel
        }
        picker.onNoting = { [weak self] index in self?.overlay[safe: index]?.makeKey() }
        let underMouse = picker.freeze.screens.firstIndex { NSMouseInRect(NSEvent.mouseLocation, $0.screen.frame, false) } ?? 0
        for (index, panel) in overlay.enumerated() where index != underMouse { panel.orderFrontRegardless() }
        overlay[safe: underMouse]?.present()
        if case .noting(let index, _) = picker.stage { overlay[safe: index]?.makeKey() }
    }

    private func closeOverlay() {
        overlay.forEach { $0.close() }
        overlay = []
    }

    private func save(_ choice: RegionChoice?, ticket: AnnotationLedger.Ticket) {
        guard let choice,
              let pixels = ScreenGeometry.pixelRect(
                  of: choice.region, screenSize: choice.screen.frame.size,
                  imageSize: CGSize(width: choice.screen.image.width, height: choice.screen.image.height)
              ),
              let crop = choice.screen.image.cropping(to: pixels),
              let url = try? sessions.screenshotURL()
        else {
            sessions.close(ticket, with: nil)
            return
        }
        let note = choice.note
        let source = choice.source
        Task {
            do {
                try await Task.detached { try PNG.write(crop, to: url) }.value
                sessions.close(ticket, with: Annotation(time: ticket.time, kind: .screenshot(Asset(url: url)), note: note, source: source))
            } catch {
                sessions.post(notice: "Koe couldn't save the screenshot.")
                sessions.close(ticket, with: nil)
            }
        }
    }

    // MARK: Note

    func note(text: String? = nil, holds: Bool = true) {
        guard !isBusy, ensureSession(), let ticket = sessions.openTicket() else { return }
        let model = NoteModel(text: text ?? "")
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = NSSize(width: NoteCard.width + 40, height: NoteCard.height + 40)
        let panel = ToolPanel(
            frame: NSRect(x: visible.midX - size.width / 2, y: visible.maxY - PillPanel.noteTop - size.height,
                          width: size.width, height: size.height),
            level: .popUpMenu
        )
        let finish: (Bool) -> Void = { [weak self] keep in
            guard let self, notePanel != nil else { return }
            notePanel?.close()
            notePanel = nil
            let annotation = keep ? Annotation(time: ticket.time, kind: .note, note: model.text) : nil
            sessions.close(ticket, with: annotation?.trimmedNote == nil ? nil : annotation)
        }
        panel.host(NoteCard(
            placeholder: "Write a note for the agent", action: "Add note",
            text: Binding(get: { model.text }, set: { model.text = $0 }),
            submit: { finish(true) }, cancel: { finish(false) }
        )
        .padding(.top, 8)
        .frame(width: size.width, height: size.height, alignment: .top))
        panel.onCancel = { finish(false) }
        notePanel = panel
        panel.present()
        if text != nil, !holds {
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                finish(true)
            }
        }
    }

    // MARK: Drop

    /// Files dropped on the pill, copied into the session's folder so the bundle still has them if the originals move.
    func drop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            guard let ticket = sessions.openTicket() else { return }
            guard let copy = try? sessions.fileURL(named: url.lastPathComponent) else {
                sessions.close(ticket, with: nil)
                continue
            }
            Task {
                do {
                    try await Task.detached { try FileManager.default.copyItem(at: url, to: copy) }.value
                    sessions.close(ticket, with: Annotation(time: ticket.time, kind: .file(Asset(url: copy))))
                } catch {
                    Self.log.error("Copy failed: \(error.localizedDescription, privacy: .public)")
                    sessions.post(notice: "Koe couldn't attach \(url.lastPathComponent).")
                    sessions.close(ticket, with: nil)
                }
            }
        }
    }
}

@MainActor
@Observable
private final class NoteModel {
    var text: String

    init(text: String) {
        self.text = text
    }
}

extension Freeze {
    /// One screen showing `image` and no windows, for `--backdrop`.
    @MainActor
    static func backdrop(_ image: CGImage) -> Freeze {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.screens[0]
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return Freeze(
            screens: [FrozenScreen(screen: screen, image: image, frame: ScreenGeometry.flip(screen.frame, mainScreenHeight: mainHeight))],
            windows: [], frontApp: "Acme Studio"
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
