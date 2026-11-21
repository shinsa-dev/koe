import FluidAudio
import Foundation
import KoeCore
import Network
import Observation
import os
import WhisperKit

/// The downloaded speech models, one folder each in `~/Library/Application Support/Koe/Models`. Downloads come from
/// Hugging Face and nothing else goes online: audio and text never leave the Mac.
@MainActor @Observable
final class ModelStore {
    @ObservationIgnored private static let log = Logger(subsystem: "studio.overclock.koe", category: "models")
    /// Written last, once every file is in and the model loads, so a download cut short never counts as installed.
    private static let marker = ".koe-installed"

    let root: URL
    /// Parakeet's and Whisper's Core ML models run only on Apple silicon.
    let canDownload: Bool
    private(set) var installs: [ModelID: ModelInstall] = [:]
    /// Which model transcribes and why, as the transcriber last worked it out. Settings shows it.
    var route = TranscriberRoute.resolve(chosen: .apple, install: .installed, canRun: true, loadError: nil)
    /// Called on the main actor when a download starts, ends or is deleted, so the transcriber switches at once.
    @ObservationIgnored var onChange: ((ModelID) -> Void)?
    @ObservationIgnored private var downloads: [ModelID: Task<Void, Never>] = [:]

    static var standardRoot: URL {
        URL.applicationSupportDirectory.appending(path: "Koe/Models", directoryHint: .isDirectory)
    }

    init(root: URL = ModelStore.standardRoot, canDownload: Bool = SystemInfo.isAppleSilicon) {
        self.root = root
        self.canDownload = canDownload
        for model in TranscriptionModel.catalog where model.needsDownload {
            let done = FileManager.default.fileExists(atPath: folder(for: model.id).appending(path: Self.marker).path)
            installs[model.id] = done ? .installed : .notInstalled
        }
    }

    func install(_ id: ModelID) -> ModelInstall {
        TranscriptionModel.model(id).needsDownload ? installs[id] ?? .notInstalled : .installed
    }

    func isInstalled(_ id: ModelID) -> Bool { install(id).isInstalled }

    /// Koe's own choice of models from what is on this Mac, leaving out the ones you deleted.
    func plan(deleted: Set<ModelID>) -> ModelPlan {
        ModelPlan(installs: installs, deleted: deleted, canDownload: canDownload)
    }

    /// Starts the next download the plan has due, if any: Fluid Speech Pro, then Whisper. Called at launch and whenever
    /// a download ends, so they come one after the other by themselves.
    func downloadNext(deleted: Set<ModelID>) {
        if let id = plan(deleted: deleted).nextDownload { download(id) }
    }

    /// Everything one model keeps on disk. Deleting it deletes the model.
    func folder(for id: ModelID) -> URL {
        root.appending(path: id.rawValue, directoryHint: .isDirectory)
    }

