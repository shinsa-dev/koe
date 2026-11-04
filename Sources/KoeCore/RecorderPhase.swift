import Foundation

/// Where a dictation session stands. The hotkey and the pill's button both toggle it.
public enum RecorderPhase: Sendable, Equatable {
    case idle
    /// Loading the speech model and opening the microphone.
    case preparing
    case recording(since: Date)
    /// The microphone is closed and the last words are being settled.
    case finishing
    case failed(String)

    public enum Intent: Sendable, Equatable { case start, stop, ignore }

    /// What pressing the hotkey does now. While a session finishes, a press waits for it rather than start another.
    public var toggleIntent: Intent {
        switch self {
        case .idle, .failed: .start
        case .preparing, .recording: .stop
        case .finishing: .ignore
        }
    }

    public var isActive: Bool {
        switch self {
        case .preparing, .recording, .finishing: true
        case .idle, .failed: false
        }
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
