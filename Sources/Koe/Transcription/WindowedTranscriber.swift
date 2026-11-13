@preconcurrency import AVFoundation
import Foundation
import KoeCore

/// A model that reads a whole stretch of 16 kHz mono audio at once and times what it heard.
protocol WindowDecoder: Sendable {
    /// Loads the model from disk. Cheap once it is loaded.
    func load() async throws
    /// What was said in `samples`, with times counted from their start.
    func decode(_ samples: [Float]) async throws -> [TimedToken]
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
        let runs = TokenRuns.words(try await decoder.decode(samples))
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
        while true {
            try await buffer.wait(upTo: interval)
            try Task.checkCancellation()
            let snapshot = buffer.snapshot(from: Int(window.decodeFrom * rate))
            let samples = snapshot.samples
            let tokens = samples.isEmpty ? [] : try await decoder.decode(samples)
            let runs = TokenRuns.words(tokens, offset: Double(snapshot.total - samples.count) / rate)
            let (final, volatile) = window.take(runs, heard: Double(snapshot.total) / rate, ended: snapshot.ended)
            if let final { events.yield(.update(final)) }
            events.yield(.update(volatile))
            buffer.drop(before: Int(window.decodeFrom * rate))
            if snapshot.ended { return }
        }
    }
}

/// The session's audio as samples, from the start of the open window on. Buffers arrive on an audio thread; the
/// transcriber reads on its own.
final class SampleBuffer: @unchecked Sendable {
    private let lock = NSLock()
    /// Samples before `base` are settled and gone.
    private var base = 0
    private var samples: [Float] = []
    private var ended = false

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let new = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        lock.withLock { samples.append(contentsOf: new) }
    }

    func end() { lock.withLock { ended = true } }

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
        lock.withLock {
            let from = min(max(start - base, 0), samples.count)
            return Snapshot(samples: Array(samples[from...]), total: base + samples.count, ended: ended)
        }
    }

    func drop(before start: Int) {
        lock.withLock {
            let count = min(max(start - base, 0), samples.count)
            samples.removeFirst(count)
            base += count
        }
    }

    /// Sleeps for `interval`, waking early once the audio ends so a finished session settles at once.
    func wait(upTo interval: Duration) async throws {
        let step = Duration.milliseconds(50)
        var waited = Duration.zero
        while waited < interval, !isEnded {
            try await Task.sleep(for: step)
            waited += step
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
        while let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: chunk) {
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
