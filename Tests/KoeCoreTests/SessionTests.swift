import Foundation
import KoeCore
import Testing

struct TranscriptRunTests {
    @Test func splitsARunIntoWordsSharingItsTimeByLength() {
        var words: [TimedWord] = []
        words.appendRun("hi there", start: 0, end: 7)
        #expect(words == [TimedWord("hi", start: 0, end: 2), TimedWord("there", start: 2, end: 7)])
    }

    @Test func punctuationJoinsThePreviousWordAcrossRuns() {
        var words: [TimedWord] = []
        words.appendRun("done", start: 0, end: 1)
        words.appendRun(" .", start: 1, end: 1.2)
        #expect(words == [TimedWord("done.", start: 0, end: 1.2)])
        #expect(words[0].endsSentence)
    }

    @Test func leadingPunctuationWithNoWordBeforeItStaysAWord() {
        var words: [TimedWord] = []
        words.appendRun("…", start: 0, end: 1)
        #expect(words.map(\.text) == ["…"])
    }

    @Test func blankRunsAddNothing() {
        var words: [TimedWord] = []
        words.appendRun("   ", start: 0, end: 1)
        #expect(words.isEmpty)
    }

    @Test func sessionAppendsTranscriptAndAnnotations() {
        var session = Session()
        session.appendTranscript("look here", start: 0, end: 2)
        session.add(Annotation(time: 5, kind: .note, note: "later"))
        #expect(session.words.map(\.text) == ["look", "here"])
        #expect(session.duration == 5)
    }
}

struct TimedWordTests {
    @Test func sentenceEndsSeeThroughClosingQuotes() {
        #expect(TimedWord("done.\u{201D}", start: 0, end: 1).endsSentence)
        #expect(TimedWord("why?)", start: 0, end: 1).endsSentence)
        #expect(!TimedWord("so,", start: 0, end: 1).endsSentence)
        #expect(!TimedWord("\"", start: 0, end: 1).endsSentence)
    }

    @Test func endNeverPrecedesStart() {
        #expect(TimedWord("x", start: 2, end: 1).end == 2)
    }
}

struct AnnotationTests {
    @Test func assetKindComesFromTheExtension() {
        #expect(Asset(url: URL(fileURLWithPath: "/a/shot.PNG")).kind == .image)
        #expect(Asset(url: URL(fileURLWithPath: "/a/clip.mov")).kind == .video)
        #expect(Asset(url: URL(fileURLWithPath: "/a/spec.pdf")).kind == .file)
        #expect(Asset(url: URL(fileURLWithPath: "/a/raw"), kind: .image).kind == .image)
    }

    @Test func notesAreTrimmedAndBlankOnesAreNil() {
        #expect(Annotation(time: 0, kind: .note, note: " hi \n").trimmedNote == "hi")
        #expect(Annotation(time: 0, kind: .note, note: " \n").trimmedNote == nil)
        #expect(Annotation(time: 0, kind: .note).asset == nil)
    }

    @Test func timeNeverGoesNegative() {
        #expect(Annotation(time: -1, kind: .note).time == 0)
    }

    @Test func sessionRoundTripsThroughJSON() throws {
        let session = Session(
            startedAt: Date(timeIntervalSince1970: 1_000),
            words: [TimedWord("hi", start: 0, end: 1)],
            annotations: [
                Annotation(time: 0.5, kind: .screenshot(Asset(url: URL(fileURLWithPath: "/tmp/a.png"))),
                           note: "n", source: CaptureSource(app: "Safari", window: "Home")),
                Annotation(time: 0.7, kind: .note, note: "x"),
            ]
        )
        let decoded = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session))
        #expect(decoded == session)
    }
}
