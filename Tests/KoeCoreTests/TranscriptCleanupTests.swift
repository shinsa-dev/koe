import Foundation
import KoeCore
import Testing

struct TranscriptCleanupTests {
    /// Words a quarter second each from `start`.
    private func words(_ text: String, from start: AudioTime = 0) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { index, token in
            let begin = start + Double(index) * 0.25
            return TimedWord(String(token), start: begin, end: begin + 0.2)
        }
    }

    private func text(_ words: [TimedWord]) -> String { words.map(\.text).joined(separator: " ") }

    @Test func fillerWordsGo() {
        let cleaned = TranscriptCleanup.apply(words: words("so uh if you um already have a machine erm basically"))
        #expect(text(cleaned) == "so if you already have a machine basically")
    }

    @Test func aSentenceThatStartedWithAFillerStartsWithTheNextWordCapitalized() {
        let cleaned = TranscriptCleanup.apply(words: words("It works. Um, the menu opens slowly."))
        #expect(text(cleaned) == "It works. The menu opens slowly.")
    }

    @Test func aFillerThatClosedASentenceHandsItsFullStopBack() {
        let cleaned = TranscriptCleanup.apply(words: words("it shows a black screen, uh. Then"))
        #expect(text(cleaned) == "it shows a black screen. Then")
    }

    @Test func wordsThatOnlyContainAFillerStay() {
        let cleaned = TranscriptCleanup.apply(words: words("the umbrella error hummed"))
        #expect(text(cleaned) == "the umbrella error hummed")
    }

    @Test func keptWordsKeepTheirTimes() {
        let original = words("look uh here")
        #expect(TranscriptCleanup.apply(words: original) == [original[0], original[2]])
    }

    @Test func aGuessThatRepeatsTheLastSettledWordsIsDropped() {
        // Session A757: the guess timed "broken there." again after the final words.
        let settled = words("so something's broken there.", from: 21)
        let guess = [TimedWord("broken", start: 22.37, end: 22.78), TimedWord("there.", start: 22.78, end: 23.2)]
        let cleaned = TranscriptCleanup.apply(words: settled, pending: guess)
        #expect(text(cleaned) == "so something's broken there.")
    }

    @Test func aGuessThatGoesOnPastTheRepeatKeepsItsNewWords() {
        let settled = words("something's broken there.")
        let guess = words("there. Then it closes", from: 1)
        #expect(text(TranscriptCleanup.apply(words: settled, pending: guess)) == "something's broken there. Then it closes")
    }

    @Test func aGuessOfNewWordsStaysWhole() {
        let settled = words("look at the")
        let guess = words("sidebar now", from: 1)
        #expect(text(TranscriptCleanup.apply(words: settled, pending: guess)) == "look at the sidebar now")
    }

    @Test func wordsHeardWhereTheAudioStayedAtTheNoiseFloorGo() {
        // Session E259: speech, then a minute of room noise in which the model heard "Oh", "Okay." and "I".
        var levels = LevelTrack()
        for step in 0..<1800 {
            let time = Double(step) * LevelTrack.step
            levels.record(time < 10 ? 0.7 : 0.18 + Float(step % 3) * 0.01, at: time)
        }
        let spoken = words("that's the only scenario really", from: 8)
        let invented = [TimedWord("Oh", start: 55.93, end: 56.01), TimedWord("Okay.", start: 67.5, end: 68.14),
                        TimedWord("I", start: 81.01, end: 81.17)]
        let cleaned = TranscriptCleanup.apply(words: spoken + invented, levels: levels)
        #expect(cleaned == spoken)
    }

    @Test func quietSpeechOverTheFloorStays() {
        var levels = LevelTrack()
        for step in 0..<400 { levels.record(0.15, at: Double(step) * LevelTrack.step) }
        levels.record(0.3, at: 12.1)
        let quiet = TimedWord("yes", start: 12, end: 12.3)
        #expect(TranscriptCleanup.apply(words: [quiet], levels: levels) == [quiet])
    }

    @Test func wordsPastTheEndOfTheTrackStay() {
        var levels = LevelTrack()
        levels.record(0.1, at: 0)
        let late = TimedWord("late", start: 5, end: 5.2)
        #expect(TranscriptCleanup.apply(words: [late], levels: levels) == [late])
    }
}

struct LevelTrackTests {
    @Test func keepsTheLoudestLevelOfEachStretch() {
        var track = LevelTrack()
        track.record(0.2, at: 0.01)
        track.record(0.6, at: 0.03)
        track.record(0.4, at: 0.12)
        #expect(track.peaks == [0.6, 0, 0.4])
        #expect(track.peak(from: 0, to: 0.12) == 0.6)
        #expect(track.peak(from: 0.2, to: 0.3) == nil)
    }

    @Test func theNoiseFloorIsWhereMostQuietStretchesStay() {
        let track = LevelTrack(peaks: Array(repeating: 0.2, count: 50) + Array(repeating: 0.8, count: 50))
        #expect(track.noiseFloor == 0.2)
        #expect(LevelTrack().noiseFloor == 0)
    }

    @Test func recordsSamplesAFiftyMillisecondStretchAtATime() {
        var track = LevelTrack()
        let rate = 16_000.0
        track.record(samples: Array(repeating: 0.5, count: 800) + Array(repeating: 0, count: 800), rate: rate, at: 1)
        #expect(track.peaks.count == 22)
        #expect(track.peaks[20] > 0.85)
        #expect(track.peaks[21] == 0)
        #expect(abs(track.duration - 1.1) < 0.0001)
    }
}
