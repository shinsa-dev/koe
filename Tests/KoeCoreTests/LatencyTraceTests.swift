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

    @Test func aRefinementAfterTheCopyIsReportedButNotCounted() throws {
        let measured = trace(quick.merging([.lastPassDone: 20.09, .refined: 20.092]) { _, late in late })
        #expect(measured.finishStages.map(\.stage).last == .refined)
        #expect(abs(try #require(measured.finish) - 0.045) < 1e-9)
        #expect(measured.meetsBudget)
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

    @Test func aSessionWithinTheCapLogsNothing() {
        #expect(trace(quick).breach == nil)
    }

    @Test func aSlowFinishLogsOneLineNamingTheSlowestStep() {
        let slow = trace(quick.merging([.delivered: 20.07, .copied: 20.075]) { _, late in late })
        #expect(slow.breach == "Over the 50.0 ms cap: start 12.0 ms, finish 75.0 ms, slowest step last pass done 37.0 ms.")
    }

    @Test func theVerdictSaysWhetherTheModelMeetsTheCapAndWhetherItsLastPassFits() {
        #expect(LatencyReport([trace(quick)]).verdict(model: "Parakeet v3") == [
            "Parakeet v3 meets the 50.0 ms cap: every start and finish was within it.",
            "Its last pass takes 37.0 ms (median), so the copy has the last words.",
        ])
        let whisper = trace(quick.merging([.lastPassDone: 20.7, .copied: 20.06]) { _, late in late })
        #expect(LatencyReport([trace(quick), whisper]).verdict(model: "Whisper") == [
            "Whisper missed the 50.0 ms cap in 1 of 2 sessions.",
            "Its last pass takes 367.0 ms (median), over the cap: the copy goes out first and the last words refine it.",
        ])
        #expect(LatencyReport([]).verdict(model: "Apple") == ["Apple: nothing measured."])
        #expect(!LatencyReport([whisper]).meetsBudget)
    }
}
