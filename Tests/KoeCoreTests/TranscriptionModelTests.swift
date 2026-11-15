import KoeCore
import Testing

struct TranscriptionModelTests {
    @Test func parakeetV3IsTheRecommendedDefaultAndAppleTheBuiltInFallback() {
        #expect(TranscriptionModel.standard.id == .parakeetV3)
        #expect(TranscriptionModel.catalog.filter(\.isRecommended).map(\.id) == [.parakeetV3])
        #expect(TranscriptionModel.catalog.first?.id == .parakeetV3)
        #expect(TranscriptionModel.catalog.last?.id == .apple)
        #expect(!TranscriptionModel.apple.needsDownload)
        #expect(TranscriptionModel.apple.sizeLabel == "Built in")
        let downloaded = TranscriptionModel.catalog.filter { $0.id != .apple }
        #expect(downloaded.filter(\.needsDownload).count == downloaded.count)
    }

    @Test func theCatalogListsEveryModelOnce() {
        #expect(TranscriptionModel.catalog.map(\.id) == ModelID.allCases)
        for id in ModelID.allCases {
            #expect(TranscriptionModel.model(id).id == id)
        }
    }

    @Test func settingsRememberTheModelsYouDeleted() {
        #expect(KoeSettings(values: [:]).deletedModels.isEmpty)

        var settings = KoeSettings()
        settings.deletedModels = [.whisperTurbo, .parakeetV3]
        #expect(settings.values["deletedModels"] as? [String] == ["parakeet-v3", "whisper-large-v3-turbo"])
        #expect(KoeSettings(values: settings.values) == settings)
    }

    @Test func anOldModelChoiceIsIgnoredAndUnknownDeletionsDrop() {
        let settings = KoeSettings(values: ["transcriptionModel": "apple", "startedFirstDownload": true,
                                            "deletedModels": ["whisper-tiny", "parakeet-v2"]])
        #expect(settings.deletedModels == [.parakeetV2])
        #expect(settings.values["transcriptionModel"] == nil)
    }

    @Test func downloadProgressIsMeasuredFromTheBytesOnDiskAndNeverReachesDone() {
        #expect(ModelInstall.progress(onDisk: 0, expected: 400) == .downloading(fraction: 0))
        #expect(ModelInstall.progress(onDisk: 100, expected: 400) == .downloading(fraction: 0.25))
        #expect(ModelInstall.progress(onDisk: 500, expected: 400) == .downloading(fraction: 0.99))
        #expect(ModelInstall.progress(onDisk: 10, expected: 0) == .downloading(fraction: 0))
        #expect(ModelInstall.downloading(fraction: 0.5).isDownloading)
        #expect(!ModelInstall.installed.isDownloading)
        #expect(ModelInstall.installed.isInstalled)
        #expect(!ModelInstall.failed("No network").isInstalled)
        #expect(!ModelInstall.preparing.isInstalled)
        #expect(!ModelInstall.preparing.isDownloading)
    }
}

struct TranscriberRouteTests {
    @Test func aDownloadedModelThatLoadsRuns() {
        let route = TranscriberRoute.resolve(chosen: .parakeetV3, install: .installed, canRun: true, loadError: nil)
        #expect(route.model == .parakeetV3)
        #expect(route.reason == nil)
    }

    @Test func appleRunsWithoutADownload() {
        let route = TranscriberRoute.resolve(chosen: .apple, install: .notInstalled, canRun: false, loadError: nil)
        #expect(route.model == .apple)
        #expect(route.fallback == nil)
    }

    @Test func everyReasonTheChosenModelCantRunFallsBackToApple() {
        struct Case {
            let install: ModelInstall
            var canRun = true
            var error: String?
            let fallback: TranscriberRoute.Fallback
        }
        let cases = [
            Case(install: .notInstalled, fallback: .notDownloaded),
            Case(install: .failed("offline"), fallback: .notDownloaded),
            Case(install: .downloading(fraction: 0.4), fallback: .downloading),
            Case(install: .preparing, fallback: .preparing),
            Case(install: .installed, canRun: false, fallback: .needsAppleSilicon),
            Case(install: .installed, error: "Missing file.", fallback: .failedToLoad("Missing file.")),
        ]
        for item in cases {
            let route = TranscriberRoute.resolve(chosen: .whisperTurbo, install: item.install, canRun: item.canRun,
                                                 loadError: item.error)
            #expect(route.model == .apple)
            #expect(route.fallback == item.fallback)
            #expect(route.reason?.contains("Whisper large-v3 turbo") == true)
        }
    }

    @Test func aDownloadedModelThatHasntLoadedYetLetsAppleTakeTheSession() {
        let route = TranscriberRoute.resolve(chosen: .whisperTurbo, install: .installed, canRun: true,
                                             loadError: nil, isLoaded: false)
        #expect(route.model == .apple)
        #expect(route.fallback == .preparing)
        #expect(route.reason == "Koe uses Apple's model while Whisper large-v3 turbo gets ready for this Mac.")
    }

    @Test func aLoadErrorOutranksAModelStillLoading() {
        let route = TranscriberRoute.resolve(chosen: .parakeetV3, install: .installed, canRun: true,
                                             loadError: "Missing file.", isLoaded: false)
        #expect(route.fallback == .failedToLoad("Missing file."))
    }

    @Test func appleNeverWaitsToLoad() {
        let route = TranscriberRoute.resolve(chosen: .apple, install: .installed, canRun: true, loadError: nil,
                                             isLoaded: false)
        #expect(route.model == .apple)
        #expect(route.fallback == nil)
    }

    @Test func onlyAFailedLoadGivesTheRowsAnError() {
        let failed = TranscriberRoute.resolve(chosen: .parakeetV3, install: .installed, canRun: true,
                                              loadError: "Missing file.")
        #expect(failed.loadErrors == [.parakeetV3: "Missing file."])
        let loading = TranscriberRoute.resolve(chosen: .parakeetV3, install: .installed, canRun: true,
                                               loadError: nil, isLoaded: false)
        #expect(loading.loadErrors.isEmpty)
    }

    @Test func theReasonSaysWhatToExpect() {
        let downloading = TranscriberRoute.resolve(chosen: .parakeetV3, install: .downloading(fraction: 0.1),
                                                   canRun: true, loadError: nil)
        #expect(downloading.reason == "Koe uses Apple's model until Parakeet v3 finishes downloading.")
        let preparing = TranscriberRoute.resolve(chosen: .whisperTurbo, install: .preparing, canRun: true,
                                                 loadError: nil)
        #expect(preparing.reason == "Koe uses Apple's model while Whisper large-v3 turbo gets ready for this Mac.")
        let waiting = TranscriberRoute.resolve(chosen: .parakeetV3, install: .notInstalled, canRun: true,
                                               loadError: nil)
        #expect(waiting.reason == "Koe uses Apple's model until Parakeet v3 is downloaded.")
    }
}
