import Foundation

/// What the Transcription card shows: one dropdown of every model, and the chosen model's download under it.
public struct ModelPicker: Sendable, Equatable {
    /// One model in the dropdown.
    public struct Option: Sendable, Equatable, Identifiable {
        public let id: ModelID
        public let title: String
        /// Where it stands, under its name: built in, downloaded, its download size or progress.
        public let note: String
        public let isChosen: Bool
        public let isEnabled: Bool
    }

    /// The one button beside the dropdown, for the chosen model's download.
    public enum Action: Sendable, Equatable {
        case download, cancel, retry
    }

    public let chosen: TranscriptionModel
    public let options: [Option]
    /// Downloaded models, which a submenu deletes, with their size as the note.
    public let deletable: [Option]
    public let action: Action?
    /// The chosen model's size and languages, its download's progress, or why it stopped.
    public let detail: String
    /// 0 to 1 while the chosen model downloads.
    public let fraction: Double?
    public let isError: Bool

    public init(chosen: ModelID, installs: [ModelID: ModelInstall], canDownload: Bool) {
        let model = TranscriptionModel.model(chosen)
        self.chosen = model
        func install(_ id: ModelID) -> ModelInstall { installs[id] ?? .notInstalled }
        options = TranscriptionModel.catalog.map { option in
            let state = Self.note(option, install: install(option.id), canDownload: canDownload)
            return Option(id: option.id, title: option.name,
                          note: option.isRecommended ? "Recommended · \(state)" : state,
                          isChosen: option.id == model.id,
                          isEnabled: !option.needsDownload || canDownload || install(option.id).isInstalled)
        }
        deletable = TranscriptionModel.catalog
            .filter { $0.needsDownload && install($0.id).isInstalled }
            .map { Option(id: $0.id, title: $0.name, note: $0.sizeLabel, isChosen: $0.id == model.id, isEnabled: true) }

        let summary = "\(model.sizeLabel) · \(model.languages)"
        var fraction: Double?
        var isError = false
        switch install(model.id) {
        case _ where !model.needsDownload:
            action = nil
            detail = summary
        case .downloading(let done):
            action = .cancel
            fraction = done
            let bytes = Int64(done * Double(model.bytes))
            detail = bytes < 1_000_000
                ? "Starting the \(model.sizeLabel) download"
                : "Downloading, \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) of \(model.sizeLabel)"
        case .failed(let message):
            action = .retry
            isError = true
            detail = message
        case .notInstalled where !canDownload:
            action = nil
            isError = true
            detail = "Needs a Mac with Apple silicon."
        case .notInstalled:
            action = .download
            detail = summary
        case .installed:
            action = nil
            detail = summary
        }
        self.fraction = fraction
        self.isError = isError
    }

    /// Choosing a model that isn't on this Mac yet starts its download, so picking it is all it takes.
    public static func startsDownload(_ id: ModelID, install: ModelInstall, canDownload: Bool) -> Bool {
        guard TranscriptionModel.model(id).needsDownload, canDownload else { return false }
        return switch install {
        case .notInstalled, .failed: true
        case .downloading, .installed: false
        }
    }

    private static func note(_ model: TranscriptionModel, install: ModelInstall, canDownload: Bool) -> String {
        guard model.needsDownload else { return "Built in" }
        return switch install {
        case .installed: "Downloaded"
        case .downloading(let done): "Downloading, \(Int(done * 100))%"
        case .failed: "Download failed"
        case .notInstalled where !canDownload: "Needs Apple silicon"
        case .notInstalled: "\(model.sizeLabel) download"
        }
    }
}
