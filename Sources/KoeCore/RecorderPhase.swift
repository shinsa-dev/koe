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

/// When a stopped session can be copied. Koe gives the model a moment to settle the last words, as a copy made
/// before then can miss them, then copies with what it has and refines the copy when they settle. It waits longer
/// only for a tool you still have open, or when the model has not produced a single word yet but is still working.
public enum Delivery: Sendable, Equatable {
    /// A tool is still open on the session: its annotation belongs in the copy.
    case wait
    /// The model is settling the last words: copy once it has, or once the short wait for them is over.
    case waitForWords
    /// Copy now. `final` when the transcript is settled, so no refinement follows.
    case deliver(final: Bool)
    /// The short wait is over, nothing is heard yet and the model is still catching up: the session ends now and
    /// copies once it has the words.
    case whenSettled

    public static func decide(openTools: Int, hasContent: Bool, transcriptDone: Bool, waitedForWords: Bool)
        -> Delivery {
        guard openTools == 0 else { return .wait }
        if transcriptDone { return .deliver(final: true) }
        guard waitedForWords else { return .waitForWords }
        return hasContent ? .deliver(final: false) : .whenSettled
    }
}

/// What happens to a session that ends with no words and no attachments. Only a model that settled the whole
/// recording and heard nothing proves it was silence; one that gave up waiting may still hear words in the audio.
public enum EmptyEnding: Sendable, Equatable {
    /// "We couldn't hear you": the folder and its audio go.
    case discard
    /// The folder stays as an unfinished recording, which launch recovery transcribes.
    case keep

    public static func decide(modelSettled: Bool) -> EmptyEnding {
        modelSettled ? .discard : .keep
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
