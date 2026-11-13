import Foundation
import KoeCore

enum TranscriberEvent: Sendable, Equatable {
    /// The model is attached and catching up on the audio recorded so far.
    case listening
    case update(TranscriptUpdate)
}

/// Turns a source's audio into timed text, with a time for every word, as `BundleComposer` places attachments at word
/// boundaries. `AppleSpeechTranscriber` streams natively; Parakeet and Whisper are `WindowDecoder`s behind
/// `WindowedTranscriber`. `ActiveTranscriber` picks the one sessions use.
protocol Transcriber: Sendable {
    /// Gets the model ready ahead of the first session, so a session's audio reaches it at once.
    func prewarm() async
    /// Events until the source finishes and every word is settled. The source is already recording; stopping it ends
    /// the stream. A failure ends the stream and leaves the recording running.
    func transcribe(_ source: any AudioSource) -> AsyncThrowingStream<TranscriberEvent, any Error>
    /// The words of a whole recording, as fast as the model reads it: how a recording Koe never finished is recovered.
    func transcribe(file: URL) async throws -> [TimedWord]
}
