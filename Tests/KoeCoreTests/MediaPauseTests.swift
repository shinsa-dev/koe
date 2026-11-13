import KoeCore
import Testing

struct MediaPauseTests {
    private let loud: Float = 0.2
    private let quiet: Float = 0

    @Test func pausesWhatPlaysAndPlaysItAgainWhenTheSessionCloses() {
        var pause = MediaPause()
        func step<T>(_ call: (inout MediaPause) -> T) -> T { call(&pause) }
        #expect(step { $0.sessionOpened(enabled: true, allowed: true, streamsOpen: true) })
        #expect(step { $0.heard(peak: loud) } == .pause)
        #expect(step { $0.settled(peak: quiet) } == nil)
        #expect(step { $0.sessionClosed() } == .play)
        #expect(step { $0.sessionClosed() } == nil)
    }

    @Test(arguments: [(false, true, true), (true, false, true), (true, true, false)])
    func listensOnlyWhenOnAllowedAndSomethingHasAStream(enabled: Bool, allowed: Bool, streamsOpen: Bool) {
        var pause = MediaPause()
        func step<T>(_ call: (inout MediaPause) -> T) -> T { call(&pause) }
        #expect(!step { $0.sessionOpened(enabled: enabled, allowed: allowed, streamsOpen: streamsOpen) })
        #expect(step { $0.heard(peak: loud) } == nil)
        #expect(step { $0.sessionClosed() } == nil)
    }

    @Test func silenceIsNeverPausedOrPlayed() {
        var pause = MediaPause()
        func step<T>(_ call: (inout MediaPause) -> T) -> T { call(&pause) }
        #expect(step { $0.sessionOpened(enabled: true, allowed: true, streamsOpen: true) })
        #expect(step { $0.heard(peak: MediaPause.silence / 2) } == nil)
        #expect(step { $0.sessionClosed() } == nil)
    }

    @Test func soundThePauseDidNotStopIsNeverPlayed() {
        var pause = MediaPause()
        func step<T>(_ call: (inout MediaPause) -> T) -> T { call(&pause) }
        _ = step { $0.sessionOpened(enabled: true, allowed: true, streamsOpen: true) }
        #expect(step { $0.heard(peak: loud) } == .pause)
        #expect(step { $0.settled(peak: loud) } == nil)
        #expect(step { $0.sessionClosed() } == nil)
    }

    @Test func aSessionClosedBeforeThePauseNeverPauses() {
        var pause = MediaPause()
        func step<T>(_ call: (inout MediaPause) -> T) -> T { call(&pause) }
        _ = step { $0.sessionOpened(enabled: true, allowed: true, streamsOpen: true) }
        #expect(step { $0.sessionClosed() } == nil)
        #expect(step { $0.heard(peak: loud) } == nil)
    }

    @Test func aSessionClosedWhileThePauseSettlesPlaysOnceItSettles() {
        var pause = MediaPause()
        func step<T>(_ call: (inout MediaPause) -> T) -> T { call(&pause) }
        _ = step { $0.sessionOpened(enabled: true, allowed: true, streamsOpen: true) }
        #expect(step { $0.heard(peak: loud) } == .pause)
        #expect(step { $0.sessionClosed() } == nil)
        #expect(step { $0.settled(peak: quiet) } == .play)
    }

    @Test func aNewSessionKeepsWhatKoePausedPausedWithoutListeningAgain() {
        var pause = MediaPause()
        func step<T>(_ call: (inout MediaPause) -> T) -> T { call(&pause) }
        _ = step { $0.sessionOpened(enabled: true, allowed: true, streamsOpen: true) }
        #expect(step { $0.heard(peak: loud) } == .pause)
        #expect(step { $0.sessionClosed() } == nil)
        #expect(!step { $0.sessionOpened(enabled: true, allowed: true, streamsOpen: true) })
        #expect(step { $0.settled(peak: quiet) } == nil)
        #expect(step { $0.sessionClosed() } == .play)
    }

    @Test func aNewSessionAfterAPlayListensAgain() {
        var pause = MediaPause()
        func step<T>(_ call: (inout MediaPause) -> T) -> T { call(&pause) }
        _ = step { $0.sessionOpened(enabled: true, allowed: true, streamsOpen: true) }
        _ = step { $0.heard(peak: loud) }
        _ = step { $0.settled(peak: quiet) }
        #expect(step { $0.sessionClosed() } == .play)
        #expect(step { $0.sessionOpened(enabled: true, allowed: true, streamsOpen: true) })
    }
}
