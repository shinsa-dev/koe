import Foundation
import KoeCore
import Testing

struct ModelRowTests {
    private func row(_ model: TranscriptionModel, _ install: ModelInstall, chosen: ModelID = .parakeetV3,
                     running: ModelID = .apple, canDownload: Bool = true) -> ModelRow {
        ModelRow(model, install: install, chosen: chosen, running: running, canDownload: canDownload)
    }

    @Test func aModelNotOnDiskOffersItsDownloadWithSizeAndLanguages() {
        let parakeet = row(.parakeetV3, .notInstalled)
        #expect(parakeet.action == .download)
        #expect(!parakeet.inUse)
        #expect(!parakeet.canDelete)
        #expect(parakeet.detail == "483 MB · 25 European languages")
        #expect(parakeet.fraction == nil)
    }

    @Test func aDownloadShowsItsProgressAndCanBeCancelled() {
        let parakeet = row(.parakeetV3, .downloading(fraction: 0.5))
        #expect(parakeet.action == .cancel)
        #expect(parakeet.fraction == 0.5)
        let half = ByteCountFormatter.string(fromByteCount: 241_500_000, countStyle: .file)
        #expect(parakeet.detail == "Downloading, \(half) of 483 MB")
        #expect(!parakeet.canDelete)
    }

    @Test func aFailedDownloadSaysWhyAndOffersToTryAgain() {
        let whisper = row(.whisperTurbo, .failed("The download needs an internet connection."))
        #expect(whisper.action == .retry)
        #expect(whisper.isError)
        #expect(whisper.detail == "The download needs an internet connection.")
    }

    @Test func aDownloadedModelCanBeUsedOrDeleted() {
        let other = row(.whisperTurbo, .installed)
        #expect(other.action == .use)
        #expect(other.canDelete)

        let chosen = row(.parakeetV3, .installed, running: .parakeetV3)
        #expect(chosen.action == nil)
        #expect(chosen.inUse)
        #expect(chosen.canDelete)
    }

    @Test func appleIsInUseWheneverTheChosenModelCantRunAndIsNeverDeleted() {
        let fallback = row(.apple, .installed, chosen: .parakeetV3, running: .apple)
        #expect(fallback.inUse)
        #expect(fallback.action == nil)
        #expect(!fallback.canDelete)
        #expect(fallback.detail == "Built in · Your system language")

        let idle = row(.apple, .installed, chosen: .parakeetV3, running: .parakeetV3)
        #expect(!idle.inUse)
        #expect(idle.action == .use)
    }

    @Test func withoutAppleSiliconNothingDownloads() {
        let parakeet = row(.parakeetV2, .notInstalled, canDownload: false)
        #expect(parakeet.action == nil)
        #expect(parakeet.detail == "Needs a Mac with Apple silicon.")
    }
}
