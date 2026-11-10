import CoreGraphics
import Foundation
import KoeCore
import Testing

/// A clip where the screen changed at 0, 0.1, 0.25 and 0.7 s, and that ran for 1 s.
private let frames = ClipFrames(times: [0.25, 0, 0.7, 0.1, 0.1], duration: 1)

struct ClipFramesTests {
    @Test func framesAreSortedOnceEach() {
        #expect(frames.times == [0, 0.1, 0.25, 0.7])
        #expect(frames.count == 4)
    }

    @Test func theFrameOnScreenIsTheLastOneThatAppeared() {
        #expect(frames.index(at: 0.05) == 0)
        #expect(frames.index(at: 0.1) == 1)
        #expect(frames.index(at: 0.69) == 2)
        #expect(frames.index(at: 0.95) == 3)
        #expect(frames.index(at: -1) == 0)
        #expect(frames.index(at: 5) == 3)
    }

    @Test func steppingGoesChangeByChangeAndStopsAtTheEnds() {
        #expect(frames.step(from: 1, by: 1) == 2)
        #expect(frames.step(from: 0, by: -1) == 0)
        #expect(frames.step(from: 3, by: 1) == 3)
        #expect(frames.step(from: 1, by: 10) == 3)
    }

    @Test func seekingAimsAtTheMiddleOfAFrame() {
        #expect(frames.seekTime(of: 0) == 0.05)
        #expect(abs(frames.seekTime(of: 2) - 0.475) < 1e-9)
        #expect(abs(frames.seekTime(of: 3) - 0.85) < 1e-9)
    }

    @Test func theScrubberMapsBothWays() {
        #expect(frames.fraction(of: 2) == 0.25)
        #expect(frames.index(atFraction: 0.3) == 2)
        #expect(frames.index(atFraction: 2) == 3)
        #expect(frames.index(atFraction: -1) == 0)
    }

    @Test func theDurationCoversTheLastFrame() {
        #expect(ClipFrames(times: [0, 2], duration: 1).duration == 2)
    }

    @Test func anEmptyClipStaysAtZero() {
        let empty = ClipFrames(times: [], duration: 0)
        #expect(empty.index(at: 3) == 0)
        #expect(empty.time(of: 4) == 0)
        #expect(empty.seekTime(of: 1) == 0)
        #expect(empty.fraction(of: 0) == 0)
    }

    @Test func aClipOpensAtFullSpeed() {
        #expect(PlaybackSpeed.initial == .normal)
        #expect(PlaybackSpeed.allCases.map(\.label) == ["1×", "0.5×", "0.25×", "0.1×"])
    }
}

struct ClipReviewTests {
    @Test func picksStayInClipOrderAndOnceEach() {
        var review = ClipReview(frames: frames)
        let first = review.pick(3)
        let second = review.pick(1)
        let again = review.pick(3)
        #expect(first && second && !again)
        #expect(review.picks.map(\.index) == [1, 3])
        #expect(review.picks.map(\.time) == [0.1, 0.7])
        #expect(review.isPicked(1))
    }

    @Test func aPickOutsideTheClipTakesTheNearestEnd() {
        var review = ClipReview(frames: frames)
        review.pick(9)
        #expect(review.picks.map(\.index) == [3])
    }

    @Test func nothingToPickInAnEmptyClip() {
        var review = ClipReview(frames: ClipFrames(times: [], duration: 0))
        let picked = review.pick(0)
        #expect(!picked)
        #expect(review.picks.isEmpty)
    }

    @Test func unpickingAndNotes() {
        var review = ClipReview(frames: frames)
        review.pick(1)
        review.pick(2)
        review.setNote("The menu jumps here", for: 2)
        review.setNote("ignored", for: 0)
        review.unpick(1)
        #expect(review.picks == [PickedFrame(index: 2, time: 0.25, note: "The menu jumps here")])
    }

