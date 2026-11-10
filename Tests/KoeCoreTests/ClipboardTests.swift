import Foundation
import KoeCore
import Testing

private func asset(_ path: String, number: Int) -> BundleAsset {
    BundleAsset(number: number, asset: Asset(url: URL(fileURLWithPath: path)), annotationID: UUID())
}

struct ClipboardPlanTests {
    let bundle = ComposedBundle(
        text: "Look [1] here [2].", html: "<p>Look [1] here [2].</p>",
        assets: [asset("/s/screenshot-1.png", number: 1), asset("/s/clip-1.mov", number: 2)]
    )

    @Test func theTextComesFirstThenEachFileInMarkerOrder() {
        let items = ClipboardPlan.items(for: bundle, copyFiles: true) { _ in true }
        #expect(items == [
            .text(plain: "Look [1] here [2].", html: "<p>Look [1] here [2].</p>"),
            .file(URL(fileURLWithPath: "/s/screenshot-1.png")),
            .file(URL(fileURLWithPath: "/s/clip-1.mov")),
        ])
    }

    @Test func withoutCopyFilesOnlyTheTextGoesOn() {
        let items = ClipboardPlan.items(for: bundle, copyFiles: false) { _ in true }
        #expect(items == [.text(plain: bundle.text, html: bundle.html)])
    }

    @Test func aMissingFileIsLeftOut() {
        let items = ClipboardPlan.items(for: bundle, copyFiles: true) { $0.lastPathComponent != "clip-1.mov" }
        #expect(items.count == 2)
        #expect(items.last == .file(URL(fileURLWithPath: "/s/screenshot-1.png")))
    }

    @Test func aFileNamedTwiceGoesOnOnce() {
        var twice = bundle
        twice.assets.append(asset("/s/screenshot-1.png", number: 3))
        #expect(ClipboardPlan.items(for: twice, copyFiles: true) { _ in true }.count == 3)
    }

    @Test func anEmptyBundleCopiesNothing() {
        let empty = ComposedBundle(text: "", html: "", assets: [])
        #expect(ClipboardPlan.items(for: empty, copyFiles: true) { _ in true }.isEmpty)
    }

    @Test func theSummaryCountsWordsAndFiles() {
        let text = ClipboardItem.text(plain: "a", html: "a")
        let file = ClipboardItem.file(URL(fileURLWithPath: "/a.png"))
        #expect(ClipboardPlan.summary(for: [text], pasted: false)
            == ("Copied to clipboard", "Press ⌘V to paste your words anywhere"))
        #expect(ClipboardPlan.summary(for: [text, file], pasted: false)
            == ("Copied to clipboard", "Press ⌘V to paste your words and 1 attachment anywhere"))
        #expect(ClipboardPlan.summary(for: [text, file, file], pasted: true)
            == ("Pasted for you", "Your words and 2 attachments went straight in"))
    }

    @Test func theSummarySaysOnePressBringsEverything() {
        let text = ClipboardItem.text(plain: "a", html: "a")
        let file = ClipboardItem.file(URL(fileURLWithPath: "/a.png"))
        #expect(ClipboardPlan.summary(for: [text, file, file], pasted: false, together: true)
            == ("Copied to clipboard", "Press ⌘V once for your words and 2 attachments"))
        #expect(ClipboardPlan.summary(for: [text], pasted: false, together: true)
            == ("Copied to clipboard", "Press ⌘V to paste your words anywhere"))
    }
}

struct PastePlanTests {
    let text = ClipboardItem.text(plain: "Look [1].", html: "<p>Look [1].</p>")
    let shot = URL(fileURLWithPath: "/s/screenshot-1.png")
    let clip = URL(fileURLWithPath: "/s/clip-1.mov")

    @Test func theWordsStayAndTheFilesFollowInOrder() {
        let split = PastePlan.split([text, .file(shot), .file(clip)])
        #expect(split?.words == text)
        #expect(split?.files == [shot, clip])
    }

    @Test func wordsAloneOrFilesAloneNeedNoSecondPaste() {
        #expect(PastePlan.split([text]) == nil)
        #expect(PastePlan.split([.file(shot)]) == nil)
        #expect(PastePlan.split([]) == nil)
    }

    @Test(arguments: ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable"])
    func aTerminalGetsOnlyTheWords(id: String) {
        #expect(!PastePlan.takesFiles(appWithBundleID: id))
    }

    @Test(arguments: ["com.anthropic.claudefordesktop", "com.tinyspeck.slackmacgap", "com.apple.Safari",
                      "com.apple.TerminalX"])
    func anyOtherAppGetsTheFiles(id: String) {
        #expect(PastePlan.takesFiles(appWithBundleID: id))
    }

    @Test func anUnknownAppGetsTheFiles() {
        #expect(PastePlan.takesFiles(appWithBundleID: nil))
    }
}

struct KoeSettingsTests {
    @Test func defaultsWhenNothingIsSet() {
        let settings = KoeSettings(values: [:])
        #expect(settings == KoeSettings())
        #expect(settings.copyFiles && settings.pasteTogether && !settings.autoPaste)
        #expect(settings.theme == .system && settings.recentCount == 5)
    }

    @Test func roundTripsThroughItsValues() {
        var settings = KoeSettings()
        settings.copyFiles = false
        settings.autoPaste = true
        settings.theme = .dark
        settings.recentCount = 10
        settings.freezeScreen = false
        settings.pasteTogether = false
        #expect(KoeSettings(values: settings.values) == settings)
    }

