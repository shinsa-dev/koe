import Foundation

/// A piece of text a model timed: a sub-word token from Parakeet or a word from Whisper. A leading space marks the
/// start of a new word, as both models write them; a token without one continues the word before it.
public struct TimedToken: Sendable, Equatable {
    public var text: String
    public var start: AudioTime
    public var end: AudioTime

    public init(_ text: String, start: AudioTime, end: AudioTime) {
        self.text = text
        self.start = start
        self.end = end
    }
}

public enum TokenRuns {
    /// Joins tokens into one run per word, timed from its first token's start to its last token's end and moved
    /// `offset` seconds later, as a window's times count from the window's start. Each run keeps a leading space so
    /// `LiveTranscript` reads it as a word of its own. Control tokens (`<|en|>`) and empty ones are dropped.
    public static func words(_ tokens: [TimedToken], offset: AudioTime = 0) -> [TranscriptRun] {
        var runs: [TranscriptRun] = []
        for token in tokens {
            let piece = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty, !(piece.hasPrefix("<|") && piece.hasSuffix("|>")) else { continue }
            let start = max(0, token.start) + offset
            let end = max(token.start, token.end) + offset
            let startsWord = token.text.first?.isWhitespace ?? false
            if !startsWord, var last = runs.last {
                last.text += piece
                last.end = max(last.end, end)
                runs[runs.count - 1] = last
            } else {
                runs.append(TranscriptRun(" " + piece, start: start, end: end))
            }
        }
        return runs
    }
}
