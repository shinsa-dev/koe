import CoreML
import FluidAudio
import Foundation
import KoeCore

/// NVIDIA's Parakeet TDT 0.6B through FluidAudio's Core ML port, on the Neural Engine, or FluidVoice's fine-tune of it
/// in the same files. It times every sub-word token, which `TokenRuns` joins into words.
actor ParakeetDecoder: WindowDecoder {
    /// Where the Core ML files come from, which decides who may touch the folder.
    enum Files {
        /// FluidAudio's own download, which it fetches again if a load fails.
        case fluidAudio(AsrModelVersion)
        /// A snapshot Koe fetched. Loaded here, as FluidAudio's loader would delete it and fetch NVIDIA's v3 instead.
        case snapshot
    }

    /// Parakeet reads at least one second; a shorter window is padded with silence.
    private static let minimumSamples = 16_000

    private let folder: URL
    private let files: Files
    private let gate = SerialGate()
    // Only touched inside `gate`, one call at a time, which is what FluidAudio's non-Sendable manager needs.
    private nonisolated(unsafe) var manager: AsrManager?

    init(folder: URL, files: Files) {
        self.folder = folder
        self.files = files
    }

    func load() async throws {
        _ = try await gate.run { try await self.loaded() }
    }

    func decode(_ samples: [Float], language: String?) async throws -> DecodedWindow {
        try await gate.run {
            let manager = try await self.loaded()
            let length = Double(samples.count) / WindowedTranscriber.rate
            let padded = samples.count < Self.minimumSamples
                ? samples + [Float](repeating: 0, count: Self.minimumSamples - samples.count) : samples
            let result = try await manager.value.transcribe(padded, source: .microphone)
            let tokens = (result.tokenTimings ?? [])
                .filter { $0.startTime < length }
                .map { TimedToken($0.token, start: $0.startTime, end: min($0.endTime, length)) }
            return DecodedWindow(tokens: tokens)
        }
    }

    private nonisolated func loaded() async throws -> Unchecked<AsrManager> {
        if let manager { return Unchecked(manager) }
        let models = switch files {
        case .fluidAudio(let version): try await AsrModels.load(from: folder, version: version)
        case .snapshot: try await Self.models(in: folder)
        }
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        self.manager = manager
        return Unchecked(manager)
    }
}

extension ParakeetDecoder {
    /// Loads a snapshot's four Core ML models and vocabulary as FluidAudio would, without its fallback download. Its
    /// files match Parakeet v3's in names, inputs, outputs and vocabulary, so it decodes as v3.
    nonisolated static func models(in folder: URL) async throws -> AsrModels {
        let config = AsrModels.defaultConfiguration()
        // FluidAudio runs the preprocessor on the CPU, where all of its operations land anyway.
        let cpu = MLModelConfiguration()
        cpu.computeUnits = .cpuOnly
        func load(_ name: String, _ config: MLModelConfiguration) async throws -> MLModel {
            try await MLModel.load(contentsOf: folder.appending(path: name, directoryHint: .isDirectory),
                                   configuration: config)
        }
        let names = ModelNames.ASR.self
        let vocabulary = try JSONDecoder().decode(
            [String: String].self, from: Data(contentsOf: folder.appending(path: names.vocabularyFile)))
        return try await AsrModels(
            encoder: load(names.encoderFile, config), preprocessor: load(names.preprocessorFile, cpu),
            decoder: load(names.decoderFile, config), joint: load(names.jointFile, config), configuration: config,
            vocabulary: Dictionary(uniqueKeysWithValues: vocabulary.compactMap { key, piece in
                Int(key).map { ($0, piece) }
            }),
            version: .v3)
    }
}

/// Carries a value the gate already keeps to one user at a time.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

extension WindowedTranscriber {
    @MainActor static func parakeet(_ id: ModelID, store: ModelStore) -> WindowedTranscriber? {
        if let snapshot = id.snapshot {
            let folder = ModelStore.snapshotFolder(in: store.folder(for: id), snapshot: snapshot)
            return WindowedTranscriber(decoder: ParakeetDecoder(folder: folder, files: .snapshot))
        }
        guard let version = id.parakeetVersion else { return nil }
        let folder = ModelStore.parakeetFolder(in: store.folder(for: id), version: version)
        return WindowedTranscriber(decoder: ParakeetDecoder(folder: folder, files: .fluidAudio(version)))
    }
}
