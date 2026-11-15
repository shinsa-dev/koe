import Foundation
import KoeCore
import WhisperKit

/// OpenAI's Whisper large-v3 turbo through WhisperKit's Core ML build. It finds the language itself and times each
/// word from the decoder's attention.
actor WhisperDecoder: WindowDecoder {
    private let folder: URL
    private let variant: String
    private let hints: HintWords
    private let gate = SerialGate()
    // Only touched inside `gate`, one call at a time.
    private nonisolated(unsafe) var whisper: WhisperKit?
    private nonisolated(unsafe) var prompt: (words: [String], tokens: [Int])?

    init(folder: URL, variant: String, hints: HintWords = HintWords()) {
        self.folder = folder
        self.variant = variant
        self.hints = hints
    }

    func load() async throws {
        _ = try await gate.run { try await self.loaded() }
    }

    func decode(_ samples: [Float], language: String?) async throws -> DecodedWindow {
        try await gate.run {
            let whisper = try await self.loaded()
            return try await Self.read(samples, whisper: whisper.value, language: language,
                                       prompt: self.promptTokens(whisper.value), chunking: .vad)
        }
    }

    /// A whole recording, cut at its own pauses into stretches Whisper reads in one window each, in the language the
    /// first settled. WhisperKit's own cuts start each piece mid-sentence, so past the first 30 s the punctuation and
    /// capitals went. A stretch is read without a prompt: with one, WhisperKit times every word near the window's end.
    func decodeWhole(_ samples: [Float]) async throws -> DecodedWindow {
        try await gate.run {
            let whisper = try await self.loaded()
            let rate = WindowedTranscriber.rate
            let stretches = SpeechStretches.cut(LevelTrack(samples: samples, rate: rate))
            var tokens: [TimedToken] = []
            var language = LanguageLock()
            for stretch in stretches {
                try Task.checkCancellation()
                let from = min(samples.count, Int(stretch.start * rate))
                let until = min(samples.count, Int(stretch.end * rate))
                guard from < until else { continue }
                let read = try await Self.read(Array(samples[from..<until]), whisper: whisper.value,
                                               language: language.language, prompt: nil, chunking: nil)
                language.observe(read.language, heard: stretch.end - stretch.start)
                tokens += read.tokens.map {
                    TimedToken($0.text, start: $0.start + stretch.start, end: $0.end + stretch.start)
                }
            }
            return DecodedWindow(tokens: tokens, language: language.language)
        }
    }

    private static func read(
        _ samples: [Float], whisper: WhisperKit, language: String?, prompt: [Int]?, chunking: ChunkingStrategy?
    ) async throws -> DecodedWindow {
        let options = DecodingOptions(
            task: .transcribe, language: language, detectLanguage: language == nil, skipSpecialTokens: true,
            wordTimestamps: true, promptTokens: prompt, chunkingStrategy: chunking
        )
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        let tokens = results.flatMap(\.segments).flatMap { $0.words ?? [] }
            .map { TimedToken($0.word, start: Double($0.start), end: Double($0.end)) }
        return DecodedWindow(tokens: tokens, language: language == nil ? results.first?.language : nil)
    }

    /// Compiles the model for this Mac's Neural Engine and lets it go again, so the next load takes seconds.
    static func prepare(folder: URL, variant: String) async throws {
        _ = try await WhisperKit(config(folder: folder, variant: variant, prewarm: true))
    }

    private nonisolated func loaded() async throws -> Unchecked<WhisperKit> {
        if let whisper { return Unchecked(whisper) }
        let whisper = try await WhisperKit(Self.config(folder: folder, variant: variant, prewarm: false))
        self.whisper = whisper
        return Unchecked(whisper)
    }

    /// Your dictionary as Whisper's prompt, the text it reads as coming before the audio: a list of names makes it
    /// spell them that way. Encoded again only when the words change.
    private nonisolated func promptTokens(_ whisper: WhisperKit) -> [Int]? {
        let words = hints.words
        guard !words.isEmpty, let tokenizer = whisper.tokenizer else { return nil }
        if let prompt, prompt.words == words { return prompt.tokens.isEmpty ? nil : prompt.tokens }
        let tokens = encode(words.joined(separator: ", "), whisper) ?? []
        prompt = (words, tokens)
        return tokens.isEmpty ? nil : tokens
    }

    private nonisolated func encode(_ text: String, _ whisper: WhisperKit) -> [Int]? {
        guard !text.isEmpty, let tokenizer = whisper.tokenizer else { return nil }
        let tokens = tokenizer.encode(text: " " + text).filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    /// `prewarm` loads each model one at a time and unloads it, which compiles them without holding them in memory.
    private static func config(folder: URL, variant: String, prewarm: Bool) -> WhisperKitConfig {
        WhisperKitConfig(
            model: variant,
            modelFolder: ModelStore.whisperFolder(in: folder, variant: variant).path,
            tokenizerFolder: folder,
            verbose: false,
            logLevel: .error,
            prewarm: prewarm,
            load: !prewarm,
            // Everything is on disk already: loading never goes online.
            download: false
        )
    }
}

extension WindowedTranscriber {
    @MainActor static func whisper(_ id: ModelID, store: ModelStore, hints: HintWords) -> WindowedTranscriber? {
        guard let variant = id.whisperVariant else { return nil }
        return WindowedTranscriber(decoder: WhisperDecoder(folder: store.folder(for: id), variant: variant, hints: hints))
    }
}
