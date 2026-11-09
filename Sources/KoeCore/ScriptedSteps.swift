import CoreGraphics
import Foundation

/// Steps `--script` plays into a session at given audio times, so the tools can be tried and captured without
/// hands: `1.5 shot 120,80,640,360 The padding is off; 3 note Compare with Finder; 4 drop /tmp/spec.pdf`.
/// `6 clip 120,80,640,360 2 0.4,1.1` records that region for 2 s and picks the frames on screen 0.4 s and 1.1 s in.
/// `2 pin 400,300 Too tight` comments on the spot at 400,300 as if clicked.
/// `shot!`, `pin!`, `note!` and `clip!` open the tool and leave it open. `2 pause 3` pauses for 3 s of wall time and resumes;
/// `4 finish` and `4 cancel` finish or discard the session.
public struct ScriptedStep: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        /// A region in the screen's own space (points from its top-left), and the note typed for it.
        case screenshot(CGRect, note: String?)
        /// A spot in the screen's own space, as if clicked with the comment tool, and the comment typed for it.
        case comment(CGPoint, note: String?)
        case note(String)
        case drop(String)
        /// A region to record for `seconds`, and the times into the clip whose frames to pick.
        case clip(CGRect, seconds: AudioTime, picks: [AudioTime])
        case pause(seconds: TimeInterval)
        case finish
        case cancel
    }

    public var time: AudioTime
    public var action: Action
    /// Leaves the tool open instead of finishing it.
    public var holds: Bool

    public init(time: AudioTime, action: Action, holds: Bool = false) {
        self.time = time
        self.action = action
        self.holds = holds
    }

    public enum ParseError: Error, Equatable {
        case badStep(String)
    }

    public static func parse(_ script: String) throws -> [ScriptedStep] {
        try script.split(separator: ";").compactMap { raw in
            let step = raw.trimmingCharacters(in: .whitespaces)
            guard !step.isEmpty else { return nil }
            let parts = step.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count >= 2, let time = AudioTime(parts[0]), time >= 0 else { throw ParseError.badStep(step) }
            let rest = parts.count > 2 ? parts[2] : nil
            let holds = parts[1].hasSuffix("!")
            let kind = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "!"))
            guard let action = action(kind, rest) else { throw ParseError.badStep(step) }
            return ScriptedStep(time: time, action: action, holds: holds && kind != "drop")
        }
        .sorted { $0.time < $1.time }
    }

    private static func action(_ kind: String, _ rest: String?) -> Action? {
        switch kind {
        case "shot":
            let pieces = rest?.split(separator: " ", maxSplits: 1).map(String.init) ?? []
            guard let rect = pieces.first.flatMap(rect) else { return nil }
            return .screenshot(rect, note: pieces.count > 1 ? pieces[1] : nil)
        case "pin":
            let pieces = rest?.split(separator: " ", maxSplits: 1).map(String.init) ?? []
            let numbers = pieces.first?.split(separator: ",").compactMap { Double($0) } ?? []
            guard numbers.count == 2 else { return nil }
            return .comment(CGPoint(x: numbers[0], y: numbers[1]), note: pieces.count > 1 ? pieces[1] : nil)
        case "clip":
            let pieces = rest?.split(separator: " ").map(String.init) ?? []
            guard pieces.count >= 2, pieces.count <= 3, let rect = rect(pieces[0]),
                  let seconds = AudioTime(pieces[1]), seconds > 0 else { return nil }
            let picks = pieces.count == 3 ? pieces[2].split(separator: ",").compactMap { AudioTime($0) } : []
            return .clip(rect, seconds: seconds, picks: picks)
        case "note":
            return rest.map(Action.note)
        case "drop":
            return rest.map(Action.drop)
        default:
            return control(kind, rest)
        }
    }

    private static func control(_ kind: String, _ rest: String?) -> Action? {
        switch kind {
        case "pause":
            guard let seconds = rest.flatMap({ TimeInterval($0) }), seconds > 0 else { return nil }
            return .pause(seconds: seconds)
        case "finish": return .finish
        case "cancel": return .cancel
        default: return nil
        }
    }

    private static func rect(_ text: String) -> CGRect? {
        let numbers = text.split(separator: ",").compactMap { Double($0) }
        guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }
}
