import KoeCore
import Testing

struct CorpusGroupTests {
    @Test func aCorpusClipBelongsToItsLevel() {
        #expect(CorpusGroup.name(ofFolder: "quiet-03") == "quiet")
        #expect(CorpusGroup.name(ofFolder: "loud-10") == "loud")
    }

    @Test func aRecordedSessionBelongsToNoGroup() {
        #expect(CorpusGroup.name(ofFolder: "2026-11-19-210932-DE07") == nil)
        #expect(CorpusGroup.name(ofFolder: "session") == nil)
        #expect(CorpusGroup.name(ofFolder: "-01") == nil)
    }
}
