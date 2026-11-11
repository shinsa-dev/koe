import Foundation
import KoeCore
import Testing

struct LiveTranscriptTests {
    private func update(_ runs: [TranscriptRun], final isFinal: Bool, start: AudioTime = 0, end: AudioTime? = nil) -> TranscriptUpdate {
        TranscriptUpdate(runs: runs, isFinal: isFinal, start: start, end: end ?? runs.last?.end ?? start)
    }

    @Test func aVolatileResultReplacesTheLastGuess() {
        var transcript = LiveTranscript()
        transcript.apply(update([TranscriptRun("Look", start: 0, end: 0.3)], final: false))
        transcript.apply(update([TranscriptRun("Look at the", start: 0, end: 0.6)], final: false))
        #expect(transcript.words.isEmpty)
        #expect(transcript.text == "Look at the")
    }

    @Test func aFinalResultSettlesItsWordsWithTheirOwnTimes() {
        var transcript = LiveTranscript()
        transcript.apply(update([TranscriptRun("Look at", start: 0, end: 0.5)], final: false))
        transcript.apply(update([
            TranscriptRun("Look", start: 0, end: 0.24),
            TranscriptRun(" at", start: 0.24, end: 0.48),
            TranscriptRun(" the", start: 0.48, end: 0.54),
            TranscriptRun(" sidebar.", start: 0.54, end: 1.2),
        ], final: true))
        #expect(transcript.words == [
            TimedWord("Look", start: 0, end: 0.24),
            TimedWord("at", start: 0.24, end: 0.48),
            TimedWord("the", start: 0.48, end: 0.54),
            TimedWord("sidebar.", start: 0.54, end: 1.2),
        ])
        #expect(transcript.pending.isEmpty)
    }

    @Test func aRunWithoutLeadingSpaceContinuesTheWordBeforeIt() {
        var transcript = LiveTranscript()
        transcript.apply(update([
            TranscriptRun("don", start: 0, end: 0.2),
            TranscriptRun("'t", start: 0.2, end: 0.3),
            TranscriptRun(" go", start: 0.3, end: 0.5),
        ], final: true))
        #expect(transcript.words == [TimedWord("don't", start: 0, end: 0.3), TimedWord("go", start: 0.3, end: 0.5)])
    }

    @Test func aNewResultNeverGluesOntoTheLastSettledWord() {
        var transcript = LiveTranscript()
        transcript.apply(update([TranscriptRun("Look", start: 0, end: 0.3)], final: true))
        transcript.apply(update([TranscriptRun("here", start: 1, end: 1.3)], final: true))
        #expect(transcript.words.map(\.text) == ["Look", "here"])
    }

    @Test func leadingPunctuationOfAFinalResultJoinsTheSettledWord() {
        var transcript = LiveTranscript()
        transcript.apply(update([TranscriptRun("Look", start: 0, end: 0.3)], final: true))
        transcript.apply(update([TranscriptRun(",", start: 0.3, end: 0.35), TranscriptRun(" here", start: 0.4, end: 0.7)], final: true))
        #expect(transcript.words == [TimedWord("Look,", start: 0, end: 0.35), TimedWord("here", start: 0.4, end: 0.7)])
    }

    @Test func aFinalResultKeepsTheGuessForLaterAudio() {
        var transcript = LiveTranscript()
        transcript.apply(update([TranscriptRun("next words", start: 2, end: 3)], final: false))
        transcript.apply(update([TranscriptRun("First.", start: 0, end: 1)], final: true, end: 1.5))
        #expect(transcript.text == "First. next words")
        transcript.apply(update([TranscriptRun("Next words.", start: 2, end: 3)], final: true))
        #expect(transcript.text == "First. Next words.")
        #expect(transcript.pending.isEmpty)
    }

    @Test func emptyUntilSomethingIsHeard() {
        var transcript = LiveTranscript()
        #expect(transcript.isEmpty)
        transcript.apply(update([], final: false))
        #expect(transcript.isEmpty)
        #expect(transcript.text.isEmpty)
    }

    @Test func tailKeepsShortTextWhole() {
        var transcript = LiveTranscript()
        transcript.apply(update([TranscriptRun("short", start: 0, end: 1)], final: true))
        #expect(transcript.tail(limit: 20) == "short")
    }

    @Test func tailCutsAtAWordAndLeadsWithAnEllipsis() {
        var transcript = LiveTranscript()
        transcript.apply(update([TranscriptRun("one two three four", start: 0, end: 4)], final: true))
        #expect(transcript.tail(limit: 12) == "…three four")
        #expect(transcript.tail(limit: 12).count <= 12)
    }

    @Test func tailCutsInsideAWordLongerThanTheLimit() {
        var transcript = LiveTranscript()
        transcript.apply(update([TranscriptRun("supercalifragilistic", start: 0, end: 1)], final: true))
        #expect(transcript.tail(limit: 6) == "…istic")
    }
}

