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
        #expect(text(combined) == "One blank screen and")
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
        #expect(text(combined) == "It works. Now")
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
        #expect(text(combined) == "Hello there. General kenobi")
        #expect(combined[2].start == 10)
    }

    @Test func aStretchTheMostTrustedSkippedKeepsTheOtherReadingsWords() {
        let said: [(String, AudioTime)] = [("open", 0), ("the", 3), ("card.", 5), ("then", 6.4), ("it", 9), ("closes", 10)]
        let parakeet = said.map { TimedWord($0.0, start: $0.1, end: $0.1 + 0.8) }
        let whisper = [TimedWord("Open", start: 0, end: 0.8), TimedWord("it", start: 9, end: 9.8),
                       TimedWord("closes.", start: 10, end: 10.8)]
        let combined = TranscriptVote.combine([
            TranscriptVote.Reading(model: .whisperTurbo, words: whisper),
            TranscriptVote.Reading(model: .parakeetV3, words: parakeet),
        ])
        #expect(text(combined) == "Open the card. Then it closes.")
    }

    @Test func aWordTheMostTrustedHeardAroundIsntAddedByOneOtherReading() {
        let combined = TranscriptVote.combine([
            reading(.whisperTurbo, "Then the menu opens."),
            TranscriptVote.Reading(model: .parakeetV3, words: words("then the menu opens") + [TimedWord("um", start: 3.9, end: 4.1)]),
        ])
        #expect(text(combined) == "Then the menu opens.")
    }

    @Test func punctuationTheMostTrustedLeftOutComesFromTheOthers() {
        let combined = TranscriptVote.combine([
            reading(.whisperTurbo, "make them instant you can save stuff async like this"),
            reading(.parakeetV3, "Make them instant. You can save stuff async, like this."),
            reading(.apple, "Make them instant. You can save stuff async like this."),
        ])
        #expect(text(combined) == "Make them instant. You can save stuff async like this.")
        #expect(text(TranscriptVote.combine([
            reading(.whisperTurbo, "it works now"),
            reading(.parakeetV3, "it works now"),
            reading(.apple, "It works. Now"),
        ])) == "It works now")
        let runOn = (1...30).map { "w\($0)" }.joined(separator: " ")
        let appleRunOn = (1...30).map { $0 == 10 ? "w10." : "w\($0)" }.joined(separator: " ")
        #expect(text(TranscriptVote.combine([
            reading(.whisperTurbo, runOn),
            reading(.parakeetV3, runOn),
            reading(.apple, appleRunOn),
        ])) == "W1 w2 w3 w4 w5 w6 w7 w8 w9 w10. W11 w12 w13 w14 w15 w16 w17 w18 w19 w20 w21 w22 w23 w24 w25 w26 w27 w28 w29 w30")
        let pair = TranscriptVote.combine([
            reading(.whisperTurbo, "it works now"),
            reading(.parakeetV3, "It works. Now"),
        ])
        #expect(text(pair) == "It works. Now")
    }

    @Test func theMostTrustedPunctuationStands() {
        let combined = TranscriptVote.combine([
            reading(.whisperTurbo, "It works, now."),
            reading(.parakeetV3, "it works now"),
            reading(.apple, "it works. now"),
        ])
        #expect(text(combined) == "It works, now.")
    }

    @Test func aSentenceStartsWithACapitalAfterADroppedWord() {
        var parakeet = reading(.parakeetV3, "it is long there's a widescreen")
        var apple = reading(.apple, "it is long there's a widescreen")
        for index in 3..<6 { parakeet.words[index].start += 1; parakeet.words[index].end += 1 }
        for index in 3..<6 { apple.words[index].start += 1; apple.words[index].end += 1 }
        let combined = TranscriptVote.combine([
            reading(.whisperTurbo, "It is long. And there's a widescreen."),
            parakeet,
            apple,
        ])
        #expect(text(combined) == "It is long. There's a widescreen.")
    }

    @Test func aReadingWithNoWordsHasNoVoteWhenMostHeardSomething() {
        let combined = TranscriptVote.combine([
            reading(.whisperTurbo, "Keep this."),
            reading(.parakeetV3, "keep this"),
            TranscriptVote.Reading(model: .apple, words: []),
        ])
        #expect(text(combined) == "Keep this.")
        let pair = TranscriptVote.combine([
            reading(.whisperTurbo, "Keep this."),
            TranscriptVote.Reading(model: .parakeetV3, words: []),
        ])
        #expect(text(pair) == "Keep this.")
        #expect(TranscriptVote.combine([]).isEmpty)
    }

    @Test func wordsOnlyOneModelHeardWhileMostHeardNothingAreDropped() {
        let combined = TranscriptVote.combine([
            TranscriptVote.Reading(model: .whisperTurbo, words: []),
            TranscriptVote.Reading(model: .parakeetV3, words: []),
            reading(.apple, "Okay."),
        ])
        #expect(combined.isEmpty)
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
        #expect(text(combined) == "Go. Go")
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
