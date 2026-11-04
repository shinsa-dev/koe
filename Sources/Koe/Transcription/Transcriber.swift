import KoeCore

enum TranscriberEvent: Sendable, Equatable {
    /// The model is loaded and audio is flowing: the session has started.
    case listening
    case update(TranscriptUpdate)
}

/// Turns a source's audio into timed text. Apple's on-device model is the one Koe ships; WhisperKit or Parakeet
/// would plug in here.
protocol Transcriber: Sendable {
    /// Events until the source finishes and every word is settled. Stopping the source ends the stream.
    func transcribe(_ source: any AudioSource) -> AsyncThrowingStream<TranscriberEvent, any Error>
}
