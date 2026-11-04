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

    func transcribe(_ source: any AudioSource) -> AsyncThrowingStream<TranscriberEvent, any Error> {
        let locale = locale
        return AsyncThrowingStream { continuation in
            let work = Task {
                do {
                    try await Self.run(source: source, locale: locale, events: continuation)
                    continuation.finish()
                } catch {
                    source.stop()
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    private static func run(
        source: any AudioSource,
        locale: Locale,
        events: AsyncThrowingStream<TranscriberEvent, any Error>.Continuation
    ) async throws {
        guard SpeechTranscriber.isAvailable else { throw Failure.unavailable }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw Failure.unsupportedLanguage(locale)
        }
        let module = SpeechTranscriber(
            locale: supported,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await install.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw Failure.noAudioFormat
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        try await analyzer.prepareToAnalyze(in: format)

        let (input, feed) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let results = Task {
            for try await result in module.results {
                events.yield(.update(TranscriptUpdate(result)))
            }
        }
        try source.start(format: format, deliver: { feed.yield(AnalyzerInput(buffer: $0)) }, finish: { feed.finish() })
        events.yield(.listening)
        if let end = try await analyzer.analyzeSequence(input) {
            try await analyzer.finalizeAndFinish(through: end)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        try await results.value
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
