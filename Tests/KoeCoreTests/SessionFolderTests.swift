import Foundation
import KoeCore
import Testing

struct SessionFolderTests {

    @Test func theNameSortsByTimeAndCarriesTheIdsStart() throws {
        let id = try #require(UUID(uuidString: "1A2B3C4D-0000-0000-0000-000000000000"))
        let date = Date(timeIntervalSince1970: 1_793_815_200) // 2026-11-04 18:00:00 UTC
        let name = SessionFolder.name(startedAt: date, id: id, timeZone: try #require(TimeZone(identifier: "UTC")))
        #expect(name == "2026-11-04-180000-1A2B")
    }

    @Test func screenshotsAreNumberedInOrder() {
        var folder = SessionFolder(url: URL(fileURLWithPath: "/tmp/s"))
        let shots = names(&folder, screenshots: 2)
        #expect(shots == ["screenshot-1.png", "screenshot-2.png"])
    }

    @Test func aDroppedFileKeepsItsNameWithoutSpaces() {
        var folder = SessionFolder(url: URL(fileURLWithPath: "/tmp/s"))
        let url = folder.reserve("spec sheet v2.pdf")
        #expect(url.path == "/tmp/s/spec-sheet-v2.pdf")
    }

    @Test func aRepeatedNameGetsANumber() {
        var folder = SessionFolder(url: URL(fileURLWithPath: "/tmp/s"))
        let names = names(&folder, reserving: ["spec.pdf", "Spec.pdf", "spec.pdf", "README", "README"])
        #expect(names == ["spec.pdf", "Spec-2.pdf", "spec-3.pdf", "README", "README-2"])
    }

    @Test func aDroppedScreenshotNameNeverClashesWithKoesOwn() {
        var folder = SessionFolder(url: URL(fileURLWithPath: "/tmp/s"))
        let dropped = names(&folder, reserving: ["screenshot-1.png"])
        let shot = names(&folder, screenshots: 1)
        #expect(dropped + shot == ["screenshot-1.png", "screenshot-1-2.png"])
    }

    @Test func unsafeNamesAreCleanedUp() {
        var folder = SessionFolder(url: URL(fileURLWithPath: "/tmp/s"))
        let cleaned = names(&folder, reserving: [" .. ", "a/b:c"])
        #expect(cleaned == ["file", "a-b-c"])
    }

    private func names(_ folder: inout SessionFolder, reserving names: [String]) -> [String] {
        names.map { folder.reserve($0).lastPathComponent }
    }

    private func names(_ folder: inout SessionFolder, screenshots count: Int) -> [String] {
        (0..<count).map { _ in folder.nextScreenshot().lastPathComponent }
    }
}

struct AnnotationLedgerTests {
    @Test func anAnnotationTakesItsTicketsTime() {
        var ledger = AnnotationLedger()
        let ticket = ledger.open(at: 4.2)
        let closed = ledger.close(ticket, with: Annotation(time: 9, kind: .note, note: "later"))
        #expect(closed)
        #expect(ledger.annotations.map(\.time) == [4.2])
    }

    @Test func aCancelledToolAddsNothing() {
        var ledger = AnnotationLedger()
        let ticket = ledger.open(at: 1)
        ledger.close(ticket, with: nil)
        #expect(ledger.annotations.isEmpty)
        #expect(ledger.openCount == 0)
    }

    @Test func aTicketClosesOnce() {
        var ledger = AnnotationLedger()
        let ticket = ledger.open(at: 1)
        ledger.close(ticket, with: Annotation(time: 0, kind: .note, note: "a"))
        let again = ledger.close(ticket, with: Annotation(time: 0, kind: .note, note: "b"))
        #expect(!again)
        #expect(ledger.annotations.count == 1)
    }

    @Test func theSessionWaitsForAnOpenTool() {
        var ledger = AnnotationLedger()
        let ticket = ledger.open(at: 1)
        ledger.endTranscript()
        #expect(!ledger.isSettled)
        ledger.close(ticket, with: nil)
        #expect(ledger.isSettled)
    }

    @Test func theSessionWaitsForTheTranscript() {
        var ledger = AnnotationLedger()
        #expect(!ledger.isSettled)
        ledger.endTranscript()
        #expect(ledger.isSettled)
    }

    @Test func aNegativeTimeIsClampedToTheStart() {
        var ledger = AnnotationLedger()
        let ticket = ledger.open(at: -2)
        #expect(ticket.time == 0)
    }
}

struct ScriptedStepTests {
    @Test func parsesEveryKindOfStepInTimeOrder() throws {
        let steps = try ScriptedStep.parse("3 pin 1,2 talk 2.5; 1.5 shot 120,80,640,360 The padding is off; 4 drop /tmp/a b.pdf")
        #expect(steps == [
            ScriptedStep(time: 1.5, action: .screenshot(CGRect(x: 120, y: 80, width: 640, height: 360), note: "The padding is off")),
            ScriptedStep(time: 3, action: .comment(CGPoint(x: 1, y: 2), note: nil, talk: 2.5)),
            ScriptedStep(time: 4, action: .drop("/tmp/a b.pdf")),
        ])
    }

    @Test func aPinCommentsOnASpot() throws {
        let steps = try ScriptedStep.parse("2 pin 400,300 Too tight; 3 pin! 10,20")
        #expect(steps[0].action == .comment(CGPoint(x: 400, y: 300), note: "Too tight"))
        #expect(steps[1].action == .comment(CGPoint(x: 10, y: 20), note: nil) && steps[1].holds)
    }

    @Test func aBangHoldsTheToolOpen() throws {
        let steps = try ScriptedStep.parse("2 shot! 0,0,10,10; 3 pin! 1,1")
        #expect(steps.map(\.holds) == [true, true])
        #expect(steps[0].action == .screenshot(CGRect(x: 0, y: 0, width: 10, height: 10), note: nil))
    }

    @Test(arguments: ["x note hi", "1 shot 1,2,3", "1 pin 4", "1 pin", "1 shot 0,0,0,10", "1 note hi", "1 wave hi", "-1 drop hi"])
    func rejectsABadStep(_ script: String) {
        #expect(throws: ScriptedStep.ParseError.self) { try ScriptedStep.parse(script) }
    }

    @Test func emptyStepsAreSkipped() throws {
        #expect(try ScriptedStep.parse(" ; ").isEmpty)
    }
}
