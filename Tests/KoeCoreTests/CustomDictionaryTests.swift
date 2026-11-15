import Foundation
import KoeCore
import Testing

struct CustomDictionaryTests {
    private func words(_ text: String, from start: AudioTime = 0) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { index, token in
            let begin = start + Double(index) * 0.25
            return TimedWord(String(token), start: begin, end: begin + 0.2)
        }
    }

    private func text(_ words: [TimedWord]) -> String { words.map(\.text).joined(separator: " ") }

    private static let english: Set<String> = [
        "the", "a", "in", "on", "open", "shins", "shine", "shin", "pay", "wall", "next", "buzz", "kit", "code",
        "notion", "cursor", "it", "is", "and", "my", "project", "fix", "so", "look", "at", "page", "koala",
    ]
    private func dictionary(_ entries: [String]) -> CustomDictionary {
        CustomDictionary(words: entries) { Self.english.contains($0) }
    }

    @Test func spellingsThatSoundAlikeShareASoundKey() {
        let keys = ["Shinsa", "Shinza", "Shinz", "shins", "SHINSA"].map(CustomDictionary.soundKey)
        #expect(Set(keys) == ["shins"])
        #expect(CustomDictionary.soundKey("BuzzKit") == CustomDictionary.soundKey("bus kit"))
        #expect(CustomDictionary.soundKey("phone") == CustomDictionary.soundKey("fone"))
        #expect(CustomDictionary.soundKey("Kodama") != CustomDictionary.soundKey("Kodiak"))
    }

    @Test func everyWayAModelHearsShinsaBecomesShinsa() {
        let fix = dictionary(["Shinsa"])
        for heard in ["Shinza", "Shinz", "shins", "shinsa"] {
            #expect(text(fix.apply(words("open \(heard) now"))) == "open Shinsa now")
        }
    }

    @Test func aNameHeardAsSeveralWordsBecomesOneWord() {
        let fix = dictionary(["Shinsa", "paywall-next", "BuzzKit"])
        #expect(text(fix.apply(words("open shin za and pay wall next"))) == "open Shinsa and paywall-next")
        #expect(text(fix.apply(words("the paywall next page"))) == "the paywall-next page")
        #expect(text(fix.apply(words("my buzz kit project"))) == "my BuzzKit project")
    }

    @Test func aReplacedRunSpansTheTimesOfTheWordsItReplaced() {
        let heard = words("open shin za now")
        let fixed = dictionary(["Shinsa"]).apply(heard)
        #expect(fixed.count == 3)
        #expect(fixed[1] == TimedWord("Shinsa", start: heard[1].start, end: heard[2].end))
        #expect(fixed[0] == heard[0] && fixed[2] == heard[3])
    }

    @Test func punctuationAndPossessivesStay() {
        let fix = dictionary(["Shinsa"])
        #expect(text(fix.apply(words("I use Shinza."))) == "I use Shinsa.")
        #expect(text(fix.apply(words("(shinz, then"))) == "(Shinsa, then")
        #expect(text(fix.apply(words("Shinza's queue"))) == "Shinsa's queue")
    }

    @Test func aLowercaseEntryTakesTheCapitalOfASentenceStart() {
        let fixed = dictionary(["paywall-next"]).apply(words("Pay wall next is slow."))
        #expect(text(fixed) == "Paywall-next is slow.")
    }

    @Test func aNearMatchFixesAWordThatIsNotEnglish() {
        let fix = dictionary(["Kodama", "Superwall"])
        #expect(text(fix.apply(words("open Kodima"))) == "open Kodama")
        #expect(text(fix.apply(words("in superwell"))) == "in Superwall")
    }

    @Test func ordinaryWordsThatOnlyResembleAnEntryStay() {
        let fix = dictionary(["Shinsa", "Koala", "Kodama"])
        #expect(text(fix.apply(words("shine a shin on the code"))) == "shine a shin on the code")
        #expect(text(fix.apply(words("koala"))) == "Koala")
    }

    @Test func shortEntriesOnlyFixTheirOwnCasing() {
        let fix = dictionary(["Koe"])
        #expect(text(fix.apply(words("open koe"))) == "open Koe")
        #expect(text(fix.apply(words("a key on the co op"))) == "a key on the co op")
    }

    @Test func theFirstOfTwoEntriesThatSoundAlikeWins() {
        let fix = dictionary(["Shinsa", "Shinza"])
        #expect(text(fix.apply(words("shins"))) == "Shinsa")
        #expect(fix.entries == ["Shinsa", "Shinza"])
    }

    @Test func blankAndRepeatedEntriesAreDropped() {
        let fix = CustomDictionary(words: ["  ", "Shinsa", "shinsa", " BuzzKit "])
        #expect(fix.entries == ["Shinsa", "BuzzKit"])
        #expect(CustomDictionary(words: []).isEmpty)
        #expect(CustomDictionary(words: []).apply(words("as heard")) == words("as heard"))
    }

    @Test func aSessionKeepsItsAttachmentsWhileItsWordsAreSpelled() {
        let file = Annotation(time: 0.3, kind: .file(Asset(url: URL(filePath: "/tmp/notes.txt"))))
        let session = Session(words: words("open Shinza now"), annotations: [file])
        let spelled = dictionary(["Shinsa"]).apply(to: session)
        #expect(text(spelled.words) == "open Shinsa now")
        #expect(spelled.annotations == session.annotations)
        #expect(spelled.id == session.id)
    }

    @Test func swappedLettersCountAsOneEdit() {
        #expect(CustomDictionary.distance("shins", "hsins") == 1)
        #expect(CustomDictionary.distance("kodam", "kodom") == 1)
        #expect(CustomDictionary.distance("", "abc") == 3)
    }

    /// About seven minutes of talking against 504 entries, timed at its best of ten as other work shares the Mac.
    @Test func aLongTranscriptIsFixedWithinFiveMilliseconds() {
        let names = (0..<500).map { "Project\($0)name" } + ["Shinsa", "paywall-next", "BuzzKit", "Kodama"]
        let fix = dictionary(names)
        let sentence = "so look at the Shinza page and fix the pay wall next code in Kodima it is my project "
        let transcript = words(String(repeating: sentence, count: 56))
        #expect(transcript.count > 1_000)
        let clock = ContinuousClock()
        let best = (0..<10).map { _ in clock.measure { _ = fix.apply(transcript) } }.min() ?? .zero
        #expect(best < .milliseconds(5))
        let fixed = text(Array(fix.apply(transcript).prefix(17)))
        #expect(fixed == "so look at the Shinsa page and fix the paywall-next code in Kodama it is my project")
    }

    @Test func theDictionarySettingsSurviveARoundTrip() {
        var settings = KoeSettings()
        #expect(settings.dictionaryWords.isEmpty && settings.learnedNames && settings.removedNames.isEmpty)
        settings.dictionaryWords = ["Shinsa", "paywall-next"]
        settings.learnedNames = false
        settings.removedNames = ["Notes"]
        #expect(KoeSettings(values: settings.values) == settings)
        #expect(KoeSettings(values: [KoeSettings.Key.dictionaryWords: "Shinsa"]).dictionaryWords.isEmpty)
    }
}
