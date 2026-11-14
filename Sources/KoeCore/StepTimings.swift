import Foundation

/// How long each pass of the live window took, against the time it has before the next one: the benchmark prints it,
/// so a slower model or setting shows before it lags a session.
public struct StepTimings: Sendable, Equatable {
    /// The time between passes.
    public let budget: TimeInterval
    public private(set) var steps: [TimeInterval] = []

    public init(budget: TimeInterval) {
        self.budget = budget
    }

    public mutating func record(_ seconds: TimeInterval) { steps.append(seconds) }

    public mutating func merge(_ other: StepTimings) { steps += other.steps }

    public var mean: TimeInterval { steps.isEmpty ? 0 : steps.reduce(0, +) / Double(steps.count) }
    public var worst: TimeInterval { steps.max() ?? 0 }
    /// Passes that took longer than the budget, so the next one started late.
    public var overBudget: Int { steps.filter { $0 > budget }.count }

    /// One line, as "96 steps, mean 0.61 s, worst 3.56 s, 13 over 0.90 s".
    public var summary: String {
        let format = { (seconds: TimeInterval) in String(format: "%.2f s", seconds) }
        return "\(steps.count) steps, mean \(format(mean)), worst \(format(worst)), \(overBudget) over \(format(budget))"
    }
}
