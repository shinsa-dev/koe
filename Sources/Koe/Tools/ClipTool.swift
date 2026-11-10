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

/// The clip tool from start to end: you pick a region, Koe records it until you stop, however long that is, then the clip
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
    private let status: ToolStatus
    private let pickRegion: (CGRect?, @escaping (RegionChoice?) -> Void) -> Void
    private var recording: Recording?
    private var stopping = false
    private var reviewPanel: ToolPanel?
    private var reviewer: ClipReviewer?
    /// The session finished while the clip was recording: it attaches as it is, with no review.
    private var attachWhenStopped = false
    private var reviewKeys: Any?
    private var busy = false
    var clipFile: URL?
    private static let log = Logger(subsystem: "studio.shinsa.koe", category: "clip")

    init(sessions: SessionController, status: ToolStatus,
         pickRegion: @escaping (CGRect?, @escaping (RegionChoice?) -> Void) -> Void) {
        self.sessions = sessions
        self.status = status
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
            // Set before the recorder starts, so the pill goes from picking straight to recording.
            if clipFile == nil || preset != nil { promptRecording(limit: preset?.seconds) }
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
        let limit = script?.seconds
        // A scripted --clip-file run still shows the outline for its length, so the indicator can be seen without recording.
        let indicator = recorder == nil && script == nil ? nil : RecordingIndicator(region: global)
        indicator?.show()
        if indicator != nil { promptRecording(limit: limit) }
        recording = Recording(ticket: ticket, url: url, startOffset: offset, source: source, recorder: recorder,
                              indicator: indicator, script: script)
        if let limit {
            recording?.autoStop = Task { [weak self] in
                try? await Task.sleep(for: .seconds(limit))
                guard !Task.isCancelled else { return }
                self?.stopRecording()
            }
        }
        if recorder == nil, script == nil { stopRecording() }
    }

    func stopRecording() {
        guard let recording, !stopping else { return }
        stopping = true
        recording.autoStop?.cancel()
        recording.indicator?.close()
        // Straight to the review's page, so the pill never shows its home page while the clip is read.
        if attachWhenStopped { status.clear() } else { promptReview(nil) }
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
                attachWhenStopped = false
                fail(recording.ticket, "Koe couldn't save the clip.")
            }
        }
    }

    /// The session is finishing and won't wait for a click: a clip still recording stops and attaches, and a clip
    /// in review attaches with the frames picked so far.
    func sessionStopping() {
        if recording != nil {
            attachWhenStopped = true
            stopRecording()
        }
        reviewer?.finish(attach: true)
    }

    /// Drops the clip in progress, recording or in review, when its session was discarded.
    func discard() {
        attachWhenStopped = false
        if let recording {
            recording.autoStop?.cancel()
            recording.indicator?.close()
            self.recording = nil
            Task {
                try? await recording.recorder?.stop()
                try? FileManager.default.removeItem(at: recording.url)
            }
        }
        closeReview()
        busy = false
    }

    // MARK: Review

    private func review(_ recording: Recording, info: ClipMovie.Info) {
        let label = recording.source.map { [$0.app, $0.window].compactMap(\.self).joined(separator: " · ") }
        let reviewer = ClipReviewer(url: recording.url, info: info, sourceLabel: label,
                                    now: { [sessions] in sessions.currentTime },
                                    spoken: { [sessions] in sessions.spoken(in: $0) })
        if attachWhenStopped {
            attachWhenStopped = false
            status.clear()
            attach(reviewer, recording: recording)
            return
        }
        self.reviewer = reviewer
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
        panel.onCancel = { reviewer.finish(attach: false) }
        promptReview(reviewer)
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
            guard let reviewer, event.window === panel else { return event }
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
        if reviewPanel != nil { status.clear() }
        reviewPanel?.close()
        reviewPanel = nil
        reviewer = nil
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
        status.clear()
        sessions.post(notice: notice)
        end(ticket, with: [])
    }

    private func end(_ ticket: AnnotationLedger.Ticket, with annotations: [(annotation: Annotation, after: AudioTime)]) {
        busy = false
        sessions.close(ticket, with: annotations)
    }
}

extension ClipTool {
    /// Throws away the clip that is recording and nothing else: the session carries on.
    func cancelRecording() {
        guard let recording, !stopping else { return }
        recording.autoStop?.cancel()
        recording.indicator?.close()
        self.recording = nil
        status.clear()
        Task {
            try? await recording.recorder?.stop()
            try? FileManager.default.removeItem(at: recording.url)
        }
        end(recording.ticket, with: [])
    }

    private func promptRecording(limit: AudioTime?) {
        status.prompt = ToolPrompt(stage: .recording, icon: .video, title: "Recording a clip", detail: nil,
                                   confirm: "Stop recording", canTalk: false, cancel: "Discard this clip",
                                   clock: .init(started: Date(), limit: limit))
        status.onCancel = { [weak self] in self?.cancelRecording() }
        status.onConfirm = { [weak self] in self?.stopRecording() }
    }

    /// While the clip is open, the pill's discard and confirm act on it, not on the whole session.
    private func promptReview(_ reviewer: ClipReviewer?) {
        status.prompt = ToolPrompt(stage: .confirming, icon: .video, title: "Pick the frames to attach",
                                   detail: "Then attach the clip, or discard it", confirm: "Attach clip",
                                   canTalk: false, cancel: "Discard this clip")
        status.onCancel = reviewer.map { reviewer in { reviewer.finish(attach: false) } }
        status.onConfirm = reviewer.map { reviewer in { reviewer.finish(attach: true) } }
    }
}
