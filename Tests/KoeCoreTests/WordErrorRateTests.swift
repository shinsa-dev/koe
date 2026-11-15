@testable import KoeCore
import Testing

struct WordErrorRateTests {
    @Test func theSameWordsScoreNothing() {
        let score = WordErrorRate.compare("Hello, world.", to: "hello world")
        #expect(score == WordErrorRate(errors: 0, words: 2))
        #expect(score.rate == 0)
    }

    @Test func aSwappedWordIsOneError() {
        #expect(WordErrorRate.compare("I use shinza daily", to: "I use Shinsa daily") == .init(errors: 1, words: 4))
    }

    @Test func aDroppedAndAnAddedWordEachCount() {
        #expect(WordErrorRate.compare("open the menu", to: "open the settings menu") == .init(errors: 1, words: 4))
        #expect(WordErrorRate.compare("um open the menu", to: "open the menu") == .init(errors: 1, words: 3))
    }

    @Test func itCountsTheFewestEdits() {
        // A shifted run is one drop and one add, not a swap of every word.
        #expect(WordErrorRate.compare("b c d e", to: "a b c d") == .init(errors: 2, words: 4))
    }

    @Test func emptyTranscripts() {
        #expect(WordErrorRate.compare("", to: "").rate == 0)
        #expect(WordErrorRate.compare("", to: "two words") == .init(errors: 2, words: 2))
        #expect(WordErrorRate.compare("made up", to: "").rate == 1)
    }

    @Test func scoresAddUpByWords() {
        var total = WordErrorRate.compare("a b", to: "a c")
        total += WordErrorRate.compare("x y z w", to: "x y z w")
        #expect(total == .init(errors: 1, words: 6))
        #expect(total.summary == "16.7% (1 of 6 words)")
    }
}
