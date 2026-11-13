@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import KoeCore
import Speech

/// Apple's on-device speech model (SpeechAnalyzer with SpeechTranscriber, macOS 26). Nothing leaves the Mac, and the
/// model is part of the system, so there is nothing to download for most languages.
struct AppleSpeechTranscriber: Transcriber {
    var locale: Locale = .current

    enum Failure: LocalizedError {
        case unavailable
        case unsupportedLanguage(Locale)
        case noAudioFormat

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Apple's speech model isn't available on this Mac."
            case .unsupportedLanguage(let locale):
                let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
                return "Apple's speech model doesn't support \(name) yet."
            case .noAudioFormat: return "Apple's speech model can't take audio right now."
            }
        }
    }

    func prewarm() async {
        _ = try? await SpeechSetup.shared.prepare(locale)
    }

    func transcribe(_ source: any AudioSource) -> AsyncThrowingStream<TranscriberEvent, any Error> {
        let locale = locale
        return AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    try await Self.run(source: source, locale: locale, events: continuation)
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
        let prepared = try await SpeechSetup.shared.prepare(locale)
        let module = SpeechSetup.module(for: prepared.locale)
        let analyzer = SpeechAnalyzer(modules: [module])
        let audio = try AVAudioFile(forReading: file)
        let results = Task {
            var transcript = LiveTranscript()
            for try await result in module.results { transcript.apply(TranscriptUpdate(result)) }
            return transcript.words + transcript.pending
        }
        if let end = try await analyzer.analyzeSequence(from: audio) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await results.value
    }

    private static func run(
        source: any AudioSource,
        locale: Locale,
        events: AsyncThrowingStream<TranscriberEvent, any Error>.Continuation
    ) async throws {
        let prepared = try await SpeechSetup.shared.prepare(locale)
        let module = SpeechSetup.module(for: prepared.locale)
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: prepared.format)

        let (input, feed) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let results = Task {
            for try await result in module.results {
                events.yield(.update(TranscriptUpdate(result)))
            }
        }
        source.attach(format: prepared.format, deliver: { feed.yield(AnalyzerInput(buffer: $0)) }, finish: { feed.finish() })
        events.yield(.listening)
        if let end = try await analyzer.analyzeSequence(input) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        try await results.value
    }
}

/// What every session needs from the model before audio can flow: the supported locale, the installed assets and the
/// audio format. Worked out once, at launch, and kept, so starting a session costs only the analyzer itself.
actor SpeechSetup {
    static let shared = SpeechSetup()

    struct Prepared: @unchecked Sendable {
        let locale: Locale
        let format: AVAudioFormat
    }

    private var cache: [String: Prepared] = [:]

    static func module(for locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [.volatileResults],
                          attributeOptions: [.audioTimeRange])
    }

    func prepare(_ locale: Locale) async throws -> Prepared {
        if let cached = cache[locale.identifier] { return cached }
        guard SpeechTranscriber.isAvailable else { throw AppleSpeechTranscriber.Failure.unavailable }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AppleSpeechTranscriber.Failure.unsupportedLanguage(locale)
        }
        let module = Self.module(for: supported)
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await install.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw AppleSpeechTranscriber.Failure.noAudioFormat
        }
        let prepared = Prepared(locale: supported, format: format)
        cache[locale.identifier] = prepared
        return prepared
    }
}

extension TranscriptUpdate {
    /// A final result times each word; a volatile one often times none, so its words share the result's range.
    init(_ result: SpeechTranscriber.Result) {
        let range = result.range
        let runs = result.text.runs.map { run in
            let timed = run.audioTimeRange ?? range
            return TranscriptRun(
                String(result.text[run.range].characters),
                start: timed.start.audioSeconds,
                end: timed.end.audioSeconds
            )
        }
        self.init(runs: runs, isFinal: result.isFinal, start: range.start.audioSeconds, end: range.end.audioSeconds)
    }
}

private extension CMTime {
    var audioSeconds: AudioTime { isNumeric ? max(0, seconds) : 0 }
}
