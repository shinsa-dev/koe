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

    @Test func settingsStartOnParakeetV3AndKeepTheChosenModel() {
        let fresh = KoeSettings(values: [:])
        #expect(fresh.transcriptionModel == .parakeetV3)
        #expect(!fresh.startedFirstDownload)

        var settings = KoeSettings()
        settings.transcriptionModel = .whisperTurbo
        settings.startedFirstDownload = true
        #expect(settings.values["transcriptionModel"] as? String == "whisper-large-v3-turbo")
        #expect(KoeSettings(values: settings.values) == settings)
    }

    @Test func anUnknownModelFallsBackToTheDefault() {
        let settings = KoeSettings(values: ["transcriptionModel": "whisper-tiny", "startedFirstDownload": "yes"])
        #expect(settings.transcriptionModel == .parakeetV3)
        #expect(!settings.startedFirstDownload)
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

    @Test func theReasonSaysWhatToExpect() {
        let downloading = TranscriberRoute.resolve(chosen: .parakeetV3, install: .downloading(fraction: 0.1),
                                                   canRun: true, loadError: nil)
        #expect(downloading.reason == "Koe uses Apple's model until Parakeet v3 finishes downloading.")
    }
}