    @Test func theClipComesFirstAndEachFrameLandsWhenItShowed() throws {
        var review = ClipReview(frames: frames)
        review.pick(3)
        review.pick(1)
        review.setNote("Starts here", for: 1)
        let clip = Asset(url: URL(fileURLWithPath: "/s/clip-1.mov"))
        let assets = [1: Asset(url: URL(fileURLWithPath: "/s/clip-1-frame-2.png")),
                      3: Asset(url: URL(fileURLWithPath: "/s/clip-1-frame-4.png"))]
        let source = CaptureSource(app: "Figma")
        let result = review.annotations(clip: clip, frameAssets: assets, recordingStart: 1.5, source: source)

        #expect(result.map(\.after) == [1.5, 1.6, 2.2])
        let first = try #require(result.first?.annotation)
        #expect(first.kind == .clip(clip))
        #expect(result[1].annotation.kind == .screenshot(assets[1]!))
        #expect(result[1].annotation.note == "Starts here")
        #expect(result[1].annotation.frame == ClipFrame(clipID: first.id, time: 0.1))
        #expect(result.allSatisfy { $0.annotation.source == source })
    }

    @Test func aFrameWhoseImageFailedIsLeftOut() {
        var review = ClipReview(frames: frames)
        review.pick(1)
        let result = review.annotations(clip: Asset(url: URL(fileURLWithPath: "/s/c.mov")), frameAssets: [:], recordingStart: 0)
        #expect(result.count == 1)
    }
}

