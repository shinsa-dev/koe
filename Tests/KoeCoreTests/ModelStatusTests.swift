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

    @Test func everyModelGetsARowButAParakeetV2ThatIsntHere() {
        #expect(status().rows.map(\.id) == [.parakeetV3, .whisperTurbo, .apple])
        #expect(status([.parakeetV2: .installed]).rows.map(\.id) == [.parakeetV3, .parakeetV2, .whisperTurbo, .apple])
    }

    @Test func aFreshMacSaysParakeetDownloadsThenWhisper() {
        let fresh = status([.parakeetV3: .downloading(fraction: 0.5)])
        let half = ByteCountFormatter.string(fromByteCount: 241_500_000, countStyle: .file)
        #expect(row(fresh, .parakeetV3)?.state == "Downloading, \(half) of 483 MB.")
        #expect(row(fresh, .parakeetV3)?.fraction == 0.5)
        #expect(row(fresh, .parakeetV3)?.role == "Live and refine")
        #expect(row(fresh, .whisperTurbo)?.state == "Downloads after Parakeet v3.")
        #expect(row(fresh, .whisperTurbo)?.role == "Refine")
        #expect(row(fresh, .apple)?.state == "Built in. Koe uses it until Parakeet v3 is ready.")
        #expect(row(fresh, .apple)?.role == "Live and refine")
        #expect(fresh.rows.allSatisfy { $0.action == nil && !$0.isError })
    }

    @Test func aDownloadJustStartingSaysSo() {
        #expect(row(status([.parakeetV3: .downloading(fraction: 0)]), .parakeetV3)?.state
            == "Starting the 483 MB download.")
        #expect(row(status(), .parakeetV3)?.state == "Downloads soon. 483 MB.")
    }

    @Test func preparingTakesAFewMinutesAndHasNoButton() {
        let preparing = row(status([.parakeetV3: .installed, .whisperTurbo: .preparing], inUse: .parakeetV3),
                            .whisperTurbo)
        #expect(preparing?.state == "Preparing it for this Mac. This happens once and takes a few minutes.")
        #expect(preparing?.action == nil)
        #expect(preparing?.fraction == nil)
    }

    @Test func aFailedDownloadSaysWhyAndOffersToTryAgain() {
        let failed = row(status([.parakeetV3: .failed("The download needs an internet connection.")]), .parakeetV3)
        #expect(failed?.state == "The download needs an internet connection.")
        #expect(failed?.action == .retry)
        #expect(failed?.isError == true)
    }

    @Test func readyModelsSayReadyAndAppleStepsBack() {
        let ready = status([.parakeetV3: .installed, .whisperTurbo: .installed], inUse: .parakeetV3)
        #expect(ready.rows.map(\.state) == ["Ready.", "Ready.", "Built in."])
        #expect(ready.rows.map(\.role) == ["Live and refine", "Refine", "Refine"])
    }

    @Test func aModelInButNotLoadedYetIsLoading() {
        #expect(row(status([.parakeetV3: .installed], inUse: .apple), .parakeetV3)?.state == "Loading.")
    }

    @Test func aModelThatDidntLoadSaysWhy() {
        let broken = row(status([.parakeetV3: .installed], loadErrors: [.parakeetV3: "A file is missing."]),
                         .parakeetV3)
        #expect(broken?.state == "Didn't load. A file is missing.")
        #expect(broken?.isError == true)
    }

    @Test func aDeletedModelOffersItsDownloadAndIsForNothing() {
        let deleted = row(status([.parakeetV3: .installed], deleted: [.whisperTurbo], inUse: .parakeetV3),
                          .whisperTurbo)
        #expect(deleted?.state == "Not downloaded. 650 MB.")
        #expect(deleted?.action == .download)
        #expect(deleted?.role == nil)
    }

    @Test func anIntelMacSaysTheModelsNeedAppleSilicon() {
        let intel = status(canDownload: false)
        #expect(row(intel, .parakeetV3)?.state == "Needs a Mac with Apple silicon.")
        #expect(row(intel, .parakeetV3)?.action == nil)
        #expect(row(intel, .apple)?.state == "Built in.")
        #expect(row(intel, .apple)?.role == "Live")
    }

    @Test func onlyDownloadedModelsCanBeDeleted() {
        let some = status([.parakeetV3: .installed, .whisperTurbo: .installed, .parakeetV2: .downloading(fraction: 0.1)])
        #expect(some.deletable.map(\.id) == [.parakeetV3, .whisperTurbo])
        #expect(some.deletable.map(\.size) == ["483 MB", "650 MB"])
        #expect(status().deletable.isEmpty)
    }
}
