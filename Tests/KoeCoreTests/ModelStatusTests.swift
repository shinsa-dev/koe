import Foundation
import KoeCore
import Testing

struct ModelStatusTests {
    private func status(_ installs: [ModelID: ModelInstall] = [:], deleted: Set<ModelID> = [],
                        canDownload: Bool = true, inUse: ModelID = .apple,
                        loadErrors: [ModelID: String] = [:]) -> ModelStatus {
        ModelStatus(plan: ModelPlan(installs: installs, deleted: deleted, canDownload: canDownload),
                    inUse: inUse, loadErrors: loadErrors)
    }

    private func row(_ status: ModelStatus, _ id: ModelID) -> ModelStatus.Row? {
        status.rows.first { $0.id == id }
    }

    @Test func everyModelGetsARowButNvidiasParakeetsThatArentHere() {
        #expect(status().rows.map(\.id) == [.fluidSpeechPro, .whisperTurbo, .apple])
        #expect(status([.parakeetV2: .installed]).rows.map(\.id)
            == [.fluidSpeechPro, .parakeetV2, .whisperTurbo, .apple])
        #expect(status([.parakeetV3: .installed]).rows.map(\.id)
            == [.fluidSpeechPro, .parakeetV3, .whisperTurbo, .apple])
    }

    @Test func aParakeetV3StreamsWhileFluidSpeechProDownloads() {
        let switching = status([.parakeetV3: .installed, .whisperTurbo: .installed,
                                .fluidSpeechPro: .downloading(fraction: 0.5)], inUse: .parakeetV3)
        #expect(row(switching, .parakeetV3)?.role == "Live")
        #expect(row(switching, .parakeetV3)?.state == "Ready.")
        #expect(row(switching, .fluidSpeechPro)?.role == "Live and refine")
        #expect(switching.deletable.map(\.id) == [.parakeetV3, .whisperTurbo])
    }

    @Test func aLeftoverParakeetV3IsADeletableDownloadWithNoRole() {
        let after = status([.parakeetV3: .installed, .whisperTurbo: .installed, .fluidSpeechPro: .installed],
                           inUse: .fluidSpeechPro)
        #expect(row(after, .parakeetV3)?.role == nil)
        #expect(row(after, .parakeetV3)?.state == "Ready.")
        #expect(row(after, .fluidSpeechPro)?.role == "Live and refine")
        #expect(after.deletable.map(\.id) == [.fluidSpeechPro, .parakeetV3, .whisperTurbo])
    }

    @Test func aFreshMacSaysParakeetDownloadsThenWhisper() {
        let fresh = status([.fluidSpeechPro: .downloading(fraction: 0.5)])
        let half = ByteCountFormatter.string(fromByteCount: 326_000_000, countStyle: .file)
        #expect(row(fresh, .fluidSpeechPro)?.state == "Downloading, \(half) of 652 MB.")
        #expect(row(fresh, .fluidSpeechPro)?.fraction == 0.5)
        #expect(row(fresh, .fluidSpeechPro)?.role == "Live and refine")
        #expect(row(fresh, .whisperTurbo)?.state == "Downloads after Fluid Speech Pro.")
        #expect(row(fresh, .whisperTurbo)?.role == "Refine")
        #expect(row(fresh, .apple)?.state == "Built in. Koe uses it until Fluid Speech Pro is ready.")
        #expect(row(fresh, .apple)?.role == "Live and refine")
        #expect(fresh.rows.allSatisfy { $0.action == nil && !$0.isError })
    }

    @Test func aDownloadJustStartingSaysSo() {
        #expect(row(status([.fluidSpeechPro: .downloading(fraction: 0)]), .fluidSpeechPro)?.state
            == "Starting the 652 MB download.")
        #expect(row(status(), .fluidSpeechPro)?.state == "Downloads soon. 652 MB.")
    }

    @Test func preparingTakesAFewMinutesAndHasNoButton() {
        let preparing = row(status([.fluidSpeechPro: .installed, .whisperTurbo: .preparing], inUse: .fluidSpeechPro),
                            .whisperTurbo)
        #expect(preparing?.state == "Preparing it for this Mac. This happens once and takes a few minutes.")
        #expect(preparing?.action == nil)
        #expect(preparing?.fraction == nil)
    }

    @Test func aFailedDownloadSaysWhyAndOffersToTryAgain() {
        let failed = row(status([.fluidSpeechPro: .failed("The download needs an internet connection.")]), .fluidSpeechPro)
        #expect(failed?.state == "The download needs an internet connection.")
        #expect(failed?.action == .retry)
        #expect(failed?.isError == true)
    }

    @Test func readyModelsSayReadyAndAppleStepsBack() {
        let ready = status([.fluidSpeechPro: .installed, .whisperTurbo: .installed], inUse: .fluidSpeechPro)
        #expect(ready.rows.map(\.state) == ["Ready.", "Ready.", "Built in."])
        #expect(ready.rows.map(\.role) == ["Live and refine", "Refine", "Refine"])
    }

    @Test func aModelInButNotLoadedYetIsLoading() {
        #expect(row(status([.fluidSpeechPro: .installed], inUse: .apple), .fluidSpeechPro)?.state == "Loading.")
    }

    @Test func aModelThatDidntLoadSaysWhy() {
        let broken = row(status([.fluidSpeechPro: .installed], loadErrors: [.fluidSpeechPro: "A file is missing."]),
                         .fluidSpeechPro)
        #expect(broken?.state == "Didn't load. A file is missing.")
        #expect(broken?.isError == true)
    }

    @Test func aDeletedModelOffersItsDownloadAndIsForNothing() {
        let deleted = row(status([.fluidSpeechPro: .installed], deleted: [.whisperTurbo], inUse: .fluidSpeechPro),
                          .whisperTurbo)
        #expect(deleted?.state == "Not downloaded. 650 MB.")
        #expect(deleted?.action == .download)
        #expect(deleted?.role == nil)
    }

    @Test func anIntelMacSaysTheModelsNeedAppleSilicon() {
        let intel = status(canDownload: false)
        #expect(row(intel, .fluidSpeechPro)?.state == "Needs a Mac with Apple silicon.")
        #expect(row(intel, .fluidSpeechPro)?.action == nil)
        #expect(row(intel, .apple)?.state == "Built in.")
        #expect(row(intel, .apple)?.role == "Live")
    }

    @Test func onlyDownloadedModelsCanBeDeleted() {
        let some = status([.fluidSpeechPro: .installed, .whisperTurbo: .installed, .parakeetV2: .downloading(fraction: 0.1)])
        #expect(some.deletable.map(\.id) == [.fluidSpeechPro, .whisperTurbo])
        #expect(some.deletable.map(\.size) == ["652 MB", "650 MB"])
        #expect(status().deletable.isEmpty)
    }
}
