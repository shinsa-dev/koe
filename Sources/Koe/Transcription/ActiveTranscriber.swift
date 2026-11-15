import Foundation
import KoeCore
import os

/// The transcriber sessions use: the model chosen in Settings once it is downloaded and has loaded, otherwise Apple's.
/// It switches as soon as the choice or a download changes, without a relaunch; a session already running keeps the
/// model it started with.
final class ActiveTranscriber: Transcriber, @unchecked Sendable {
    private static let log = Logger(subsystem: "studio.shinsa.koe", category: "transcription")

    private let apple: AppleSpeechTranscriber
    private let hints: HintWords
    private let lock = NSLock()
    private var current: (id: ModelID, model: WindowedTranscriber?) = (.apple, nil)
    private var loaded: [ModelID: WindowedTranscriber] = [:]
    private var loadErrors: [ModelID: String] = [:]
    /// Models that have loaded in this run. Only these take a session, so none waits on a load.
    private var ready: Set<ModelID> = []
    private var route = TranscriberRoute.resolve(chosen: .apple, install: .installed, canRun: true, loadError: nil)
    /// Called on the main actor whenever the model that runs, or the reason it isn't the chosen one, changes.
    @MainActor var onRouteChange: ((TranscriberRoute) -> Void)?
    @MainActor private var refresh: (() -> Void)?

    /// `hints` are your dictionary, which Apple's model and Whisper hear before they decode.
    @MainActor init(hints: HintWords = HintWords()) {
        self.hints = hints
        apple = AppleSpeechTranscriber(hints: hints)
    }

    var currentRoute: TranscriberRoute { lock.withLock { route } }

    /// Works out which model runs for `chosen` and readies it. Call again whenever the choice or a download changes.
    @MainActor func update(chosen: ModelID, store: ModelStore) {
        refresh = { [weak self, weak store] in
            guard let self, let store else { return }
            self.update(chosen: chosen, store: store)
        }
        let install = store.install(chosen)
        let next = lock.withLock { () -> (route: TranscriberRoute, warm: (ModelID, WindowedTranscriber?))? in
            // A model downloaded again gets another chance to load.
            for id in loadErrors.keys where !store.isInstalled(id) { loadErrors[id] = nil }
            for id in loaded.keys where !store.isInstalled(id) || id != chosen { loaded[id] = nil }
            ready = ready.filter { loaded[$0] != nil }
            let runnable = TranscriberRoute.resolve(chosen: chosen, install: install, canRun: store.canDownload,
                                                    loadError: loadErrors[chosen])
            var model: WindowedTranscriber?
            if runnable.model != .apple {
                model = loaded[chosen] ?? Self.make(chosen, store: store, hints: hints)
                loaded[chosen] = model
            }
            let route = TranscriberRoute.resolve(chosen: chosen, install: install, canRun: store.canDownload,
                                                 loadError: loadErrors[chosen], isLoaded: ready.contains(chosen))
            let changed = route != self.route || current.id != route.model
            self.route = route
            current = route.model == .apple ? (.apple, nil) : (chosen, model)
            // Until the chosen model has loaded, it loads in the background while Apple's takes the sessions.
            let warm: (ModelID, WindowedTranscriber?) = route.fallback == .preparing && model != nil
                ? (chosen, model) : current
            return changed ? (route, warm) : nil
        }
        guard let next else { return }
        onRouteChange?(next.route)
        let (id, model) = next.warm
        Task {
            if model != nil, id != next.route.model { await self.apple.prewarm() }
            await self.prewarm(model, id: id)
        }
    }

    func prewarm() async {
        let current = lock.withLock { self.current }
        await prewarm(current.model, id: current.id)
    }

    func transcribe(_ source: any AudioSource) -> AsyncThrowingStream<TranscriberEvent, any Error> {
        let (id, model) = lock.withLock { current }
        guard let model else { return apple.transcribe(source) }
        return AsyncThrowingStream { continuation in
            let work = Task {
                let events: AsyncThrowingStream<TranscriberEvent, any Error>
                do {
                    try await model.load()
                    events = model.transcribe(source)
                } catch {
                    // Nothing is attached yet, so Apple's model can take the same audio from the start.
                    self.failed(id, error)
                    events = self.apple.transcribe(source)
                }
                do {
                    for try await event in events { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    func transcribe(file: URL) async throws -> [TimedWord] {
        let (id, model) = lock.withLock { current }
        guard let model else { return try await apple.transcribe(file: file) }
        do {
            try await model.load()
        } catch {
            failed(id, error)
            return try await apple.transcribe(file: file)
        }
        return try await model.transcribe(file: file)
    }

    private func prewarm(_ model: WindowedTranscriber?, id: ModelID) async {
        guard let model else { return await apple.prewarm() }
        do {
            try await model.load()
            loadedNow(id)
        } catch {
            failed(id, error)
            await apple.prewarm()
        }
    }

    private func loadedNow(_ id: ModelID) {
        let first = lock.withLock { loaded[id] != nil && ready.insert(id).inserted }
        if first { Task { @MainActor in self.refresh?() } }
    }

    private func failed(_ id: ModelID, _ error: any Error) {
        Self.log.error("\(id.rawValue, privacy: .public) didn't load: \(error, privacy: .public)")
        lock.withLock {
            loadErrors[id] = error.localizedDescription
            loaded[id] = nil
            ready.remove(id)
        }
        Task { @MainActor in self.refresh?() }
    }

    @MainActor private static func make(_ id: ModelID, store: ModelStore, hints: HintWords) -> WindowedTranscriber? {
        switch TranscriptionModel.model(id).engine {
        case .parakeet: .parakeet(id, store: store)
        case .whisper: .whisper(id, store: store, hints: hints)
        case .apple: nil
        }
    }
}

extension WindowedTranscriber {
    func load() async throws { try await decoder.load() }
}
