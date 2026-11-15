import Foundation
import KoeCore

/// `Koe --bench --refine [--text] [count | audio files…]`: for every recorded session on this Mac (or the newest `count`, or
/// the files named), streams it live with the fastest installed model as a session would, then reads it whole with
/// every model the refine uses and combines them as `Refiner` does. It prints each one's word error rate against the
/// combined transcript (and against a `reference.txt` in the session folder, when you add one), how long the refine
/// took, and the live passes alone and while a refine reads beside them. Nothing leaves the Mac.
@MainActor
enum RefineBench {
    private struct Line {
        var name: String
        var score = WordErrorRate()
        var truth = WordErrorRate()
    }

    /// Every recording's scores and timings added up.
    private struct Totals {
        var lines: [Line]
        var combined = Line(name: "combined")
        var endings: [TailScore.Result] = []
        var alone = StepTimings(budget: 0.9)
        var beside = StepTimings(budget: 0.9)
        var refine: Double = 0
        var audio: Double = 0
        var truths = 0

        init(names: [String]) { lines = names.map { Line(name: $0) } }

        mutating func add(_ result: Result) {
            for index in lines.indices { lines[index].score += result.scores[index] }
            if let truths = result.truths, let combinedTruth = result.combinedTruth {
                for index in lines.indices { lines[index].truth += truths[index] }
                combined.truth += combinedTruth
                self.truths += 1
            }
            endings.append(result.ending)
            alone.merge(result.alone)
            beside.merge(result.beside)
            refine += result.refine
            audio += result.length
        }

        func report() {
            print("\nAll \(endings.count) recordings, \(String(format: "%.0f s", audio)) of audio")
            print("Word error rate against the combined transcript:")
            for line in lines { print("  \(pad(line.name)) \(line.score.summary)") }
            if truths > 0 {
                print("Word error rate against reference.txt (\(truths) recordings):")
                for line in lines + [combined] { print("  \(pad(line.name)) \(line.truth.summary)") }
            }
            print("Live ending matches the combined one: \(TailScore.total(endings))")
            print("Refine took \(String(format: "%.1f s", refine)) in all, "
                + String(format: "%.2f s per minute of audio", audio > 0 ? refine / audio * 60 : 0))
            print("Live passes alone:           \(alone.summary)")
            print("Live passes beside a refine: \(beside.summary)")
        }
    }

    static func run(_ files: [URL], vocabulary: Vocabulary) async -> Int32 {
        // A long run prints each recording as it goes, also into a file.
        setvbuf(stdout, nil, _IOLBF, 0)
        let store = ModelStore()
        let installed = Set(TranscriptionModel.catalog.map(\.id).filter(store.isInstalled))
        let models = RefinePlan.readers(installed: installed)
        guard let liveID = [ModelID.parakeetV3, .parakeetV2].first(where: installed.contains),
              let live = WindowedTranscriber.parakeet(liveID, store: store), !models.isEmpty else {
            print("Download Parakeet in Koe's settings first: it streams, and the refine needs it.")
            return 1
        }
        guard !files.isEmpty else {
            print("No recordings to read.")
            return 1
        }
        await vocabulary.rescan()
        let dictionary = vocabulary.dictionary
        let readers = models.compactMap { id in
            Refiner.makeReader(id, store: store, hints: vocabulary.hints).map { (id, $0) }
        }
        let clock = ContinuousClock()
        print("Streams with \(TranscriptionModel.model(liveID).name); refines with "
            + readers.map { TranscriptionModel.model($0.0).name }.joined(separator: ", ") + ".")
        do {
            let load = try await clock.measure { try await live.decoder.load() }
            print("\(TranscriptionModel.model(liveID).name) loaded in \(TailBench.seconds(load))")
        } catch {
            print("\(TranscriptionModel.model(liveID).name) didn't load: \(error.localizedDescription)")
            return 1
        }
        for (id, reader) in readers {
            let load = await clock.measure { await reader.prewarm() }
            print("\(TranscriptionModel.model(id).name) loaded in \(TailBench.seconds(load))")
        }

        var totals = Totals(names: ["live"] + readers.map { TranscriptionModel.model($0.0).name })
        for file in files {
            do {
                totals.add(try await bench(file, live: live, readers: readers, dictionary: dictionary))
            } catch {
                print("skip \(file.path): \(error.localizedDescription)")
            }
        }
        totals.report()
        return 0
    }