    func download(_ id: ModelID) {
        let model = TranscriptionModel.model(id)
        guard model.needsDownload, canDownload, downloads[id] == nil, !isInstalled(id) else { return }
        let folder = folder(for: id)
        installs[id] = .downloading(fraction: 0)
        defer { onChange?(id) }
        downloads[id] = Task { [weak self] in
            let progress = Task { [weak self] in
                while !Task.isCancelled {
                    let onDisk = await Self.size(of: folder)
                    guard !Task.isCancelled, let self, self.installs[id]?.isDownloading == true else { return }
                    self.installs[id] = .progress(onDisk: onDisk, expected: model.bytes)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            let outcome: ModelInstall
            do {
                try await Self.fetch(model, into: folder)
                self?.installs[id] = .preparing
                self?.onChange?(id)
                try await Self.prepare(model, in: folder)
                try Data().write(to: folder.appending(path: Self.marker))
                outcome = .installed
            } catch {
                if Task.isCancelled || error is CancellationError {
                    outcome = .notInstalled
                } else {
                    Self.log.error("Download of \(id.rawValue, privacy: .public) failed: \(error, privacy: .public)")
                    outcome = .failed(DownloadFailure(error, online: await Self.isOnline()).message)
                }
                try? FileManager.default.removeItem(at: folder)
            }
            progress.cancel()
            guard let self else { return }
            self.downloads[id] = nil
            self.installs[id] = outcome
            self.onChange?(id)
        }
    }

    /// Downloads a model you asked for (Download, Try again), taking it off the models you deleted.
    func request(_ id: ModelID, in library: SessionLibrary) {
        if library.settings.deletedModels.contains(id) { library.update { $0.deletedModels.remove(id) } }
        download(id)
    }

    /// Stops a download and throws away what it fetched.
    func cancel(_ id: ModelID) {
        downloads[id]?.cancel()
    }

    /// Deletes a model you asked to delete, and remembers it so Koe doesn't download it again by itself.
    func delete(_ id: ModelID, in library: SessionLibrary) {
        guard TranscriptionModel.model(id).needsDownload else { return }
        library.update { $0.deletedModels.insert(id) }
        delete(id)
    }

    func delete(_ id: ModelID) {
        guard TranscriptionModel.model(id).needsDownload else { return }
        // A running download removes its own folder as it stops.
        if let download = downloads[id] { return download.cancel() }
        try? FileManager.default.removeItem(at: folder(for: id))
        installs[id] = .notInstalled
        onChange?(id)
    }

    // MARK: - Fetching

    private nonisolated static func fetch(_ model: TranscriptionModel, into folder: URL) async throws {
        // Files a download cut short by a quit would pass for a model and then fail to load.
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        switch model.engine {
        case .parakeet:
            if let snapshot = model.id.snapshot {
                let hub = HubApiWrapper(downloadBase: folder)
                _ = try await hub.snapshot(from: .init(id: snapshot.repository), revision: snapshot.revision,
                                           matching: snapshot.globs)
                try Task.checkCancellation()
                try snapshot.verify(in: snapshotFolder(in: folder, snapshot: snapshot))
                break
            }
            // Without a source an empty folder would pass for the model.
            guard let version = model.id.parakeetVersion else { throw CocoaError(.featureUnsupported) }
            // Downloads every file, then compiles the models once, which proves they load.
            try await AsrModels.download(to: parakeetFolder(in: folder, version: version), version: version)
        case .whisper:
            guard let variant = model.id.whisperVariant else { return }
            _ = try await WhisperKit.download(variant: variant, downloadBase: folder)
            // WhisperKit fetches the tokenizer on first load; fetch it now so loading later stays offline.
            _ = try await ModelUtilities.loadTokenizer(for: .largev3, tokenizerFolder: folder)
        case .apple:
            return
        }
        try Task.checkCancellation()
    }

    /// Loads the model once, so Core ML compiles it for the Neural Engine now rather than when a session needs it.
    /// Whisper's compile takes minutes the first time and is then cached; FluidAudio's download already compiled
    /// Parakeet, and a snapshot's first load proves every file came.
    private nonisolated static func prepare(_ model: TranscriptionModel, in folder: URL) async throws {
        if let snapshot = model.id.snapshot {
            _ = try await ParakeetDecoder.models(in: snapshotFolder(in: folder, snapshot: snapshot))
        } else if model.engine == .whisper, let variant = model.id.whisperVariant {
            try await WhisperDecoder.prepare(folder: folder, variant: variant)
        }
        try Task.checkCancellation()
    }

    /// Where FluidAudio keeps a Parakeet model inside its folder.
    nonisolated static func parakeetFolder(in folder: URL, version: AsrModelVersion) -> URL {
        folder.appending(path: version == .v2 ? Repo.parakeetV2.folderName : Repo.parakeet.folderName,
                         directoryHint: .isDirectory)
    }

    /// Where Hugging Face's client keeps a snapshot inside its folder.
    nonisolated static func snapshotFolder(in folder: URL, snapshot: HubSnapshot) -> URL {
        folder.appending(path: snapshot.folder, directoryHint: .isDirectory)
    }

    /// Where WhisperKit keeps a Whisper model inside its folder.
    nonisolated static func whisperFolder(in folder: URL, variant: String) -> URL {
        folder.appending(path: "models/argmaxinc/whisperkit-coreml/\(variant)", directoryHint: .isDirectory)
    }

    private nonisolated static func size(of folder: URL) async -> Int64 {
        await Task.detached(priority: .utility) { bytes(in: folder) }.value
    }

    private nonisolated static func bytes(in folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys))
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Whether the Mac has a network now, from the path `NWPathMonitor` reports first.
    private nonisolated static func isOnline() async -> Bool {
        let monitor = NWPathMonitor()
        defer { monitor.cancel() }
        let path = await withCheckedContinuation { (done: CheckedContinuation<NWPath, Never>) in
            let once = OSAllocatedUnfairLock(initialState: false)
            monitor.pathUpdateHandler = { path in
                guard once.withLock({ fired in defer { fired = true }; return !fired }) else { return }
                done.resume(returning: path)
            }
            monitor.start(queue: DispatchQueue(label: "studio.overclock.koe.network"))
        }
        return path.status == .satisfied
    }
}

extension ModelID {
    var parakeetVersion: AsrModelVersion? {
        switch self {
        case .parakeetV3: .v3
        case .parakeetV2: .v2
        case .fluidSpeechPro, .whisperTurbo, .apple: nil
        }
    }

    /// WhisperKit's Neural Engine build of large-v3 turbo (OpenAI's 2024-09-30 release), quantized to 632 MB.
    var whisperVariant: String? {
        self == .whisperTurbo ? "openai_whisper-large-v3-v20240930_turbo_632MB" : nil
    }
}
