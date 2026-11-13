import Foundation
import KoeCore
import os

/// The transcriber sessions use: the model chosen in Settings when it is downloaded and loads, otherwise Apple's.
/// It switches as soon as the choice or a download changes, without a relaunch; a session already running keeps the
/// model it started with.
final class ActiveTranscriber: Transcriber, @unchecked Sendable {
    private static let log = Logger(subsystem: "studio.shinsa.koe", category: "transcription")

    private let apple = AppleSpeechTranscriber()
    private let lock = NSLock()
    private var current: (id: ModelID, model: WindowedTranscriber?) = (.apple, nil)
    private var loaded: [ModelID: WindowedTranscriber] = [:]
    private var loadErrors: [ModelID: String] = [:]
    private var route = TranscriberRoute.resolve(chosen: .apple, install: .installed, canRun: true, loadError: nil)
    /// Called on the main actor whenever the model that runs, or the reason it isn't the chosen one, changes.
    @MainActor var onRouteChange: ((TranscriberRoute) -> Void)?
    @MainActor private var refresh: (() -> Void)?

    @MainActor init() {}

    var currentRoute: TranscriberRoute { lock.withLock { route } }

    /// Works out which model runs for `chosen` and readies it. Call again whenever the choice or a download changes.
    @MainActor func update(chosen: ModelID, store: ModelStore) {
        refresh = { [weak self, weak store] in
            guard let self, let store else { return }
            self.update(chosen: chosen, store: store)
        }
        let install = store.install(chosen)
        let next = lock.withLock { () -> (route: TranscriberRoute, model: WindowedTranscriber?)? in
            // A model downloaded again gets another chance to load.
            for id in loadErrors.keys where !store.isInstalled(id) { loadErrors[id] = nil }
            for id in loaded.keys where !store.isInstalled(id) || id != chosen { loaded[id] = nil }
            let route = TranscriberRoute.resolve(chosen: chosen, install: install, canRun: store.canDownload,
                                                 loadError: loadErrors[chosen])
            var model: WindowedTranscriber?
            if route.model != .apple {
                model = loaded[chosen] ?? Self.make(chosen, store: store)
                loaded[chosen] = model
            }
            let changed = route != self.route || current.id != route.model
            self.route = route
            current = (route.model, model)
            return changed ? (route, model) : nil
        }
        guard let next else { return }
        onRouteChange?(next.route)
        Task { await self.prewarm(next.model, id: next.route.model) }
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
        } catch {
            failed(id, error)
            await apple.prewarm()
        }
    }

    private func failed(_ id: ModelID, _ error: any Error) {
        Self.log.error("\(id.rawValue, privacy: .public) didn't load: \(error, privacy: .public)")
        lock.withLock {
            loadErrors[id] = error.localizedDescription
            loaded[id] = nil
        }
        Task { @MainActor in self.refresh?() }
    }

    @MainActor private static func make(_ id: ModelID, store: ModelStore) -> WindowedTranscriber? {
        switch TranscriptionModel.model(id).engine {
        case .parakeet: .parakeet(id, store: store)
        case .whisper: .whisper(id, store: store)
        case .apple: nil
        }
    }
}

extension WindowedTranscriber {
    func load() async throws { try await decoder.load() }
}
