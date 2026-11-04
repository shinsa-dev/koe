import Foundation
import KoeCore
import Testing

/// Words as `(text, start...end)`, to keep the timelines below readable.
private func words(_ spec: [(String, ClosedRange<AudioTime>)]) -> [TimedWord] {
    spec.map { TimedWord($0.0, start: $0.1.lowerBound, end: $0.1.upperBound) }
}

private func shot(_ name: String, at time: AudioTime, note: String? = nil, source: CaptureSource? = nil) -> Annotation {
    Annotation(time: time, kind: .screenshot(Asset(url: URL(fileURLWithPath: "/tmp/koe/\(name).png"))), note: note, source: source)
}

/// "the button here looks off" spoken from 0 to 2.5 s, one word every half second.
private let sentence = words([
    ("the", 0.0...0.4), ("button", 0.5...0.9), ("here", 1.0...1.4), ("looks", 1.5...1.9), ("off", 2.0...2.4),
])

struct PlacementTests {
    let composer = BundleComposer()

    @Test func annotationInAGapLandsInThatGap() {
        #expect(composer.placement(for: 1.45, in: sentence).gap == 3)
    }

    @Test func annotationMidWordGoesToTheNearerSide() {
        #expect(composer.placement(for: 1.05, in: sentence).gap == 2)
        #expect(composer.placement(for: 1.35, in: sentence).gap == 3)
    }

    @Test func exactMiddleOfAWordGoesAfterIt() {
        #expect(composer.placement(for: 1.2, in: sentence).gap == 3)
    }

    @Test func beforeTheFirstWordAndAfterTheLast() {
        let late = words([("hello", 1.0...1.5), ("there", 1.6...2.0), ("friend", 2.1...2.6)])
        #expect(composer.placement(for: 0.1, in: late).gap == 0)
        #expect(composer.placement(for: 30, in: late).gap == 3)
    }

    @Test func noWordsPutsEverythingAtTheStart() {
        #expect(composer.placement(for: 5, in: []) == Placement(gap: 0, leading: false))
    }

    @Test func nearbySentenceEndWinsOverAGapMidSentence() {
        let speech = words([("Look", 0...0.3), ("here.", 0.4...0.8), ("The", 0.9...1.1), ("padding", 1.2...1.6)])
        // Nearest is the gap after "The" (1.15), but the sentence end at 0.8–0.9 is within 0.6 s.
        #expect(composer.placement(for: 1.15, in: speech).gap == 2)
        // Too far from the sentence end: stays where it was.
        #expect(composer.placement(for: 1.65, in: speech).gap == 4)
    }

    @Test func lateHalfOfAPauseLeadsTheNextParagraph() {
        let speech = words([("Done.", 0...0.5), ("Next", 4.0...4.4)])
        #expect(composer.placement(for: 1.0, in: speech) == Placement(gap: 1, leading: false))
        #expect(composer.placement(for: 3.5, in: speech) == Placement(gap: 1, leading: true))
    }
}

struct BundleComposerTests {
    let composer = BundleComposer()

    @Test func splicesMarkersWhereYouAddedThem() {
        let session = Session(words: sentence, annotations: [shot("a", at: 1.45)])
        let bundle = composer.compose(session)
        #expect(bundle.text == "the button here [1] looks off\n\nAttachments:\n[1] Image: /tmp/koe/a.png")
        #expect(bundle.assets.map(\.number) == [1])
    }

    @Test func numbersFollowTheTextNotTheOrderAdded() {
        // A file dropped late but stamped early (rare, but the clock decides) still reads first.
        let late = shot("late", at: 2.45)
        let early = shot("early", at: 0.45)
        let bundle = composer.compose(Session(words: sentence, annotations: [late, early]))
        #expect(bundle.text.hasPrefix("the [1] button here looks off [2]"))
        #expect(bundle.assets.map(\.asset.url.lastPathComponent) == ["early.png", "late.png"])
        #expect(bundle.assets.map(\.annotationID) == [early.id, late.id])
    }

    @Test func annotationsInOneGapKeepTheirTimeOrder() {
        let first = shot("first", at: 1.42)
        let second = shot("second", at: 1.41)
        let bundle = composer.compose(Session(words: sentence, annotations: [first, second]))
        #expect(bundle.assets.map(\.asset.url.lastPathComponent) == ["second.png", "first.png"])
    }

