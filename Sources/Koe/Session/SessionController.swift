import Foundation
import KoeCore
import os

/// Runs one dictation session at a time: opens the source, feeds the transcriber, keeps the live transcript, and
/// hands the finished session on when you stop.
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
    private(set) var transcript = LiveTranscript()
    private(set) var lastSession: Session?
    /// How many screenshots, notes and files this session holds so far.
    private(set) var annotationCount = 0
    /// A short message the pill shows for a few seconds, such as a capture that failed.
    private(set) var notice: String?
    @ObservationIgnored private var noticeDismissal: Task<Void, Never>?

    @ObservationIgnored private static let log = Logger(subsystem: "studio.shinsa.koe", category: "session")
    @ObservationIgnored var onPhaseChange: ((RecorderPhase) -> Void)?
    /// A session that holds something, with the folder its files are in.
    @ObservationIgnored var onFinish: ((Session, URL) -> Void)?

    @ObservationIgnored private let transcriber: any Transcriber
    @ObservationIgnored private let makeSource: () -> any AudioSource
    @ObservationIgnored private var source: (any AudioSource)?
    @ObservationIgnored private var session = Session()
    @ObservationIgnored private var ledger = AnnotationLedger()
    @ObservationIgnored private var folder: SessionFolder?
    @ObservationIgnored private var transcriptFailure: (any Error)?
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    /// How long a failure stays in the pill before it goes away by itself.
    @ObservationIgnored var failureDisplay: Duration = .seconds(6)

    @ObservationIgnored private let sessionsRoot: URL

    init(transcriber: any Transcriber, sessionsRoot: URL = SessionController.defaultRoot,
         makeSource: @escaping () -> any AudioSource) {
        self.transcriber = transcriber
        self.sessionsRoot = sessionsRoot
        self.makeSource = makeSource
    }

    /// `~/Library/Application Support/Koe/Sessions`: one folder per session for its screenshots and files.
    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Koe/Sessions", directoryHint: .isDirectory)
    }

    /// Seconds into the session's audio, which every annotation is stamped with.
    var currentTime: AudioTime { source?.currentTime ?? 0 }

    /// How loud the microphone is right now, 0...1. Read by the pill's waveform on each frame.
    var level: Float { source?.level ?? 0 }

    func toggle() {
        switch phase.toggleIntent {
        case .start: start()
        case .stop: stop()
        case .ignore: break
        }
    }

    func start() {
        guard !phase.isActive else { return }
        dismissal?.cancel()
        // A new session goes straight to its waveform, whatever the last one left in the pill.
        noticeDismissal?.cancel()
        notice = nil
        let source = makeSource()
        self.source = source
        session = Session()
        ledger = AnnotationLedger()
        annotationCount = 0
        transcriptFailure = nil
        folder = SessionFolder(url: sessionsRoot.appending(
            path: SessionFolder.name(startedAt: session.startedAt, id: session.id), directoryHint: .isDirectory
        ))
        transcript = LiveTranscript()
        phase = .preparing
        let events = transcriber.transcribe(source)
        Task {
            do {
                for try await event in events { handle(event) }
            } catch {
                transcriptFailure = error
            }
            ledger.endTranscript()
            if !ledger.isSettled { phase = .finishing }
            settleIfDone()
        }
    }

    /// Stamps the moment a tool starts with the session's audio time. Nil when no session is running.
    func openTicket() -> AnnotationLedger.Ticket? {
        guard phase.isActive, !ledger.transcriptDone else { return nil }
        return ledger.open(at: currentTime)
    }

    /// Hands back a tool's annotation, or nil when you cancelled it. A session that stopped meanwhile ends now.
    func close(_ ticket: AnnotationLedger.Ticket, with annotation: Annotation?) {
        guard ledger.close(ticket, with: annotation) else { return }
        annotationCount = ledger.annotations.count
        settleIfDone()
    }

    /// Hands back a clip and the frames picked from it, each stamped some seconds after the ticket's time.
    func close(_ ticket: AnnotationLedger.Ticket, with annotations: [(annotation: Annotation, after: AudioTime)]) {
        guard ledger.close(ticket, with: annotations) else { return }
        annotationCount = ledger.annotations.count
        settleIfDone()
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
        guard var folder else { throw CocoaError(.fileNoSuchFile) }
        let url = pick(&folder)
        self.folder = folder
        try FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
        return url
    }

    /// Closes the microphone; the session ends once the transcriber has settled the last words.
    func stop() {
        guard phase.toggleIntent == .stop else { return }
        phase = .finishing
        source?.stop()
    }

    func post(notice: String) {
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

    private func handle(_ event: TranscriberEvent) {
        switch event {
        case .listening:
            if phase == .preparing { phase = .recording(since: Date()) }
        case .update(let update):
            transcript.apply(update)
        }
    }

    private func settleIfDone() {
        guard ledger.isSettled, phase.isActive else { return }
        finish(failure: transcriptFailure)
    }

    private func finish(failure: (any Error)?) {
        source = nil
        session.words = transcript.words + transcript.pending
        session.annotations = ledger.annotations
        if !session.words.isEmpty || !session.annotations.isEmpty, let folder {
            lastSession = session
            onFinish?(session, folder.url)
        } else if failure == nil {
            post(notice: "Koe didn't hear anything, so nothing was copied.")
        }
        guard let failure, !(failure is CancellationError) else {
            phase = .idle
            return
        }
        phase = .failed(failure.localizedDescription)
        let display = failureDisplay
        dismissal = Task { [weak self] in
            try? await Task.sleep(for: display)
            guard !Task.isCancelled else { return }
            self?.dismissFailure()
        }
    }
}
