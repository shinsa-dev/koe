import KoeCore
import Testing

struct DictionaryCardTests {
    private let names = [
        LearnedName("Shinsa", source: .repository("/Users/me/Developer/shinsa")),
        LearnedName("kodama", source: .repository("/Volumes/Work/kodama")),
        LearnedName("BuzzKit", source: .repository("/Users/me/Developer/buzzkit")),
        LearnedName("OrbStack", source: .app("/Applications/OrbStack.app")),
    ]

    @Test func showsYourWordsNewestFirst() {
        var settings = KoeSettings()
        settings.dictionaryWords = ["Kanna", "paywall-next"]
        let card = DictionaryCard(settings: settings, learned: [], home: "/Users/me")
        #expect(card.words == ["paywall-next", "Kanna"])
    }

    @Test func learnedNamesAreSortedAndSayWhereTheyCameFrom() {
        let card = DictionaryCard(settings: KoeSettings(), learned: names, home: "/Users/me")
        #expect(card.learned.map(\.name) == ["BuzzKit", "kodama", "OrbStack", "Shinsa"])
        #expect(card.learned.map(\.detail) == [
            "Repository in ~/Developer/buzzkit", "Repository in /Volumes/Work/kodama", "App",
            "Repository in ~/Developer/shinsa",
        ])
        #expect(card.learningDetail == "3 names from your repositories and 1 name from your apps.")
    }

    @Test func removedNamesLeaveTheListWhateverTheirCase() {
        var settings = KoeSettings()
        settings.removedNames = ["buzzkit", "Kodama"]
        let card = DictionaryCard(settings: settings, learned: names, home: "/Users/me")
        #expect(card.learned.map(\.name) == ["OrbStack", "Shinsa"])
        #expect(card.removedCount == 2)
        #expect(card.learningDetail == "1 name from your repositories and 1 name from your apps.")
    }

    @Test func learningOffListsNoNames() {
        var settings = KoeSettings()
        settings.learnedNames = false
        let card = DictionaryCard(settings: settings, learned: names, home: "/Users/me")
        #expect(card.learned.isEmpty)
        #expect(card.learningDetail == "Off. Only the words you add are in the dictionary.")
        #expect(DictionaryCard(settings: KoeSettings(), learned: [], home: "/Users/me").learningDetail
            == "Names of your git repositories and apps. None found yet.")
    }

    @Test func addingTrimsAndRefusesEmptyOrRepeatedWords() {
        var settings = KoeSettings()
        DictionaryCard.add("  Kodama   Labs ", to: &settings)
        DictionaryCard.add("   ", to: &settings)
        DictionaryCard.add("kodama labs", to: &settings)
        DictionaryCard.add("—", to: &settings)
        #expect(settings.dictionaryWords == ["Kodama Labs"])
    }

    @Test func addingARemovedNameBringsItBack() {
        var settings = KoeSettings()
        DictionaryCard.remove(learned: "BuzzKit", from: &settings)
        DictionaryCard.remove(learned: "buzzkit", from: &settings)
        #expect(settings.removedNames == ["BuzzKit"])
        DictionaryCard.add("Buzzkit", to: &settings)
        #expect(settings.removedNames.isEmpty)
        #expect(settings.dictionaryWords == ["Buzzkit"])
    }

    @Test func removingAndRestoring() {
        var settings = KoeSettings()
        settings.dictionaryWords = ["Kanna", "Lue"]
        DictionaryCard.remove(word: "Kanna", from: &settings)
        #expect(settings.dictionaryWords == ["Lue"])
        DictionaryCard.remove(learned: "Shinsa", from: &settings)
        DictionaryCard.restoreRemoved(in: &settings)
        #expect(settings.removedNames.isEmpty)
    }
}
