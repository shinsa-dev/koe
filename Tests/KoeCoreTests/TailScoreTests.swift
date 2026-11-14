import KoeCore
import Testing

struct TailScoreTests {
    @Test func caseAndPunctuationDontCount() {
        let result = TailScore.compare(live: "You know what I mean?", reference: "you know, what i mean")
        #expect(result.isComplete)
        #expect(result.live == ["what", "i", "mean"])
    }

    @Test func aCutEndingIsIncomplete() {
        let result = TailScore.compare(live: "the initial exit tax, you know what I",
                                       reference: "the initial exit tax, you know what I mean?")
        #expect(!result.isComplete)
        #expect(result.live == ["know", "what", "i"])
        #expect(result.reference == ["what", "i", "mean"])
    }

    @Test func aDoubledLastWordIsIncomplete() {
        #expect(!TailScore.compare(live: "any other differences differences?",
                                   reference: "any other differences?").isComplete)
    }

    @Test func wordsThatAreOnlyPunctuationGo() {
        #expect(TailScore.words("so - yeah … ok.") == ["so", "yeah", "ok"])
    }

    @Test func shortTranscriptsCompareWhatTheyHave() {
        #expect(TailScore.compare(live: "Okay.", reference: "okay").isComplete)
        #expect(TailScore.compare(live: "", reference: "").isComplete)
        #expect(!TailScore.compare(live: "", reference: "okay").isComplete)
    }

    @Test func theTotalCountsCompleteEndings() {
        let results = [
            TailScore.compare(live: "a b c", reference: "a b c"),
            TailScore.compare(live: "a b", reference: "a b c"),
        ]
        #expect(TailScore.total(results) == "1/2")
    }
}