    @Test func sameTimeKeepsTheOrderAdded() {
        let first = shot("first", at: 1.45)
        let second = shot("second", at: 1.45)
        let bundle = composer.compose(Session(words: sentence, annotations: [first, second]))
        #expect(bundle.assets.map(\.annotationID) == [first.id, second.id])
    }

    @Test func notesReadInlineAndAttachmentsCarryTheirNote() {
        let session = Session(words: sentence, annotations: [
            Annotation(time: 0.95, kind: .note, note: "  the primary one "),
            shot("pad", at: 2.45, note: "padding is 8, should be 12"),
        ])
        let bundle = composer.compose(session)
        #expect(bundle.text.hasPrefix("the button [Note: the primary one] here looks off [1: padding is 8, should be 12]"))
        #expect(bundle.assets.count == 1)
    }

    @Test func emptyNoteWithNothingAttachedIsDropped() {
        let session = Session(words: sentence, annotations: [Annotation(time: 1, kind: .note, note: "   ")])
        #expect(composer.compose(session).text == "the button here looks off")
    }

    @Test func footerNamesTheAppAndWindow() {
        let session = Session(words: sentence, annotations: [
            shot("a", at: 0.45, source: CaptureSource(app: "Safari", window: "Settings")),
            Annotation(time: 2.45, kind: .clip(Asset(url: URL(fileURLWithPath: "/tmp/koe/clip.mov"))), source: CaptureSource(app: "Figma")),
            Annotation(time: 2.45, kind: .file(Asset(url: URL(fileURLWithPath: "/tmp/koe/spec.pdf")))),
        ])
        let footer = composer.compose(session).text.components(separatedBy: "Attachments:\n")[1]
        #expect(footer == """
        [1] Image of Safari, "Settings": /tmp/koe/a.png
        [2] Video of Figma: /tmp/koe/clip.mov
        [3] File: /tmp/koe/spec.pdf
        """)
    }

    @Test func longPauseAfterASentenceStartsAParagraph() {
        let speech = words([("First", 0...0.3), ("point.", 0.4...0.8), ("Second", 4.0...4.4), ("point.", 4.5...4.9)])
        let session = Session(words: speech, annotations: [shot("a", at: 1.0), shot("b", at: 3.8)])
        #expect(composer.compose(session).text.hasPrefix("First point. [1]\n\n[2] Second point."))
    }

    @Test func longPauseMidSentenceStaysInOneParagraph() {
        let speech = words([("so", 0...0.3), ("this", 4.0...4.3)])
        #expect(composer.compose(Session(words: speech)).text == "so this")
    }

    @Test func noSpeechStillListsEverythingInOrder() {
        let session = Session(annotations: [shot("b", at: 2), shot("a", at: 1)])
        let bundle = composer.compose(session)
        #expect(bundle.text.hasPrefix("[1] [2]\n\nAttachments:"))
        #expect(bundle.assets.map(\.asset.url.lastPathComponent) == ["a.png", "b.png"])
    }

    @Test func emptySessionIsEmpty() {
        let bundle = composer.compose(Session())
        #expect(bundle.text.isEmpty)
        #expect(bundle.html.isEmpty)
        #expect(bundle.assets.isEmpty)
    }

    @Test func htmlEscapesTextAndLeavesImagesToTheFiles() {
        let speech = words([("a<b", 0...0.3), ("&", 0.4...1.6)])
        let session = Session(words: speech, annotations: [
            shot("x", at: 0.35, note: "\"quoted\""),
            Annotation(time: 1.7, kind: .clip(Asset(url: URL(fileURLWithPath: "/tmp/koe/c.mov")))),
        ])
        let html = composer.compose(session).html
        #expect(html.hasPrefix("<p>a&lt;b <b>[1: &quot;quoted&quot;]</b> &amp; <b>[2]</b></p>"))
        #expect(!html.contains("<img"))
        #expect(html.contains("<li>[2] Video: <a href=\"file:///tmp/koe/c.mov\">/tmp/koe/c.mov</a></li>"))
    }
}
