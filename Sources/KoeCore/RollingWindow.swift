import Foundation

/// How Koe streams with a model that only reads whole stretches of audio (Parakeet, Whisper): every second or so it
/// decodes again from the first word not yet settled to the newest audio. Words that end well before the newest audio
/// no longer change with more context, so they settle and the next window starts after them; the rest are a guess the
/// next decode replaces.
public struct RollingWindow: Sendable, Equatable {
    /// Where the audio not yet settled begins, in session seconds: the start of the next window.
    public private(set) var start: AudioTime = 0
    /// How far behind the newest audio a word must end to settle.
    public var settleLag: AudioTime
    /// The longest a window may grow. Past it, words settle with a shorter lag so decoding stays fast; Parakeet reads
    /// up to 15 s in one pass.
    public var maxWindow: AudioTime

    /// Settled audio decoded again ahead of the window, whose words are dropped: a model starting cold on the first
    /// word of a window often misses it.
    public var leftContext: AudioTime

    public init(settleLag: AudioTime = 2, maxWindow: AudioTime = 14, leftContext: AudioTime = 1.5) {
        self.settleLag = settleLag
        self.maxWindow = maxWindow
        self.leftContext = leftContext
    }

    /// Where the next decode's audio begins: the window's start, less the context ahead of it.
    public var decodeFrom: AudioTime { max(0, start - leftContext) }

    /// What a decode of the window up to `heard` means for the transcript: the words that settle, as a final update,
    /// and the guess at the rest, as a volatile one. `words` carry session times. Once the audio has `ended`, every
    /// word settles.
    public mutating func take(_ words: [TranscriptRun], heard: AudioTime, ended: Bool)
        -> (final: TranscriptUpdate?, volatile: TranscriptUpdate) {
        let windowStart = start
        // A word the window's edge cuts belongs to the window holding most of it.
        let words = words.filter { ($0.start + $0.end) / 2 >= windowStart }
        guard !ended else {
            start = max(start, heard)
            let final = TranscriptUpdate(runs: words, isFinal: true, start: windowStart, end: start)
            return (final, TranscriptUpdate(runs: [], isFinal: false, start: start, end: start))
        }
        let lag = heard - decodeFrom > maxWindow ? min(settleLag, 0.5) : settleLag
        let cutoff = heard - lag
        let settledCount = words.prefix { $0.end <= cutoff }.count
        let settled = Array(words.prefix(settledCount))
        let rest = Array(words.dropFirst(settledCount))

        if let last = settled.last {
            // Halfway into the gap before the next word, so neither word's edge falls outside its window.
            start = rest.first.map { max(last.end, ($0.start + last.end) / 2) } ?? last.end
        } else if words.isEmpty {
            // Silence: nothing will be said in audio already this old, so the window needn't keep it.
            start = max(start, cutoff)
        }
        let final = settled.isEmpty ? nil
            : TranscriptUpdate(runs: settled, isFinal: true, start: windowStart, end: start)
        return (final, TranscriptUpdate(runs: rest, isFinal: false, start: start, end: max(start, heard)))
    }
}
