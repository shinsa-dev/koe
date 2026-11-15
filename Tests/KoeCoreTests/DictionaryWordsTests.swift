import KoeCore
import Testing

struct DictionaryWordsTests {
    private let learned = [
        LearnedName("Shinsa", source: .repository("/Users/me/Developer/shinsa")),
        LearnedName("BuzzKit", source: .repository("/Users/me/Sandbox/buzzkit")),
        LearnedName("OrbStack", source: .app("/Applications/OrbStack.app")),
    ]

    private func settings(words: [String] = ["Koe"], learnedNames: Bool = true, removed: [String] = []) -> KoeSettings {
        var settings = KoeSettings()
        settings.dictionaryWords = words
        settings.learnedNames = learnedNames
        settings.removedNames = removed
        return settings
    }

    @Test func yourWordsComeBeforeLearnedNames() {
        #expect(DictionaryWords.list(settings: settings(), learned: learned) == ["Koe", "Shinsa", "BuzzKit", "OrbStack"])
    }

    @Test func learnedNamesTurnedOffLeaveOnlyYourWords() {
        #expect(DictionaryWords.list(settings: settings(learnedNames: false), learned: learned) == ["Koe"])
    }

    @Test func aRemovedNameStaysOutWhateverItsCasing() {
        let words = DictionaryWords.list(settings: settings(removed: ["buzzkit"]), learned: learned)
        #expect(words == ["Koe", "Shinsa", "OrbStack"])
    }

    @Test func hintsStopAtTheLimitAndKeepTheOrder() {
        #expect(DictionaryWords.hints(["Shinsa", "Kodama", "OrbStack"], limit: 14) == ["Shinsa", "Kodama"])
        #expect(DictionaryWords.hints(["Shinsa", "Kodama"], limit: 5).isEmpty)
        #expect(DictionaryWords.hints([]).isEmpty)
    }

    @Test func hintWordsHoldTheLatestList() {
        let hints = HintWords(["Shinsa"])
        hints.words = ["Kodama"]
        #expect(hints.words == ["Kodama"])
    }
}
