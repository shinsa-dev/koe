import AppKit
import KoeCore
import os
import SwiftUI

/// Runs the tools you use while talking: a comment pinned on anything, a screenshot of a region or window, a clip of a
/// region you review slowed down, and files dropped on the pill. The pill asks what to do while one is open, and a
/// note is what you say, never typed. Each is stamped with the session's audio time at the moment you
/// start it, and starts a session when none is running.
@MainActor
final class ToolCoordinator {
    private let sessions: SessionController
    private let permissions: PermissionCenter
    /// Starts a session when none runs (or opens setup when it can't) and says whether one is running now.
    private let ensureSession: () -> Bool
    private let presentSetup: () -> Void
    private var overlay: [ToolPanel] = []
    /// A screenshot's freeze is under way: its overlay isn't up yet, but a second press must not start another.
    private var freezing = false
    /// What the pill asks while a tool is open.
    let status = ToolStatus()
    private lazy var clips = ClipTool(sessions: sessions, pickRegion: { [weak self] preset, done in
        guard let self else { return done(nil) }
        pickClipRegion(preset: preset, done: done)
    })
    private static let log = Logger(subsystem: "studio.shinsa.koe", category: "tools")

    /// Replaces the live screen capture for `--backdrop`, so captures of Koe show a known image, not your screen.
    var backdrop: CGImage?
    /// Stands in for every recorded clip with `--clip-file`, so the review can be tried and captured without
    /// recording the screen.
    var clipFile: URL? {
        get { clips.clipFile }
        set { clips.clipFile = newValue }
    }

    init(sessions: SessionController, permissions: PermissionCenter, ensureSession: @escaping () -> Bool,
         presentSetup: @escaping () -> Void) {
        self.sessions = sessions
        self.permissions = permissions
        self.ensureSession = ensureSession
        self.presentSetup = presentSetup
    }

    var isBusy: Bool { freezing || !overlay.isEmpty || clips.isBusy }
    var isRecordingClip: Bool { clips.isRecording }

    // MARK: Screenshot

    /// Freezes the screen to pin a comment on whatever you click: the window there, or the area around the spot,
    /// with a pin on it. What you say next is the comment, until you add it.
    func comment(at spot: CGPoint? = nil, note: String? = nil, talk: AudioTime? = nil, holds: Bool = true) {
        screenshot(note: note, talk: talk, holds: holds, purpose: .comment, spot: spot)
    }

    func screenshot(preset: CGRect? = nil, note: String? = nil, talk: AudioTime? = nil, holds: Bool = true,
                    purpose: RegionPicker.Purpose = .screenshot, spot: CGPoint? = nil) {
        guard !isBusy else { return }
        permissions.refresh()
        guard backdrop != nil || permissions.checklist.status(of: .screenRecording) == .granted else {
            presentSetup()
            return
        }
        guard ensureSession(), let ticket = sessions.openTicket() else { return }
        freezing = true
        Task { [self] in
            let freeze: Freeze
            do {
                freeze = try await self.freeze()
            } catch {
                freezing = false
                Self.log.error("Freeze failed: \(error.localizedDescription, privacy: .public)")
                sessions.post(notice: error.localizedDescription)
                sessions.close(ticket, with: nil)
                return
            }
            freezing = false
            let picker = RegionPicker(freeze: freeze, purpose: purpose)
            let voice = VoiceNote { [sessions] in sessions.currentTime }
            prompt(picker, voice: voice)
            picker.onFinish = { [weak self] choice in
                self?.status.clear()
                self?.closeOverlay()
                self?.save(choice, ticket: ticket)
            }
            showOverlay(for: picker)
            if let preset { picker.preset(preset, note: note) }
            if let spot { picker.preset(click: spot, note: note) }
            if preset != nil || spot != nil, !holds {
                if let talk {
                    if !voice.isListening { voice.begin() }
                    try? await Task.sleep(for: .seconds(talk))
                } else {
                    try? await Task.sleep(for: .milliseconds(600))
                }
                picker.submit(voice: voice.span())
            }
        }
    }

    /// Keeps the pill in step with the picker: what to do while picking, then attach, or listen for a comment.
    private func prompt(_ picker: RegionPicker, voice: VoiceNote) {
        let comment = picker.purpose == .comment
        let picking = ToolPrompt(
            stage: .picking, icon: comment ? .comment : .screenCapture,
            title: comment ? "Click anything to comment on it" : "Drag over a region, or click a window",
            detail: nil, confirm: comment ? "Add comment" : "Attach", canTalk: false
        )
        status.prompt = picking
        status.onCancel = { picker.cancel() }
        status.onConfirm = nil
        status.onTalk = nil
        picker.onHover = { [weak self] label in self?.status.prompt?.detail = label }
        picker.onChoosing = { [weak self] in
            voice.stop()
            self?.status.prompt = picking
            self?.status.onConfirm = nil
        }
        picker.onPicked = { [weak self] in
            guard let self else { return }
            status.onConfirm = { picker.submit(voice: voice.span()) }
            status.onTalk = { [weak self] in
                if voice.isListening { voice.stop() } else { voice.begin() }
                self?.status.prompt?.stage = voice.isListening ? .listening : .confirming
                self?.status.prompt?.title = Self.title(comment: comment, listening: voice.isListening)
            }
            // A comment is something said: it listens the moment you click.
            if comment { voice.begin() }
            status.prompt = ToolPrompt(
                stage: voice.isListening ? .listening : .confirming, icon: comment ? .comment : .screenCapture,
                title: Self.title(comment: comment, listening: voice.isListening), detail: picker.sourceLabel,
                confirm: comment ? "Add comment" : "Attach"
            )
        }
    }

