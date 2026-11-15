import Foundation
import KoeCore
import os

/// Reads a finished recording again after it was copied: every model `RefinePlan` picks reads the whole file in
/// parallel, `TranscriptVote` keeps the best reading of each stretch, and the result is cleaned up and spelled as the
/// live words were before the library saves it and updates the copy. Never during a session: a session pauses it (`pause`), as its live
/// passes need the Neural Engine to themselves.
@MainActor
final class Refiner {
    struct Job: Identifiable, Sendable {
        var session: Session
        var folder: URL
        var id: UUID { session.id }
    }

    nonisolated private static let log = Logger(subsystem: "studio.shinsa.koe", category: "refine")
    /// How long the models stay loaded after the last recording, so back-to-back sessions don't reload them.
    var idleUnload: Duration = .seconds(600)
    private let store: ModelStore
    private let library: SessionLibrary
    private let hints: HintWords
    private let dictionary: () -> CustomDictionary
    private var queue = RefineQueue<Job>()
    private var work: (run: Int, task: Task<Void, Never>)?
    private var runs = 0
    private var readers: [ModelID: any Transcriber] = [:]
    private var unload: Task<Void, Never>?
    /// The refined words of the last recordings read, so live words that settle after the refine don't undo it.
    private var done: [UUID: [TimedWord]] = [:]
    private var doneOrder: [UUID] = []

    init(store: ModelStore, library: SessionLibrary, hints: HintWords, dictionary: @escaping () -> CustomDictionary) {
        self.store = store
        self.library = library
        self.hints = hints
        self.dictionary = dictionary
    }

    /// Reads `session`'s recording again once nothing else needs the models.
    func refine(_ session: Session, folder: URL) {
        let models = RefinePlan.readers(installed: Set(TranscriptionModel.catalog.map(\.id).filter(store.isInstalled)))
        guard store.canDownload, !models.isEmpty else { return }
        if work != nil, queue.running?.id == session.id { work?.task.cancel() }
        start(queue.add(Job(session: session, folder: folder)))
    }

    /// While a session is open the recording being read stops, to be read again from the start once it closes.
    func sessionOpen(_ open: Bool) {
        guard open else { return start(queue.resume()) }
        if queue.pause() != nil { work?.task.cancel() }
        work = nil
    }

    /// The live session's last words settled after it was copied: it is saved spelled as the live words were, with
    /// the refined words in their place when the refine came first.
    func settled(_ session: Session, folder: URL) {
        let session = dictionary().apply(to: session)
        let refined = done[session.id].flatMap { RefinePlan.refined(session, words: $0) }
        library.refined(refined ?? session, folder: folder)
    }

    private func start(_ job: Job?) {
        guard let job else { return }
        unload?.cancel()
        runs += 1
        let run = runs
        let models = RefinePlan.readers(installed: Set(TranscriptionModel.catalog.map(\.id).filter(store.isInstalled)))
        let readers = models.compactMap { id in reader(id).map { (id, $0) } }
        let dictionary = dictionary()
        let task = Task { [weak self] in
            let words = await Self.read(job.folder.appending(path: SessionArchive.audioName), readers: readers,
                                        dictionary: dictionary)
            guard !Task.isCancelled else { return }
            self?.finished(job, words: words, run: run)
        }
        work = (run, task)
    }

    private func finished(_ job: Job, words: [TimedWord], run: Int) {
        guard work?.run == run else { return }
        work = nil
        if !words.isEmpty {
            done[job.id] = words
            doneOrder.removeAll { $0 == job.id }
            doneOrder.append(job.id)
            while doneOrder.count > 8 { done[doneOrder.removeFirst()] = nil }
        }
        if let refined = RefinePlan.refined(job.session, words: words) {
            library.refined(refined, folder: job.folder)
            if Launch.has("--print-session") {
                FileHandle.standardOutput.write(Data(("Refined: " + BundleComposer().compose(refined).text + "\n").utf8))
            }
        }
        start(queue.done(job.id))
        if queue.running == nil { scheduleUnload() }
    }

    private func scheduleUnload() {
        let delay = idleUnload
        unload = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.readers = [:]
        }
    }

    private func reader(_ id: ModelID) -> (any Transcriber)? {
        if let reader = readers[id] { return reader }
        let reader = Self.makeReader(id, store: store, hints: hints)
        readers[id] = reader
        return reader
    }

    static func makeReader(_ id: ModelID, store: ModelStore, hints: HintWords) -> (any Transcriber)? {
        switch TranscriptionModel.model(id).engine {
        case .parakeet: WindowedTranscriber.parakeet(id, store: store)
        case .whisper: WindowedTranscriber.whisper(id, store: store, hints: hints)
        case .apple: AppleSpeechTranscriber(hints: hints)
        }
    }

    /// Every model reads the file at once; one that fails is left out of the vote.
    nonisolated static func read(_ file: URL, readers: [(ModelID, any Transcriber)],
                                 dictionary: CustomDictionary) async -> [TimedWord] {
        guard let samples = try? SampleBuffer.read(file), hasAudio(samples) else { return [] }
        let started = ContinuousClock.now
        let readings = await withTaskGroup(of: TranscriptVote.Reading?.self) { group in
            for (id, reader) in readers {
                group.addTask {
                    do {
                        return TranscriptVote.Reading(model: id, words: try await reader.transcribe(file: file))
                    } catch {
                        if !(error is CancellationError) {
                            Self.log.error("\(id.rawValue, privacy: .public) couldn't read the recording: \(error, privacy: .public)")
                        }
                        return nil
                    }
                }
            }
            var readings: [TranscriptVote.Reading] = []
            for await reading in group { if let reading { readings.append(reading) } }
            return readings
        }
        guard !Task.isCancelled else { return [] }
        let levels = LevelTrack(samples: samples, rate: WindowedTranscriber.rate)
        let words = polish(TranscriptVote.combine(readings), levels: levels, dictionary: dictionary)
        let took = ContinuousClock.now - started
        log.info("Refined with \(readings.map(\.model.rawValue).joined(separator: ", "), privacy: .public) in \(took, privacy: .public)")
        return words
    }

    /// Whether a recording is long enough to read: Apple's model never answers on an empty one, which would hold up
    /// every recording after it.
    nonisolated static func hasAudio(_ samples: [Float]) -> Bool {
        Double(samples.count) >= 0.5 * WindowedTranscriber.rate
    }

    /// Cleaned up and spelled as the live words are.
    nonisolated static func polish(_ words: [TimedWord], levels: LevelTrack?, dictionary: CustomDictionary)
        -> [TimedWord] {
        dictionary.apply(TranscriptCleanup.apply(words: words, levels: levels))
    }
}
