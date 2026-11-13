import FluidAudio
import Foundation
import KoeCore

/// NVIDIA's Parakeet TDT 0.6B through FluidAudio's Core ML port, on the Neural Engine. It times every sub-word token,
/// which `TokenRuns` joins into words.
actor ParakeetDecoder: WindowDecoder {
    /// Parakeet reads at least one second; a shorter window is padded with silence.
    private static let minimumSamples = 16_000

    private let folder: URL
    private let version: AsrModelVersion
    private let gate = SerialGate()
    // Only touched inside `gate`, one call at a time, which is what FluidAudio's non-Sendable manager needs.
    private nonisolated(unsafe) var manager: AsrManager?

    init(folder: URL, version: AsrModelVersion) {
        self.folder = folder
        self.version = version
    }

    func load() async throws {
        _ = try await gate.run { try await self.loaded() }
    }

    func decode(_ samples: [Float]) async throws -> [TimedToken] {
        try await gate.run {
            let manager = try await self.loaded()
            let length = Double(samples.count) / WindowedTranscriber.rate
            let padded = samples.count < Self.minimumSamples
                ? samples + [Float](repeating: 0, count: Self.minimumSamples - samples.count) : samples
            let result = try await manager.value.transcribe(padded, source: .microphone)
            return (result.tokenTimings ?? [])
                .filter { $0.startTime < length }
                .map { TimedToken($0.token, start: $0.startTime, end: min($0.endTime, length)) }
        }
    }

    private nonisolated func loaded() async throws -> Unchecked<AsrManager> {
        if let manager { return Unchecked(manager) }
        let models = try await AsrModels.load(from: folder, version: version)
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: models)
        self.manager = manager
        return Unchecked(manager)
    }
}

/// Carries a value the gate already keeps to one user at a time.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

extension WindowedTranscriber {
    @MainActor static func parakeet(_ id: ModelID, store: ModelStore) -> WindowedTranscriber? {
        guard let version = id.parakeetVersion else { return nil }
        let folder = ModelStore.parakeetFolder(in: store.folder(for: id), version: version)
        return WindowedTranscriber(decoder: ParakeetDecoder(folder: folder, version: version))
    }
}
