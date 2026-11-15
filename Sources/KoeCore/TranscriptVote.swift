import Foundation

/// How Koe combines several models' transcripts of one recording into one. The most trusted model's words are the
/// backbone; every other reading is lined up against it by text and time. Each word then goes to a vote: a word most
/// readings agree on is kept, a word most readings didn't hear is dropped, and a word most readings add between two
/// backbone words is added. A tie goes to the most trusted reading among those tied.
public enum TranscriptVote {
    /// One model's words for the whole recording.
    public struct Reading: Sendable, Equatable {
        public var model: ModelID
        public var words: [TimedWord]

        public init(model: ModelID, words: [TimedWord]) {
            self.model = model
            self.words = words
        }
    }

    /// Most trusted first: Whisper writes the cleanest sentences, Parakeet hears the most words right, and Apple's
    /// model makes up words in silence.
    public static let trust: [ModelID] = [.whisperTurbo, .parakeetV3, .parakeetV2, .apple]

    /// How far apart two words may be said and still be the same word: Apple's model times words up to a second off
    /// when it shares one range among them.
    public static let reach: AudioTime = 1.5

    /// The combined words. A reading with no words is a model that heard nothing (a model that failed gives no
    /// reading): when most readings heard nothing, nothing was said, as a model alone in hearing words in a short
    /// recording is making them up. Otherwise it has no vote.
    public static func combine(_ readings: [Reading]) -> [TimedWord] {
        let silent = readings.count { $0.words.isEmpty }
        guard silent * 2 <= readings.count else { return [] }
        let ranked = readings.filter { !$0.words.isEmpty }
            .sorted { rank($0.model) < rank($1.model) }
        guard let backbone = ranked.first else { return [] }
        guard ranked.count > 1 else { return backbone.words }
        let others = ranked.dropFirst().map { align($0.words, to: backbone.words) }
        let total = ranked.count
        var result: [TimedWord] = []
        for gap in 0...backbone.words.count {
            result += inserted(at: gap, from: others, total: total)
            guard gap < backbone.words.count else { break }
            let word = backbone.words[gap]
            let matches = others.map { $0.matches[gap] }
            if let chosen = choose(word, matches: matches, total: total) {
                result.append(chosen)
            } else {
                carryPunctuation(of: word, into: &result)
            }
        }
        return result
    }

    static func rank(_ model: ModelID) -> Int { trust.firstIndex(of: model) ?? trust.count }

    // MARK: Voting

    /// The backbone word as the vote leaves it: kept, swapped for the word most readings heard there, or dropped (nil).
    static func choose(_ word: TimedWord, matches: [TimedWord?], total: Int) -> TimedWord? {
        // Readings in trust order: the backbone, then the others. A gap is a vote for no word.
        let votes = [key(word.text)] + matches.map { $0.map { key($0.text) } }
        var counts: [String?: Int] = [:]
        for vote in votes { counts[vote, default: 0] += 1 }
        let best = counts.values.max() ?? 0
        guard let winner = votes.first(where: { counts[$0] == best }), let winner else { return nil }
        if winner == votes[0] { return word }
        guard let other = matches.compactMap({ $0 }).first(where: { key($0.text) == winner }) else { return word }
        return TimedWord(restyle(other.text, like: word.text), start: word.start, end: word.end)
    }

    /// The words other readings put between backbone words `gap - 1` and `gap` that most of all readings heard there.
    /// The backbone votes against each, so with two readings nothing is ever added.
    static func inserted(at gap: Int, from others: [Alignment], total: Int) -> [TimedWord] {
        let extras = others.map { $0.extras[gap] ?? [] }
        var added: [TimedWord] = []
        var taken: [String: Int] = [:]
        for words in extras {
            var seen: [String: Int] = [:]
            for word in words {
                let wordKey = key(word.text)
                let occurrence = seen[wordKey, default: 0]
                seen[wordKey] = occurrence + 1
                guard taken[wordKey, default: 0] <= occurrence else { continue }
                let votes = extras.filter { $0.count(where: { key($0.text) == wordKey }) > occurrence }.count
                guard votes * 2 > total else { continue }
                taken[wordKey] = occurrence + 1
                added.append(word)
            }
        }
        return added.sorted { $0.start < $1.start }
    }

