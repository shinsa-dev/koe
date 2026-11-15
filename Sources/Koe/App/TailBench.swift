import Foundation
import KoeCore

/// `Koe --bench [--model <id> | --refine] [count | audio files…]`: replays recorded sessions through the live window, fed 0.9 s
/// at a time as the microphone would, and checks each ends with the same words as one decode of the whole recording.
/// It prints how long the model took to load and each pass took, against the 0.9 s it has. It reads the newest
/// sessions on this Mac with the default model, or the one named; nothing leaves it.
@MainActor
enum TailBench {
    private static let interval: TimeInterval = 0.9

    static func run(_ arguments: [String]) async -> Int32 {
        var arguments = arguments
        if let flag = arguments.firstIndex(of: "--refine") {
            arguments.remove(at: flag)
            arguments.removeAll { $0 == "--text" }
            return await RefineBench.run(recordings(arguments.isEmpty ? [String(Int.max)] : arguments),
                                         vocabulary: vocabulary)
        }
        guard let model = chosenModel(&arguments) else {
            let ids = TranscriptionModel.catalog.filter { $0.engine != .apple }.map(\.id.rawValue)
            print("Name a model to bench: \(ids.joined(separator: ", ")).")
            return 1
        }
        let files = recordings(arguments)
        guard !files.isEmpty else {
            print("No recordings to replay.")
            return 1
        }
        let store = ModelStore()
        guard model.engine != .apple else {
            print("Apple's model streams on its own, so the bench can't replay it.")
            return 1
        }
        guard store.isInstalled(model.id), let transcriber = windowed(model, store: store) else {
            print("Download \(model.name) in Koe's settings first.")
            return 1
        }
        let clock = ContinuousClock()
        await vocabulary.rescan()
        print("Dictionary: \(dictionary.entries.count) words")
        do {
            let load = try await clock.measure { try await transcriber.decoder.load() }
            print("\(model.name) loaded in \(seconds(load))")
        } catch {
            print("\(model.name) didn't load: \(error.localizedDescription)")
            return 1
        }
        var results: [TailScore.Result] = []
        var timings = StepTimings(budget: interval)
        for file in files {
            do {
                let (result, steps) = try await bench(file, transcriber: transcriber)
                results.append(result)
                timings.merge(steps)
            } catch {
                print("skip \(file.path): \(error.localizedDescription)")
            }
        }
        print("Endings complete: \(TailScore.total(results))")
        print("All steps: \(timings.summary)")
        return 0
    }

    /// Replays one recording live and decodes it whole, printing how its ending and its timings compare.
    private static func bench(_ file: URL, transcriber: WindowedTranscriber) async throws
        -> (TailScore.Result, StepTimings) {
        let samples = try SampleBuffer.read(file)
        let (transcript, steps) = try await replay(samples, decoder: transcriber.decoder)
        let live = transcript.text
        var words: [TimedWord] = []
        let whole = try await ContinuousClock().measure { words = try await transcriber.transcribe(file: file) }
        let result = TailScore.compare(live: live, reference: words.map(\.text).joined(separator: " "))
        let mark = result.isComplete ? "ok  " : "CUT "
        let length = Double(samples.count) / WindowedTranscriber.rate
        print("\(mark)\(file.deletingLastPathComponent().lastPathComponent)  live: …\(result.live.joined(separator: " "))"
            + "  whole: …\(result.reference.joined(separator: " "))")
        print("     \(String(format: "%.0f s", length)) of audio, steps: \(steps.summary), whole decode \(seconds(whole))")
        print("     \(cleanup(words, samples: samples, folder: file.deletingLastPathComponent()))")
        print("     \(spelling(words, folder: file.deletingLastPathComponent()))")
        return (result, steps)
    }

    /// What the cleanup takes out of the whole decode and of the words this session was copied with, and how long it
    /// takes. Reading the levels from the file is timed apart: a live session records them as it goes.
    private static func cleanup(_ words: [TimedWord], samples: [Float], folder: URL) -> String {
        let clock = ContinuousClock()
        var levels = LevelTrack()
        let reading = clock.measure { levels = LevelTrack(samples: samples, rate: WindowedTranscriber.rate) }
        var cleaned: [TimedWord] = []
        let took = clock.measure { cleaned = TranscriptCleanup.apply(words: words, levels: levels) }
        var line = "cleanup \(String(format: "%.2f ms", milliseconds(took))) (levels read in "
            + "\(String(format: "%.0f ms", milliseconds(reading)))), removed: \(removed(from: words, kept: cleaned))"
        if let saved = savedWords(in: folder) {
            line += "\n     copied words, removed: "
                + removed(from: saved, kept: TranscriptCleanup.apply(words: saved, levels: levels))
        }
        return line
    }

