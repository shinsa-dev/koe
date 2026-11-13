import Foundation

/// Pauses what plays while you dictate, and plays it again when you finish. macOS doesn't tell apps what is playing,
/// so Koe listens to the Mac's output: it pauses only when it hears sound, and plays again only when its pause made
/// the sound stop. So it never starts something you had paused yourself.
///
/// A session opens, Koe listens (`listen`), pauses on sound (`heard`), listens again once the player has had time to
/// stop (`settled`), and plays when the session closes (`sessionClosed`). A session can close at any step.
public struct MediaPause: Sendable, Equatable {
    /// Below this peak the output counts as silent: about -60 dB.
    public static let silence: Float = 0.001

    public enum Command: Sendable, Equatable { case pause, play }

    enum State: Sendable, Equatable {
        case idle
        /// Listening for sound before pausing.
        case listening
        /// Paused; listening for the sound to stop.
        case pausing
        /// Koe's pause silenced the output, so Koe plays it again when the session closes.
        case holding
    }

    private(set) var state = State.idle
    private(set) var sessionOpen = false

    public init() {}

    /// A session opened. Says whether to listen for sound: only when the setting is on, Koe may hear the Mac's
    /// output and another app has an audio stream open. Something Koe already paused stays paused.
    public mutating func sessionOpened(enabled: Bool, allowed: Bool, streamsOpen: Bool) -> Bool {
        sessionOpen = true
        guard state == .idle, enabled, allowed, streamsOpen else { return false }
        state = .listening
        return true
    }

    /// What Koe heard before pausing. Pauses on sound, unless the session closed meanwhile.
    public mutating func heard(peak: Float) -> Command? {
        guard state == .listening else { return nil }
        guard sessionOpen, peak >= Self.silence else {
            state = .idle
            return nil
        }
        state = .pausing
        return .pause
    }

    /// What Koe heard once the pause had time to land. Silence means the pause stopped the sound, so it is Koe's to
    /// undo: at once when the session closed meanwhile, otherwise when it closes.
    public mutating func settled(peak: Float) -> Command? {
        guard state == .pausing else { return nil }
        guard peak < Self.silence else {
            state = .idle
            return nil
        }
        if sessionOpen {
            state = .holding
            return nil
        }
        state = .idle
        return .play
    }

    /// The session closed: plays what Koe paused. A pause still settling plays once it does.
    public mutating func sessionClosed() -> Command? {
        sessionOpen = false
        guard state == .holding else { return nil }
        state = .idle
        return .play
    }
}
