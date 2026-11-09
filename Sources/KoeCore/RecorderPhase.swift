import Foundation

/// Where a dictation session stands. Recording starts the moment you press the hotkey: the microphone opens at once
/// and the speech model catches up on what it missed, so there is no "getting ready".
public enum RecorderPhase: Sendable, Equatable {
    case idle
    case recording
    /// The microphone is closed until you resume; the clock stops with it.
    case paused
    /// Stopped, waiting only for a tool you still have open, or for the first words of a very short session.
    case finishing
    case failed(String)

    public enum Intent: Sendable, Equatable { case start, stop, ignore }

    /// What pressing the hotkey does now. While a session finishes, a press waits for it rather than start another.
    public var toggleIntent: Intent {
        switch self {
        case .idle, .failed: .start
        case .recording, .paused: .stop
        case .finishing: .ignore
        }
    }

    public var isActive: Bool {
        switch self {
        case .recording, .paused, .finishing: true
        case .idle, .failed: false
        }
    }

    /// Recording or paused: the session still takes audio, attachments, a pause or a cancel.
    public var isOpen: Bool { self == .recording || self == .paused }
}

/// When a stopped session can be copied. Koe copies at once with the words it has heard so far, including the
/// model's latest guess, and refines the copy when the last words settle. It waits only for a tool you still have
/// open, or when the model has not produced a single word yet but is still working.
public enum Delivery: Sendable, Equatable {
    case wait
    /// Copy now. `final` when the transcript is settled, so no refinement follows.
    case deliver(final: Bool)

    public static func decide(openTools: Int, hasWords: Bool, transcriptDone: Bool) -> Delivery {
        guard openTools == 0 else { return .wait }
        if transcriptDone { return .deliver(final: true) }
        return hasWords ? .deliver(final: false) : .wait
    }
}

public enum Elapsed {
    /// A session clock: "0:07", "12:30", "1:02:05".
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = total / 60 % 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
