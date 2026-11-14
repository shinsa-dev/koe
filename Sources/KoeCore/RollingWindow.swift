import Foundation

/// How Koe streams with a model that only reads whole stretches of audio (Parakeet, Whisper): every second or so it
/// decodes again from the first word not yet settled to the newest audio. Words that end well before the newest audio
/// no longer change with more context, so they settle and the next window starts after them; the rest are a guess the
/// next decode replaces.
public struct RollingWindow: Sendable, Equatable {
    /// Where the audio not yet settled begins, in session seconds: the start of the next window.
    public private(set) var start: AudioTime = 0
    /// The guess at the words after `start` from the last decode that heard any.
    public private(set) var pending: [TranscriptRun] = []
    /// The last word that settled, so a later decode that times it again doesn't add it twice.
    public private(set) var lastSettled: TranscriptRun?
    /// How far behind the newest audio a word must end to settle.
    public var settleLag: AudioTime
    /// The longest a window may grow. Past it, words settle with a shorter lag so decoding stays fast; Parakeet reads
    /// up to 15 s in one pass.
    public var maxWindow: AudioTime

    /// Settled audio decoded again ahead of the window, whose words are dropped: a model starting cold on the first
    /// word of a window often misses it.
    public var leftContext: AudioTime
    /// How far back the last decode reaches once the audio has ended. Parakeet often hears nothing at all in a few
    /// seconds of speech followed by silence, which is what the end of a session looks like, but reads a long stretch
    /// reliably; 12 s stays inside its 15 s single pass.
    public var finalContext: AudioTime

    public init(settleLag: AudioTime = 2, maxWindow: AudioTime = 14, leftContext: AudioTime = 1.5,
                finalContext: AudioTime = 12) {
        self.settleLag = settleLag
        self.maxWindow = maxWindow
        self.leftContext = leftContext
        self.finalContext = finalContext
    }

    /// Where the next decode's audio begins: the window's start, less the context ahead of it.
    public var decodeFrom: AudioTime { max(0, start - leftContext) }

    /// Where the last decode's audio begins once the audio has ended at `heard`: at least `finalContext` back.
    public func finalDecodeFrom(heard: AudioTime) -> AudioTime {
        min(decodeFrom, max(0, heard - finalContext))
    }

    /// What a decode of the window up to `heard` means for the transcript: the words that settle, as a final update,
    /// and the guess at the rest, as a volatile one. `words` carry session times. Once the audio has `ended`, every
    /// word settles.
    public mutating func take(_ words: [TranscriptRun], heard: AudioTime, ended: Bool)
        -> (final: TranscriptUpdate?, volatile: TranscriptUpdate) {
        let windowStart = start
        // A word the window's edge cuts belongs to the window holding most of it, and a word that starts in the first
        // half of the last settled one is that word timed again.
        let repeatEdge = lastSettled.map { ($0.start + $0.end) / 2 } ?? -.infinity
        var words = words.filter { ($0.start + $0.end) / 2 >= windowStart && $0.start >= repeatEdge }
        guard !ended else {
            words += Self.unheard(pending, after: words.last)
            start = max(start, heard)
            pending = []
            lastSettled = words.last ?? lastSettled
            let final = TranscriptUpdate(runs: words, isFinal: true, start: windowStart, end: start)
            return (final, TranscriptUpdate(runs: [], isFinal: false, start: start, end: start))
        }
        let long = heard - decodeFrom > maxWindow
        if words.isEmpty, !pending.isEmpty {
            // An empty decode of audio that held words is the model missing them, not silence. Keep the guess and
            // decode the same audio again; only a window grown too long settles the guess as it stands.
            guard long else {
                return (nil, TranscriptUpdate(runs: pending, isFinal: false, start: start, end: max(start, heard)))
            }
            words = pending
        }
        let cutoff = heard - (long ? min(settleLag, 0.5) : settleLag)
        let settledCount = words.prefix { $0.end <= cutoff }.count
        let settled = Array(words.prefix(settledCount))
        let rest = Array(words.dropFirst(settledCount))

        if let last = settled.last {
            // Halfway into the gap before the next word, so neither word's edge falls outside its window.
            start = rest.first.map { max(last.end, ($0.start + last.end) / 2) } ?? last.end
            lastSettled = last
        } else if words.isEmpty {
            // Silence: nothing will be said in audio already this old, so the window needn't keep it.
            start = max(start, cutoff)
        }
        pending = rest
        let final = settled.isEmpty ? nil
            : TranscriptUpdate(runs: settled, isFinal: true, start: windowStart, end: start)
        return (final, TranscriptUpdate(runs: rest, isFinal: false, start: start, end: max(start, heard)))
    }

    /// The end of the guess a final decode that stopped short of it missed: the guess was heard, so it is kept. The
    /// guess picks up after its word that the decode ended on, matched by text and the nearest start as the two time
    /// it differently; with none, after the decode's last word ends.
    static func unheard(_ guess: [TranscriptRun], after last: TranscriptRun?) -> [TranscriptRun] {
        guard let last else { return guess }
        let key = Self.key(last.text)
        let match = guess.indices
            .filter { Self.key(guess[$0].text) == key && abs(guess[$0].start - last.start) < matchReach }
            .min { abs(guess[$0].start - last.start) < abs(guess[$1].start - last.start) }
        if let match { return Array(guess[(match + 1)...]) }
        return guess.filter { $0.start >= last.end }
    }

    /// How far from the decode's last word the guess may have timed the same word.
    private static let matchReach: AudioTime = 1

    private static func key(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
