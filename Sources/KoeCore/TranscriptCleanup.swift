import Foundation

/// What Koe takes out of a transcript before it is copied or saved: filler words, a leftover guess that repeats the
/// words that settled before it, and words heard where the audio stayed at the session's noise floor. Each kept word
/// keeps its times, so attachments still land between words.
public enum TranscriptCleanup {
    /// How far over the noise floor a word's loudest moment must reach to count as said aloud, on `AudioLevel`'s
    /// 0...1 scale (0.1 is 5 dB).
    public static let silenceMargin: Float = 0.1

    public static func apply(words: [TimedWord], pending: [TimedWord] = [], levels: LevelTrack? = nil) -> [TimedWord] {
        let all = words + dropRepeat(of: words, in: pending)
        return dropFillers(levels.map { dropSilent(all, levels: $0) } ?? all)
    }

    /// The guess without the words at its start that repeat the last settled ones: a guess timed again after the
    /// final words would otherwise say them twice ("broken there. broken there.").
    static func dropRepeat(of words: [TimedWord], in pending: [TimedWord]) -> [TimedWord] {
        let settled = words.map { key($0.text) }
        let guess = pending.map { key($0.text) }
        for count in stride(from: min(settled.count, guess.count), through: 1, by: -1)
        where Array(settled.suffix(count)) == Array(guess.prefix(count)) {
            return Array(pending.dropFirst(count))
        }
        return pending
    }

    static func dropSilent(_ words: [TimedWord], levels: LevelTrack) -> [TimedWord] {
        let threshold = levels.noiseFloor + silenceMargin
        return words.filter { word in
            guard let peak = levels.peak(from: word.start, to: word.end) else { return true }
            return peak > threshold
        }
    }

    static func dropFillers(_ words: [TimedWord]) -> [TimedWord] {
        var kept: [TimedWord] = []
        var capitalizeNext = false
        for (index, word) in words.enumerated() {
            guard fillers.contains(key(word.text)) else {
                var word = word
                if capitalizeNext { word.text = capitalized(word.text) }
                capitalizeNext = false
                kept.append(word)
                continue
            }
            let startsSentence = index == 0 || words[index - 1].endsSentence
            if startsSentence, word.text.first?.isUppercase == true { capitalizeNext = true }
            // A filler that closed a sentence ("so uh.") hands its full stop to the word before it.
            if word.endsSentence, var previous = kept.last, !previous.endsSentence,
               let mark = word.text.last(where: { ".?!".contains($0) }) {
                previous.text = previous.text.trimmingCharacters(in: .punctuationCharacters) + String(mark)
                kept[kept.count - 1] = previous
            }
        }
        return kept
    }

    private static let fillers: Set<String> = ["um", "umm", "uh", "uhh", "uhm", "erm", "er", "hmm", "mm"]

    private static func key(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func capitalized(_ text: String) -> String {
        guard let first = text.firstIndex(where: \.isLetter) else { return text }
        return text.replacingCharacters(in: first...first, with: text[first].uppercased())
    }
}
