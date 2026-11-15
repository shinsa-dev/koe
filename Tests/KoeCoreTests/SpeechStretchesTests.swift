import KoeCore
import Testing

struct SpeechStretchesTests {
    /// A track from (seconds, level) pieces, in order.
    private func track(_ pieces: [(AudioTime, Float)]) -> LevelTrack {
        var peaks: [Float] = []
        for (seconds, level) in pieces {
            peaks += Array(repeating: level, count: Int((seconds / LevelTrack.step).rounded()))
        }
        return LevelTrack(peaks: peaks)
    }

    private func cuts(_ levels: LevelTrack) -> [SpeechStretches.Stretch] {
        SpeechStretches.cut(levels).map { .init(start: ($0.start * 100).rounded() / 100, end: ($0.end * 100).rounded() / 100) }
    }

    @Test func aShortRecordingIsOneStretch() {
        #expect(cuts(track([(12, 0.8)])) == [.init(start: 0, end: 12)])
    }

    @Test func aLongRecordingIsCutInTheMiddleOfItsPause() {
        let levels = track([(1, 0), (19, 0.8), (2, 0), (18, 0.8)])
        #expect(cuts(levels) == [.init(start: 0, end: 21), .init(start: 21, end: 40)])
    }

    @Test func everyStretchStaysUnderTheLimit() {
        let levels = track([(20, 0.8), (1, 0), (20, 0.8), (1, 0), (20, 0.8), (1, 0), (40, 0.8)])
        let stretches = SpeechStretches.cut(levels)
        #expect(stretches.allSatisfy { $0.end - $0.start <= SpeechStretches.maxLength })
        #expect(stretches.first?.start == 0)
        #expect(abs((stretches.last?.end ?? 0) - levels.duration) < 0.001)
        for (earlier, later) in zip(stretches, stretches.dropFirst()) {
            #expect(earlier.end == later.start)
        }
    }

    @Test func withoutAPauseItCutsAtTheQuietestMoment() {
        let levels = track([(4, 0), (15, 0.9), (0.1, 0.6), (20, 0.9)])
        #expect(cuts(levels).first?.end == 19.05)
    }

    @Test func theLongestPauseWinsOverAnEarlierShortOne() {
        let levels = track([(10, 0.8), (0.3, 0), (8, 0.8), (1.2, 0), (15, 0.8)])
        #expect(cuts(levels).first?.end == 18.9)
    }

    @Test func aPauseTooSoonAfterTheLastCutIsSkipped() {
        let levels = track([(3, 0.8), (2, 0), (20, 0.8), (0.5, 0), (9, 0.8)])
        #expect(cuts(levels).first?.end == 25.25)
    }

    @Test func stretchesWithNoSpeechAreLeftOut() {
        let levels = track([(10, 0.8), (1, 0), (30, 0.05), (1, 0), (10, 0.8)])
        let stretches = SpeechStretches.cut(levels)
        #expect(!stretches.isEmpty)
        #expect(stretches.allSatisfy { stretch in
            levels.peak(from: stretch.start, to: stretch.end - LevelTrack.step) ?? 0 > 0.5
        })
    }

    @Test func aClickInSilenceIsNoSpeech() {
        let levels = track([(10, 0.8), (1, 0), (20, 0), (0.2, 0.9), (10, 0)])
        #expect(cuts(levels) == [.init(start: 0, end: 19)])
    }

    @Test func silenceAloneGivesNothing() {
        #expect(SpeechStretches.cut(track([(40, 0)])).isEmpty)
        #expect(SpeechStretches.cut(LevelTrack()).isEmpty)
    }

    @Test func thePromptIsTheHintsThenTheEndOfWhatCameBefore() {
        let previous = (1...50).map { "w\($0)" }.joined(separator: " ") + "."
        let prompt = SpeechStretches.prompt(hints: ["Shinsa", "Koe"], previous: previous)
        #expect(prompt.hasPrefix("Shinsa, Koe. w11 w12"))
        #expect(prompt.hasSuffix("w50."))
    }

    @Test func aPromptWithoutHintsOrTextIsWhatThereIs() {
        #expect(SpeechStretches.prompt(hints: [], previous: "Open the menu.") == "Open the menu.")
        #expect(SpeechStretches.prompt(hints: ["Shinsa"], previous: "") == "Shinsa")
        #expect(SpeechStretches.prompt(hints: [], previous: "").isEmpty)
    }
}