    /// What the dictionary spells differently in the whole decode and in the words this session was copied with, and
    /// how long it takes.
    private static func spelling(_ words: [TimedWord], folder: URL) -> String {
        var fixed: [TimedWord] = []
        let took = ContinuousClock().measure { fixed = dictionary.apply(words) }
        var line = "dictionary \(String(format: "%.2f ms", milliseconds(took))), replaced: \(replaced(words, fixed))"
        if let saved = savedWords(in: folder) {
            line += "\n     copied words, replaced: \(replaced(saved, dictionary.apply(saved)))"
        }
        return line
    }

    /// Each replaced run of heard words with what it became: a word the fix made that wasn't heard, against the heard
    /// words it spans.
    private static func replaced(_ words: [TimedWord], _ fixed: [TimedWord]) -> String {
        let changes = fixed.filter { !words.contains($0) }.map { word in
            let before = words.drop { $0.start < word.start }.prefix(CustomDictionary.maxSpan)
                .prefix { $0.end <= word.end }.map(\.text)
            return "\(before.joined(separator: " ")) → \(word.text)"
        }
        return changes.isEmpty ? "nothing" : changes.joined(separator: ", ")
    }

    /// Your words and the names learned from this Mac, scanned fresh into a scratch cache so the bench saves nothing.
    static let vocabulary: Vocabulary = {
        let vocabulary = Vocabulary(cache: FileManager.default.temporaryDirectory.appending(path: "koe-bench-names.json"))
        vocabulary.update(settings: KoeSettings(values: UserDefaults.standard.dictionaryRepresentation()))
        return vocabulary
    }()

    private static var dictionary: CustomDictionary { vocabulary.dictionary }

    private static func removed(from words: [TimedWord], kept: [TimedWord]) -> String {
        let starts = Set(kept.map(\.start))
        let gone = words.filter { !starts.contains($0.start) }
            .map { "\($0.text) (\(String(format: "%.1f", $0.start)) s)" }
        return gone.isEmpty ? "nothing" : gone.joined(separator: ", ")
    }

    private static func savedWords(in folder: URL) -> [TimedWord]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: folder.appending(path: SessionArchive.fileName)))
            .flatMap { try? decoder.decode(Session.self, from: $0) }?.words
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    /// The model `--model <id>` names, taken out of `arguments`, or the default one; nil for a name Koe doesn't know.
    private static func chosenModel(_ arguments: inout [String]) -> TranscriptionModel? {
        guard let flag = arguments.firstIndex(of: "--model") else { return .standard }
        let name = arguments.indices.contains(flag + 1) ? arguments[flag + 1] : ""
        arguments.removeSubrange(flag...min(flag + 1, arguments.count - 1))
        return ModelID(rawValue: name).map(TranscriptionModel.model)
    }

    private static func windowed(_ model: TranscriptionModel, store: ModelStore) -> WindowedTranscriber? {
        switch model.engine {
        case .parakeet: WindowedTranscriber.parakeet(model.id, store: store)
        case .whisper: WindowedTranscriber.whisper(model.id, store: store, hints: vocabulary.hints)
        case .apple: nil
        }
    }

    static func seconds(_ duration: Duration) -> String {
        String(format: "%.2f s", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    /// The live transcript a session of `samples` ends with, stepped as `WindowedTranscriber` steps a session, and how
    /// long each step took.
    static func replay(_ samples: [Float], decoder: any WindowDecoder) async throws -> (LiveTranscript, StepTimings) {
        try await decoder.load()
        let buffer = SampleBuffer()
        var window = RollingWindow()
        var language = LanguageLock()
        var transcript = LiveTranscript()
        var timings = StepTimings(budget: interval)
        let clock = ContinuousClock()
        let chunk = Int(interval * WindowedTranscriber.rate)
        var fed = 0
        while true {
            if fed < samples.count {
                buffer.append(Array(samples[fed..<min(fed + chunk, samples.count)]))
                fed += chunk
            } else {
                buffer.end()
            }
            let started = clock.now
            let (updates, ended) = try await WindowedTranscriber.step(
                &window, language: &language, buffer: buffer, decoder: decoder)
            let took = started.duration(to: clock.now)
            timings.record(Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18)
            for update in updates { transcript.apply(update) }
            if ended { return (transcript, timings) }
        }
    }

    /// The files named, or the newest `count` (40 when not given) recorded sessions.
    static func recordings(_ arguments: [String]) -> [URL] {
        if let first = arguments.first, Int(first) == nil {
            return arguments.map { URL(filePath: $0) }
        }
        let count = arguments.first.flatMap(Int.init) ?? 40
        let root = SessionController.defaultRoot
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return folders.sorted().reversed()
            .map { root.appending(path: $0).appending(path: "audio.caf") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .prefix(count).reversed()
    }
}
