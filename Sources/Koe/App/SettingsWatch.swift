import AppKit
import KoeCore

/// `--snapshots <folder>`, for tests: every second, draws the settings page into the folder when it changed and prints
/// the models' state when that changed, so a run in the background shows each state it went through without a window.
@MainActor
enum SettingsWatch {
    static func start(into folder: URL, models: ModelStore, window: SettingsWindowController) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Task { @MainActor in
            let started = Date()
            var lastImage: Data?
            var lastState = ""
            while true {
                let seconds = Int(Date().timeIntervalSince(started))
                let state = describe(models)
                if state != lastState {
                    lastState = state
                    print("\(seconds)s \(state)")
                    fflush(stdout)
                }
                if let image = window.snapshotPNG(), image != lastImage {
                    lastImage = image
                    try? image.write(to: folder.appending(path: String(format: "%04ds.png", seconds)))
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private static func describe(_ models: ModelStore) -> String {
        let installs = ModelID.allCases.filter { TranscriptionModel.model($0).needsDownload }
            .map { "\($0.rawValue)=\(models.install($0))" }
        return "uses \(models.route.model.rawValue) (\(models.route.reason ?? "ready")) " + installs.joined(separator: " ")
    }
}
