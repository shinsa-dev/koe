import AppKit
import KoeCore
import os

/// For `--script`: a clip recorded hands-free, and the frames to pick from it.
struct ClipScript {
    let region: CGRect
    let seconds: AudioTime
    let picks: [AudioTime]
    let holds: Bool
}

/// The clip tool from start to end: you pick a region, Koe records it until you stop (or for 30 s), then the clip
/// opens slowed down for you to step through and pick frames. Attaching adds the clip at the moment it started
/// recording and each frame at the moment it was on screen, all on the ticket taken when you pressed the shortcut.
@MainActor
final class ClipTool {
    private struct Recording {
        let ticket: AnnotationLedger.Ticket
        let url: URL
        /// Seconds after the ticket's time that recording began.
        let startOffset: AudioTime
        let source: CaptureSource?
        let recorder: ClipRecorder?
        let indicator: RecordingIndicator?
        let script: ClipScript?
        var autoStop: Task<Void, Never>?
    }

    private let sessions: SessionController
    private let pickRegion: (CGRect?, @escaping (RegionChoice?) -> Void) -> Void
    private var recording: Recording?
    private var stopping = false
    private var reviewPanel: ToolPanel?
    private var reviewKeys: Any?
    private var busy = false
    var clipFile: URL?
    private static let log = Logger(subsystem: "studio.shinsa.koe", category: "clip")

    init(sessions: SessionController, pickRegion: @escaping (CGRect?, @escaping (RegionChoice?) -> Void) -> Void) {
        self.sessions = sessions
        self.pickRegion = pickRegion
    }

    var isBusy: Bool { busy }
    var isRecording: Bool { recording != nil && !stopping }

    func begin(ticket: AnnotationLedger.Ticket, preset: ClipScript?) {
        busy = true
        pickRegion(preset?.region) { [weak self] choice in
            guard let self else { return }
            guard let choice else {
                end(ticket, with: [])
                return
            }
            Task { await self.record(choice, ticket: ticket, script: preset) }
        }
    }

