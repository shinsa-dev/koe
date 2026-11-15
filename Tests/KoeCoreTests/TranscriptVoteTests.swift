import KoeCore
import Testing

struct TranscriptVoteTests {
    /// Words one per second from `at`, so readings of the same speech line up in time.
    private func words(_ text: String, at start: AudioTime = 0, step: AudioTime = 1) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { index, word in
            let begin = start + AudioTime(index) * step
            return TimedWord(String(word), start: begin, end: begin + step * 0.8)
        }
    }

    private func reading(_ model: ModelID, _ text: String, at start: AudioTime = 0) -> TranscriptVote.Reading {
        TranscriptVote.Reading(model: model, words: words(text, at: start))
    }

    private func text(_ words: [TimedWord]) -> String { words.map(\.text).joined(separator: " ") }

    @Test func readingsThatAgreeGiveTheMostTrustedWriting() {
        let combined = TranscriptVote.combine([
            reading(.parakeetV3, "the padding is too tight"),
            reading(.whisperTurbo, "The padding is too tight."),
            reading(.apple, "the padding is too tight"),
        ])
        #expect(text(combined) == "The padding is too tight.")
    }

    @Test func twoReadingsOutvoteTheMostTrusted() {
        let combined = TranscriptVote.combine([
            reading(.whisperTurbo, "Open the settings paste."),
            reading(.parakeetV3, "open the settings page"),
            reading(.apple, "open the settings page"),
        ])
        #expect(text(combined) == "Open the settings page.")
    }

    @Test func aWordEveryReadingHearsDifferentlyGoesToTheMostTrusted() {
        let combined = TranscriptVote.combine([
            reading(.apple, "ask shins about it"),
            reading(.whisperTurbo, "Ask Shinza about it."),
            reading(.parakeetV3, "ask shinz about it"),
        ])
        #expect(text(combined) == "Ask Shinza about it.")
    }

    @Test func withTwoReadingsTheMostTrustedBreaksEveryTie() {
        let combined = TranscriptVote.combine([
            reading(.apple, "one black spring"),
            reading(.parakeetV3, "one blank screen and"),
        ])
        #expect(text(combined) == "one blank screen and")
    }

    @Test func aWordMostReadingsDidntHearIsDropped() {
        let combined = TranscriptVote.combine([
            reading(.whisperTurbo, "It works okay. now"),
            reading(.parakeetV3, "it works now"),
            reading(.apple, "it works now"),
        ].map { reading in
            var timed = reading
            // The made-up word sits in a silence, so only Whisper's reading has a word at 2 s.
            if reading.model != .whisperTurbo { timed.words[2].start = 3; timed.words[2].end = 3.8 }
            return timed
        })
        #expect(text(combined) == "It works. now")
    }

    @Test func aWordMostReadingsAddIsKept() {
        var whisper = reading(.whisperTurbo, "Then the menu opens slowly.")
        whisper.words.remove(at: 3)
        let combined = TranscriptVote.combine([
            whisper,
            reading(.parakeetV3, "then the menu opens slowly"),
            reading(.apple, "then the menu opens slowly"),
        ])
        #expect(text(combined) == "Then the menu opens slowly.")
        #expect(combined[3].start == 3)
    }

    @Test func aWordOnlyOneOtherReadingAddsIsLeftOut() {
        var whisper = reading(.whisperTurbo, "Then the menu opens.")
        whisper.words[3].start = 4
        whisper.words[3].end = 4.8
        let combined = TranscriptVote.combine([
            whisper,
            reading(.parakeetV3, "then the menu um opens"),
            reading(.apple, "then the menu opens"),
        ])
        #expect(text(combined) == "Then the menu opens.")
    }

    @Test func wordsSaidFarApartNeverStandForEachOther() {
        let combined = TranscriptVote.combine([
            reading(.whisperTurbo, "Hello there."),
            reading(.parakeetV3, "general kenobi", at: 10),
        ])
        #expect(text(combined) == "Hello there.")
    }

    @Test func aReadingWithNoWordsHasNoVote() {
        let combined = TranscriptVote.combine([
            reading(.whisperTurbo, "Keep this."),
            TranscriptVote.Reading(model: .parakeetV3, words: []),
            TranscriptVote.Reading(model: .apple, words: []),
        ])
        #expect(text(combined) == "Keep this.")
        #expect(TranscriptVote.combine([]).isEmpty)
    }

    @Test func aSingleReadingIsReturnedAsItIs() {
        let only = reading(.parakeetV3, "so um yeah")
        #expect(TranscriptVote.combine([only]) == only.words)
    }

    @Test func aRepeatedWordIsAddedAsOftenAsMostReadingsSayIt() {
        let combined = TranscriptVote.combine([
            TranscriptVote.Reading(model: .whisperTurbo, words: [TimedWord("Go.", start: 0, end: 0.5)]),
            reading(.parakeetV3, "go go go"),
            TranscriptVote.Reading(model: .apple, words: words("go go", step: 1)),
        ])
        #expect(text(combined) == "Go. go")
    }

    @Test func aDroppedWordLeavesItsFullStopBehind() {
        var whisper = reading(.whisperTurbo, "That is broken there.")
        whisper.words[3].start = 6
        whisper.words[3].end = 6.5
        let combined = TranscriptVote.combine([
            whisper,
            reading(.parakeetV3, "that is broken"),
            reading(.apple, "that is broken"),
        ])
        #expect(text(combined) == "That is broken.")
    }

    @Test func whisperIsTrustedMostAndAppleLeast() {
        #expect(TranscriptVote.trust.first == .whisperTurbo)
        #expect(TranscriptVote.trust.last == .apple)
    }
}
