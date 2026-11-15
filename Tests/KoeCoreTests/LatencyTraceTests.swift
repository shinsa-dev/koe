import Foundation
import KoeCore
import Testing

struct LatencyTraceTests {
    private func trace(_ marks: [LatencyTrace.Stage: TimeInterval]) -> LatencyTrace {
        var trace = LatencyTrace()
        for (stage, time) in marks { trace.mark(stage, at: time) }
        return trace
    }

    private let quick: [LatencyTrace.Stage: TimeInterval] = [
        .startPressed: 10, .captureOpen: 10.004, .pillShown: 10.012, .deviceStarted: 10.3, .firstAudio: 10.41,
        .finishPressed: 20, .audioEnded: 20.001, .lastPassStarted: 20.003, .lastPassDone: 20.04,
        .delivered: 20.041, .copied: 20.045,
    ]

    @Test func startRunsFromTheShortcutToWhicheverOfPillAndRecordingCameLast() throws {
        let start = try #require(trace(quick).start)
        #expect(abs(start - 0.012) < 1e-9)
    }

    @Test func theDevicesOwnWarmUpIsReportedButNotCounted() {
        let measured = trace(quick)
        #expect(measured.startStages.map(\.stage) == [.captureOpen, .pillShown, .deviceStarted, .firstAudio])
        #expect(measured.meetsBudget)
    }

    @Test func finishRunsFromTheShortcutToTheClipboard() throws {
        let finish = try #require(trace(quick).finish)
        #expect(abs(finish - 0.045) < 1e-9)
    }

    @Test func onlyTheFirstMarkOfAStageCounts() {
        var measured = trace(quick)
        measured.mark(.pillShown, at: 25)
        #expect(measured.marks[.pillShown] == 10.012)
    }

    @Test func aMissingStageLeavesItsSideUnmeasuredAndOverBudget() {
        var marks = quick
        marks[.copied] = nil
        let measured = trace(marks)
        #expect(measured.finish == nil)
        #expect(measured.start != nil)
        #expect(!measured.meetsBudget)
        #expect(measured.summary.contains("finish not measured"))
    }

    @Test func aSlowFinishMissesTheBudgetAndNamesTheStepThatTookTheTime() throws {
        var marks = quick
        marks[.delivered] = 21.5
        marks[.copied] = 21.51
        let measured = trace(marks)
        #expect(!measured.meetsBudget)
        let slowest = try #require(measured.slowestStep)
        #expect(slowest.stage == .delivered)
        #expect(abs(slowest.took - 1.46) < 1e-9)
    }

    @Test func theSummaryListsEachStageInMilliseconds() {
        #expect(trace(quick).summary == "start 12.0 ms (recording open 4.0, pill shown 12.0, device started 300.0, "
            + "first audio 410.0) · finish 45.0 ms (audio ended 1.0, last pass started 3.0, last pass done 40.0, "
            + "delivered 41.0, copied 45.0)")
    }

    @Test func aReportGivesTheMedianAndWorstOfEachStage() {
        var slow = quick
        slow[.copied] = 20.090
        var slower = quick
        slower[.copied] = 21
        let report = LatencyReport([trace(quick), trace(slow), trace(slower)])
        #expect(report.lines.contains("finish: median 90.0 ms, worst 1000.0 ms"))
        #expect(report.lines.contains("  copied: median 90.0 ms, worst 1000.0 ms"))
        #expect(!report.meetsBudget)
        #expect(LatencyReport([trace(quick)]).meetsBudget)
        #expect(!LatencyReport([]).meetsBudget)
    }
}
