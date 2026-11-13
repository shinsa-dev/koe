import Foundation
import KoeCore
import WhisperKit

/// OpenAI's Whisper large-v3 turbo through WhisperKit's Core ML build. It finds the language itself and times each
/// word from the decoder's attention.
actor WhisperDecoder: WindowDecoder {
    private let folder: URL
    private let variant: String
    private let gate = SerialGate()
    // Only touched inside `gate`, one call at a time.
    private nonisolated(unsafe) var whisper: WhisperKit?

    init(folder: URL, variant: String) {
        self.folder = folder
        self.variant = variant
    }

    func load() async throws {
        _ = try await gate.run { try await self.loaded() }
    }

    func decode(_ samples: [Float]) async throws -> [TimedToken] {
        try await gate.run {
            let whisper = try await self.loaded()
            let options = DecodingOptions(
                task: .transcribe, detectLanguage: true, skipSpecialTokens: true, wordTimestamps: true,
                chunkingStrategy: .vad
            )
            let results = try await whisper.value.transcribe(audioArray: samples, decodeOptions: options)
            return results.flatMap(\.segments).flatMap { $0.words ?? [] }
                .map { TimedToken($0.word, start: Double($0.start), end: Double($0.end)) }
        }
    }

    private nonisolated func loaded() async throws -> Unchecked<WhisperKit> {
        if let whisper { return Unchecked(whisper) }
        let config = WhisperKitConfig(
            model: variant,
            modelFolder: ModelStore.whisperFolder(in: folder, variant: variant).path,
            tokenizerFolder: folder,
            verbose: false,
            logLevel: .error,
            load: true,
            // Everything is on disk already: loading never goes online.
            download: false
        )
        let whisper = try await WhisperKit(config)
        self.whisper = whisper
        return Unchecked(whisper)
    }
}

extension WindowedTranscriber {
    @MainActor static func whisper(_ id: ModelID, store: ModelStore) -> WindowedTranscriber? {
        guard let variant = id.whisperVariant else { return nil }
        return WindowedTranscriber(decoder: WhisperDecoder(folder: store.folder(for: id), variant: variant))
    }
}
