import KoeCore
import Testing

struct ModelPlanTests {
    private func plan(_ installs: [ModelID: ModelInstall] = [:], deleted: Set<ModelID> = [],
                      canDownload: Bool = true) -> ModelPlan {
        ModelPlan(installs: installs, deleted: deleted, canDownload: canDownload)
    }

    @Test func fluidSpeechProStreamsOnceItIsInAndIsTheCandidateWhileItComes() {
        #expect(plan().liveCandidate == .fluidSpeechPro)
        #expect(plan([.fluidSpeechPro: .downloading(fraction: 0.3)]).liveCandidate == .fluidSpeechPro)
        #expect(plan([.fluidSpeechPro: .installed, .parakeetV3: .installed, .parakeetV2: .installed]).liveCandidate
            == .fluidSpeechPro)
    }

    @Test func aParakeetAlreadyHereStreamsUntilFluidSpeechProIsIn() {
        let standingIn = plan([.parakeetV3: .installed, .fluidSpeechPro: .downloading(fraction: 0.5)])
        #expect(standingIn.liveCandidate == .parakeetV3)
        #expect(plan([.parakeetV3: .installed, .parakeetV2: .installed]).liveCandidate == .parakeetV3)
        #expect(plan([.parakeetV2: .installed, .fluidSpeechPro: .downloading(fraction: 0.5)]).liveCandidate
            == .parakeetV2)
    }

    @Test func withFluidSpeechProDeletedALeftoverParakeetOrAppleStreams() {
        #expect(plan(deleted: [.fluidSpeechPro]).liveCandidate == .apple)
        #expect(plan([.parakeetV3: .installed], deleted: [.fluidSpeechPro]).liveCandidate == .parakeetV3)
        #expect(plan([.parakeetV2: .installed], deleted: [.fluidSpeechPro]).liveCandidate == .parakeetV2)
    }

    @Test func anIntelMacStreamsWithAppleAndDownloadsNothing() {
        let intel = plan(canDownload: false)
        #expect(intel.liveCandidate == .apple)
        #expect(intel.nextDownload == nil)
    }

    @Test func fluidSpeechProDownloadsFirstThenWhisper() {
        #expect(plan().nextDownload == .fluidSpeechPro)
        #expect(plan([.fluidSpeechPro: .installed]).nextDownload == .whisperTurbo)
        #expect(plan([.fluidSpeechPro: .installed, .whisperTurbo: .installed]).nextDownload == nil)
    }

    @Test func aMacWithParakeetV3StillDownloadsFluidSpeechPro() {
        #expect(plan([.parakeetV3: .installed, .whisperTurbo: .installed]).nextDownload == .fluidSpeechPro)
    }

    @Test func oneDownloadAtATime() {
        #expect(plan([.fluidSpeechPro: .downloading(fraction: 0.1)]).nextDownload == nil)
        #expect(plan([.fluidSpeechPro: .installed, .whisperTurbo: .preparing]).nextDownload == nil)
    }

    @Test func aDeletedModelNeverComesBackByItself() {
        #expect(plan([.fluidSpeechPro: .installed], deleted: [.whisperTurbo]).nextDownload == nil)
        #expect(plan(deleted: [.fluidSpeechPro]).nextDownload == .whisperTurbo)
    }

    @Test func aFailedDownloadLetsTheNextOneGo() {
        #expect(plan([.fluidSpeechPro: .failed("Offline")]).nextDownload == .whisperTurbo)
    }

    @Test func nvidiasParakeetsAreNeverDownloaded() {
        let all = plan([.fluidSpeechPro: .installed, .whisperTurbo: .installed])
        #expect(all.nextDownload == nil)
        #expect(!all.isComing(.parakeetV3))
        #expect(!all.isComing(.parakeetV2))
    }

    @Test func rolesSayWhatEachModelIsFor() {
        let full = plan([.fluidSpeechPro: .installed, .whisperTurbo: .installed])
        #expect(full.roles(.fluidSpeechPro, inUse: .fluidSpeechPro) == [.live, .refine])
        #expect(full.roles(.whisperTurbo, inUse: .fluidSpeechPro) == [.refine])
        #expect(full.roles(.apple, inUse: .fluidSpeechPro) == [.refine])
    }

    @Test func appleIsLiveOnlyWhileItStandsIn() {
        let coming = plan([.fluidSpeechPro: .downloading(fraction: 0.2)])
        #expect(coming.roles(.apple, inUse: .apple) == [.live, .refine])
        #expect(coming.roles(.fluidSpeechPro, inUse: .apple) == [.live, .refine])
        #expect(coming.roles(.whisperTurbo, inUse: .apple) == [.refine])
    }

    @Test func withoutWhisperTheRefineIsFluidSpeechProAlone() {
        let noWhisper = plan([.fluidSpeechPro: .installed], deleted: [.whisperTurbo])
        #expect(noWhisper.roles(.whisperTurbo, inUse: .fluidSpeechPro).isEmpty)
        #expect(noWhisper.roles(.apple, inUse: .fluidSpeechPro).isEmpty)
        #expect(noWhisper.roles(.fluidSpeechPro, inUse: .fluidSpeechPro) == [.live, .refine])
    }

    @Test func aParakeetV3StandingInIsLiveAndFluidSpeechProStaysLiveToo() {
        let both = plan([.parakeetV3: .installed, .fluidSpeechPro: .downloading(fraction: 0.5)])
        #expect(both.roles(.parakeetV3, inUse: .parakeetV3) == [.live])
        #expect(both.roles(.fluidSpeechPro, inUse: .parakeetV3) == [.live, .refine])
    }

    @Test func aLeftoverParakeetV3IsForNothingOnceFluidSpeechProIsIn() {
        let after = plan([.parakeetV3: .installed, .fluidSpeechPro: .installed, .whisperTurbo: .installed])
        #expect(after.roles(.parakeetV3, inUse: .fluidSpeechPro).isEmpty)
        #expect(after.roles(.fluidSpeechPro, inUse: .fluidSpeechPro) == [.live, .refine])
    }
}