    /// A dropped word that closed a sentence leaves its full stop on the word before it.
    static func carryPunctuation(of dropped: TimedWord, into result: inout [TimedWord]) {
        let mark = trailingPunctuation(dropped.text)
        guard !mark.isEmpty, let last = result.last, trailingPunctuation(last.text).isEmpty else { return }
        result[result.count - 1].text = last.text + mark
    }

    /// `text` with the backbone word's capital and closing punctuation when it has none of its own, as the backbone
    /// model writes the sentences.
    static func restyle(_ text: String, like backbone: String) -> String {
        var styled = text
        if backbone.first?.isUppercase == true, let first = styled.first, first.isLowercase {
            styled = first.uppercased() + styled.dropFirst()
        }
        let mark = trailingPunctuation(backbone)
        if !mark.isEmpty, trailingPunctuation(styled).isEmpty { styled += mark }
        return styled
    }

    static func trailingPunctuation(_ text: String) -> String {
        String(text.reversed().prefix { $0.isPunctuation }.reversed())
    }

    /// What two readings must share to be the same word: its letters and digits in lower case.
    static func key(_ text: String) -> String {
        let letters = String(text.lowercased().filter { $0.isLetter || $0.isNumber })
        return letters.isEmpty ? text : letters
    }

    // MARK: Alignment

    /// One reading lined up against the backbone: the word it heard at each backbone word (nil where it heard none),
    /// and the words it heard between backbone words, keyed by the backbone word they come before (`count` for after
    /// the last).
    struct Alignment: Equatable {
        var matches: [TimedWord?]
        var extras: [Int: [TimedWord]]
    }

    /// The cheapest way to turn `backbone` into `words`, where a word may stand for a backbone word only if they were
    /// said within `reach` of each other. A word that matches costs nothing, one that differs 1, and a word only one
    /// side has 1; a pair said further apart costs a little more, so a repeated word pairs with the one said with it.
    static func align(_ words: [TimedWord], to backbone: [TimedWord]) -> Alignment {
        let rows = backbone.count, columns = words.count
        var cost = [[Double]](repeating: [Double](repeating: 0, count: columns + 1), count: rows + 1)
        for row in 0...rows { cost[row][0] = Double(row) }
        for column in 0...columns { cost[0][column] = Double(column) }
        for row in stride(from: 1, through: rows, by: 1) {
            for column in stride(from: 1, through: columns, by: 1) {
                let pair = pairCost(backbone[row - 1], words[column - 1])
                cost[row][column] = min(cost[row - 1][column] + 1, cost[row][column - 1] + 1,
                                        cost[row - 1][column - 1] + pair)
            }
        }
        return trace(cost, words: words, backbone: backbone)
    }

    /// Walks the table back from its end, preferring a pair over a gap at equal cost.
    static func trace(_ cost: [[Double]], words: [TimedWord], backbone: [TimedWord]) -> Alignment {
        var alignment = Alignment(matches: Array(repeating: nil, count: backbone.count), extras: [:])
        var row = backbone.count, column = words.count
        while row > 0 || column > 0 {
            if row > 0, column > 0,
               cost[row][column] == cost[row - 1][column - 1] + pairCost(backbone[row - 1], words[column - 1]) {
                alignment.matches[row - 1] = words[column - 1]
                row -= 1
                column -= 1
            } else if column > 0, row == 0 || cost[row][column] == cost[row][column - 1] + 1 {
                alignment.extras[row, default: []].insert(words[column - 1], at: 0)
                column -= 1
            } else {
                row -= 1
            }
        }
        return alignment
    }

    /// 0 for the same word, 1 for a different word said at the same time, and too much to pair for words said apart.
    static func pairCost(_ backbone: TimedWord, _ word: TimedWord) -> Double {
        let apart = max(0, word.start - backbone.end, backbone.start - word.end)
        guard apart <= reach else { return 3 }
        return (key(backbone.text) == key(word.text) ? 0 : 1) + apart * 0.01
    }
}
