import Foundation

/// A stretch of text the transcriber timed as one piece: a word, a word with its punctuation, or part of a word.
public struct TranscriptRun: Sendable, Equatable {
    public var text: String
    public var start: AudioTime
    public var end: AudioTime

    public init(_ text: String, start: AudioTime, end: AudioTime) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// One result from a transcriber. A volatile result is a guess that the next result for the same audio replaces;
/// a final one is settled and never changes.
public struct TranscriptUpdate: Sendable, Equatable {
    public var runs: [TranscriptRun]
    public var isFinal: Bool
    /// The audio the result covers, which can reach past its last word into silence.
    public var start: AudioTime
    public var end: AudioTime

    public init(runs: [TranscriptRun], isFinal: Bool, start: AudioTime, end: AudioTime) {
        self.runs = runs
        self.isFinal = isFinal
        self.start = start
        self.end = end
    }
}

/// What has been said so far: settled words, then the transcriber's current guess at the words after them.
public struct LiveTranscript: Sendable, Equatable {
    public private(set) var words: [TimedWord] = []
    public private(set) var pending: [TimedWord] = []

    public init() {}

    public mutating func apply(_ update: TranscriptUpdate) {
        var incoming: [TimedWord] = []
        for (index, run) in update.runs.enumerated() {
            incoming.appendRun(run.text, start: run.start, end: run.end, joiningPrevious: index > 0)
        }
        guard update.isFinal else {
            pending = incoming
            return
        }
        // A final result's leading punctuation (", and") still belongs to the word before it.
        if let first = incoming.first, first.text.allSatisfy(\.isPunctuation), !words.isEmpty {
            words.appendRun(first.text, start: first.start, end: first.end)
            incoming.removeFirst()
        }
        words.append(contentsOf: incoming)
        pending.removeAll { $0.start < update.end }
    }

    public var isEmpty: Bool { words.isEmpty && pending.isEmpty }

    public var text: String { (words + pending).map(\.text).joined(separator: " ") }

    /// What was said inside `span`, as far as it has been heard.
    public func text(in span: VoiceSpan) -> String {
        (words + pending).filter(span.contains).map(\.text).joined(separator: " ")
    }

    /// The end of the text, at most `limit` characters, cut at a word and led by an ellipsis when cut:
    /// what the pill shows while you talk.
    public func tail(limit: Int) -> String {
        let full = text
        guard full.count > limit, limit > 1 else { return full }
        let kept = full.suffix(limit - 1)
        let fromWord = kept.firstIndex(where: \.isWhitespace).map { kept[kept.index(after: $0)...] } ?? kept
        return "…" + (fromWord.isEmpty ? kept : fromWord)
    }
}
