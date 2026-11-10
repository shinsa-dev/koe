import Foundation
import KoeCore
import os

/// What the pill says when it has something to say instead of the waveform.
struct PillNotice: Equatable {
    enum Kind { case success, neutral, failure }

    var kind: Kind
    var title: String
    var detail: String?
    /// The glyph in the notice's badge; each kind has its own when none is given.
    var icon: Icon?
}

/// One recording: its audio source, the transcript as it settles, the tools still open on it and its folder.
/// It outlives the session in the pill: once copied it keeps transcribing until the last words settle.
@MainActor
private final class Take {
    var session = Session()
    var transcript = LiveTranscript()
    var ledger = AnnotationLedger()
    var folder: SessionFolder
    let source: any AudioSource
    var transcription: Task<Void, Never>?
    var transcriptDone = false
    var failure: (any Error)?
    var delivered: Session?
    var cancelled = false
    /// Finished before the model heard anything: copied as soon as the transcript settles.
    var awaitingWords = false

    init(source: any AudioSource, root: URL) {
        self.source = source
        folder = SessionFolder(url: root.appending(
            path: SessionFolder.name(startedAt: session.startedAt, id: session.id), directoryHint: .isDirectory
        ))
    }

    var audioURL: URL { folder.url.appending(path: SessionArchive.audioName) }

    /// The session as it stands: every word heard so far, the model's latest guess included. When the model failed
    /// and heard nothing, the recording itself is attached so nothing you said is lost.
    func snapshot() -> Session {
        var session = session
        session.words = transcript.words + transcript.pending
        session.annotations = ledger.annotations
        if failure != nil, session.words.isEmpty {
            session.annotations.append(Annotation(
                time: 0, kind: .file(Asset(url: audioURL, kind: .file)),
                note: "Koe couldn't transcribe this, so the recording is attached."
            ))
        }
        return session
    }
}

/// Runs one dictation session at a time. Recording starts the moment you ask: the microphone opens at once and the
/// model catches up on what it missed. Finishing copies at once with what has been heard, and refines the copy when
/// the last words settle.
@MainActor
@Observable
final class SessionController {
    private(set) var phase: RecorderPhase = .idle {
        didSet {
            guard phase != oldValue else { return }
            Self.log.info("Session phase: \(String(describing: self.phase), privacy: .public)")
            onPhaseChange?(phase)
        }
    }
    /// What this session holds so far: comments, screenshots, clips and files, in the order you added them.
    private(set) var attachments: [Annotation] = []
    var annotationCount: Int { attachments.count }
    /// What the pill says for a few seconds instead of the waveform: a copy, a discard, a capture that failed.
    private(set) var notice: PillNotice?
    @ObservationIgnored private var noticeDismissal: Task<Void, Never>?

    @ObservationIgnored private static let log = Logger(subsystem: "studio.shinsa.koe", category: "session")
    @ObservationIgnored var onPhaseChange: ((RecorderPhase) -> Void)?
    /// A session copied at once, with the folder its files are in.
    /// The session ended before the model had any words; they are copied once they arrive.
    @ObservationIgnored var onCopyPending: (() -> Void)?
    /// A notice that came after the session ended, such as nothing heard once the model settled.
    @ObservationIgnored var onLateNotice: (() -> Void)?
    @ObservationIgnored var onFinish: ((Session, URL) -> Void)?
    /// The same session once its last words settled, when they differ from what was copied.
    @ObservationIgnored var onRefine: ((Session, URL) -> Void)?
    /// A session you discarded, so its open tools close.
    @ObservationIgnored var onCancel: (() -> Void)?

    @ObservationIgnored private let transcriber: any Transcriber
    @ObservationIgnored private let makeSource: () -> any AudioSource
    @ObservationIgnored private var take: Take?
    @ObservationIgnored private let archive: SessionArchive
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    /// How long a failure stays in the pill before it goes away by itself.
    @ObservationIgnored var failureDisplay: Duration = .seconds(6)

    init(transcriber: any Transcriber, sessionsRoot: URL = SessionController.defaultRoot,
         makeSource: @escaping () -> any AudioSource) {
        self.transcriber = transcriber
        archive = SessionArchive(root: sessionsRoot)
        self.makeSource = makeSource
    }