struct ClipBundleTests {
    @Test func aFrameNamesTheClipItCameFrom() {
        let clipURL = URL(fileURLWithPath: "/s/clip-1.mov")
        let frameURL = URL(fileURLWithPath: "/s/clip-1-frame-4.png")
        let clip = Annotation(time: 0.5, kind: .clip(Asset(url: clipURL)), source: CaptureSource(app: "Figma"))
        let frame = Annotation(time: 1.2, kind: .screenshot(Asset(url: frameURL)), note: "Jumps here",
                               source: CaptureSource(app: "Figma"), frame: ClipFrame(clipID: clip.id, time: 0.7))
        let session = Session(words: [TimedWord("watch", start: 0, end: 0.4), TimedWord("this.", start: 0.6, end: 1)],
                              annotations: [frame, clip])
        let text = BundleComposer().compose(session).text
        #expect(text == """
        watch this. [1] [2: Jumps here]

        Attachments:
        [1] Video of Figma: /s/clip-1.mov
        [2] Frame 0.70 s into [1], of Figma: /s/clip-1-frame-4.png
        """)
    }

    @Test func aFrameWithoutItsClipStillSaysWhatItIs() {
        let frame = Annotation(time: 0, kind: .screenshot(Asset(url: URL(fileURLWithPath: "/s/f.png"))),
                               frame: ClipFrame(clipID: UUID(), time: 1.25))
        #expect(BundleComposer().compose(Session(annotations: [frame])).text.hasSuffix("[1] Frame 1.25 s into a clip: /s/f.png"))
    }

    @Test func aSessionWithAFrameRoundTripsThroughJSON() throws {
        let frame = Annotation(time: 1, kind: .screenshot(Asset(url: URL(fileURLWithPath: "/s/f.png"))),
                               frame: ClipFrame(clipID: UUID(), time: 0.3))
        let session = Session(annotations: [frame])
        #expect(try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(session)) == session)
    }
}

struct ClipLedgerTests {
    @Test func aClipAndItsFramesAreStampedAfterTheTicket() {
        var ledger = AnnotationLedger()
        let ticket = ledger.open(at: 3)
        let note = Annotation(time: 99, kind: .note, note: "x")
        let closed = ledger.close(ticket, with: [(annotation: note, after: 0.5), (annotation: note, after: -2)])
        let twice = ledger.close(ticket, with: [(annotation: note, after: 1)])
        #expect(closed && !twice)
        #expect(ledger.annotations.map(\.time) == [3.5, 3])
        #expect(ledger.openCount == 0)
    }

    @Test func cancellingAClipAttachesNothing() {
        var ledger = AnnotationLedger()
        let ticket = ledger.open(at: 1)
        ledger.close(ticket, with: [])
        ledger.endTranscript()
        #expect(ledger.annotations.isEmpty)
        #expect(ledger.isSettled)
    }
}

struct ClipFilesTests {
    @Test func clipsAndTheirFramesAreNamedAfterEachOther() {
        var folder = SessionFolder(url: URL(fileURLWithPath: "/tmp/s"))
        let clip = folder.nextClip()
        let frame = folder.frame(24, of: clip)
        let second = folder.nextClip()
        #expect([clip, frame, second].map(\.lastPathComponent) == ["clip-1.mov", "clip-1-frame-25.png", "clip-2.mov"])
    }

    @Test(arguments: [
        (CGSize(width: 101, height: 50), 1.0, 100, 50),
        (CGSize(width: 100.4, height: 33.3), 2.0, 200, 66),
        (CGSize(width: 0.2, height: 0), 2.0, 2, 2),
        (CGSize(width: 10, height: 10), 0.5, 10, 10),
    ])
    func recordingSizesAreWholeAndEven(size: CGSize, scale: CGFloat, width: Int, height: Int) {
        let pixels = ScreenGeometry.recordingPixels(of: size, scale: scale)
        #expect(pixels.width == width)
        #expect(pixels.height == height)
    }

    @Test func theClipShortcutIsR() {
        #expect(KeyCombo.clip.displayName == "R")
    }
}

struct ClipScriptTests {
    @Test func parsesPauseFinishAndCancel() throws {
        #expect(try ScriptedStep.parse("1 pause 2.5; 4 finish; 5 cancel") == [
            ScriptedStep(time: 1, action: .pause(seconds: 2.5)),
            ScriptedStep(time: 4, action: .finish),
            ScriptedStep(time: 5, action: .cancel),
        ])
        #expect(throws: ScriptedStep.ParseError.self) { try ScriptedStep.parse("1 pause") }
    }

    @Test func parsesOpeningTheAttachmentList() throws {
        #expect(try ScriptedStep.parse("3 list") == [ScriptedStep(time: 3, action: .attachments)])
    }

    @Test func parsesAClipWithPicks() throws {
        let steps = try ScriptedStep.parse("6 clip! 120,80,640,360 2 0.4,1.1; 2 clip 0,0,10,10 1.5")
        #expect(steps == [
            ScriptedStep(time: 2, action: .clip(CGRect(x: 0, y: 0, width: 10, height: 10), seconds: 1.5, picks: [])),
            ScriptedStep(time: 6, action: .clip(CGRect(x: 120, y: 80, width: 640, height: 360), seconds: 2, picks: [0.4, 1.1]),
                         holds: true),
        ])
    }

    @Test(arguments: ["1 clip 0,0,10,10", "1 clip 0,0,10,10 0", "1 clip 0,0,10 2", "1 clip 0,0,10,10 2 0.1 extra"])
    func rejectsABadClip(_ script: String) {
        #expect(throws: ScriptedStep.ParseError.self) { try ScriptedStep.parse(script) }
    }
}

struct ClipQualityTests {
    @Test func recordsAtTheScreensRefreshRate() {
        #expect(ClipQuality.frameRate(ofScreen: 60) == 60)
        #expect(ClipQuality.frameRate(ofScreen: 120) == 120)
        #expect(ClipQuality.frameRate(ofScreen: 30) == 60)
        #expect(ClipQuality.frameRate(ofScreen: 240) == 120)
    }

    @Test func theBitRateFollowsThePictureWithinItsBounds() {
        #expect(ClipQuality.bitRate(width: 1600, height: 1000, frameRate: 60) == 7_680_000)
        #expect(ClipQuality.bitRate(width: 200, height: 100, frameRate: 60) == 6_000_000)
        #expect(ClipQuality.bitRate(width: 5120, height: 2880, frameRate: 120) == 32_000_000)
    }

    @Test func aRegionPastH264sLimitIsHEVC() {
        #expect(ClipQuality.fitsH264(width: 4096, height: 2304))
        #expect(!ClipQuality.fitsH264(width: 5120, height: 2880))
        #expect(!ClipQuality.fitsH264(width: 1000, height: 2400))
    }
}
