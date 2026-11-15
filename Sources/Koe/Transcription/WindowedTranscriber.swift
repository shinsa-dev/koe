@preconcurrency import AVFoundation
import Foundation
import KoeCore

/// A model that reads a whole stretch of 16 kHz mono audio at once and times what it heard.
protocol WindowDecoder: Sendable {
    /// Loads the model from disk. Cheap once it is loaded.
    func load() async throws
    /// What was said in `samples`, with times counted from their start. A model that finds the language itself decodes
    /// in `language` when one is given, and says which it detected otherwise.
    func decode(_ samples: [Float], language: String?) async throws -> DecodedWindow
}

struct DecodedWindow: Sendable {
    var tokens: [TimedToken]
    var language: String?
}

/// Streams with a model that doesn't stream (Parakeet, Whisper): about every second it decodes the audio not yet
/// settled and lets `RollingWindow` decide which words are final. Both models read far faster than real time, so
/// the window keeps up.
struct WindowedTranscriber: Transcriber {
    let decoder: any WindowDecoder
    var interval: Duration = .milliseconds(900)

    func prewarm() async {
        try? await decoder.load()
    }

    func transcribe(_ source: any AudioSource) -> AsyncThrowingStream<TranscriberEvent, any Error> {
        let decoder = decoder
        let interval = interval
        return AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    try await Self.run(source: source, decoder: decoder, interval: interval, events: continuation)
                    continuation.finish()
                } catch {
                    source.detach()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    func transcribe(file: URL) async throws -> [TimedWord] {
        try await decoder.load()
        let samples = try SampleBuffer.read(file)
        var transcript = LiveTranscript()
        let runs = TokenRuns.words(try await decoder.decode(samples, language: nil).tokens)
        transcript.apply(TranscriptUpdate(runs: runs, isFinal: true, start: 0, end: Double(samples.count) / Self.rate))
        return transcript.words
    }

    static let rate = CaptureStream.format.sampleRate

    private static func run(
        source: any AudioSource,
        decoder: any WindowDecoder,
        interval: Duration,
        events: AsyncThrowingStream<TranscriberEvent, any Error>.Continuation
    ) async throws {
        try await decoder.load()
        let buffer = SampleBuffer()
        source.attach(format: CaptureStream.format, deliver: { buffer.append($0) }, finish: { buffer.end() })
        events.yield(.listening)
        var window = RollingWindow()
        var language = LanguageLock()
        while true {
            try await buffer.wait(upTo: interval)
            try Task.checkCancellation()
            let (updates, ended) = try await step(&window, language: &language, buffer: buffer, decoder: decoder)
            for update in updates { events.yield(.update(update)) }
            if ended { return }
        }
    }

    /// One pass of the window over the audio heard so far: the updates it gives and whether the audio has ended.
    /// Once it has, the decode reaches far back, as Parakeet often hears nothing in a short window at the end.
    /// The language is settled once in a session, from the first pass that read enough audio.
    static func step(
        _ window: inout RollingWindow, language: inout LanguageLock, buffer: SampleBuffer, decoder: any WindowDecoder
    ) async throws -> (updates: [TranscriptUpdate], ended: Bool) {
        let current = window
        let snapshot = buffer.snapshot { total, ended in
            let from = ended ? current.finalDecodeFrom(heard: Double(total) / rate) : current.decodeFrom
            return Int(from * rate)
        }
        let samples = snapshot.samples
        if snapshot.ended { LatencyLog.shared.mark(.lastPassStarted) }
        defer { if snapshot.ended { LatencyLog.shared.mark(.lastPassDone) } }
        let tokens: [TimedToken]
        if samples.isEmpty {
            tokens = []
        } else {
            let decoded = try await decoder.decode(samples, language: language.language)
            language.observe(decoded.language, heard: Double(samples.count) / rate)
            tokens = decoded.tokens
        }
        let runs = TokenRuns.words(tokens, offset: Double(snapshot.total - samples.count) / rate)
        let heard = Double(snapshot.total) / rate
        let (final, volatile) = window.take(runs, heard: heard, ended: snapshot.ended)
        // Audio stays for the last decode's long reach, besides the open window.
        buffer.drop(before: Int(window.finalDecodeFrom(heard: heard) * rate))
        return ((final.map { [$0] } ?? []) + [volatile], snapshot.ended)
    }
}

/// The session's audio as samples, from the start of the open window or the last decode's reach on. Buffers arrive on an audio thread; the
/// transcriber reads on its own.
final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    /// Samples before `base` are settled and gone.
    private var base = 0
    private var samples: [Float] = []
    private var ended = false
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let new = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        lock.withLock { samples.append(contentsOf: new) }
    }

    func append(_ new: [Float]) { lock.withLock { samples.append(contentsOf: new) } }

    func end() {
        let waiting = lock.withLock {
            ended = true
            defer { waiters.removeAll() }
            return Array(waiters.values)
        }
        for waiter in waiting { waiter.resume() }
    }

    var isEnded: Bool { lock.withLock { ended } }

    struct Snapshot {
        /// From the asked-for sample to now.
        let samples: [Float]
        /// How many samples the session has had in all.
        let total: Int
        let ended: Bool
    }

    /// The samples from `start`, counted from the session's start, to now.
    func snapshot(from start: Int) -> Snapshot {
        snapshot { _, _ in start }
    }

    /// The samples from where `start` says, given the total so far and whether the audio has ended, to now; both
    /// read at the same moment, so the audio can't end between choosing the start and reading.
    func snapshot(from start: (_ total: Int, _ ended: Bool) -> Int) -> Snapshot {
        lock.withLock {
            let total = base + samples.count
            let from = min(max(start(total, ended) - base, 0), samples.count)
            return Snapshot(samples: Array(samples[from...]), total: total, ended: ended)
        }
    }

    func drop(before start: Int) {
        lock.withLock {
            let count = min(max(start - base, 0), samples.count)
            samples.removeFirst(count)
            base += count
        }
    }

    /// Sleeps for `interval`, waking the moment the audio ends so the last pass starts at once.
    func wait(upTo interval: Duration) async throws {
        guard !isEnded else { return }
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await Task.sleep(for: interval) }
            group.addTask { await self.untilEnded() }
            try await group.next()
            group.cancelAll()
        }
    }

    /// Returns once the audio ends, or once the task waiting is cancelled.
    private func untilEnded() async {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiter in
                let now = lock.withLock {
                    if ended || Task.isCancelled { return true }
                    waiters[id] = waiter
                    return false
                }
                if now { waiter.resume() }
            }
        } onCancel: {
            lock.withLock { waiters.removeValue(forKey: id) }?.resume()
        }
    }

    /// A whole recording as 16 kHz mono samples.
    static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let converter = AudioConversion.toCapture(from: file.processingFormat) else {
            throw AudioSourceError.unconvertible
        }
        let buffer = SampleBuffer()
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate)
        // Reading at the end of a file throws rather than returning no frames.
        while file.framePosition < file.length,
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) {
            try file.read(into: input, frameCount: chunk)
            guard input.frameLength > 0 else { break }
            if let converted = AudioConversion.convert(input, with: converter, to: CaptureStream.format) {
                buffer.append(converted)
            }
        }
        return buffer.snapshot(from: 0).samples
    }
}

/// Lets one piece of work at a time use a model: a session and the recovery of an old recording may both reach for
/// it, and neither FluidAudio nor WhisperKit is safe to call twice at once.
actor SerialGate {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            busy = true
        }
        defer { if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() } }
        return try await work()
    }
}
