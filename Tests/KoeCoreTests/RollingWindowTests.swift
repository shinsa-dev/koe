import KoeCore
import Testing

struct TokenRunsTests {
    @Test func subWordTokensJoinIntoTimedWords() {
        let tokens = [
            TimedToken(" Hel", start: 0.2, end: 0.4), TimedToken("lo", start: 0.4, end: 0.6),
            TimedToken(",", start: 0.6, end: 0.64), TimedToken(" world", start: 0.8, end: 1.2),
        ]
        #expect(TokenRuns.words(tokens) == [
            TranscriptRun(" Hello,", start: 0.2, end: 0.64), TranscriptRun(" world", start: 0.8, end: 1.2),
        ])
    }

    @Test func timesMoveByTheWindowStart() {
        let runs = TokenRuns.words([TimedToken(" Hi", start: 0.5, end: 0.9)], offset: 10)
        #expect(runs == [TranscriptRun(" Hi", start: 10.5, end: 10.9)])
    }

    @Test func controlAndEmptyTokensAreDropped() {
        let tokens = [
            TimedToken("<|en|>", start: 0, end: 0), TimedToken(" ", start: 0, end: 0.1),
            TimedToken(" Yes", start: 0.1, end: 0.4),
        ]
        #expect(TokenRuns.words(tokens).map(\.text) == [" Yes"])
    }

    @Test func aFirstTokenWithoutASpaceStillStartsAWord() {
        #expect(TokenRuns.words([TimedToken("Okay", start: 0, end: 0.3)]).map(\.text) == [" Okay"])
    }

    @Test func runsFeedTheLiveTranscriptAsSeparateWords() {
        var transcript = LiveTranscript()
        let runs = TokenRuns.words([
            TimedToken(" Don", start: 0, end: 0.2), TimedToken("'t", start: 0.2, end: 0.3),
            TimedToken(" go", start: 0.4, end: 0.6), TimedToken(".", start: 0.6, end: 0.62),
        ])
        transcript.apply(TranscriptUpdate(runs: runs, isFinal: true, start: 0, end: 1))
        #expect(transcript.words == [TimedWord("Don't", start: 0, end: 0.3), TimedWord("go.", start: 0.4, end: 0.62)])
    }
}

struct RollingWindowTests {
    private func word(_ text: String, _ start: Double, _ end: Double) -> TranscriptRun {
        TranscriptRun(" " + text, start: start, end: end)
    }

    @Test func onlyWordsEndingWellBeforeTheNewestAudioSettle() {
        var window = RollingWindow()
        let words = [word("one", 0.2, 0.5), word("two", 1.0, 1.4), word("three", 2.5, 2.9)]
        let (final, volatile) = window.take(words, heard: 3.6, ended: false)
        #expect(final?.runs == [words[0], words[1]])
        #expect(final?.isFinal == true)
        #expect(volatile.runs == [words[2]])
        #expect(!volatile.isFinal)
        // Halfway between "two" ending and "three" starting.
        #expect(window.start == 1.95)
        #expect(final?.end == 1.95)
        #expect(volatile.start == 1.95 && volatile.end == 3.6)
    }

    @Test func nothingSettlesWhileEveryWordIsRecent() {
        var window = RollingWindow()
        let (final, volatile) = window.take([word("hello", 0.3, 0.8)], heard: 2.0, ended: false)
        #expect(final == nil)
        #expect(volatile.runs.map(\.text) == [" hello"])
        #expect(window.start == 0)
    }

    @Test func silenceMovesTheWindowOn() {
        var window = RollingWindow()
        let (final, volatile) = window.take([], heard: 5, ended: false)
        #expect(final == nil)
        #expect(volatile.runs.isEmpty)
        #expect(window.start == 3)
    }

    @Test func theLastSettledWordStartsTheNextWindowWhenNothingFollows() {
        var window = RollingWindow()
        _ = window.take([word("done", 0.5, 1.0)], heard: 4, ended: false)
        #expect(window.start == 1.0)
    }

    @Test func aLongWindowSettlesWithAShortLag() {
        var window = RollingWindow(settleLag: 2, maxWindow: 14)
        let words = [word("a", 1, 2), word("b", 13.0, 14.2), word("c", 14.3, 14.6)]
        let (final, _) = window.take(words, heard: 15, ended: false)
        #expect(final?.runs == [words[0], words[1]])
    }

    @Test func theEndSettlesEverything() {
        var window = RollingWindow()
        let words = [word("last", 0.2, 0.6), word("words", 0.7, 1.1)]
        let (final, volatile) = window.take(words, heard: 1.3, ended: true)
        #expect(final?.runs == words)
        #expect(final?.end == 1.3)
        #expect(volatile.runs.isEmpty)
        #expect(window.start == 1.3)
    }

    @Test func wordsBeforeTheWindowAreIgnored() {
        var window = RollingWindow()
        _ = window.take([word("one", 0.2, 0.5)], heard: 3, ended: false)
        let (final, volatile) = window.take([word("one", 0.2, 0.4), word("two", 0.6, 0.9)], heard: 3.2, ended: false)
        #expect(final?.runs == [word("two", 0.6, 0.9)])
        #expect(volatile.runs.isEmpty)
    }

    @Test func theNextDecodeStartsWithSettledAudioAsContext() {
        var window = RollingWindow()
        #expect(window.decodeFrom == 0)
        // "gray" starts the moment "not" ends, so the window's edge sits right on it.
        _ = window.take([word("blue", 1.9, 2.3), word("not", 2.3, 2.6), word("gray", 2.6, 3.1)], heard: 4.9, ended: false)
        #expect(window.start == 2.6)
        #expect(window.decodeFrom == 2.6 - 1.5)
        // Decoded with that context, the model hears "gray" again; the context's own words are dropped.
        let (final, volatile) = window.take(
            [word("not", 2.3, 2.6), word("gray", 2.6, 3.1), word("then", 3.1, 3.4)], heard: 5.6, ended: true
        )
        #expect(final?.runs.map(\.text) == [" gray", " then"])
        #expect(volatile.runs.isEmpty)
    }

    @Test func settledAndGuessedWordsBuildTheLiveTranscript() {
        var window = RollingWindow()
        var transcript = LiveTranscript()
        func apply(_ result: (final: TranscriptUpdate?, volatile: TranscriptUpdate)) {
            if let final = result.final { transcript.apply(final) }
            transcript.apply(result.volatile)
        }
        apply(window.take([word("Hello", 0.2, 0.6)], heard: 1, ended: false))
        #expect(transcript.words.isEmpty)
        #expect(transcript.text == "Hello")
        apply(window.take([word("Hello", 0.2, 0.6), word("there", 1.0, 1.3)], heard: 3, ended: false))
        #expect(transcript.words.map(\.text) == ["Hello"])
        #expect(transcript.text == "Hello there")
        apply(window.take([word("there.", 1.0, 1.4)], heard: 3.5, ended: true))
        #expect(transcript.words.map(\.text) == ["Hello", "there."])
        #expect(transcript.pending.isEmpty)
    }
}