    @Test func aMistypedValueFallsBackToTheDefault() {
        let settings = KoeSettings(values: ["appearance": "sepia", "recentCount": 7, "autoPaste": "yes"])
        #expect(settings == KoeSettings())
    }

    @Test func themeSharesTheAppearanceKey() {
        #expect(KoeSettings(values: ["appearance": "light"]).theme == .light)
    }
}

struct HistoryEntryTests {
    let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
    let locale = Locale(identifier: "en_US")
    /// 2026-11-04 18:15:00 UTC
    let started = Date(timeIntervalSince1970: 1_793_816_100)

    private func entry(_ text: String, annotations: Int = 0, at date: Date? = nil) -> HistoryEntry {
        var session = Session(startedAt: date ?? started)
        if !text.isEmpty { session.appendTranscript(text, start: 0, end: 5) }
        for index in 0..<annotations { session.add(Annotation(time: Double(index), kind: .note, note: "n")) }
        return HistoryEntry(session: session, folder: URL(fileURLWithPath: "/s"))
    }

    @Test func shortTextIsTheWholeTitle() {
        #expect(entry("Look at the sidebar.").title() == "Look at the sidebar.")
    }

    @Test func longTextIsCutAtAWord() {
        let title = entry("Look at the sidebar, the padding on this card is far too tight").title(limit: 24)
        #expect(title == "Look at the sidebar…")
    }

    @Test func withoutWordsTheTitleCountsAttachments() {
        #expect(entry("", annotations: 1).title() == "1 attachment")
        #expect(entry("", annotations: 3).title() == "3 attachments")
    }

    @Test func detailSaysTodayYesterdayOrTheDate() {
        let now = started.addingTimeInterval(3600)
        #expect(entry("hi").detail(now: now, calendar: utc, locale: locale) == "Today at 6:15\u{202F}PM")
        #expect(entry("hi", annotations: 2).detail(now: now.addingTimeInterval(86_400), calendar: utc, locale: locale)
            == "Yesterday at 6:15\u{202F}PM · 2 attachments")
        #expect(entry("hi", annotations: 1).detail(now: now.addingTimeInterval(5 * 86_400), calendar: utc, locale: locale)
            == "Nov 4 at 6:15\u{202F}PM · 1 attachment")
    }
}

struct SessionArchiveTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "koe-archive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func savedSessionsComeBackNewestFirst() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(root: root)
        for (offset, word) in ["first", "second", "third"].enumerated() {
            var session = Session(startedAt: Date(timeIntervalSince1970: 1_000 + Double(offset) * 60))
            session.appendTranscript(word, start: 0, end: 1)
            session.add(Annotation(time: 0.5, kind: .note, note: "n"))
            try archive.save(session, in: root.appending(path: "2026-11-04-00000\(offset)-AAAA"))
        }
        let recent = archive.recent(limit: 2)
        #expect(recent.map { $0.session.words.map(\.text) } == [["third"], ["second"]])
        #expect(recent.first?.session.annotations.first?.note == "n")
        #expect(recent.first?.folder.lastPathComponent == "2026-11-04-000002-AAAA")
    }

    @Test func aFolderWithoutASessionIsSkipped() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "2026-11-05-000000-BBBB"),
                                                withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: root.appending(path: "2026-11-05-000000-BBBB/session.json"))
        let archive = SessionArchive(root: root)
        try archive.save(Session(words: [TimedWord("kept", start: 0, end: 1)]), in: root.appending(path: "2026-11-04-000000-AAAA"))
        #expect(archive.recent(limit: 5).map { $0.session.words.first?.text } == ["kept"])
    }

    @Test func aFolderWithAudioButNoSessionIsUnfinished() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(root: root)
        let crashed = root.appending(path: "2026-11-09-100000-CCCC")
        try FileManager.default.createDirectory(at: crashed, withIntermediateDirectories: true)
        try Data([0]).write(to: crashed.appending(path: SessionArchive.audioName))
        try archive.saveDraft(Session(annotations: [Annotation(time: 2, kind: .note, note: "kept")]), in: crashed)
        let bare = root.appending(path: "2026-11-09-110000-DDDD")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try Data([0]).write(to: bare.appending(path: SessionArchive.audioName))
        let done = root.appending(path: "2026-11-09-120000-EEEE")
        try FileManager.default.createDirectory(at: done, withIntermediateDirectories: true)
        try Data([0]).write(to: done.appending(path: SessionArchive.audioName))
        try archive.save(Session(), in: done)

        let unfinished = archive.unfinished()
        #expect(unfinished.map(\.folder.lastPathComponent) == ["2026-11-09-100000-CCCC", "2026-11-09-110000-DDDD"])
        #expect(unfinished.first?.draft?.annotations.first?.note == "kept")
        #expect(unfinished.last?.draft == nil)
    }

    @Test func savingASessionRemovesItsDraft() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = SessionArchive(root: root)
        let folder = root.appending(path: "2026-11-09-100000-CCCC")
        try archive.saveDraft(Session(), in: folder)
        try archive.save(Session(), in: folder)
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: SessionArchive.draftName).path))
    }

    @Test func aMissingRootIsEmpty() {
        let archive = SessionArchive(root: URL(fileURLWithPath: "/tmp/koe-missing-\(UUID().uuidString)"))
        #expect(archive.recent(limit: 5).isEmpty)
    }
}