    /// `~/Library/Application Support/Koe/Sessions`: one folder per session for its audio, screenshots and files.
    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Koe/Sessions", directoryHint: .isDirectory)
    }

    /// Seconds of the session's audio, pauses left out: what the clock shows and every annotation is stamped with.
    var currentTime: AudioTime { take?.source.currentTime ?? 0 }

    /// How loud the microphone is right now, 0...1. Read by the pill's waveform on each frame.
    var level: Float { phase == .recording ? take?.source.level ?? 0 : 0 }

    func toggle() {
        switch phase.toggleIntent {
        case .start: start()
        case .stop: finish()
        case .ignore: break
        }
    }

    func start() {
        guard !phase.isActive else { return }
        dismissal?.cancel()
        // A new session goes straight to its waveform, whatever the last one left in the pill.
        noticeDismissal?.cancel()
        notice = nil
        let take = Take(source: makeSource(), root: archive.root)
        do {
            try FileManager.default.createDirectory(at: take.folder.url, withIntermediateDirectories: true)
            try take.source.start(recordingTo: take.audioURL)
        } catch {
            try? FileManager.default.removeItem(at: take.folder.url)
            fail(error)
            return
        }
        self.take = take
        attachments = []
        phase = .recording
        saveDraft(take)
        let events = transcriber.transcribe(take.source)
        take.transcription = Task { [weak self] in
            var failure: (any Error)?
            do {
                for try await event in events {
                    if case .update(let update) = event { take.transcript.apply(update) }
                }
            } catch {
                failure = error
            }
            self?.transcriptEnded(take, failure: failure)
        }
    }

    func pause() {
        guard phase == .recording, let take else { return }
        take.source.pause()
        phase = .paused
    }

    func resume() {
        guard phase == .paused, let take else { return }
        take.source.resume()
        phase = .recording
    }

    /// Stops recording and copies. Waits only for a tool still open, or for the very first words.
    func finish() {
        guard phase.isOpen, let take else { return }
        phase = .finishing
        take.source.stop()
        deliverIfReady()
    }

    /// Stops recording and throws the session away: nothing is copied and its folder goes.
    func cancel() {
        guard phase.isActive, let take else { return }
        take.cancelled = true
        take.source.stop()
        take.transcription?.cancel()
        try? FileManager.default.removeItem(at: take.folder.url)
        self.take = nil
        attachments = []
        // The notice goes up before the phase changes, so the pill stays to show it.
        post(PillNotice(kind: .neutral, title: "Recording thrown away", detail: "Nothing was copied or kept",
                        icon: .trash))
        onCancel?()
        phase = .idle
    }

    /// Stamps the moment a tool starts with the session's audio time. Nil when no session is open.
    /// What you said inside `span`, as far as the model has heard it.
    func spoken(in span: VoiceSpan) -> String {
        take?.transcript.text(in: span) ?? ""
    }

    func openTicket() -> AnnotationLedger.Ticket? {
        guard phase.isOpen, let take else { return nil }
        return take.ledger.open(at: currentTime)
    }

    /// Hands back a tool's annotation, or nil when you cancelled it. A session that stopped meanwhile is copied now.
    func close(_ ticket: AnnotationLedger.Ticket, with annotation: Annotation?) {
        guard let take, take.ledger.close(ticket, with: annotation) else { return }
        annotationClosed(take)
    }

    /// Hands back a clip and the frames picked from it, each stamped some seconds after the ticket's time.
    func close(_ ticket: AnnotationLedger.Ticket, with annotations: [(annotation: Annotation, after: AudioTime)]) {
        guard let take, take.ledger.close(ticket, with: annotations) else { return }
        annotationClosed(take)
    }

    /// Takes an attachment out of the session, as from the pill's list, and deletes the file Koe kept for it.
    func remove(_ id: UUID) {
        guard let take, let annotation = take.ledger.annotations.first(where: { $0.id == id }),
              take.ledger.remove(id) else { return }
        if let url = annotation.asset?.url, url.path.hasPrefix(take.folder.url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        attachments = take.ledger.annotations
        saveDraft(take)
    }

    private func annotationClosed(_ take: Take) {
        attachments = take.ledger.annotations
        saveDraft(take)
        deliverIfReady()
    }

    func clipURL() throws -> URL {
        try reserveFile { $0.nextClip() }
    }

    func frameURL(_ index: Int, of clip: URL) throws -> URL {
        try reserveFile { $0.frame(index, of: clip) }
    }

    /// Where the session's next screenshot goes; the folder exists once this returns.
    func screenshotURL() throws -> URL {
        try reserveFile { $0.nextScreenshot() }
    }

    /// Where a dropped file is copied to, keeping its name.
    func fileURL(named name: String) throws -> URL {
        try reserveFile { $0.reserve(name) }
    }

    private func reserveFile(_ pick: (inout SessionFolder) -> URL) throws -> URL {
        guard let take else { throw CocoaError(.fileNoSuchFile) }
        let url = pick(&take.folder)
        try FileManager.default.createDirectory(at: take.folder.attachments, withIntermediateDirectories: true)
        return url
    }

    func post(notice: String) {
        post(PillNotice(kind: .neutral, title: notice))
    }

    func post(_ notice: PillNotice) {
        self.notice = notice
        noticeDismissal?.cancel()
        noticeDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func dismissFailure() {
        dismissal?.cancel()
        if case .failed = phase { phase = .idle }
    }

    private func transcriptEnded(_ take: Take, failure: (any Error)?) {
        take.transcriptDone = true
        if let failure, !(failure is CancellationError) {
            take.failure = failure
            Self.log.error("Transcription stopped: \(failure.localizedDescription, privacy: .public)")
        }
        guard !take.cancelled else { return }
        if take.awaitingWords, take.delivered == nil {
            deliver(take)
            return
        }
        if let delivered = take.delivered {
            let settled = take.snapshot()
            if settled.words != delivered.words || settled.annotations != delivered.annotations {
                onRefine?(settled, take.folder.url)
            }
            return
        }
        guard take === self.take else { return }
        if phase.isOpen {
            // The audio ended by itself (a played file ran out): that finishes the session. A model that failed
            // leaves the recording running; the audio is attached when you finish.
            if take.failure == nil { finish() }
        } else {
            deliverIfReady()
        }
    }

    private func deliverIfReady() {
        guard phase == .finishing, let take else { return }
        let decision = Delivery.decide(openTools: take.ledger.openCount,
                                       hasContent: !take.transcript.isEmpty || !take.ledger.annotations.isEmpty,
                                       transcriptDone: take.transcriptDone)
        switch decision {
        case .wait:
            return
        case .deliver:
            self.take = nil
            // The notice goes up before the phase changes, so the pill stays to show it.
            deliver(take)
            phase = .idle
        case .whenSettled:
            // Never hold the pill for the model: the session ends now and is copied once its words arrive.
            take.awaitingWords = true
            self.take = nil
            // The notice goes up before the phase changes, so the pill goes straight to it.
            onCopyPending?()
            phase = .idle
        }
    }

    private func deliver(_ take: Take) {
        let session = take.snapshot()
        if session.words.isEmpty, session.annotations.isEmpty {
            take.transcription?.cancel()
            try? FileManager.default.removeItem(at: take.folder.url)
            post(PillNotice(kind: .neutral, title: "We couldn't hear you", detail: "Check your microphone and try again",
                            icon: .muted))
            if take.awaitingWords { onLateNotice?() }
        } else {
            take.delivered = session
            onFinish?(session, take.folder.url)
        }
    }

    private func saveDraft(_ take: Take) {
        var draft = take.session
        draft.annotations = take.ledger.annotations
        try? archive.saveDraft(draft, in: take.folder.url)
    }

    private func fail(_ error: any Error) {
        Self.log.error("Could not start: \(error.localizedDescription, privacy: .public)")
        phase = .failed(error.localizedDescription)
        let display = failureDisplay
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: display)
            guard !Task.isCancelled else { return }
            self?.dismissFailure()
        }
    }
}
