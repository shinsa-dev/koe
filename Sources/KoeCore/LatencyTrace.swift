import Foundation

/// When each stage of one session's start and finish happened, in seconds on one monotonic clock. Starting is
/// measured from the shortcut to the pill showing and the recording open; finishing from the shortcut to the words on
/// the clipboard. Each must take at most `budget`.
public struct LatencyTrace: Sendable, Equatable {
    public enum Stage: String, CaseIterable, Sendable {
        case startPressed, captureOpen, pillShown, deviceStarted, firstAudio
        case finishPressed, audioEnded, lastPassStarted, lastPassDone, delivered, copied, refined

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
            case .refined: "refined"
            }
        }

        /// The stages that count toward starting: what you wait for before you can talk.
        static let start: [Stage] = [.captureOpen, .pillShown]
        /// Reported after a start, but the device's own warm-up isn't part of the cap.
        static let afterStart: [Stage] = [.deviceStarted, .firstAudio]
        static let finish: [Stage] = [.audioEnded, .lastPassStarted, .lastPassDone, .delivered, .copied]
        /// The last pass's words replacing the copy, after the cap: reported, but not part of it.
        static let afterFinish: [Stage] = [.refined]
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
        stages(Stage.finish + Stage.afterFinish, since: .finishPressed)
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

    /// One line for the log when the session missed the budget, naming where the time went; nil when it met it or
    /// isn't measured yet.
    public var breach: String? {
        guard let start, let finish, !meetsBudget else { return nil }
        let slowest = slowestStep.map { ", slowest step \($0.stage.name) \(Self.ms($0.took)) ms" } ?? ""
        return "Over the \(Self.ms(Self.budget)) ms cap: start \(Self.ms(start)) ms, finish \(Self.ms(finish)) ms\(slowest)."
    }

    /// Seconds the last pass took, from the audio's end to its words.
    public var lastPass: TimeInterval? {
        guard let started = marks[.lastPassStarted], let done = marks[.lastPassDone] else { return nil }
        return done - started
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
            + (LatencyTrace.Stage.finish + LatencyTrace.Stage.afterFinish).map { stage in
                ("  " + stage.name, traces.compactMap { $0.finishStages.first { $0.stage == stage }?.after })
            }
        return rows.map { name, times in
            guard let worst = times.max() else { return "\(name): not measured" }
            return "\(name): median \(LatencyTrace.ms(Self.median(times))) ms, worst \(LatencyTrace.ms(worst)) ms"
        }
    }

    /// What the run says about the model as the live one: whether every start and finish met the cap, and whether its
    /// last pass is quick enough to put the last words in the copy or only refines it afterwards.
    public func verdict(model: String) -> [String] {
        let cap = LatencyTrace.ms(LatencyTrace.budget)
        guard !traces.isEmpty else { return ["\(model): nothing measured."] }
        let missed = traces.filter { !$0.meetsBudget }.count
        var lines = [missed == 0
            ? "\(model) meets the \(cap) ms cap: every start and finish was within it."
            : "\(model) missed the \(cap) ms cap in \(missed) of \(traces.count) sessions."]
        let passes = traces.compactMap(\.lastPass)
        if !passes.isEmpty {
            let pass = Self.median(passes)
            lines.append(pass <= LatencyTrace.budget
                ? "Its last pass takes \(LatencyTrace.ms(pass)) ms (median), so the copy has the last words."
                : "Its last pass takes \(LatencyTrace.ms(pass)) ms (median), over the cap: the copy goes out first "
                    + "and the last words refine it.")
        }
        return lines
    }

    static func median(_ times: [TimeInterval]) -> TimeInterval {
        let sorted = times.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }
}
