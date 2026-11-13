import Foundation
import KoeCore
import Testing

struct ModelPickerTests {
    private func picker(_ chosen: ModelID = .parakeetV3, _ installs: [ModelID: ModelInstall] = [:],
                        canDownload: Bool = true) -> ModelPicker {
        ModelPicker(chosen: chosen, installs: installs, canDownload: canDownload)
    }

    @Test func theDropdownListsEveryModelWithWhereItStands() {
        let models = picker(.parakeetV3, [.parakeetV2: .installed, .whisperTurbo: .downloading(fraction: 0.42)])
        #expect(models.options.map(\.id) == [.parakeetV3, .parakeetV2, .whisperTurbo, .apple])
        #expect(models.options.map(\.note) == [
            "Recommended · 483 MB download", "Downloaded", "Downloading, 42%", "Built in",
        ])
        #expect(models.options.map(\.isChosen) == [true, false, false, false])
        #expect(models.options.allSatisfy { $0.isEnabled })
    }

    @Test func aChosenModelNotOnDiskOffersItsDownloadWithSizeAndLanguages() {
        let models = picker(.parakeetV3)
        #expect(models.chosen == .parakeetV3)
        #expect(models.action == .download)
        #expect(models.detail == "483 MB · 25 European languages")
        #expect(models.fraction == nil)
        #expect(!models.isError)
    }

    @Test func aDownloadShowsItsProgressAndCanBeCancelled() {
        let models = picker(.parakeetV3, [.parakeetV3: .downloading(fraction: 0.5)])
        #expect(models.action == .cancel)
        #expect(models.fraction == 0.5)
        let half = ByteCountFormatter.string(fromByteCount: 241_500_000, countStyle: .file)
        #expect(models.detail == "Downloading, \(half) of 483 MB.")
        #expect(picker(.parakeetV3, [.parakeetV3: .downloading(fraction: 0)]).detail == "Starting the 483 MB download.")
    }

    @Test func aFailedDownloadSaysWhyAndOffersToTryAgain() {
        let models = picker(.whisperTurbo, [.whisperTurbo: .failed("The download needs an internet connection.")])
        #expect(models.action == .retry)
        #expect(models.isError)
        #expect(models.detail == "The download needs an internet connection.")
        #expect(models.options[2].note == "Download failed")
    }

    @Test func aDownloadedOrBuiltInModelNeedsNoButton() {
        #expect(picker(.parakeetV3, [.parakeetV3: .installed]).action == nil)
        let apple = picker(.apple)
        #expect(apple.action == nil)
        #expect(apple.detail == "Built in · Your system language")
    }

    @Test func onlyDownloadedModelsCanBeDeleted() {
        let models = picker(.parakeetV3, [.parakeetV3: .installed, .whisperTurbo: .installed,
                                          .parakeetV2: .downloading(fraction: 0.1)])
        #expect(models.deletable.map(\.id) == [.parakeetV3, .whisperTurbo])
        #expect(models.deletable.map(\.note) == ["483 MB", "650 MB"])
        #expect(picker(.apple).deletable.isEmpty)
    }

    @Test func withoutAppleSiliconOnlyWhatIsOnDiskCanBeChosen() {
        let models = picker(.parakeetV2, [.whisperTurbo: .installed], canDownload: false)
        #expect(models.action == nil)
        #expect(models.isError)
        #expect(models.detail == "Needs a Mac with Apple silicon.")
        #expect(models.options.map(\.isEnabled) == [false, false, true, true])
        #expect(models.options[0].note == "Recommended · Needs Apple silicon")
    }

    @Test func pickingAModelNotOnDiskKeepsTheOneInUseUntilItIsIn() {
        #expect(ModelPicker.choose(.whisperTurbo, chosen: .parakeetV3, install: .notInstalled, canDownload: true)
            == .downloadThenUse)
        #expect(ModelPicker.choose(.whisperTurbo, chosen: .parakeetV3, install: .failed("x"), canDownload: true)
            == .downloadThenUse)
        #expect(ModelPicker.choose(.whisperTurbo, chosen: .parakeetV3, install: .installed, canDownload: true) == .use)
        #expect(ModelPicker.choose(.apple, chosen: .parakeetV3, install: .notInstalled, canDownload: true) == .use)
        #expect(ModelPicker.choose(.parakeetV3, chosen: .parakeetV3, install: .notInstalled, canDownload: true)
            == .download)
        #expect(ModelPicker.choose(.whisperTurbo, chosen: .parakeetV3, install: .notInstalled, canDownload: false)
            == .unavailable)
    }

    @Test func thePendingModelIsChosenOnlyOnceItsDownloadIsIn() {
        #expect(ModelPicker.settle(pending: .whisperTurbo, changed: .whisperTurbo, install: .installed) == .adopt)
        #expect(ModelPicker.settle(pending: .whisperTurbo, changed: .whisperTurbo, install: .notInstalled) == .drop)
        #expect(ModelPicker.settle(pending: .whisperTurbo, changed: .whisperTurbo, install: .failed("x")) == .keep)
        #expect(ModelPicker.settle(pending: .whisperTurbo, changed: .whisperTurbo,
                                   install: .downloading(fraction: 0.3)) == .keep)
        #expect(ModelPicker.settle(pending: .whisperTurbo, changed: .parakeetV2, install: .installed) == .keep)
        #expect(ModelPicker.settle(pending: nil, changed: .whisperTurbo, install: .installed) == .keep)
    }

    @Test func aPendingDownloadShowsInTheDropdownAndSaysWhatRunsMeanwhile() {
        let models = ModelPicker(chosen: .parakeetV3, pending: .whisperTurbo, inUse: .parakeetV3,
                                 installs: [.parakeetV3: .installed, .whisperTurbo: .downloading(fraction: 0)],
                                 canDownload: true)
        #expect(models.chosen == .whisperTurbo)
        #expect(models.options.map(\.isChosen) == [false, false, true, false])
        #expect(models.action == .cancel)
        #expect(models.detail == "Starting the 650 MB download. Koe uses Parakeet v3 until then.")
        let failed = ModelPicker(chosen: .parakeetV3, pending: .whisperTurbo, inUse: .parakeetV3,
                                 installs: [.whisperTurbo: .failed("The download stopped.")], canDownload: true)
        #expect(failed.action == .retry)
        #expect(failed.detail == "The download stopped. Koe uses Parakeet v3 until then.")
    }
}