struct RecorderPhaseTests {
    @Test func theHotkeyStartsWhenIdleOrAfterAFailure() {
        #expect(RecorderPhase.idle.toggleIntent == .start)
        #expect(RecorderPhase.failed("No microphone").toggleIntent == .start)
    }

    @Test func theHotkeyFinishesWhileRecordingOrPaused() {
        #expect(RecorderPhase.recording.toggleIntent == .stop)
        #expect(RecorderPhase.paused.toggleIntent == .stop)
    }

    @Test func theHotkeyWaitsWhileASessionFinishes() {
        #expect(RecorderPhase.finishing.toggleIntent == .ignore)
    }

    @Test func activeCoversEveryPhaseWithASession() {
        #expect(RecorderPhase.recording.isActive)
        #expect(RecorderPhase.paused.isActive)
        #expect(RecorderPhase.finishing.isActive)
        #expect(!RecorderPhase.idle.isActive)
        #expect(!RecorderPhase.failed("x").isActive)
    }

    @Test func onlyRecordingAndPausedAreOpen() {
        #expect(RecorderPhase.recording.isOpen)
        #expect(RecorderPhase.paused.isOpen)
        #expect(!RecorderPhase.finishing.isOpen)
        #expect(!RecorderPhase.idle.isOpen)
    }
}

struct DeliveryTests {
    @Test func copiesAtOnceWithTheWordsHeardSoFar() {
        #expect(Delivery.decide(openTools: 0, hasContent: true, transcriptDone: false) == .deliver(final: false))
    }

    @Test func aSettledTranscriptIsFinal() {
        #expect(Delivery.decide(openTools: 0, hasContent: true, transcriptDone: true) == .deliver(final: true))
        #expect(Delivery.decide(openTools: 0, hasContent: false, transcriptDone: true) == .deliver(final: true))
    }

    @Test func waitsForAToolStillOpen() {
        #expect(Delivery.decide(openTools: 1, hasContent: true, transcriptDone: true) == .wait)
    }

    @Test func waitsWhenTheModelHasNoWordYetButIsStillWorking() {
        #expect(Delivery.decide(openTools: 0, hasContent: false, transcriptDone: false) == .whenSettled)
    }
}

struct ElapsedTests {
    @Test(arguments: [
        (0.0, "0:00"), (7.9, "0:07"), (65, "1:05"), (750, "12:30"), (3725, "1:02:05"), (-3, "0:00"),
    ])
    func clock(seconds: TimeInterval, expected: String) {
        #expect(Elapsed.clock(seconds) == expected)
    }
}

struct KeyComboTests {
    @Test func theDefaultToggleIsFnAlone() {
        #expect(KeyCombo.toggleSession.displayName == "fn")
    }

    @Test func modifiersReadInTheOrderMacOSUses() {
        let combo = KeyCombo(keyCode: 1, modifiers: KeyCombo.command | KeyCombo.shift | KeyCombo.control | KeyCombo.option)
        #expect(combo.displayName == "⌃⌥⇧⌘S")
    }

    @Test func anUnknownKeyIsNamedByItsCode() {
        #expect(KeyCombo(keyCode: 200, modifiers: 0).displayName == "Key 200")
    }
}

struct SpokenSpanTests {
    @Test func theWordsInsideASpanAreItsNote() {
        var transcript = LiveTranscript()
        transcript.apply(TranscriptUpdate(runs: [TranscriptRun("Look here this is too tight okay", start: 0, end: 6)],
                                          isFinal: true, start: 0, end: 6))
        let said = transcript.text(in: VoiceSpan(start: 2, end: 5))
        #expect(!said.isEmpty)
        #expect(said.contains("tight"))
        #expect(!said.contains("Look"))
    }

    @Test func aSpanNobodySpokeInIsEmpty() {
        var transcript = LiveTranscript()
        transcript.apply(TranscriptUpdate(runs: [TranscriptRun("Hello", start: 0, end: 1)], isFinal: true, start: 0, end: 1))
        #expect(transcript.text(in: VoiceSpan(start: 4, end: 6)).isEmpty)
    }
}
