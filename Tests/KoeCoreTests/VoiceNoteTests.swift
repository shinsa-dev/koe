import Foundation
import KoeCore
import Testing

private func spoken(_ text: String, from start: AudioTime) -> [TimedWord] {
    text.split(separator: " ").enumerated().map { index, word in
        TimedWord(String(word), start: start + Double(index) * 0.5, end: start + Double(index) * 0.5 + 0.4)
    }
}

private func shot(at time: AudioTime, voice: VoiceSpan? = nil, note: String? = nil) -> Annotation {
    Annotation(time: time, kind: .screenshot(Asset(url: URL(fileURLWithPath: "/tmp/koe/1.png"))), note: note, voice: voice)
}

struct VoiceNoteTests {
    @Test func wordsSaidInTheSpanBecomeTheAttachmentsNote() {
        // "Look at this." 0–1.4, then "the padding is too tight" 2.0–4.4 about the screenshot, then "Next thing."
        let words = spoken("Look at this.", from: 0) + spoken("the padding is too tight", from: 2) + spoken("Next thing.", from: 5)
        let session = Session(words: words, annotations: [shot(at: 1.8, voice: VoiceSpan(start: 1.8, end: 4.6))])
        let bundle = BundleComposer().compose(session)
        #expect(bundle.text.hasPrefix("Look at this. [1: the padding is too tight] Next thing."))
    }

    @Test func aSpokenNoteFollowsATypedOne() {
        let session = Session(words: spoken("too tight", from: 1), annotations: [
            shot(at: 0.9, voice: VoiceSpan(start: 0.9, end: 2), note: "Padding."),
        ])
        let (words, annotations) = BundleComposer.splitVoiceNotes(session)
        #expect(words.isEmpty)
        #expect(annotations[0].note == "Padding. too tight")
    }

    @Test func withoutSpansNothingMoves() {
        let session = Session(words: spoken("hello there", from: 0), annotations: [shot(at: 0.5)])
        let (words, annotations) = BundleComposer.splitVoiceNotes(session)
        #expect(words == session.words)
        #expect(annotations == session.annotations)
    }

    @Test func aWordCountsByItsMiddle() {
        let span = VoiceSpan(start: 1, end: 2)
        #expect(span.contains(TimedWord("in", start: 0.7, end: 1.4)))
        #expect(!span.contains(TimedWord("out", start: 0.2, end: 1.6)))
        #expect(!span.contains(TimedWord("after", start: 1.9, end: 2.3)))
    }

    @Test func aWordInTwoSpansGoesToTheLaterOne() {
        let session = Session(words: spoken("one", from: 1), annotations: [
            shot(at: 0, voice: VoiceSpan(start: 0, end: 3)), shot(at: 0.5, voice: VoiceSpan(start: 0.5, end: 3)),
        ])
        let (_, annotations) = BundleComposer.splitVoiceNotes(session)
        #expect(annotations[0].trimmedNote == nil)
        #expect(annotations[1].note == "one")
    }

    @Test func aSpanEndsNoEarlierThanItStarts() {
        let span = VoiceSpan(start: 3, end: 1)
        #expect(span.end == 3)
    }
}

struct LedgerRemovalTests {
    @Test func removingAnAttachmentTakesItOut() {
        var ledger = AnnotationLedger()
        let ticket = ledger.open(at: 1)
        let annotation = Annotation(time: 1, kind: .note, note: "x")
        ledger.close(ticket, with: annotation)
        let removed = ledger.remove(annotation.id)
        let again = ledger.remove(annotation.id)
        #expect(removed && !again)
        #expect(ledger.annotations.isEmpty)
    }
}

struct FrameVoiceTests {
    @Test func aFrameCarriesWhatWasSaidAboutIt() throws {
        var review = ClipReview(frames: ClipFrames(times: [0, 0.5, 1], duration: 1.5))
        review.pick(1)
        review.setVoice(VoiceSpan(start: 4, end: 6), for: 1)
        review.setVoice(VoiceSpan(start: 9, end: 9.5), for: 2)
        let clip = Asset(url: URL(fileURLWithPath: "/tmp/c.mov"), kind: .video)
        let frame = Asset(url: URL(fileURLWithPath: "/tmp/f.png"))
        let result = review.annotations(clip: clip, frameAssets: [1: frame], recordingStart: 0)
        #expect(result[1].annotation.voice == VoiceSpan(start: 4, end: 6))
        #expect(review.picks.count == 1)
    }
}

struct AttachmentLabelTests {
    @Test func namesEachKind() {
        let image = Asset(url: URL(fileURLWithPath: "/tmp/1.png"))
        let shot = Annotation(time: 12, kind: .screenshot(image), source: CaptureSource(app: "Dia", window: "Settings"))
        #expect(AttachmentLabel.title(of: shot) == "Screenshot")
        #expect(AttachmentLabel.detail(of: shot) == "Dia · Settings · At 0:12")
        let spoken = Annotation(time: 0, kind: .screenshot(image), voice: VoiceSpan(start: 0, end: 1))
        #expect(AttachmentLabel.title(of: spoken) == "Screenshot with what you said")
        #expect(AttachmentLabel.detail(of: spoken) == "At 0:00")
        let comment = Annotation(time: 0, kind: .screenshot(image), voice: VoiceSpan(start: 0, end: 1), comment: true)
        #expect(comment.isComment)
        #expect(AttachmentLabel.title(of: comment) == "Comment")
        let frame = Annotation(time: 3, kind: .screenshot(image), frame: ClipFrame(clipID: UUID(), time: 0.42))
        #expect(AttachmentLabel.title(of: frame) == "Frame 0.42 s into the clip")
        #expect(AttachmentLabel.title(of: Annotation(time: 0, kind: .clip(Asset(url: URL(fileURLWithPath: "/c.mov"))))) == "Clip")
        #expect(AttachmentLabel.title(of: Annotation(time: 0, kind: .file(Asset(url: URL(fileURLWithPath: "/a/spec.pdf"))))) == "spec.pdf")
        #expect(AttachmentLabel.title(of: Annotation(time: 0, kind: .note)) == "Note")
    }
}
