import KoeCore
import Testing

struct ModelPlanTests {
    private func plan(_ installs: [ModelID: ModelInstall] = [:], deleted: Set<ModelID> = [],
                      canDownload: Bool = true) -> ModelPlan {
        ModelPlan(installs: installs, deleted: deleted, canDownload: canDownload)
    }

    @Test func parakeetV3StreamsOnceItIsInAndIsTheCandidateWhileItComes() {
        #expect(plan().liveCandidate == .parakeetV3)
        #expect(plan([.parakeetV3: .downloading(fraction: 0.3)]).liveCandidate == .parakeetV3)
        #expect(plan([.parakeetV3: .installed, .parakeetV2: .installed]).liveCandidate == .parakeetV3)
    }

    @Test func aParakeetV2AlreadyHereStreamsUntilV3IsIn() {
        #expect(plan([.parakeetV2: .installed, .parakeetV3: .downloading(fraction: 0.5)]).liveCandidate == .parakeetV2)
    }

    @Test func withParakeetDeletedAppleStreams() {
        #expect(plan(deleted: [.parakeetV3]).liveCandidate == .apple)
        #expect(plan([.parakeetV2: .installed], deleted: [.parakeetV3]).liveCandidate == .parakeetV2)
    }

    @Test func anIntelMacStreamsWithAppleAndDownloadsNothing() {
        let intel = plan(canDownload: false)
        #expect(intel.liveCandidate == .apple)
        #expect(intel.nextDownload == nil)
    }

    @Test func parakeetDownloadsFirstThenWhisper() {
        #expect(plan().nextDownload == .parakeetV3)
        #expect(plan([.parakeetV3: .installed]).nextDownload == .whisperTurbo)
        #expect(plan([.parakeetV3: .installed, .whisperTurbo: .installed]).nextDownload == nil)
    }

    @Test func oneDownloadAtATime() {
        #expect(plan([.parakeetV3: .downloading(fraction: 0.1)]).nextDownload == nil)
        #expect(plan([.parakeetV3: .installed, .whisperTurbo: .preparing]).nextDownload == nil)
    }

    @Test func aDeletedModelNeverComesBackByItself() {
        #expect(plan([.parakeetV3: .installed], deleted: [.whisperTurbo]).nextDownload == nil)
        #expect(plan(deleted: [.parakeetV3]).nextDownload == .whisperTurbo)
    }

    @Test func aFailedDownloadLetsTheNextOneGo() {
        #expect(plan([.parakeetV3: .failed("Offline")]).nextDownload == .whisperTurbo)
    }

    @Test func parakeetV2IsNeverDownloaded() {
        let all = plan([.parakeetV3: .installed, .whisperTurbo: .installed])
        #expect(all.nextDownload == nil)
        #expect(!all.isComing(.parakeetV2))
    }

    @Test func rolesSayWhatEachModelIsFor() {
        let full = plan([.parakeetV3: .installed, .whisperTurbo: .installed])
        #expect(full.roles(.parakeetV3, inUse: .parakeetV3) == [.live, .refine])
        #expect(full.roles(.whisperTurbo, inUse: .parakeetV3) == [.refine])
        #expect(full.roles(.apple, inUse: .parakeetV3) == [.refine])
    }

    @Test func appleIsLiveOnlyWhileItStandsIn() {
        let coming = plan([.parakeetV3: .downloading(fraction: 0.2)])
        #expect(coming.roles(.apple, inUse: .apple) == [.live, .refine])
        #expect(coming.roles(.parakeetV3, inUse: .apple) == [.live, .refine])
        #expect(coming.roles(.whisperTurbo, inUse: .apple) == [.refine])
    }

    @Test func withoutWhisperTheRefineIsParakeetAlone() {
        let noWhisper = plan([.parakeetV3: .installed], deleted: [.whisperTurbo])
        #expect(noWhisper.roles(.whisperTurbo, inUse: .parakeetV3).isEmpty)
        #expect(noWhisper.roles(.apple, inUse: .parakeetV3).isEmpty)
        #expect(noWhisper.roles(.parakeetV3, inUse: .parakeetV3) == [.live, .refine])
    }

    @Test func aParakeetV2StandingInIsLiveAndV3StaysLiveToo() {
        let both = plan([.parakeetV2: .installed, .parakeetV3: .downloading(fraction: 0.5)])
        #expect(both.roles(.parakeetV2, inUse: .parakeetV2) == [.live])
        #expect(both.roles(.parakeetV3, inUse: .parakeetV2) == [.live, .refine])
    }
}