    private static func title(comment: Bool, listening: Bool) -> String {
        switch (comment, listening) {
        case (true, true): "Say your comment"
        case (true, false): "Comment paused"
        case (false, true): "Say what this is about"
        case (false, false): "Attach this screenshot?"
        }
    }

    private func freeze() async throws -> Freeze {
        if let backdrop { return Freeze.backdrop(backdrop) }
        return try await ScreenFreezer.freeze()
    }

    private func showOverlay(for picker: RegionPicker) {
        overlay = picker.freeze.screens.indices.map { index in
            let panel = ToolPanel(frame: picker.freeze.screens[index].screen.frame, level: .screenSaver)
            panel.host(RegionPickerView(picker: picker, index: index))
            panel.onCancel = { picker.cancel() }
            panel.onSubmit = { [weak self] in self?.status.onConfirm?() }
            return panel
        }
        let underMouse = picker.freeze.screens.firstIndex { NSMouseInRect(NSEvent.mouseLocation, $0.screen.frame, false) } ?? 0
        for (index, panel) in overlay.enumerated() where index != underMouse { panel.orderFrontRegardless() }
        overlay[safe: underMouse]?.present()
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
              let cut = choice.screen.image.cropping(to: pixels),
              let url = try? sessions.screenshotURL()
        else {
            sessions.close(ticket, with: nil)
            return
        }
        let scale = CGFloat(choice.screen.image.width) / max(1, choice.screen.frame.width)
        let crop = choice.pin
            .flatMap { PinMark.location(of: $0, in: choice.region, scale: scale) }
            .flatMap { PinMark.draw(on: cut, at: $0, radius: 6 * scale) } ?? cut
        let note = choice.note
        let voice = choice.voice
        let source = choice.source
        Task {
            do {
                try await Task.detached { try PNG.write(crop, to: url) }.value
                sessions.close(ticket, with: Annotation(time: ticket.time, kind: .screenshot(Asset(url: url)),
                                                        note: note, source: source, voice: voice))
            } catch {
                sessions.post(notice: "Koe couldn't save the screenshot.")
                sessions.close(ticket, with: nil)
            }
        }
    }

    // MARK: Clip

    /// Picks a region to record, or stops the clip that is recording.
    func clip(preset: ClipScript? = nil) {
        if clips.isRecording {
            clips.stopRecording()
            return
        }
        guard !isBusy else { return }
        permissions.refresh()
        guard clipFile != nil || backdrop != nil || permissions.checklist.status(of: .screenRecording) == .granted else {
            presentSetup()
            return
        }
        guard ensureSession(), let ticket = sessions.openTicket() else { return }
        clips.begin(ticket: ticket, preset: preset)
    }

    /// The session is stopping: a clip still recording stops too, and goes on to its review.
    /// Closes every tool open on a session you discarded; what they would have added goes with it.
    func sessionCancelled() {
        overlay.first?.onCancel?()
        status.clear()
        closeOverlay()
        clips.discard()
    }

    func sessionStopping() {
        if clips.isRecording { clips.stopRecording() }
    }

    /// Freezes the screen for you to pick the region a clip records, and hands it on, or nil when you cancel.
    private func pickClipRegion(preset: CGRect?, done: @escaping (RegionChoice?) -> Void) {
        Task { [self] in
            let freeze: Freeze
            do {
                freeze = try await self.freeze()
            } catch {
                sessions.post(notice: error.localizedDescription)
                done(nil)
                return
            }
            let picker = RegionPicker(freeze: freeze, purpose: .clip)
            status.prompt = ToolPrompt(stage: .picking, icon: .video, title: "Drag over what to record, or click a window",
                                       detail: nil, confirm: "Record", canTalk: false)
            status.onCancel = { picker.cancel() }
            picker.onHover = { [weak self] label in self?.status.prompt?.detail = label }
            picker.onFinish = { choice in
                self.status.clear()
                self.closeOverlay()
                done(choice)
            }
            if let preset {
                status.clear()
                picker.preset(preset, note: nil)
            } else {
                showOverlay(for: picker)
            }
        }
    }

    // MARK: Drop

    /// Files dropped on the pill, copied into the session's folder so the bundle still has them if the originals move.
    func drop(_ urls: [URL]) {
        guard !urls.isEmpty, ensureSession() else { return }
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
