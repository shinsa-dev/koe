import Testing
@testable import KoeCore

@Suite struct LanguageLockTests {
    @Test func aGuessFromTooLittleAudioDoesntSettleTheLanguage() {
        var lock = LanguageLock(minimumAudio: 4)
        lock.observe("nl", heard: 1.2)
        #expect(lock.language == nil)
    }

    @Test func theFirstGuessBackedByEnoughAudioSettlesIt() {
        var lock = LanguageLock(minimumAudio: 4)
        lock.observe("en", heard: 4.5)
        #expect(lock.language == "en")
    }

    @Test func aSettledLanguageNeverChanges() {
        var lock = LanguageLock(minimumAudio: 4)
        lock.observe("en", heard: 5)
        lock.observe("de", heard: 30)
        #expect(lock.language == "en")
    }

    @Test func aPassThatDetectedNothingLeavesItOpen() {
        var lock = LanguageLock(minimumAudio: 4)
        lock.observe(nil, heard: 10)
        lock.observe("", heard: 10)
        #expect(lock.language == nil)
    }
}

@Suite struct StepTimingsTests {
    @Test func countsThePassesThatRanPastTheBudget() {
        var timings = StepTimings(budget: 0.9)
        for seconds in [0.5, 0.7, 1.2, 3.5] { timings.record(seconds) }
        #expect(timings.overBudget == 2)
        #expect(timings.worst == 3.5)
        #expect(abs(timings.mean - 1.475) < 0.0001)
    }

    @Test func sumsUpInOneLine() {
        var timings = StepTimings(budget: 0.9)
        timings.record(0.5)
        timings.record(1.5)
        #expect(timings.summary == "2 steps, mean 1.00 s, worst 1.50 s, 1 over 0.90 s")
    }

    @Test func noPassesReadAsZero() {
        let timings = StepTimings(budget: 0.9)
        #expect(timings.summary == "0 steps, mean 0.00 s, worst 0.00 s, 0 over 0.90 s")
    }

    @Test func mergesTheStepsOfSeveralRecordings() {
        var all = StepTimings(budget: 0.9)
        var one = StepTimings(budget: 0.9)
        one.record(1)
        all.merge(one)
        all.merge(one)
        #expect(all.steps == [1, 1])
    }
}