    private func record(_ choice: RegionChoice, ticket: AnnotationLedger.Ticket, script: ClipScript?) async {
        let url: URL
        do {
            url = try sessions.clipURL()
        } catch {
            fail(ticket, "Koe couldn't make room for the clip.")
            return
        }
        let source = choice.source
        var recorder: ClipRecorder?
        if let clipFile {
            do {
                try FileManager.default.copyItem(at: clipFile, to: url)
            } catch {
                fail(ticket, "Koe couldn't read the clip in --clip-file.")
                return
            }
        } else {
            do {
                recorder = try await ClipRecorder.start(region: choice.region, on: choice.screen.screen, to: url)
            } catch {
                Self.log.error("Recording failed: \(error.localizedDescription, privacy: .public)")
                fail(ticket, "Koe couldn't record the screen. Check that screen recording is allowed for Koe.")
                return
            }
        }
        let offset = max(0, sessions.currentTime - ticket.time)
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let screenFrame = choice.screen.frame
        let global = ScreenGeometry.flip(
            choice.region.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY), mainScreenHeight: mainHeight
        )
        let limit = script?.seconds ?? ClipFrames.longest
        // A scripted --clip-file run still shows the outline for its length, so the indicator can be seen without recording.
        let indicator = recorder == nil && script == nil ? nil : RecordingIndicator(
            region: global, on: choice.screen.screen, limit: limit
        ) { [weak self] in self?.stopRecording() }
        indicator?.show()
        recording = Recording(ticket: ticket, url: url, startOffset: offset, source: source, recorder: recorder,
                              indicator: indicator, script: script)
        recording?.autoStop = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled else { return }
            self?.stopRecording()
        }
        if recorder == nil, script == nil { stopRecording() }
    }

    func stopRecording() {
        guard let recording, !stopping else { return }
        stopping = true
        recording.autoStop?.cancel()
        recording.indicator?.close()
        Task {
            defer {
                self.recording = nil
                stopping = false
            }
            do {
                try await recording.recorder?.stop()
                let info = try await Task.detached { [url = recording.url] in try await ClipMovie.read(url) }.value
                review(recording, info: info)
            } catch {
                Self.log.error("Clip failed: \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: recording.url)
                fail(recording.ticket, "Koe couldn't save the clip.")
            }
        }
    }

    // MARK: Review

    private func review(_ recording: Recording, info: ClipMovie.Info) {
        let label = recording.source.map { [$0.app, $0.window].compactMap(\.self).joined(separator: " · ") }
        let reviewer = ClipReviewer(url: recording.url, info: info, sourceLabel: label)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = NSSize(width: ClipReviewView.width + 48, height: min(visible.height - PillPanel.cardsAbove, 720))
        let panel = ToolPanel(
            frame: NSRect(x: visible.midX - size.width / 2, y: visible.minY + PillPanel.cardsAbove - 8,
                          width: size.width, height: size.height),
            level: .popUpMenu
        )
        panel.host(ClipReviewView(reviewer: reviewer)
            .padding(.bottom, 8)
            .frame(width: size.width, height: size.height, alignment: .bottom))
        // Esc in a frame's note leaves the note; only Esc outside one discards the clip.
        panel.onCancel = { [weak panel] in
            if let panel, panel.firstResponder is NSText {
                panel.makeFirstResponder(nil)
            } else {
                reviewer.finish(attach: false)
            }
        }
        reviewer.onFinish = { [weak self] attach in
            self?.closeReview()
            if attach {
                self?.attach(reviewer, recording: recording)
            } else {
                try? FileManager.default.removeItem(at: recording.url)
                self?.end(recording.ticket, with: [])
            }
        }
        reviewPanel = panel
        reviewKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak reviewer, weak panel] event in
            guard let reviewer, event.window === panel, !(panel?.firstResponder is NSText) else { return event }
            return Self.handle(event, in: reviewer) ? nil : event
        }
        panel.present()
        if let script = recording.script {
            reviewer.pick(at: script.picks)
            if !script.holds {
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    reviewer.finish(attach: true)
                }
            }
        }
    }

    /// ← → step a frame (with ⇧, ten), Space plays, P picks, Return attaches. Esc is the panel's.
    private static func handle(_ event: NSEvent, in reviewer: ClipReviewer) -> Bool {
        let stride = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: reviewer.step(by: -stride)
        case 124: reviewer.step(by: stride)
        case 49: reviewer.togglePlay()
        case 35: reviewer.pickCurrent()
        case 36, 76: reviewer.finish(attach: true)
        default: return false
        }
        return true
    }

    private func closeReview() {
        if let reviewKeys { NSEvent.removeMonitor(reviewKeys) }
        reviewKeys = nil
        reviewPanel?.close()
        reviewPanel = nil
    }

    private func attach(_ reviewer: ClipReviewer, recording: Recording) {
        let review = reviewer.review
        let frames = reviewer.frames
        Task {
            var assets: [Int: Asset] = [:]
            for pick in review.picks {
                guard let url = try? sessions.frameURL(pick.index, of: recording.url) else { continue }
                do {
                    let image = try await ClipMovie.image(at: frames.seekTime(of: pick.index), of: recording.url)
                    try await Task.detached { try PNG.write(image, to: url) }.value
                    assets[pick.index] = Asset(url: url)
                } catch {
                    Self.log.error("Frame failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            if assets.count < review.picks.count { sessions.post(notice: "Koe couldn't save every frame you picked.") }
            end(recording.ticket, with: review.annotations(
                clip: Asset(url: recording.url, kind: .video), frameAssets: assets,
                recordingStart: recording.startOffset, source: recording.source
            ))
        }
    }

    private func fail(_ ticket: AnnotationLedger.Ticket, _ notice: String) {
        sessions.post(notice: notice)
        end(ticket, with: [])
    }

    private func end(_ ticket: AnnotationLedger.Ticket, with annotations: [(annotation: Annotation, after: AudioTime)]) {
        busy = false
        sessions.close(ticket, with: annotations)
    }
}
