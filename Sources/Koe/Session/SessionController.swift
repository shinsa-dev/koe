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

    @ObservationIgnored private static let log = Logger(subsystem: "studio.shinsa.koe", category: "session")
    @ObservationIgnored var onPhaseChange: ((RecorderPhase) -> Void)?
    @ObservationIgnored var onFinish: ((Session) -> Void)?

    @ObservationIgnored private let transcriber: any Transcriber
    @ObservationIgnored private let makeSource: () -> any AudioSource
    @ObservationIgnored private var source: (any AudioSource)?
    @ObservationIgnored private var session = Session()
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    /// How long a failure stays in the pill before it goes away by itself.
    @ObservationIgnored var failureDisplay: Duration = .seconds(6)

    init(transcriber: any Transcriber, makeSource: @escaping () -> any AudioSource) {
        self.transcriber = transcriber
        self.makeSource = makeSource
    }

    /// Seconds into the session's audio, which every annotation is stamped with.
    var currentTime: AudioTime { source?.currentTime ?? 0 }

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
        let source = makeSource()
        self.source = source
        session = Session()
        transcript = LiveTranscript()
        phase = .preparing
        let events = transcriber.transcribe(source)
        Task {
            do {
                for try await event in events { handle(event) }
                finish(failure: nil)
            } catch {
                finish(failure: error)
            }
        }
    }

    /// Closes the microphone; the session ends once the transcriber has settled the last words.
    func stop() {
        guard phase.toggleIntent == .stop else { return }
        phase = .finishing
        source?.stop()
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

    private func finish(failure: (any Error)?) {
        source = nil
        session.words = transcript.words + transcript.pending
        if !session.words.isEmpty || !session.annotations.isEmpty {
            lastSession = session
            onFinish?(session)
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