    private struct Result {
        var scores: [WordErrorRate]
        var truths: [WordErrorRate]?
        var combinedTruth: WordErrorRate?
        var ending: TailScore.Result
        var alone: StepTimings
        var beside: StepTimings
        var refine: Double
        var length: Double
    }

    private static func bench(_ file: URL, live: WindowedTranscriber, readers: [(ModelID, any Transcriber)],
                              dictionary: CustomDictionary) async throws -> Result {
        let folder = file.deletingLastPathComponent()
        let samples = try SampleBuffer.read(file)
        guard Refiner.hasAudio(samples) else { throw CocoaError(.fileReadCorruptFile) }
        let levels = LevelTrack(samples: samples, rate: WindowedTranscriber.rate)
        let length = Double(samples.count) / WindowedTranscriber.rate

        let (transcript, alone) = try await TailBench.replay(samples, decoder: live.decoder)
        let liveWords = dictionary.apply(
            TranscriptCleanup.apply(words: transcript.words, pending: transcript.pending, levels: levels))

        let clock = ContinuousClock()
        var readings: [(TranscriptVote.Reading, Duration)] = []
        let refine = await clock.measure { readings = await read(file, readers: readers) }
        let combined = Refiner.polish(TranscriptVote.combine(readings.map(\.0)), levels: levels, dictionary: dictionary)

        async let refining = Refiner.read(file, readers: readers, dictionary: dictionary)
        let (_, beside) = try await TailBench.replay(samples, decoder: live.decoder)
        _ = await refining

        let text = { (words: [TimedWord]) in words.map(\.text).joined(separator: " ") }
        let modelTexts = readers.map { id, _ in
            readings.first { $0.0.model == id }.map { text(Refiner.polish($0.0.words, levels: levels, dictionary: dictionary)) }
        }
        let outputs = [text(liveWords)] + modelTexts.map { $0 ?? "" }
        let reference = text(combined)
        let scores = outputs.map { WordErrorRate.compare($0, to: reference) }
        let truth = try? String(contentsOf: folder.appending(path: "reference.txt"), encoding: .utf8)
        let truths = truth.map { truth in outputs.map { WordErrorRate.compare($0, to: truth) } }
        let combinedTruth = truth.map { WordErrorRate.compare(reference, to: $0) }
        let ending = TailScore.compare(live: outputs[0], reference: reference)

        print("\(ending.isComplete ? "ok  " : "CUT ")\(folder.lastPathComponent)  \(String(format: "%.0f s", length)), "
            + "refine \(TailBench.seconds(refine))")
        print("     \(pad("live")) \(scores[0].summary)")
        for (index, (id, _)) in readers.enumerated() {
            let took = readings.first { $0.0.model == id }.map { TailBench.seconds($0.1) } ?? "failed"
            print("     \(pad(TranscriptionModel.model(id).name)) \(scores[index + 1].summary), read in \(took)")
        }
        if let truths, let combinedTruth {
            let names = ["live"] + readers.map { TranscriptionModel.model($0.0).name } + ["combined"]
            print("     against reference.txt: "
                + zip(names, truths + [combinedTruth]).map { "\($0) \($1.summary)" }.joined(separator: ", "))
        }
        print("     live passes alone: \(alone.summary); beside a refine: \(beside.summary)")
        if Launch.has("--text") {
            print("     live:     \(outputs[0])")
            print("     combined: \(reference)")
        }
        return Result(scores: scores, truths: truths, combinedTruth: combinedTruth, ending: ending, alone: alone, beside: beside,
                      refine: Double(refine.components.seconds) + Double(refine.components.attoseconds) / 1e18,
                      length: length)
    }

    /// Every model reads the file at once, as `Refiner.read` has them, each timed.
    private static func read(_ file: URL, readers: [(ModelID, any Transcriber)])
        async -> [(TranscriptVote.Reading, Duration)] {
        await withTaskGroup(of: (TranscriptVote.Reading, Duration)?.self) { group in
            for (id, reader) in readers {
                group.addTask {
                    let started = ContinuousClock.now
                    guard let words = try? await reader.transcribe(file: file) else { return nil }
                    return (TranscriptVote.Reading(model: id, words: words), ContinuousClock.now - started)
                }
            }
            var readings: [(TranscriptVote.Reading, Duration)] = []
            for await reading in group { if let reading { readings.append(reading) } }
            return readings
        }
    }

    nonisolated private static func pad(_ name: String) -> String {
        name.padding(toLength: 24, withPad: " ", startingAt: 0)
    }
}
