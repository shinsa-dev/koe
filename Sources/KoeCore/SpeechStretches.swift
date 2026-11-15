import Foundation

/// Where a whole recording is cut for a model that reads at most 30 s at a time (Whisper). WhisperKit's own cuts
/// land mid-sentence and each piece starts with no context, so its punctuation and capitals go after the first.
/// Koe cuts at its own pauses instead, each stretch under `maxLength`, and leaves out stretches with no speech,
/// where Whisper makes words up.
public enum SpeechStretches {
    public struct Stretch: Sendable, Equatable {
        public var start: AudioTime
        public var end: AudioTime

        public init(start: AudioTime, end: AudioTime) {
            self.start = start
            self.end = end
        }
    }

    /// Under Whisper's 30 s window, with room for the decoder's prompt to matter.
    public static let maxLength: AudioTime = 28
    /// A cut never comes sooner than this after the last one, so a stretch has enough audio to read well.
    public static let minLength: AudioTime = 8
    /// How far over the recording's noise floor a 50 ms stretch may be and still count as quiet.
    public static let quietMargin: Float = 0.15
    /// How much of a stretch must be louder than quiet for it to hold speech: a click or a breath doesn't.
    public static let minSpeech: AudioTime = 0.5
    /// Never quiet above this (-30 dB), so a recording with no pause in it still counts as speech.
    public static let quietCeiling: Float = 0.4

    /// The stretches of a recording `levels` tracks, in order, covering all of it but the stretches without speech.
    public static func cut(_ levels: LevelTrack) -> [Stretch] {
        let peaks = levels.peaks
        guard !peaks.isEmpty else { return [] }
        let quiet = min(levels.noiseFloor + quietMargin, quietCeiling)
        let step = LevelTrack.step
        let maxFrames = Int(maxLength / step)
        let minFrames = Int(minLength / step)
        let speechFrames = Int(minSpeech / step)
        var stretches: [Stretch] = []
        var from = 0
        while from < peaks.count {
            let end: Int
            if peaks.count - from <= maxFrames {
                end = peaks.count
            } else {
                end = pause(in: peaks, from: from + minFrames, to: from + maxFrames, quiet: quiet)
            }
            if peaks[from..<end].count(where: { $0 > quiet }) >= speechFrames {
                stretches.append(Stretch(start: Double(from) * step, end: Double(end) * step))
            }
            from = end
        }
        return stretches
    }

    /// The frame to cut at between `low` and `high`: the middle of the longest quiet run, or the quietest frame
    /// when nothing there is quiet. Ties go to the latest, so stretches stay long.
    private static func pause(in peaks: [Float], from low: Int, to high: Int, quiet: Float) -> Int {
        var best: (length: Int, middle: Int)?
        var run = 0
        for index in low..<high {
            run = peaks[index] <= quiet ? run + 1 : 0
            if run > 0, run >= (best?.length ?? 0) {
                best = (run, index - (run - 1) / 2)
            }
        }
        if let best { return best.middle }
        var quietest = low
        for index in low..<high where peaks[index] <= peaks[quietest] {
            quietest = index
        }
        return quietest
    }

    /// How many of the last words read carry into the next stretch's prompt: enough for its punctuation and
    /// capitals, well inside Whisper's 224-token prompt next to your dictionary.
    public static let carriedWords = 40

    /// The text Whisper reads as coming before a stretch: your dictionary's hints, then the end of what the
    /// stretches before it said, so it writes on in the same style.
    public static func prompt(hints: [String], previous: String) -> String {
        let carried = previous.split(whereSeparator: \.isWhitespace).suffix(carriedWords).joined(separator: " ")
        return [hints.joined(separator: ", "), carried].filter { !$0.isEmpty }.joined(separator: ". ")
    }
}
