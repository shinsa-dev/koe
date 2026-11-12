import FluidAudio
import Foundation
import KoeCore
import Observation
import os
import WhisperKit

/// The downloaded speech models, one folder each in `~/Library/Application Support/Koe/Models`. Downloads come from
/// Hugging Face and nothing else goes online: audio and text never leave the Mac.
@MainActor @Observable
final class ModelStore {
    @ObservationIgnored private static let log = Logger(subsystem: "studio.shinsa.koe", category: "models")
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
                try Data().write(to: folder.appending(path: Self.marker))
                outcome = .installed
            } catch {
                if Task.isCancelled || error is CancellationError {
                    outcome = .notInstalled
                } else {
                    Self.log.error("Download of \(id.rawValue, privacy: .public) failed: \(error, privacy: .public)")
                    outcome = .failed(Self.message(for: error))
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

    /// Stops a download and throws away what it fetched.
    func cancel(_ id: ModelID) {
        downloads[id]?.cancel()
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
            guard let version = model.id.parakeetVersion else { return }
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

    /// Where FluidAudio keeps a Parakeet model inside its folder.
    nonisolated static func parakeetFolder(in folder: URL, version: AsrModelVersion) -> URL {
        folder.appending(path: version == .v2 ? Repo.parakeetV2.folderName : Repo.parakeet.folderName,
                         directoryHint: .isDirectory)
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

    private nonisolated static func message(for error: any Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "The download needs an internet connection. Try again once you're online."
            case .timedOut:
                return "Hugging Face took too long to answer. Try again in a moment."
            default:
                break
            }
        }
        return "The download stopped: \(error.localizedDescription)"
    }
}

extension ModelID {
    var parakeetVersion: AsrModelVersion? {
        switch self {
        case .parakeetV3: .v3
        case .parakeetV2: .v2
        case .whisperTurbo, .apple: nil
        }
    }

    /// WhisperKit's Neural Engine build of large-v3 turbo (OpenAI's 2024-09-30 release), quantized to 632 MB.
    var whisperVariant: String? {
        self == .whisperTurbo ? "openai_whisper-large-v3-v20240930_turbo_632MB" : nil
    }
}
