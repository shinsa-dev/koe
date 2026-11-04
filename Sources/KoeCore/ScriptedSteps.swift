import CoreGraphics
import Foundation

/// Steps `--script` plays into a session at given audio times, so the tools can be tried and captured without
/// hands: `1.5 shot 120,80,640,360 The padding is off; 3 note Compare with Finder; 4 drop /tmp/spec.pdf`.
/// `shot!` and `note!` open the tool and leave it open.
public struct ScriptedStep: Sendable, Equatable {
    public enum Action: Sendable, Equatable {
        /// A region in the screen's own space (points from its top-left), and the note typed for it.
        case screenshot(CGRect, note: String?)
        case note(String)
        case drop(String)
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
            switch parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "!")) {
            case "shot":
                let pieces = rest?.split(separator: " ", maxSplits: 1).map(String.init) ?? []
                let numbers = pieces.first?.split(separator: ",").compactMap { Double($0) } ?? []
                guard numbers.count == 4, numbers[2] > 0, numbers[3] > 0 else { throw ParseError.badStep(step) }
                let rect = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
                return ScriptedStep(time: time, action: .screenshot(rect, note: pieces.count > 1 ? pieces[1] : nil), holds: holds)
            case "note":
                guard let rest else { throw ParseError.badStep(step) }
                return ScriptedStep(time: time, action: .note(rest), holds: holds)
            case "drop":
                guard let rest else { throw ParseError.badStep(step) }
                return ScriptedStep(time: time, action: .drop(rest))
            default:
                throw ParseError.badStep(step)
            }
        }
        .sorted { $0.time < $1.time }
    }
}
