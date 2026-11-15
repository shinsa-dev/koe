import Foundation
import KoeCore
import Testing

struct RefinePlanTests {
    @Test func everyModelReadsWhenWhisperAndParakeetAreIn() {
        #expect(RefinePlan.readers(installed: [.whisperTurbo, .parakeetV3]) == [.whisperTurbo, .parakeetV3, .apple])
    }

    @Test func onlyTheNewestParakeetReads() {
        #expect(RefinePlan.readers(installed: [.whisperTurbo, .parakeetV2, .parakeetV3])
            == [.whisperTurbo, .parakeetV3, .apple])
        #expect(RefinePlan.readers(installed: [.parakeetV2]) == [.parakeetV2])
    }

    @Test func oneModelReadsAloneWithoutApple() {
        #expect(RefinePlan.readers(installed: [.parakeetV3]) == [.parakeetV3])
        #expect(RefinePlan.readers(installed: [.whisperTurbo]) == [.whisperTurbo])
    }

    @Test func nothingInstalledReadsNothing() {
        #expect(RefinePlan.readers(installed: []).isEmpty)
        #expect(RefinePlan.readers(installed: [.apple]).isEmpty)
    }

    @Test func refinedWordsReplaceTheTranscriptAndKeepTheAttachments() {
        var session = Session()
        session.words = [TimedWord("helo", start: 0, end: 0.5)]
        session.annotations = [Annotation(time: 0.4, kind: .note, note: "Here.")]
        let refined = RefinePlan.refined(session, words: [TimedWord("Hello.", start: 0, end: 0.5)])
        #expect(refined?.words.map(\.text) == ["Hello."])
        #expect(refined?.annotations == session.annotations)
        #expect(refined?.id == session.id)
    }

    @Test func theSameWordsOrNoneLeaveTheSessionAlone() {
        var session = Session()
        session.words = [TimedWord("Hello.", start: 0, end: 0.5)]
        #expect(RefinePlan.refined(session, words: [TimedWord("Hello.", start: 0.1, end: 0.6)]) == nil)
        #expect(RefinePlan.refined(session, words: []) == nil)
    }
}

struct RefineQueueTests {
    struct Job: Identifiable, Sendable, Equatable {
        let id: Int
    }

    @Test func oneRecordingIsReadAtATime() {
        var queue = RefineQueue<Job>()
        #expect(queue.add(Job(id: 1)) == Job(id: 1))
        #expect(queue.add(Job(id: 2)) == nil)
        #expect(queue.done(1) == Job(id: 2))
        #expect(queue.done(2) == nil)
        #expect(queue.running == nil && queue.waiting.isEmpty)
    }

    @Test func aSessionPausesTheQueueAndTheRecordingIsReadAgainAfter() {
        var queue = RefineQueue<Job>()
        _ = queue.add(Job(id: 1))
        #expect(queue.pause() == Job(id: 1))
        #expect(queue.add(Job(id: 2)) == nil)
        #expect(queue.waiting == [Job(id: 1), Job(id: 2)])
        #expect(queue.resume() == Job(id: 1))
    }

    @Test func pausingWithNothingRunningCancelsNothing() {
        var queue = RefineQueue<Job>()
        #expect(queue.pause() == nil)
        #expect(queue.resume() == nil)
    }

    @Test func aRecordingAddedAgainTakesItsNewPlace() {
        var queue = RefineQueue<Job>()
        _ = queue.pause()
        _ = queue.add(Job(id: 1))
        _ = queue.add(Job(id: 2))
        _ = queue.add(Job(id: 1))
        #expect(queue.waiting == [Job(id: 2), Job(id: 1)])
    }

    @Test func aRecordingAddedAgainWhileReadStartsOver() {
        var queue = RefineQueue<Job>()
        _ = queue.add(Job(id: 1))
        #expect(queue.add(Job(id: 1)) == Job(id: 1))
    }

    @Test func aLateDoneForAnotherRecordingChangesNothing() {
        var queue = RefineQueue<Job>()
        _ = queue.add(Job(id: 1))
        _ = queue.add(Job(id: 2))
        #expect(queue.done(7) == nil)
        #expect(queue.running == Job(id: 1))
    }
}
