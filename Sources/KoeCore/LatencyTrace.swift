import Foundation

/// When each stage of one session's start and finish happened, in seconds on one monotonic clock. Starting is
/// measured from the shortcut to the pill showing and the recording open; finishing from the shortcut to the words on
/// the clipboard. Each must take at most `budget`.
public struct LatencyTrace: Sendable, Equatable {
    public enum Stage: String, CaseIterable, Sendable {
        case startPressed, captureOpen, pillShown, deviceStarted, firstAudio
        case finishPressed, audioEnded, lastPassStarted, lastPassDone, delivered, copied

        public var name: String {
            switch self {
            case .startPressed, .finishPressed: "shortcut"
            case .captureOpen: "recording open"
            case .pillShown: "pill shown"
            case .deviceStarted: "device started"
            case .firstAudio: "first audio"
            case .audioEnded: "audio ended"
            case .lastPassStarted: "last pass started"
            case .lastPassDone: "last pass done"
            case .delivered: "delivered"
            case .copied: "copied"
            }
        }

        /// The stages that count toward starting: what you wait for before you can talk.
        static let start: [Stage] = [.captureOpen, .pillShown]
        /// Reported after a start, but the device's own warm-up isn't part of the cap.
        static let afterStart: [Stage] = [.deviceStarted, .firstAudio]
        static let finish: [Stage] = [.audioEnded, .lastPassStarted, .lastPassDone, .delivered, .copied]
    }

    public static let budget: TimeInterval = 0.05

    public private(set) var marks: [Stage: TimeInterval] = [:]

    public init(marks: [Stage: TimeInterval] = [:]) {
        self.marks = marks
    }

    /// Records a stage. Only the first time counts: a pill shown again for the copy's notice is not the start.
    public mutating func mark(_ stage: Stage, at time: TimeInterval) {
        if marks[stage] == nil { marks[stage] = time }
    }

    /// Seconds from the shortcut to the pill and the recording, whichever came last.
    public var start: TimeInterval? {
        guard let pressed = marks[.startPressed] else { return nil }
        let reached = Stage.start.compactMap { marks[$0] }
        guard reached.count == Stage.start.count, let last = reached.max() else { return nil }
        return last - pressed
    }

    /// Seconds from the shortcut to the words on the clipboard.
    public var finish: TimeInterval? {
        guard let pressed = marks[.finishPressed], let copied = marks[.copied] else { return nil }
        return copied - pressed
    }

    /// Each start stage reached, as seconds since the shortcut, in order.
    public var startStages: [(stage: Stage, after: TimeInterval)] {
        stages(Stage.start + Stage.afterStart, since: .startPressed)
    }

    /// Each finish stage reached, as seconds since the shortcut, in order.
    public var finishStages: [(stage: Stage, after: TimeInterval)] {
        stages(Stage.finish, since: .finishPressed)
    }

    /// Whether both start and finish are measured and within the budget.
    public var meetsBudget: Bool {
        guard let start, let finish else { return false }
        return start <= Self.budget && finish <= Self.budget
    }

    /// The stage that took longest to follow the one before it, where the time went when the budget was missed.
    public var slowestStep: (stage: Stage, took: TimeInterval)? {
        let steps = [(Stage.startPressed, Stage.start), (Stage.finishPressed, Stage.finish)].flatMap { pressed, stages in
            zip([pressed] + stages, stages).compactMap { before, stage -> (Stage, TimeInterval)? in
                guard let from = marks[before], let until = marks[stage] else { return nil }
                return (stage, until - from)
            }
        }
        return steps.max { $0.1 < $1.1 }
    }

    /// "start 12.3 ms (recording open 3.1, pill shown 12.3, first audio 410.2) · finish 1534.0 ms (…)".
    public var summary: String {
        func part(_ name: String, _ total: TimeInterval?, _ stages: [(stage: Stage, after: TimeInterval)]) -> String {
            let list = stages.map { "\($0.stage.name) \(Self.ms($0.after))" }
            return "\(name) \(total.map(Self.ms).map { "\($0) ms" } ?? "not measured") (\(list.joined(separator: ", ")))"
        }
        return part("start", start, startStages) + " · " + part("finish", finish, finishStages)
    }

    static func ms(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", seconds * 1000)
    }

    private func stages(_ stages: [Stage], since pressed: Stage) -> [(stage: Stage, after: TimeInterval)] {
        guard let from = marks[pressed] else { return [] }
        return stages.compactMap { stage in marks[stage].map { (stage, $0 - from) } }
    }
}

/// Many sessions' traces: the median and worst of each stage, and whether every session met the budget.
public struct LatencyReport: Sendable, Equatable {
    public let traces: [LatencyTrace]

    public init(_ traces: [LatencyTrace]) {
        self.traces = traces
    }

    public var meetsBudget: Bool { !traces.isEmpty && traces.allSatisfy(\.meetsBudget) }

    /// One line per stage: its median and worst time since the shortcut, in milliseconds.
    public var lines: [String] {
        let start = LatencyTrace.Stage.start + LatencyTrace.Stage.afterStart
        let rows: [(String, [TimeInterval])] =
            [("start", traces.compactMap(\.start))]
            + start.map { stage in ("  " + stage.name, traces.compactMap { $0.startStages.first { $0.stage == stage }?.after }) }
            + [("finish", traces.compactMap(\.finish))]
            + LatencyTrace.Stage.finish.map { stage in
                ("  " + stage.name, traces.compactMap { $0.finishStages.first { $0.stage == stage }?.after })
            }
        return rows.map { name, times in
            guard let worst = times.max() else { return "\(name): not measured" }
            return "\(name): median \(LatencyTrace.ms(Self.median(times))) ms, worst \(LatencyTrace.ms(worst)) ms"
        }
    }

    static func median(_ times: [TimeInterval]) -> TimeInterval {
        let sorted = times.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
