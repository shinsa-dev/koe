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
