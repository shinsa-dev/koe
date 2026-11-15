import Foundation

/// How far one transcript is from another, in words: the fewest words swapped, added or dropped to turn one into the
/// other, over the reference's word count. Case and punctuation don't count, as `TailScore` reads words.
public struct WordErrorRate: Sendable, Equatable {
    /// Words swapped, added or dropped.
    public var errors: Int
    /// Words in the reference.
    public var words: Int

    public init(errors: Int = 0, words: Int = 0) {
        self.errors = errors
        self.words = words
    }

    /// Errors over reference words; 0 for two empty transcripts, and 1 or more when only the reference is empty.
    public var rate: Double {
        words == 0 ? (errors == 0 ? 0 : 1) : Double(errors) / Double(words)
    }

    /// One line, as "12.5% (4 of 32 words)".
    public var summary: String {
        String(format: "%.1f%%", rate * 100) + " (\(errors) of \(words) words)"
    }

    /// `hypothesis` scored against `reference`.
    public static func compare(_ hypothesis: String, to reference: String) -> WordErrorRate {
        let said = TailScore.words(hypothesis)
        let truth = TailScore.words(reference)
        return WordErrorRate(errors: distance(said, truth), words: truth.count)
    }

    /// Scores over several recordings add up word by word, so a long recording weighs more than a short one.
    public static func + (lhs: WordErrorRate, rhs: WordErrorRate) -> WordErrorRate {
        WordErrorRate(errors: lhs.errors + rhs.errors, words: lhs.words + rhs.words)
    }

    public static func += (lhs: inout WordErrorRate, rhs: WordErrorRate) { lhs = lhs + rhs }

    static func distance(_ lhs: [String], _ rhs: [String]) -> Int {
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }
        var previous = Array(0...rhs.count)
        var current = previous
        for (row, word) in lhs.enumerated() {
            current[0] = row + 1
            for column in 1...rhs.count {
                let swap = previous[column - 1] + (word == rhs[column - 1] ? 0 : 1)
                current[column] = min(swap, previous[column] + 1, current[column - 1] + 1)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
